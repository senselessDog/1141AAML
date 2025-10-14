module controller(
    clk,
    reset,
    busy,
    block_over,
    finish,
    K,
    M,
    N,

    cur_block_B,
    A_index,
    B_index,
);
    input clk;
    input reset;
    input busy;
    input block_over;
    output reg finish;
    input [7:0] K;
    input [7:0] M;
    input [7:0] N;

    output [15:0] A_index;
    output [15:0] B_index;
    reg signed [15:0] count_A;
    reg signed [15:0] count_B;
    reg [7:0] num_block_A;
    reg [7:0] cur_block_A;
    reg [7:0] num_block_B;
    output reg [7:0] cur_block_B;
    
    assign A_index = count_A;
    assign B_index = count_B;

    always @(negedge reset or negedge busy) begin
        if(finish >= 0) begin
            repeat(10) @(negedge clk);
        end
        else begin
            repeat(3) @(negedge clk);
        end
        #1
        finish = 0;

        count_A = -1;
        count_B = -1;

        num_block_A = $ceil(M/4.0);
        cur_block_A = 0;

        num_block_B = $ceil(N/4.0);
        cur_block_B = 0;
    end

    always @(posedge block_over) begin
        if(cur_block_A < num_block_A - 1) begin
            cur_block_A += 1;

            count_B = cur_block_B*K-1;
            count_A = cur_block_A*K-1;
        end
        else if (cur_block_B < num_block_B - 1) begin
            cur_block_A = 0;
            cur_block_B += 1;

            count_B = cur_block_B*K-1;
            count_A = cur_block_A*K-1;
        end
        else begin
            finish = 1;
        end
    end

    always @(negedge clk) begin
        if(busy && !block_over) begin
            if(count_A == (cur_block_A+1)*K-1 || count_A == 16320) begin
                count_A = 16320;
            end
            else begin
                count_A = count_A + 1;
            end

            if(count_B == (cur_block_B+1)*K-1 || count_B == 16320) begin
                count_B = 16320;
            end
            else begin
                count_B = count_B + 1;
            end
        end
    end

endmodule