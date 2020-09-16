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

module load_store_queue //ID-based input buffer for Load/Store Unit

    import taiga_config::*;
    import riscv_types::*;
    import taiga_types::*;

    (
        input logic clk,
        input logic rst,
        input logic gc_fetch_flush,
        input logic gc_issue_flush,

        load_store_queue_interface.queue lsq,
        //Writeback snooping
        input wb_packet_t wb_snoop,

        //Writeback release
        input id_t ids_released [COMMIT_PORTS],
        input logic wb_released [COMMIT_PORTS],
        output logic tr_possible_load_conflict_delay
    );
    localparam SQ_DEPTH = 4;
    addr_hash_t addr_hash;

    lq_entry_t lq_entry;
    logic [SQ_DEPTH-1:0] potential_store_conflicts;
    logic load_ack;
    logic lq_output_valid;

    logic sq_full;
    logic sq_empty;
    sq_entry_t sq_entry;
    logic [31:0] sq_data;
    logic store_conflict;
    logic store_ack;
    logic sq_output_valid;

    ////////////////////////////////////////////////////
    //Implementation

    //Can accept requests so long as store queue is not needed or is not full
    assign lsq.ready = lsq.load | (~sq_full);


    //Address hash for load-store collision checking
    addr_hash lsq_addr_hash (
        .clk (clk),
        .rst (rst | gc_issue_flush),
        .addr (lsq.addr),
        .addr_hash (addr_hash)
    );

    load_queue #(.SQ_DEPTH(SQ_DEPTH)) lq_block (
        .clk (clk),
        .rst (rst | gc_issue_flush),
        .lsq (lsq),
        .lq_entry (lq_entry),
        .potential_store_conflicts (potential_store_conflicts),
        .load_ack (load_ack),
        .lq_output_valid (lq_output_valid)
    );


    store_queue #(.DEPTH(SQ_DEPTH)) sq_block (
        .clk (clk),
        .rst (rst | gc_issue_flush),
        .lsq (lsq),
        .sq_empty (sq_empty),
        .sq_full (sq_full),
        .addr_hash (addr_hash),
        .potential_store_conflicts (potential_store_conflicts),
        .load_issued (load_ack),
        .prev_store_conflicts (lq_entry.potential_store_conflicts),
        .store_conflict (store_conflict),
        .sq_entry (sq_entry),
        .sq_data (sq_data),
        .wb_snoop (wb_snoop),
        .ids_released (ids_released),
        .wb_released (wb_released),
        .store_ack (store_ack),
        .sq_output_valid (sq_output_valid)
    );

    ////////////////////////////////////////////////////
    //Output
    logic load_selected;

    //Priority is for loads over stores.
    //A store will be selected only if either no loads are ready, OR if the store queue is full and a store is ready
    assign load_selected = lq_output_valid & ~store_conflict & ~(sq_full & sq_output_valid);

    assign lsq.transaction_ready = (lq_output_valid & ~store_conflict) | sq_output_valid;
    assign load_ack = lsq.accepted & load_selected;
    assign store_ack = lsq.accepted & ~load_selected;

    assign lsq.transaction_out.addr = load_selected ? lq_entry.addr : sq_entry.addr;
    assign lsq.transaction_out.load = load_selected;
    assign lsq.transaction_out.store = ~load_selected;
    assign lsq.transaction_out.be = load_selected ? '0 : sq_entry.be;
    assign lsq.transaction_out.fn3 = load_selected ? lq_entry.fn3 : sq_entry.fn3;
    assign lsq.transaction_out.data_in = sq_data;
    assign lsq.transaction_out.id = lq_entry.id;

    assign lsq.empty = ~lq_output_valid & sq_empty;

    ////////////////////////////////////////////////////
    //End of Implementation
    ////////////////////////////////////////////////////

    ////////////////////////////////////////////////////
    //Assertions

    ////////////////////////////////////////////////////
    //Trace Interface
    generate if (ENABLE_TRACE_INTERFACE) begin
        assign tr_possible_load_conflict_delay = lq_output_valid & store_conflict;
    end
    endgenerate

endmodule
