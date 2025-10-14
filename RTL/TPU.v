
`include "sysArray.v"
`include "controller.v"
`include "buffer.v"
module TPU(
    clk,
    rst_n,

    in_valid,
    K,
    M,
    N,
    busy,

    A_wr_en,
    A_index,
    A_data_in,
    A_data_out,

    B_wr_en,
    B_index,
    B_data_in,
    B_data_out,

    C_wr_en,
    C_index,
    C_data_in,
    C_data_out
);


input clk;
input rst_n;
input            in_valid;
input [7:0]      K;
input [7:0]      M;
input [7:0]      N;
output  reg      busy;

output           A_wr_en;
output [15:0]    A_index;
output [31:0]    A_data_in;
input  [31:0]    A_data_out;  //* to get this in the next cycle

output           B_wr_en;
output [15:0]    B_index;
output [31:0]    B_data_in;
input  [31:0]    B_data_out;  //* to get this in the next cycle

output           C_wr_en;
output [15:0]    C_index;    //* select this
output [127:0]   C_data_in;  //* to write the results to here in the same cycle
input  [127:0]   C_data_out;



//* Implement your design here

assign A_wr_en = 0;
assign B_wr_en = 0;
assign C_wr_en = 1;

reg [7:0] k;
reg [7:0] m;
reg [7:0] n;

output [7:0] cur_block_B;
output [31:0] delayed_A_data_out;
output [31:0] delayed_B_data_out;

output busy_c;
output block_over;  // for sysArr to tell controller that the current block pair is finished
output finish;  // for controller to tell sysArr that the data feeding is finished

controller controller(
    .clk (clk),
    .reset (rst_n),
    .block_over (block_over),
    .finish (finish),
    .K   (k),
    .M   (m),
    .N   (n),
    .cur_block_B (cur_block_B),
    .A_index (A_index),
    .B_index (B_index),
    .busy (busy_c)
);

buffer bufferA(
    .clk (clk),
    .reset (rst_n),
    .busy (busy),
    .block_over (block_over),
    .datain (A_data_out),
    .dataout (delayed_A_data_out)
);

buffer bufferB(
    .clk (clk),
    .reset (rst_n),
    .busy (busy),
    .block_over (block_over),
    .datain (B_data_out),
    .dataout (delayed_B_data_out)
);

sysArr sysArr(
    .clk (clk),
    .reset (rst_n),
    .block_over (block_over),
    .finish (finish),
    .K (k),
    .M (m),
    .cur_block_B (cur_block_B),
    .datain_h (delayed_A_data_out),
    .datain_v (delayed_B_data_out),
    .C_index (C_index),
    .C_data_in (C_data_in),
    .busy (busy_c)
);


initial begin
    busy = 0;
end

always @(negedge clk) begin
    busy <= busy_c;
end

always @(negedge clk) begin
    if(K > 0) begin
        k = K;
        m = M;
        n = N;
    end
end

endmodule













