// ============================================================================ //
// File: buffer.v (CORRECTED: Uses rst_n)
// ============================================================================ //
`include "bufferElement.v"

module buffer(
    clk,
    reset,
    busy,
    block_over,
    datain,
    dataout
);
    parameter wh = 4;
    input clk;
    input reset;
    input busy;
    input block_over;

    input [31:0] datain;
    output [31:0] dataout;
    wire [((wh-1) * wh * 8)-1:0] data_inter;

    genvar i, j;
    generate
        for(i=0; i<4; i=i+1) begin
            for(j=0; j<4; j=j+1) begin
                if(i+j == 3) begin
                    if(j == 3) begin
                        BE be(
                            .clk (clk),
                            .reset (reset),
                            .busy (busy),
                            .block_over (block_over),
                            .datain (datain[(j+1)*8-1:j*8]),
                            .dataout (dataout[31:24])
                        );
                    end
                    else begin
                        BE be(
                            .clk (clk),
                            .reset (reset),
                            .busy (busy),
                            .block_over (block_over),
                            .datain (datain[(j+1)*8-1:j*8]),
                            .dataout (data_inter[(3*i+j+1)*8-1:(3*i+j)*8])
                        );
                    end
                end
                else begin
                    if(j == 3) begin
                        BE be(
                            .clk (clk),
                            .reset (reset),
                            .busy (busy),
                            .block_over (block_over),
                            .datain (data_inter[(3*i+j)*8-1:(3*i+j-1)*8]),
                            .dataout (dataout[(3-i+1)*8-1:(3-i)*8])
                        );
                    end
                    else if(j == 0) begin
                        BE be(
                            .clk (clk),
                            .reset (reset),
                            .busy (busy),
                            .block_over (block_over),
                            .datain (8'd0),
                            .dataout (data_inter[(3*i+j+1)*8-1:(3*i+j)*8])
                        );
                    end
                    else begin
                        BE be(
                            .clk (clk),
                            .reset (reset),
                            .busy (busy),
                            .block_over (block_over),
                            .datain (data_inter[(3*i+j)*8-1:(3*i+j-1)*8]),
                            .dataout (data_inter[(3*i+j+1)*8-1:(3*i+j)*8])
                        );
                    end
                end
            end
        end
    endgenerate


endmodule