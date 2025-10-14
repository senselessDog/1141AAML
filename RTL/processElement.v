module PE(
    i,
    j,
    clk,
    reset,
    busy,
    block_over,
    datain_h,
    datain_v,
    rd_macc_en,

    dataout_h,
    dataout_v,
    maccout,
);
    input [2:0] i;
    input [2:0] j;
    input clk;
    input reset;
    input busy;
    input block_over;
    input [7:0] datain_h;
    input [7:0] datain_v;
    input rd_macc_en;

    output reg [7:0] dataout_h;
    output reg [7:0] dataout_v;
    output reg [31:0] maccout;

    reg [31:0] mul_res;
    reg [31:0] macc;
    reg [7:0] datain_h_c;
    reg [7:0] datain_v_c;

    always @(negedge reset or negedge busy or posedge block_over) begin
        macc = 0;
    end

    always @(negedge clk) begin
        if(datain_h >= 0) begin
            mul_res = datain_h * datain_v;
            macc += mul_res;
            datain_h_c = datain_h;
            datain_v_c = datain_v;
        end
    end

    always @(posedge clk) begin
        dataout_h <= datain_h_c;
        dataout_v <= datain_v_c;
    end

    always @(posedge rd_macc_en) begin
        maccout <= macc;
    end

endmodule