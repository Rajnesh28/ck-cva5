/*
 * Copyright © 2022 Eric Matthews, Lesley Shannon
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

module litex_wrapper
    import cva5_config::*;
    import cva5_types::*;

    #(
        parameter bit [31:0] RESET_VEC = 0,
        parameter bit [31:0] NON_CACHABLE_L = 32'h80000000,
        parameter bit [31:0] NON_CACHABLE_H = 32'hFFFFFFFF,
        parameter int unsigned NUM_CORES = 1
    )
    (
        input logic clk,
        input logic rst,

        input logic [NUM_CORES-1:0] meip,
        input logic [NUM_CORES-1:0] seip,
        input logic [NUM_CORES-1:0] mtip,
        input logic [NUM_CORES-1:0] msip,
        input logic [63:0] mtime,

        output logic [29:0] idbus_adr,
        output logic [31:0] idbus_dat_w,
        output logic [3:0] idbus_sel,
        output logic idbus_cyc,
        output logic idbus_stb,
        output logic idbus_we,
        output logic idbus_cti,
        output logic idbus_bte,
        input logic [31:0] idbus_dat_r,
        input logic idbus_ack,
        input logic idbus_err,

        //ABACUS
        output logic [31:0] abacus_instruction,
        output logic abacus_instruction_issued,
        
        output logic abacus_icache_request,
        output logic abacus_icache_miss,
        output logic abacus_icache_line_fill_in_progress,

        output logic abacus_dcache_request,
        output logic abacus_dcache_hit,
        output logic abacus_dcache_line_fill_in_progress,

        output logic abacus_branch_misprediction,
        output logic abacus_ras_misprediction,

        //Issue stage stall determination
        output logic abacus_issue_no_instruction_stat,
        output logic abacus_issue_no_id_stat,
        output logic abacus_issue_flush_stat,
        output logic abacus_unit_busy_stat,
        output logic abacus_issue_operands_not_ready_stat,
        output logic abacus_issue_hold_stat,
        output logic abacus_issue_multi_source_stat
    );

    localparam wb_group_config_t STANDARD_WB_GROUP_CONFIG = '{
        0 : '{0: ALU_ID, default : NON_WRITEBACK_ID},
        1 : '{0: LS_ID, default : NON_WRITEBACK_ID},
        2 : '{0: MUL_ID, 1: DIV_ID, 2: CSR_ID, 3: CUSTOM_ID, default : NON_WRITEBACK_ID},
        default : '{default : NON_WRITEBACK_ID}
    };

    //Unused interfaces
    axi_interface m_axi[NUM_CORES-1:0]();
    avalon_interface m_avalon[NUM_CORES-1:0]();
    wishbone_interface dwishbone[NUM_CORES-1:0]();
    wishbone_interface iwishbone[NUM_CORES-1:0]();
    local_memory_interface instruction_bram[NUM_CORES-1:0]();
    local_memory_interface data_bram[NUM_CORES-1:0]();

    //Interrupts
    interrupt_t[NUM_CORES-1:0] s_interrupt;
    interrupt_t[NUM_CORES-1:0] m_interrupt;

    //Memory interfaces for each core
    mem_interface mem[NUM_CORES-1:0]();

    //Final memory interface
    wishbone_interface idwishbone();

    //Mux requests from one or more cores onto the wishbone bus
    wishbone_adapter #(.NUM_CORES(NUM_CORES)) wb_adapter (
        .mems(mem),
        .wishbone(idwishbone),
    .*);

    generate for (genvar i = 0; i < NUM_CORES; i++) begin : gen_cores
        localparam cpu_config_t STANDARD_CONFIG_I = '{
            //ISA options
            MODES : MSU,
            INCLUDE_UNIT : '{
                ALU : 1,
                LS : 1,
                MUL : 1,
                DIV : 1,
                CSR : 1,
                FPU : 0,
                CUSTOM : 0,
                BR : 1,
                GC : 1
            },
            INCLUDE_IFENCE : 1,
            INCLUDE_AMO : 1,
            INCLUDE_CBO : 0,
            //CSR constants
            CSRS : '{
                MACHINE_IMPLEMENTATION_ID : 0,
                CPU_ID : i,
                RESET_VEC : RESET_VEC,
                RESET_TVEC : 32'h00000000,
                MCONFIGPTR : '0,
                INCLUDE_ZICNTR : 1,
                INCLUDE_ZIHPM : 1,
                INCLUDE_SSTC : 1,
                INCLUDE_SMSTATEEN : 1
            },
            //Memory Options
            SQ_DEPTH : 4,
            INCLUDE_FORWARDING_TO_STORES : 1,
            AMO_UNIT : '{
                LR_WAIT : 8,
                RESERVATION_WORDS : 8
            },
            INCLUDE_ICACHE : 1,
            ICACHE_ADDR : '{
                L : 32'h00000000,
                H : 32'h7FFFFFFF
            },
            ICACHE : '{
                LINES : 512,
                LINE_W : 8,
                WAYS : 2,
                USE_EXTERNAL_INVALIDATIONS : 1,
                USE_NON_CACHEABLE : 0,
                NON_CACHEABLE : '{
                    L: NON_CACHABLE_L,
                    H: NON_CACHABLE_H
                }
            },
            ITLB : '{
                WAYS : 2,
                DEPTH : 64
            },
            INCLUDE_DCACHE : 1,
            DCACHE_ADDR : '{
                L : 32'h00000000,
                H : 32'hFFFFFFFF
            },
            DCACHE : '{
                LINES : 512,
                LINE_W : 8,
                WAYS : 2,
                USE_EXTERNAL_INVALIDATIONS : 1,
                USE_NON_CACHEABLE : 1,
                NON_CACHEABLE : '{
                    L: NON_CACHABLE_L,
                    H: NON_CACHABLE_H
                }
            },
            DTLB : '{
                WAYS : 2,
                DEPTH : 64
            },
            INCLUDE_ILOCAL_MEM : 0,
            ILOCAL_MEM_ADDR : '{
                L : 32'h80000000,
                H : 32'h8FFFFFFF
            },
            INCLUDE_DLOCAL_MEM : 0,
            DLOCAL_MEM_ADDR : '{
                L : 32'h80000000,
                H : 32'h8FFFFFFF
            },
            INCLUDE_IBUS : 0,
            IBUS_ADDR : '{
                L : 32'h00000000,
                H : 32'hFFFFFFFF
            },
            INCLUDE_PERIPHERAL_BUS : 0,
            PERIPHERAL_BUS_ADDR : '{
                L : 32'h00000000,
                H : 32'hFFFFFFFF
            },
            PERIPHERAL_BUS_TYPE : WISHBONE_BUS,
            //Branch Predictor Options
            INCLUDE_BRANCH_PREDICTOR : 1,
            BP : '{
                WAYS : 2,
                ENTRIES : 512,
                RAS_ENTRIES : 8
            },
            //Writeback Options
            NUM_WB_GROUPS : 3,
            WB_GROUP : STANDARD_WB_GROUP_CONFIG
        };

        assign m_interrupt[i].software = msip[i];
        assign m_interrupt[i].timer = mtip[i];
        assign m_interrupt[i].external = meip[i];
        assign s_interrupt[i].software = 0; //Not possible
        assign s_interrupt[i].timer = 0; //Internal
        assign s_interrupt[i].external = seip[i];

        cva5 #(.CONFIG(STANDARD_CONFIG_I)) cpu(
            .instruction_bram(instruction_bram[i]),
            .data_bram(data_bram[i]),
            .m_axi(m_axi[i]),
            .m_avalon(m_avalon[i]),
            .dwishbone(dwishbone[i]),
            .iwishbone(iwishbone[i]),
            .mem(mem[i]),
            .mtime(mtime),
            .s_interrupt(s_interrupt[i]),
            .m_interrupt(m_interrupt[i]),

            //ABACUS
            .abacus_instruction_issued(abacus_instruction_issued),
            .abacus_instruction(abacus_instruction),
            
            .abacus_icache_request(abacus_icache_request),
            .abacus_icache_miss(abacus_icache_miss),
            .abacus_icache_line_fill_in_progress(abacus_icache_line_fill_in_progress),

            .abacus_dcache_request(abacus_dcache_request),
            .abacus_dcache_hit(abacus_dcache_hit),
            .abacus_dcache_line_fill_in_progress(abacus_dcache_line_fill_in_progress),

            .abacus_branch_misprediction(abacus_branch_misprediction),
            .abacus_ras_misprediction(abacus_ras_misprediction),
            
            .abacus_issue_no_instruction_stat(abacus_issue_no_instruction_stat),
            .abacus_issue_no_id_stat(abacus_issue_no_id_stat),
            .abacus_issue_flush_stat(abacus_issue_flush_stat),
            .abacus_unit_busy_stat(abacus_unit_busy_stat),
            .abacus_issue_operands_not_ready_stat(abacus_issue_operands_not_ready_stat),
            .abacus_issue_hold_stat(abacus_issue_hold_stat),
            .abacus_issue_multi_source_stat(abacus_issue_multi_source_stat),
        .*);
    end endgenerate

    assign idbus_adr = idwishbone.adr;
    assign idbus_dat_w = idwishbone.dat_w;
    assign idbus_sel = idwishbone.sel;
    assign idbus_cyc = idwishbone.cyc;
    assign idbus_stb = idwishbone.stb;
    assign idbus_we = idwishbone.we;
    assign idbus_cti = idwishbone.cti;
    assign idbus_bte = idwishbone.bte;
    assign idwishbone.dat_r = idbus_dat_r;
    assign idwishbone.ack = idbus_ack;
    assign idwishbone.err = idbus_err;

endmodule
