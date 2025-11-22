// Copyright 2021 The CFU-Playground Authors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

`include "RTL/global_buffer_bram.v"
`include "RTL/TPU.v"

module Cfu (
  input               cmd_valid,
  output              cmd_ready,
  input      [9:0]    cmd_payload_function_id,
  input      [31:0]   cmd_payload_inputs_0,
  input      [31:0]   cmd_payload_inputs_1,
  output              rsp_valid,
  input               rsp_ready,
  output     [31:0]   rsp_payload_outputs_0,
  input               reset,
  input               clk
);

  // CFU Operation Definitions
  // funct3 = 0: Write to Global Buffer A (inputs_0 = address, inputs_1 = data)
  // funct3 = 1: Write to Global Buffer B (inputs_0 = address, inputs_1 = data)
  // funct3 = 2: Start TPU computation (inputs_0 = K, M, inputs_1 = N)
  // funct3 = 3: Read busy status (return busy flag)
  // funct3 = 4: Read from Global Buffer C (inputs_0 = address, return data[31:0])
  // funct3 = 5: Read from Global Buffer C upper (inputs_0 = address, return data[63:32])
  // funct3 = 6: Read from Global Buffer C upper2 (inputs_0 = address, return data[95:64])
  // funct3 = 7: Read from Global Buffer C upper3 (inputs_0 = address, return data[127:96])

  // TPU signals
  wire        tpu_busy;
  wire        tpu_in_valid;
  wire [7:0]  tpu_K, tpu_M, tpu_N;
  
  // Global Buffer A signals
  wire        gbuff_A_wr_en;
  wire [15:0] gbuff_A_index;
  wire [31:0] gbuff_A_data_in;
  wire [31:0] gbuff_A_data_out;
  
  // Global Buffer B signals
  wire        gbuff_B_wr_en;
  wire [15:0] gbuff_B_index;
  wire [31:0] gbuff_B_data_in;
  wire [31:0] gbuff_B_data_out;
  
  // Global Buffer C signals
  wire        gbuff_C_wr_en;
  wire [15:0] gbuff_C_index;
  wire [127:0] gbuff_C_data_in;
  wire [127:0] gbuff_C_data_out;

  // CFU control signals
  reg         cfu_A_wr_en;
  reg [15:0]  cfu_A_index;
  reg [31:0]  cfu_A_data_in;
  
  reg         cfu_B_wr_en;
  reg [15:0]  cfu_B_index;
  reg [31:0]  cfu_B_data_in;
  
  reg [15:0]  cfu_C_index;
  
  reg         start_tpu;
  reg [7:0]   matrix_K, matrix_M, matrix_N;

  // Handshaking - simple for now, can be enhanced if TPU needs time
  assign cmd_ready = rsp_ready;
  assign rsp_valid = cmd_valid;

  // Mux control for global buffers
  assign gbuff_A_wr_en = tpu_busy ? tpu_A_wr_en : cfu_A_wr_en;
  assign gbuff_A_index = tpu_busy ? tpu_A_index : cfu_A_index;
  assign gbuff_A_data_in = tpu_busy ? tpu_A_data_in : cfu_A_data_in;
  
  assign gbuff_B_wr_en = tpu_busy ? tpu_B_wr_en : cfu_B_wr_en;
  assign gbuff_B_index = tpu_busy ? tpu_B_index : cfu_B_index;
  assign gbuff_B_data_in = tpu_busy ? tpu_B_data_in : cfu_B_data_in;
  
  assign gbuff_C_index = tpu_busy ? tpu_C_index : cfu_C_index;

  // TPU control
  assign tpu_in_valid = start_tpu;
  assign tpu_K = matrix_K;
  assign tpu_M = matrix_M;
  assign tpu_N = matrix_N;

  // TPU wires for connection
  wire        tpu_A_wr_en;
  wire [15:0] tpu_A_index;
  wire [31:0] tpu_A_data_in;
  
  wire        tpu_B_wr_en;
  wire [15:0] tpu_B_index;
  wire [31:0] tpu_B_data_in;
  
  wire        tpu_C_wr_en;
  wire [15:0] tpu_C_index;
  wire [127:0] tpu_C_data_in;

  // Response output mux based on function_id
  reg [31:0] response_data;
  
  always @(*) begin
    case (cmd_payload_function_id[2:0])
      3'd3: response_data = {31'd0, tpu_busy};  // Read busy status
      3'd4: response_data = gbuff_C_data_out[31:0];   // Read C[31:0]
      3'd5: response_data = gbuff_C_data_out[63:32];  // Read C[63:32]
      3'd6: response_data = gbuff_C_data_out[95:64];  // Read C[95:64]
      3'd7: response_data = gbuff_C_data_out[127:96]; // Read C[127:96]
      default: response_data = 32'd0;
    endcase
  end
  
  assign rsp_payload_outputs_0 = response_data;

  // CFU command decoder
  always @(posedge clk) begin
    if (reset) begin
      cfu_A_wr_en <= 1'b0;
      cfu_A_index <= 16'd0;
      cfu_A_data_in <= 32'd0;
      cfu_B_wr_en <= 1'b0;
      cfu_B_index <= 16'd0;
      cfu_B_data_in <= 32'd0;
      cfu_C_index <= 16'd0;
      start_tpu <= 1'b0;
      matrix_K <= 8'd0;
      matrix_M <= 8'd0;
      matrix_N <= 8'd0;
    end else begin
      // Default values
      cfu_A_wr_en <= 1'b0;
      cfu_B_wr_en <= 1'b0;
      start_tpu <= 1'b0;
      
      if (cmd_valid && cmd_ready) begin
        case (cmd_payload_function_id[2:0])
          3'd0: begin  // Write to Global Buffer A
            cfu_A_wr_en <= 1'b1;
            cfu_A_index <= cmd_payload_inputs_0[15:0];
            cfu_A_data_in <= cmd_payload_inputs_1;
          end
          3'd1: begin  // Write to Global Buffer B
            cfu_B_wr_en <= 1'b1;
            cfu_B_index <= cmd_payload_inputs_0[15:0];
            cfu_B_data_in <= cmd_payload_inputs_1;
          end
          3'd2: begin  // Start TPU
            matrix_K <= cmd_payload_inputs_0[7:0];
            matrix_M <= cmd_payload_inputs_0[15:8];
            matrix_N <= cmd_payload_inputs_1[7:0];
            start_tpu <= 1'b1;
          end
          3'd3: begin  // Read busy status - no action needed
          end
          3'd4, 3'd5, 3'd6, 3'd7: begin  // Read from Global Buffer C
            cfu_C_index <= cmd_payload_inputs_0[15:0];
          end
        endcase
      end
    end
  end

  // Instantiate Global Buffer A (for matrix A data)
  // 64 entries, each 32 bits (4 int8 values)
  global_buffer_bram #(
    .ADDR_BITS(6),   // 2^6 = 64 entries
    .DATA_BITS(32)
  ) gbuff_A (
    .clk(clk),
    .rst_n(~reset),
    .ram_en(1'b1),
    .wr_en(gbuff_A_wr_en),
    .index(gbuff_A_index[5:0]),
    .data_in(gbuff_A_data_in),
    .data_out(gbuff_A_data_out)
  );

  // Instantiate Global Buffer B (for matrix B data)
  // 64 entries, each 32 bits (4 int8 values)
  global_buffer_bram #(
    .ADDR_BITS(6),   // 2^6 = 64 entries
    .DATA_BITS(32)
  ) gbuff_B (
    .clk(clk),
    .rst_n(~reset),
    .ram_en(1'b1),
    .wr_en(gbuff_B_wr_en),
    .index(gbuff_B_index[5:0]),
    .data_in(gbuff_B_data_in),
    .data_out(gbuff_B_data_out)
  );

  // Instantiate Global Buffer C (for matrix C results)
  // 64 entries, each 128 bits (4 int32 values)
  global_buffer_bram #(
    .ADDR_BITS(6),   // 2^6 = 64 entries
    .DATA_BITS(128)
  ) gbuff_C (
    .clk(clk),
    .rst_n(~reset),
    .ram_en(1'b1),
    .wr_en(gbuff_C_wr_en),
    .index(gbuff_C_index[5:0]),
    .data_in(gbuff_C_data_in),
    .data_out(gbuff_C_data_out)
  );

  // Instantiate TPU
  TPU tpu_inst (
    .clk(clk),
    .rst_n(~reset),
    .in_valid(tpu_in_valid),
    .K(tpu_K),
    .M(tpu_M),
    .N(tpu_N),
    .busy(tpu_busy),
    .A_wr_en(tpu_A_wr_en),
    .A_index(tpu_A_index),
    .A_data_in(tpu_A_data_in),
    .A_data_out(gbuff_A_data_out),
    .B_wr_en(tpu_B_wr_en),
    .B_index(tpu_B_index),
    .B_data_in(tpu_B_data_in),
    .B_data_out(gbuff_B_data_out),
    .C_wr_en(gbuff_C_wr_en),
    .C_index(tpu_C_index),
    .C_data_in(gbuff_C_data_in),
    .C_data_out(gbuff_C_data_out)
  );

endmodule
