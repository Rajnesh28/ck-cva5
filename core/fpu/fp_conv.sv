/*
 * Copyright © 2023 Chris Keilbart, Lesley Shannon
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
 *             Chris Keilbart <ckeilbar@sfu.ca>
 */

module fp_conv
    import taiga_config::*;
    import fpu_types::*;

(
    input logic clk,
    unit_issue_interface.unit issue,
    input fp_conv_inputs_t fp_conv_inputs,
    input logic single,
    fp_intermediate_wb_interface.unit wb
);

    assign wb.rd = fp_conv_inputs.rs1;
    assign wb.hidden = fp_conv_inputs.hidden; //Prevents normalization from declaring underflow
    assign wb.done = issue.new_request;
    assign wb.id = issue.id;
    assign wb.d2s = single;
    assign wb.fflags = {fp_conv_inputs.invalid, 3'b0, fp_conv_inputs.inexact};
endmodule
