import taiga_config::*;
import riscv_types::*;
import taiga_types::*;
import fpu_types::*;

module fp_madd_fused_simulation_wrapper (
  input clk,
  input rst,
  output logic [1:0] debug_instruction,
  //inputs
  input logic [FLEN-1:0]    rs1,
  input logic [FLEN-1:0]    rs2,
  input logic [FLEN-1:0]    rs3,
  input logic [6:0]         fn7,
  input logic [6:0]         op,
  input logic [2:0]         rm,
  input logic [2:0]         instruction,
  //issue
  input logic possible_issue,
  input logic new_request,
  input logic new_request_r,
  input id_t id,
  input logic[10:0] input_counter, 
  output logic ready,
  //FP MUL writeback
  output id_t mul_id,
  output logic mul_done,
  output logic [FLEN-1:0] mul_rd,
  input logic mul_ack,
  //FP MADD and ADD writeback
  output id_t madd_id,
  output logic madd_done,
  output logic add_done,
  input logic madd_ack,
  output logic [FLEN-1:0] madd_rd, //fcsr
  output logic [4:0] fmul_fflags,
  output logic [4:0] fmadd_fflags
  );

  localparam FP_NUM_NORM_ROUND_UNITS = 4;
  fp_madd_inputs_t fp_madd_inputs;
  unit_issue_interface issue();
  fp_unit_writeback_interface fp_mul_wb, fp_madd_wb; 
  fp_unit_writeback_interface intermediate_unit_wb [FP_NUM_NORM_ROUND_UNITS](); //units that require normalization/rounding
  fp_unit_writeback_interface fp_unit_wb;
  fflags_writeback_t fp_unit_fflag_wb_packet;
  logic adder_path;
  logic add;
  logic rs1_hidden_bit;
  logic rs2_hidden_bit;
  logic rs3_hidden_bit;
  logic is_inf[FP_REGFILE_READ_PORTS];
  logic is_SNaN[FP_REGFILE_READ_PORTS];
  logic is_QNaN[FP_REGFILE_READ_PORTS];
  logic is_zero[FP_REGFILE_READ_PORTS];
  logic hidden_bit[FP_REGFILE_READ_PORTS];

  logic [10:0] input_counter_r;
  always_ff @ (posedge clk) 
    input_counter_r <= input_counter;

  localparam fp_wb_norm_round_param_t FP_NORM_ROUND_WB_IDS = '{
        FMADD : 0,
        FMUL: 1,
        FDIV_SQRT: 2,
        MISC_WB2FP : 3
    };

  fp_madd_fused_top FMA (
    .clk (clk),
    .rst (rst),
    .fp_madd_inputs (fp_madd_inputs),
    .issue (issue),
    .fp_madd_wb(intermediate_unit_wb[FP_NORM_ROUND_WB_IDS.FMADD]), 
    .fp_mul_wb (intermediate_unit_wb[FP_NORM_ROUND_WB_IDS.FMUL]) 
  );

  localparam int unsigned FP_NUM_NORM_ROUND_UNITS_PER_PORT [FP_NUM_WB_GROUPS] = '{FP_NUM_NORM_ROUND_UNITS};
  fp_normalize_rounding_top #(
    .NUM_WB_UNITS(FP_NUM_NORM_ROUND_UNITS),
    .NUM_UNITS(FP_NUM_NORM_ROUND_UNITS_PER_PORT)
  ) 
  norm_round_inst(
    .clk(clk),
    .rst(rst),
    .intermediate_unit_wb(intermediate_unit_wb),
    .unit_wb(fp_unit_wb)
  );

  assign fp_madd_inputs.rs1 = rs1;
  assign fp_madd_inputs.rs2 = rs2;
  assign fp_madd_inputs.rs3 = rs3;
  assign fp_madd_inputs.op = op;
  assign fp_madd_inputs.rm = rm;
  assign fp_madd_inputs.instruction = instruction;
  assign fp_madd_inputs.fn7 = fn7;
  assign fp_madd_inputs.rs1_special_case = {is_inf[RS1], is_SNaN[RS1], is_QNaN[RS1], is_zero[RS1]}; 
  assign fp_madd_inputs.rs2_special_case = {is_inf[RS2], is_SNaN[RS2], is_QNaN[RS2], is_zero[RS2]};
  assign fp_madd_inputs.rs3_special_case = {is_inf[RS3], is_SNaN[RS3], is_QNaN[RS3], is_zero[RS3]};
  assign fp_madd_inputs.rs1_hidden_bit = hidden_bit[RS1];
  assign fp_madd_inputs.rs2_hidden_bit = hidden_bit[RS2];
  assign fp_madd_inputs.rs3_hidden_bit = hidden_bit[RS3];

  localparam VARIABLE_EXPO_WIDTH = EXPO_WIDTH;
  localparam VARIABLE_FRAC_WIDTH = FRAC_WIDTH;
  fp_special_case_detection_sandboxed #(.SANDBOX_FRAC_W(VARIABLE_FRAC_WIDTH), .SANDBOX_EXPO_W(VARIABLE_EXPO_WIDTH))
      rs1_special_case_detection (
        .data_in (rs1),
        .is_inf (is_inf[RS1]),
        .is_SNaN (is_SNaN[RS1]),
        .is_QNaN (is_QNaN[RS1]),
        .is_zero (is_zero[RS1]),
        .hidden (hidden_bit[RS1])
      );  

  fp_special_case_detection_sandboxed #(.SANDBOX_FRAC_W(VARIABLE_FRAC_WIDTH), .SANDBOX_EXPO_W(VARIABLE_EXPO_WIDTH))
      rs2_special_case_detection (
        .data_in (rs2),
        .is_inf (is_inf[RS2]),
        .is_SNaN (is_SNaN[RS2]),
        .is_QNaN (is_QNaN[RS2]),
        .is_zero (is_zero[RS2]),
        .hidden (hidden_bit[RS2])
      );  

  fp_special_case_detection_sandboxed #(.SANDBOX_FRAC_W(VARIABLE_FRAC_WIDTH), .SANDBOX_EXPO_W(VARIABLE_EXPO_WIDTH))
      rs3_special_case_detection (
        .data_in (rs3),
        .is_inf (is_inf[RS3]),
        .is_SNaN (is_SNaN[RS3]),
        .is_QNaN (is_QNaN[RS3]),
        .is_zero (is_zero[RS3]),
        .hidden (hidden_bit[RS3])
      );

  assign ready =1;
  assign issue.possible_issue = possible_issue;
  assign issue.new_request = new_request;
  assign issue.new_request_r = new_request_r;
  assign issue.id = id;

  //control signals
  assign adder_path = 0;
  assign add = 1;

  assign mul_id = fp_unit_wb.id;
  assign mul_done = fp_unit_wb.done & ~adder_path; //asserted for fmul
  assign mul_rd = fp_unit_wb.rd;
  //assign fp_unit_wb[FP_WB_IDS.FMUL].ack = 1;// ack always asserted

  assign fp_unit_wb.ack = 1;// ack always asserted
  assign madd_done = fp_unit_wb.done & (adder_path & ~add);  //asserted for fmadd
  assign madd_id = fp_unit_wb.id;
  assign add_done = fp_unit_wb.done & (adder_path & add); //asserted for fadd
  assign madd_rd = fp_unit_wb.rd;

endmodule
