/*
 * Copyright © 2020 Eric Matthews,  Lesley Shannon
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * Initial code developed under the supervision of Dr. Lesley Shannon,
 * Reconfigurable Computing Lab, Simon Fraser University.
 *
 * Author(s):
 *             Eric Matthews <ematthew@sfu.ca>
 */

module  illegal_instruction_checker

    import taiga_config::*;
    import riscv_types::*;

    # (
        parameter cpu_config_t CONFIG = EXAMPLE_CONFIG
    )

    (
        input logic [31:0] instruction,
        output logic illegal_instruction
    );

    ////////////////////////////////////////////////////
    //Instruction Patterns for Illegal Instruction Checking

    //Base ISA
    localparam [31:0] BEQ = 32'b?????????????????000?????1100011;
    localparam [31:0] BNE = 32'b?????????????????001?????1100011;
    localparam [31:0] BLT = 32'b?????????????????100?????1100011;
    localparam [31:0] BGE = 32'b?????????????????101?????1100011;
    localparam [31:0] BLTU = 32'b?????????????????110?????1100011;
    localparam [31:0] BGEU = 32'b?????????????????111?????1100011;
    localparam [31:0] JALR = 32'b?????????????????000?????1100111;
    localparam [31:0] JAL = 32'b?????????????????????????1101111;
    localparam [31:0] LUI = 32'b?????????????????????????0110111;
    localparam [31:0] AUIPC = 32'b?????????????????????????0010111;
    localparam [31:0] ADDI = 32'b?????????????????000?????0010011;
    localparam [31:0] SLLI = 32'b000000???????????001?????0010011;
    localparam [31:0] SLTI = 32'b?????????????????010?????0010011;
    localparam [31:0] SLTIU = 32'b?????????????????011?????0010011;
    localparam [31:0] XORI = 32'b?????????????????100?????0010011;
    localparam [31:0] SRLI = 32'b000000???????????101?????0010011;
    localparam [31:0] SRAI = 32'b010000???????????101?????0010011;
    localparam [31:0] ORI = 32'b?????????????????110?????0010011;
    localparam [31:0] ANDI = 32'b?????????????????111?????0010011;
    localparam [31:0] ADD = 32'b0000000??????????000?????0110011;
    localparam [31:0] SUB = 32'b0100000??????????000?????0110011;
    localparam [31:0] SLL = 32'b0000000??????????001?????0110011;
    localparam [31:0] SLT = 32'b0000000??????????010?????0110011;
    localparam [31:0] SLTU = 32'b0000000??????????011?????0110011;
    localparam [31:0] XOR = 32'b0000000??????????100?????0110011;
    localparam [31:0] SRL = 32'b0000000??????????101?????0110011;
    localparam [31:0] SRA = 32'b0100000??????????101?????0110011;
    localparam [31:0] OR = 32'b0000000??????????110?????0110011;
    localparam [31:0] AND = 32'b0000000??????????111?????0110011;
    localparam [31:0] LB = 32'b?????????????????000?????0000011;
    localparam [31:0] LH = 32'b?????????????????001?????0000011;
    localparam [31:0] LW = 32'b?????????????????010?????0000011;
    localparam [31:0] LBU = 32'b?????????????????100?????0000011;
    localparam [31:0] LHU = 32'b?????????????????101?????0000011;
    localparam [31:0] SB = 32'b?????????????????000?????0100011;
    localparam [31:0] SH = 32'b?????????????????001?????0100011;
    localparam [31:0] SW = 32'b?????????????????010?????0100011;
    localparam [31:0] FENCE = 32'b?????????????????000?????0001111;
    localparam [31:0] FENCE_I = 32'b?????????????????001?????0001111;
    localparam [31:0] ECALL = 32'b00000000000000000000000001110011;
    localparam [31:0] EBREAK = 32'b00000000000100000000000001110011;

    localparam [31:0] CSRRW = 32'b?????????????????001?????1110011;
    localparam [31:0] CSRRS = 32'b?????????????????010?????1110011;
    localparam [31:0] CSRRC = 32'b?????????????????011?????1110011;
    localparam [31:0] CSRRWI = 32'b?????????????????101?????1110011;
    localparam [31:0] CSRRSI = 32'b?????????????????110?????1110011;
    localparam [31:0] CSRRCI = 32'b?????????????????111?????1110011;

    //Mul
    localparam [31:0] MUL = 32'b0000001??????????000?????0110011;
    localparam [31:0] MULH = 32'b0000001??????????001?????0110011;
    localparam [31:0] MULHSU = 32'b0000001??????????010?????0110011;
    localparam [31:0] MULHU = 32'b0000001??????????011?????0110011;
    //Div
    localparam [31:0] DIV = 32'b0000001??????????100?????0110011;
    localparam [31:0] DIVU = 32'b0000001??????????101?????0110011;
    localparam [31:0] REM = 32'b0000001??????????110?????0110011;
    localparam [31:0] REMU = 32'b0000001??????????111?????0110011;

    //AMO
    localparam [31:0] AMO_ADD = 32'b00000????????????010?????0101111;
    localparam [31:0] AMO_XOR = 32'b00100????????????010?????0101111;
    localparam [31:0] AMO_OR = 32'b01000????????????010?????0101111;
    localparam [31:0] AMO_AND = 32'b01100????????????010?????0101111;
    localparam [31:0] AMO_MIN = 32'b10000????????????010?????0101111;
    localparam [31:0] AMO_MAX = 32'b10100????????????010?????0101111;
    localparam [31:0] AMO_MINU = 32'b11000????????????010?????0101111;
    localparam [31:0] AMO_MAXU = 32'b11100????????????010?????0101111;
    localparam [31:0] AMO_SWAP = 32'b00001????????????010?????0101111;
    localparam [31:0] LR = 32'b00010??00000?????010?????0101111;
    localparam [31:0] SC = 32'b00011????????????010?????0101111;

    //Machine/Supervisor
    localparam [31:0] SRET = 32'b00010000001000000000000001110011;
    localparam [31:0] MRET = 32'b00110000001000000000000001110011;
    localparam [31:0] SFENCE_VMA = 32'b0001001??????????000000001110011;
    localparam [31:0] WFI = 32'b00010000010100000000000001110011;

    //RV32D 
    localparam [31:0] DP_FLD       = 32'b?????????????????011?????0000111;
    localparam [31:0] DP_FSD       = 32'b?????????????????011?????0100111;
    localparam [31:0] DP_FMADD_D   = 32'b?????01??????????????????1000011;
    localparam [31:0] DP_FMSUB_D   = 32'b?????01??????????????????1000111;
    localparam [31:0] DP_FNMSUB_D  = 32'b?????01??????????????????1001011;
    localparam [31:0] DP_FNMADD_D  = 32'b?????01??????????????????1001111;
    localparam [31:0] DP_FADD_D    = 32'b0000001??????????????????1010011;
    localparam [31:0] DP_FSUB_D    = 32'b0000101??????????????????1010011;
    localparam [31:0] DP_FMUL_D    = 32'b0001001??????????????????1010011;
    localparam [31:0] DP_FDIV_D    = 32'b0001101??????????????????1010011;
    localparam [31:0] DP_FSQRT_D   = 32'b010110100000?????????????1010011;
    localparam [31:0] DP_FSGNJ_D   = 32'b0010001??????????000?????1010011;
    localparam [31:0] DP_FSGNJN_D  = 32'b0010001??????????001?????1010011;
    localparam [31:0] DP_FSGNJX_D  = 32'b0010001??????????010?????1010011;
    localparam [31:0] DP_FMIN_D    = 32'b0010101??????????000?????1010011;
    localparam [31:0] DP_FMAX_D    = 32'b0010101??????????001?????1010011;
    localparam [31:0] DP_FCVT_W_D  = 32'b110000100000?????????????1010011;
    localparam [31:0] DP_FCVT_WU_D = 32'b110000100001?????????????1010011;
    localparam [31:0] DP_FCVT_D_W  = 32'b110100100000?????????????1010011;
    localparam [31:0] DP_FCVT_D_WU = 32'b110100100001?????????????1010011;
    localparam [31:0] DP_FEQ_D     = 32'b1010001??????????010?????1010011;
    localparam [31:0] DP_FLT_D     = 32'b1010001??????????001?????1010011;
    localparam [31:0] DP_FLE_D     = 32'b1010001??????????000?????1010011;
    localparam [31:0] DP_FLASS_D   = 32'b111000100000?????001?????1010011;
    localparam [31:0] DP_FCVT_S_D  = 32'b010000000001?????????????1010011;
    localparam [31:0] DP_FCVT_D_S  = 32'b010000100000?????????????1010011;

    logic base_legal;
    logic csr_legal;
    logic csr_addr_base;
    logic csr_addr_machine;
    logic csr_addr_supervisor;
    logic csr_addr_debug;
    logic mul_legal;
    logic div_legal;
    logic ifence_legal;
    logic amo_legal;
    logic machine_legal;
    logic supervisor_legal;
    
    //FPU support
    logic double_legal;
    ////////////////////////////////////////////////////
    //Implementation

    assign base_legal = instruction inside {
        BEQ, BNE, BLT, BGE, BLTU, BGEU, JALR, JAL, LUI, AUIPC,
        ADDI, SLLI, SLTI, SLTIU, XORI, SRLI, SRAI, ORI, ANDI,
        ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND,
        LB, LH, LW, LBU, LHU, SB, SH, SW,
        FENCE
    };

    assign csr_addr_base = instruction[31:20] inside {
        FFLAGS, FRM, FCSR,
        CYCLE, TIME, INSTRET, CYCLEH, TIMEH, INSTRETH
    };

    assign csr_addr_machine = instruction[31:20] inside {
        MVENDORID, MARCHID, MIMPID, MHARTID,
        MSTATUS, MISA, MEDELEG, MIDELEG, MIE, MTVEC, MCOUNTEREN,
        MSCRATCH, MEPC, MCAUSE, MTVAL, MIP,
        MCYCLE, MINSTRET, MCYCLEH, MINSTRETH
    };

    assign csr_addr_supervisor = instruction[31:20] inside {
        SSTATUS, SEDELEG, SIDELEG, SIE, STVEC, SCOUNTEREN,
        SSCRATCH, SEPC, SCAUSE, STVAL, SIP,
        SATP
    };

    assign csr_addr_debug = instruction[31:20] inside {
        DCSR, DPC, DSCRATCH
    };

    //Privilege check done later on instruction issue
    //Here we just check instruction encoding and valid CSR address
    assign csr_legal = instruction inside {
        CSRRW, CSRRS, CSRRC, CSRRWI, CSRRSI, CSRRCI
    } && (
        csr_addr_base |
        (CONFIG.INCLUDE_M_MODE & csr_addr_machine) |
        (CONFIG.INCLUDE_S_MODE & csr_addr_supervisor)
    );

    assign mul_legal = instruction inside {
        MUL, MULH, MULHSU, MULHU
    };

    assign div_legal = instruction inside {
        DIV, DIVU, REM, REMU
    };

    assign ifence_legal = instruction inside {FENCE_I};

    assign amo_legal = instruction inside {
        AMO_ADD, AMO_XOR, AMO_OR, AMO_AND, AMO_MIN, AMO_MAX, AMO_MINU, AMO_MAXU, AMO_SWAP,
        LR, SC
    };

    assign machine_legal = instruction inside {
        MRET, ECALL, EBREAK
    };

    assign supervisor_legal = instruction inside {
        SRET, SFENCE_VMA, WFI
    };

    assign double_legal = instruction inside {
        DP_FLD, DP_FSD, DP_FMADD_D, DP_FMSUB_D, DP_FNMSUB_D, DP_FNMADD_D, DP_FADD_D, DP_FSUB_D, DP_FMUL_D, DP_FDIV_D, DP_FSQRT_D, DP_FSGNJ_D, DP_FSGNJN_D, DP_FSGNJX_D, DP_FMIN_D, DP_FMAX_D, DP_FCVT_W_D, DP_FCVT_WU_D, DP_FCVT_D_W, DP_FCVT_D_WU, DP_FEQ_D, DP_FLT_D, DP_FLE_D, DP_FLASS_D, DP_FCVT_S_D, DP_FCVT_D_S  
    };

    assign illegal_instruction = ~(
        base_legal |
        csr_legal |
        (CONFIG.INCLUDE_MUL & mul_legal) |
        (CONFIG.INCLUDE_DIV & div_legal) |
        (CONFIG.INCLUDE_AMO & amo_legal) |
        (CONFIG.INCLUDE_IFENCE & ifence_legal) |
        (CONFIG.INCLUDE_M_MODE & machine_legal) |
        (CONFIG.INCLUDE_S_MODE & supervisor_legal) |
        (CONFIG.FP.INCLUDE_FPU & double_legal)
    );

endmodule
