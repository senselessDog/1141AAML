// ============================================================================ //
// File: sysArray.v (CORRECTED: Uses rst_n and robust reset logic)
// ============================================================================ //
`include "processElement.v"

module sysArr(
    clk,
    reset,
    busy,
    block_over,,
    finish,
    K,
    M,
    cur_block_B,
    datain_h,
    datain_v,
    C_index,
    C_data_in
);
    parameter wh = 4;
    input clk;
    input reset;
    input finish;
    input [7:0] K;
    input [7:0] M;
    input [7:0] cur_block_B;
    input [8*wh-1:0] datain_h;
    input [8*wh-1:0] datain_v;

    // Interconnection
    wire [((wh-1) * wh * 8)-1:0] datain_h_inter;
    wire [((wh-1) * wh * 8)-1:0] datain_v_inter;

    output reg busy;
    output reg block_over;
    output reg [15:0] macc_wr;
    output [15:0] C_index;
    output reg [127:0] C_data_in;
    output [511:0] C_data_in_c;

    reg signed [15:0] count;
    reg signed [15:0] accumu_index;
    reg [7:0] row;
    assign C_index = accumu_index;

    genvar i, j;
    generate
        for(i=0; i<4; i=i+1) begin
            for(j=0; j<4; j=j+1) begin
                if(i > 0 && i < 3 && j > 0 && j < 3) begin
                    PE pe(
                        .i (i[2:0]),
                        .j (j[2:0]),
                        .clk (clk),
                        .reset (reset),
                        .busy (busy),
                        .block_over (block_over),
                        .datain_h (datain_h_inter[(3*i+j)*8-1:(3*i+j-1)*8]),
                        .datain_v (datain_v_inter[(4*i+j-3)*8-1:(4*i+j-4)*8]),
                        .rd_macc_en (macc_wr[4*i+j]),
                        .dataout_h (datain_h_inter[(3*i+j+1)*8-1:(3*i+j)*8]),
                        .dataout_v (datain_v_inter[(4*i+j+1)*8-1:(4*i+j)*8]),
                        .maccout (C_data_in_c[128*i-32*j+127:128*i-32*j+96])
                    );
                end
                else if(i == 0) begin
                    if(j == 0) begin
                        PE pe(
                            .i (i[2:0]),
                            .j (j[2:0]),
                            .clk (clk),
                            .reset (reset),
                            .busy (busy),
                            .block_over (block_over),
                            .datain_h (datain_h[31:24]),
                            .datain_v (datain_v[31:24]),
                            .rd_macc_en (macc_wr[4*i+j]),
                            .dataout_h (datain_h_inter[(3*i+j+1)*8-1:(3*i+j)*8]),
                            .dataout_v (datain_v_inter[(4*i+j+1)*8-1:(4*i+j)*8]),
                            .maccout (C_data_in_c[128*i-32*j+127:128*i-32*j+96])
                        );
                    end
                    else if(j == 3) begin
                        PE pe(
                            .i (i[2:0]),
                            .j (j[2:0]),
                            .clk (clk),
                            .reset (reset),
                            .busy (busy),
                            .block_over (block_over),
                            .datain_h (datain_h_inter[(3*i+j)*8-1:(3*i+j-1)*8]),
                            .datain_v (datain_v[7:0]),
                            .rd_macc_en (macc_wr[4*i+j]),
                            .dataout_h (),
                            .dataout_v (datain_v_inter[(4*i+j+1)*8-1:(4*i+j)*8]),
                            .maccout (C_data_in_c[128*i-32*j+127:128*i-32*j+96])
                        );
                    end
                    else begin
                        PE pe(
                            .i (i[2:0]),
                            .j (j[2:0]),
                            .clk (clk),
                            .reset (reset),
                            .busy (busy),
                            .block_over (block_over),
                            .datain_h (datain_h_inter[(3*i+j)*8-1:(3*i+j-1)*8]),
                            .datain_v (datain_v[(3-j+1)*8-1:(3-j)*8]),
                            .rd_macc_en (macc_wr[4*i+j]),
                            .dataout_h (datain_h_inter[(3*i+j+1)*8-1:(3*i+j)*8]),
                            .dataout_v (datain_v_inter[(4*i+j+1)*8-1:(4*i+j)*8]),
                            .maccout (C_data_in_c[128*i-32*j+127:128*i-32*j+96])
                        );
                    end
                end
                else if(i == 3) begin
                    if(j == 0) begin
                        PE pe(
                            .i (i[2:0]),
                            .j (j[2:0]),
                            .clk (clk),
                            .reset (reset),
                            .busy (busy),
                            .block_over (block_over),
                            .datain_h (datain_h[7:0]),
                            .datain_v (datain_v_inter[(4*i+j-3)*8-1:(4*i+j-4)*8]),
                            .rd_macc_en (macc_wr[4*i+j]),
                            .dataout_h (datain_h_inter[(3*i+j+1)*8-1:(3*i+j)*8]),
                            .dataout_v (),
                            .maccout (C_data_in_c[128*i-32*j+127:128*i-32*j+96])
                        );
                    end
                    else if(j == 3) begin
                        PE pe(
                            .i (i[2:0]),
                            .j (j[2:0]),
                            .clk (clk),
                            .reset (reset),
                            .busy (busy),
                            .block_over (block_over),
                            .datain_h (datain_h_inter[(3*i+j)*8-1:(3*i+j-1)*8]),
                            .datain_v (datain_v_inter[(4*i+j-3)*8-1:(4*i+j-4)*8]),
                            .rd_macc_en (macc_wr[4*i+j]),
                            .dataout_h (),
                            .dataout_v (),
                            .maccout (C_data_in_c[128*i-32*j+127:128*i-32*j+96])
                        );
                    end
                    else begin
                        PE pe(
                            .i (i[2:0]),
                            .j (j[2:0]),
                            .clk (clk),
                            .reset (reset),
                            .busy (busy),
                            .block_over (block_over),
                            .datain_h (datain_h_inter[(3*i+j)*8-1:(3*i+j-1)*8]),
                            .datain_v (datain_v_inter[(4*i+j-3)*8-1:(4*i+j-4)*8]),
                            .rd_macc_en (macc_wr[4*i+j]),
                            .dataout_h (datain_h_inter[(3*i+j+1)*8-1:(3*i+j)*8]),
                            .dataout_v (),
                            .maccout (C_data_in_c[128*i-32*j+127:128*i-32*j+96])
                        );
                    end
                end
                else if(j == 0) begin
                    PE pe(
                        .i (i[2:0]),
                        .j (j[2:0]),
                        .clk (clk),
                        .reset (reset),
                        .busy (busy),
                        .block_over (block_over),
                        .datain_h (datain_h[(3-i+1)*8-1:(3-i)*8]),
                        .datain_v (datain_v_inter[(4*i+j-3)*8-1:(4*i+j-4)*8]),
                        .rd_macc_en (macc_wr[4*i+j]),
                        .dataout_h (datain_h_inter[(3*i+j+1)*8-1:(3*i+j)*8]),
                        .dataout_v (datain_v_inter[(4*i+j+1)*8-1:(4*i+j)*8]),
                        .maccout (C_data_in_c[128*i-32*j+127:128*i-32*j+96])
                    );
                end
                else begin
                    PE pe(
                        .i (i[2:0]),
                        .j (j[2:0]),
                        .clk (clk),
                        .reset (reset),
                        .busy (busy),
                        .block_over (block_over),
                        .datain_h (datain_h_inter[(3*i+j)*8-1:(3*i+j-1)*8]),
                        .datain_v (datain_v_inter[(4*i+j-3)*8-1:(4*i+j-4)*8]),
                        .rd_macc_en (macc_wr[4*i+j]),
                        .dataout_h (),
                        .dataout_v (datain_v_inter[(4*i+j+1)*8-1:(4*i+j)*8]),
                        .maccout (C_data_in_c[128*i-32*j+127:128*i-32*j+96])
                    );
                end
            end
        end
    endgenerate


    always @(negedge reset or negedge busy) begin
        count = 0;
        macc_wr = 0;
        if(accumu_index > 0) begin
            repeat(8) @(negedge clk);
        end
        else begin
            repeat(3) @(negedge clk);
        end
        accumu_index = -1;
        busy = 1;  // Here I do set busy to high immediately after in_valid fall from high to low
        block_over = 0;
    end
    
    always @(posedge clk) begin
        if(busy) begin
            count = count + 1;
        end
        if(count == K+12) begin
            count = 0;
            macc_wr = 0;
            block_over = 1;
            #1
            block_over = 0;
            if(finish) begin
                busy = 0;
            end
        end
        if(count >= K+8) begin
            if(accumu_index < 0 || accumu_index < M * (cur_block_B+1) - 1) begin
                accumu_index += 1;
                if((accumu_index%M)%4 == 0) begin
                    macc_wr = macc_wr + 4'b1111;
                    #1
                    C_data_in <= C_data_in_c[127:0];
                end
                else begin
                    macc_wr = macc_wr << 4;
                    #1
                    if((accumu_index%M)%4 == 1) begin
                        C_data_in <= C_data_in_c[255:128];
                    end
                    else if((accumu_index%M)%4 == 2) begin
                        C_data_in <= C_data_in_c[383:256];
                    end
                    else if((accumu_index%M)%4 == 3) begin
                        C_data_in <= C_data_in_c[511:384];
                    end
                end
            end
            
        end
    end

endmodule