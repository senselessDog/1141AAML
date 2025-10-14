module BE(
    clk,
    reset,
    busy,
    block_over,
    datain,
    dataout
);
    input clk;
    input reset;
    input busy;
    input block_over;
    input [7:0] datain;

    reg [7:0] datain_c;

    output reg [7:0] dataout;

    always @(negedge reset or negedge busy or posedge block_over) begin
        datain_c = 0;
    end

    always @(posedge clk) begin
        datain_c <= datain;
    end
    
    always @(negedge clk) begin
        dataout <= datain_c;
    end
    
endmodule