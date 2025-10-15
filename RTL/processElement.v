// ============================================================================ //
// Filename: processElement.v (CORRECTED - Ports Restored)
// Author: [Your Name]
// Description: 每個工作元件
// ============================================================================ //
module processElement(
    // --- 埠宣告  ---
    row_idx,        
    col_idx,        
    clk,
    rst_n,          

    // 控制信號
    is_busy,        
    is_block_done,  
    read_en,        

    // 資料流
    stream_in_A,    
    stream_in_B,    
    stream_out_A,   
    stream_out_B,   

    // 結果輸出
    pe_result 
);

    // --- 輸入埠 ---
    input [2:0]   row_idx;
    input [2:0]   col_idx;
    input         clk;
    input         rst_n;
    input         is_busy;
    input         is_block_done;
    input [7:0]   stream_in_A;
    input [7:0]   stream_in_B;
    input         read_en;

    // --- 輸出埠 ---
    output reg [7:0]   stream_out_A;
    output reg [7:0]   stream_out_B;
    output reg [31:0]  pe_result;

    // --- 內部暫存器 ---
    reg [31:0]  product_reg;
    reg [31:0]  accumulator;
    reg [7:0]   pipe_reg_A;
    reg [7:0]   pipe_reg_B;
    
    // --- 邏輯實作 ---

    // 這個區塊負責清空累加器。
    always @(negedge rst_n or negedge is_busy or posedge is_block_done) begin
        accumulator = 32'd0;
    end

    // 這是主要的運算邏輯。
    always @(negedge clk) begin
        if(stream_in_A >= 0) begin 
            product_reg = stream_in_A * stream_in_B;
            accumulator <= accumulator + product_reg;
            pipe_reg_A  <= stream_in_A;
            pipe_reg_B  <= stream_in_B;
        end
    end

    // 這個區塊將捕捉到的資料傳遞給下一個 PE。
    always @(posedge clk) begin
        stream_out_A <= pipe_reg_A;
        stream_out_B <= pipe_reg_B;
    end

    // 這個區塊在接到讀取致能信號時，輸出最終的累加結果。
    always @(posedge read_en) begin
        pe_result <= accumulator;
    end

endmodule