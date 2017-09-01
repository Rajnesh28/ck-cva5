/*
 * Copyright © 2017 Eric Matthews,  Lesley Shannon
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/.
 * 
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0.
 *
 * Initial code developed under the supervision of Dr. Lesley Shannon,
 * Reconfigurable Computing Lab, Simon Fraser University.
 *
 * Author(s):
 *             Eric Matthews <ematthew@sfu.ca>
 */
 
import l2_config_and_types::*;
import taiga_types::*;

module l2_arbiter (
        input logic clk,
        input logic rst,

        l2_requester_interface.arbiter request [L2_NUM_PORTS-1:0],
        l2_memory_interface.arbiter mem
        );

    l2_arbitration_interface arb();

    //FIFO interfaces
    l2_fifo_interface #(.DATA_WIDTH($bits(l2_request_t))) input_fifos [L2_NUM_PORTS-1:0]();
    l2_fifo_interface #(.DATA_WIDTH(32)) input_data_fifos [L2_NUM_PORTS-1:0]();
    l2_fifo_interface #(.DATA_WIDTH(30)) inv_response_fifos [L2_NUM_PORTS-1:0]();
    l2_fifo_interface #(.DATA_WIDTH(32 + L2_SUB_ID_W)) returndata_fifos [L2_NUM_PORTS-1:0]();


    l2_fifo_interface #(.DATA_WIDTH($bits(l2_mem_request_t))) mem_addr_fifo();
    l2_fifo_interface #(.DATA_WIDTH(32)) mem_data_fifo();

    l2_fifo_interface #(.DATA_WIDTH($bits(l2_data_attributes_t))) data_attributes();

    l2_fifo_interface #(.DATA_WIDTH(32 + L2_ID_W)) mem_returndata_fifo();


    logic advance;
    l2_request_t arb_request;
    l2_mem_request_t mem_request;

    logic reserv_valid;
    logic reserv_lr;
    logic reserv_sc;
    logic reserv_store;
    l2_request_t requests [L2_NUM_PORTS-1:0];
    l2_request_t reserv_request;
    logic [$clog2(L2_NUM_PORTS)-1:0] reserv_id;
    logic [L2_NUM_PORTS-1:0] reserv_id_v;

    logic write_done;
    logic [4:0] burst_count;
    l2_data_attributes_t new_attr;
    l2_data_attributes_t current_attr;

    logic [31:0] input_data [L2_NUM_PORTS-1:0];

    l2_mem_return_data_t mem_return_data;
    l2_return_data_t return_data  [L2_NUM_PORTS-1:0];
    logic [L2_NUM_PORTS-1:0] return_push;

    logic wr_clk, rd_clk;
    assign wr_clk = clk;
    assign rd_clk = clk;
    //Implementation
    //************************************

    /*************************************
     * Input Request FIFOs
     *************************************/
    genvar i;
    generate
        for (i=0; i < L2_NUM_PORTS; i++) begin
            //Requester FIFO side
            assign input_fifos[i].push = request[i].request_push;
            assign input_fifos[i].data_in = request[i].request;
            assign input_fifos[i].pop = input_fifos[i].valid & arb.grantee_v[i] & ~mem_addr_fifo.full;

            assign request[i].request_full =  input_fifos[i].full;

            //FIFO instantiation
            l2_fifo #(.DATA_WIDTH($bits(l2_request_t)), .FIFO_DEPTH(L2_INPUT_FIFO_DEPTHS[i]))  input_fifo (.*, .fifo(input_fifos[i]));

            //Arbiter FIFO side
            assign requests[i] = input_fifos[i].data_out;
            assign arb.requests[i] = input_fifos[i].valid;
        end
    endgenerate

    /*************************************
     * Input Data FIFOs
     *************************************/
    generate
        for (i=0; i < L2_NUM_PORTS; i++) begin
            //Requester FIFO side
            assign input_data_fifos[i].push = request[i].wr_data_push;
            assign input_data_fifos[i].data_in = request[i].wr_data;

            assign request[i].data_full =  input_data_fifos[i].full;

            //FIFO instantiation
            l2_fifo #(.DATA_WIDTH(32), .FIFO_DEPTH(L2_INPUT_FIFO_DEPTHS[i])) input_data_fifo (.*, .fifo(input_data_fifos[i]));

            //Arbiter FIFO side
            assign input_data_fifos[i].pop = (data_attributes.valid && (current_attr.id == i) && ~mem_data_fifo.full);

            assign input_data[i] = input_data_fifos[i].data_out;
        end
    endgenerate


    /*************************************
     * Arbitration
     *************************************/
    l2_round_robin rr (.*);

    assign advance = arb.grantee_valid & ~mem_addr_fifo.full;
    assign arb.strobe = advance;
    assign mem_addr_fifo.push = advance;
    assign mem_addr_fifo.pop = mem.request_pop;
    assign mem.request_valid = mem_addr_fifo.valid;

    assign arb_request = requests[arb.grantee_i];

    assign mem_request.addr =  arb_request.addr;
    assign mem_request.be =  arb_request.be;
    assign mem_request.rnw =  arb_request.rnw;
    assign mem_request.is_amo =  arb_request.is_amo;
    assign mem_request.amo_type_or_burst_size =  arb_request.amo_type_or_burst_size;
    assign mem_request.id = {arb.grantee_i, arb_request.sub_id};

    assign mem_addr_fifo.data_in = mem_request;
    assign mem.request = mem_addr_fifo.data_out;

    l2_fifo #(.DATA_WIDTH($bits(l2_mem_request_t)), .FIFO_DEPTH(L2_MEM_ADDR_FIFO_DEPTH))  input_fifo (.*, .fifo(mem_addr_fifo));


    /*************************************
     * Reservation Support
     *************************************/
    always_ff @(posedge clk) begin
        if (advance) begin
            reserv_request <= requests[arb.grantee_i];
            reserv_id <= arb.grantee_i;
            reserv_id_v <= arb.grantee_v;
        end
    end

    always_ff @(posedge clk) begin
        if (rst)
            reserv_valid <= 0;
        else
            reserv_valid <= advance;
    end

    assign reserv_lr = (reserv_request.is_amo && reserv_request.amo_type_or_burst_size == AMO_LR);
    assign reserv_sc = (reserv_request.is_amo && reserv_request.amo_type_or_burst_size == AMO_SC);
    assign reserv_store = ~reserv_request.rnw | (reserv_request.is_amo && reserv_request.amo_type_or_burst_size != AMO_LR);
    l2_reservation_logic reserv (.*,
            .addr(reserv_request.addr),
            .id(reserv_id),
            .strobe(reserv_valid),
            .lr (reserv_lr),
            .sc (reserv_sc),
            .store (reserv_store),
            .abort(mem.abort)
        );

    //sc response
    generate
        for (i=0; i < L2_NUM_PORTS; i++) begin
            always_ff @(posedge clk) begin
                if (rst)  begin
                    request[i].con_result <= 0;
                    request[i].con_valid <= 0;
                end
                else begin
                    request[i].con_result <= ~mem.abort;
                    request[i].con_valid <= reserv_sc & reserv_valid & reserv_id_v[i];
                end
            end
        end
    endgenerate

    //inv response
    generate
        for (i=0; i < L2_NUM_PORTS; i++) begin
            //Requester FIFO side
            assign inv_response_fifos[i].pop = request[i].inv_ack;
            assign request[i].inv_addr = inv_response_fifos[i].data_out;
            assign request[i].inv_valid = inv_response_fifos[i].valid;

            //FIFO instantiation
            l2_fifo #(.DATA_WIDTH(30), .FIFO_DEPTH(L2_INVALIDATION_FIFO_DEPTHS[i])) inv_response_fifo (.*, .fifo(inv_response_fifos[i]));
            //Arbiter side
            assign inv_response_fifos[i].push = reserv_valid & reserv_store  & ~reserv_id_v[i];
            assign inv_response_fifos[i].data_in = requests[i].addr;
        end
    endgenerate

    /*************************************
     * Data stage
     *************************************/
    assign new_attr.id = reserv_id;
    assign new_attr.burst_size = reserv_request.amo_type_or_burst_size;
    assign new_attr.abort = mem.abort;

    assign data_attributes.data_in = new_attr;
    assign data_attributes.push = reserv_valid & ~reserv_request.rnw & ~mem.abort;

    l2_fifo #(.DATA_WIDTH($bits(l2_data_attributes_t)), .FIFO_DEPTH(L2_DATA_ATTRIBUTES_FIFO_DEPTH))  data_attributes_fifo (.*, .fifo(data_attributes));

    assign data_attributes.pop = write_done;
    assign current_attr = data_attributes.data_out;

    always_ff @(posedge clk) begin
        if (rst)
            burst_count <= 0;
        else if (write_done)
            burst_count <= 0;
        else if (data_attributes.valid & ~mem_data_fifo.full)
            burst_count <= burst_count + 1;
    end

    assign write_done = data_attributes.valid & ~mem_data_fifo.full & (burst_count == current_attr.burst_size);

    l2_fifo #(.DATA_WIDTH($bits(32)), .FIFO_DEPTH(L2_MEM_ADDR_FIFO_DEPTH))  mem_data (.*, .fifo(mem_data_fifo));

    assign mem_data_fifo.push = data_attributes.valid & ~mem_data_fifo.full & ~current_attr.abort;
    assign mem_data_fifo.data_in = input_data[current_attr.id];

    assign mem.wr_data = mem_data_fifo.data_out;
    assign mem.wr_data_valid = mem_data_fifo.valid;
    assign mem_data_fifo.pop = mem.wr_data_read;


    /*************************************
     * Read response
     *************************************/
    l2_fifo # (.DATA_WIDTH(32 + L2_ID_W), .FIFO_DEPTH(L2_MEM_ADDR_FIFO_DEPTH))  mem_returndata (.*, .fifo(mem_returndata_fifo));
    assign mem_returndata_fifo.push = mem.rd_data_valid;
    assign mem_returndata_fifo.data_in = {mem.rd_id, mem.rd_data};
    assign mem_return_data = mem_returndata_fifo.data_out;
    assign mem_returndata_fifo.pop = mem_returndata_fifo.valid;

    always_comb begin
        return_push = '0;
        return_push[mem_return_data.id] = mem_returndata_fifo.valid;
    end

    generate
        for (i=0; i < L2_NUM_PORTS; i++) begin
            //Requester FIFO side
            assign returndata_fifos[i].pop = request[i].rd_data_ack;
            assign return_data[i] = returndata_fifos[i].data_out;
            assign request[i].rd_data =return_data[i].data;
            assign request[i].rd_sub_id = return_data[i].sub_id;
            assign request[i].rd_data_valid = returndata_fifos[i].valid;

            //FIFO instantiation
            l2_fifo #(.DATA_WIDTH(32 + L2_SUB_ID_W), .FIFO_DEPTH(L2_READ_RETURN_FIFO_DEPTHS[i])) returndata_fifo (.*, .fifo(returndata_fifos[i]));
            //Arbiter side
            assign returndata_fifos[i].push = return_push[i];
            assign returndata_fifos[i].data_in = {mem_return_data.sub_id, mem_return_data.data};
        end
    endgenerate

endmodule


