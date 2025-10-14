// ============================================================================ //
// Filename: processElement.v (CORRECTED - Ports Restored)
// Author: [Your Name]
// Description: 這個模組是原始 PE 模組的更名版本。
//              此版本已恢復所有原始埠，以解決連接錯誤。
//              其邏輯與原始範例完全相同。
// ============================================================================ //
module processElement(
    // --- 埠宣告 (已恢復原始介面) ---
    row_idx,        // 來自原始範例的 'i'
    col_idx,        // 來自原始範例的 'j'
    clk,
    rst_n,          // 來自原始範例的 'reset'

    // 控制信號
    is_busy,        // 來自原始範例的 'busy'
    is_block_done,  // 來自原始範例的 'block_over'
    read_en,        // 來自原始範例的 'rd_macc_en'

    // 資料流
    stream_in_A,    // 來自原始範例的 'datain_h'
    stream_in_B,    // 來自原始範例的 'datain_v'
    stream_out_A,   // 來自原始範例的 'dataout_h'
    stream_out_B,   // 來自原始範例的 'dataout_v'

    // 結果輸出
    pe_result       // 來自原始範例的 'maccout'
);

    // --- 輸入埠 (已恢復原始介面) ---
    input [2:0]   row_idx;
    input [2:0]   col_idx;
    input         clk;
    input         rst_n;
    input         is_busy;
    input         is_block_done;
    input [7:0]   stream_in_A; // 修正了寬度
    input [7:0]   stream_in_B; // 修正了寬度
    input         read_en;

    // --- 輸出埠 ---
    output reg [7:0]   stream_out_A;
    output reg [7:0]   stream_out_B;
    output reg [31:0]  pe_result;

    // --- 內部暫存器 (已更名) ---
    reg [31:0]  product_reg;    // 原名 'mul_res'
    reg [31:0]  accumulator;    // 原名 'macc'
    reg [7:0]   pipe_reg_A;     // 原名 'datain_h_c'
    reg [7:0]   pipe_reg_B;     // 原名 'datain_v_c'
    
    // --- 邏輯實作 (與原始範例完全相同) ---

    // 這個區塊負責清空累加器。
    always @(negedge rst_n or negedge is_busy or posedge is_block_done) begin
        accumulator = 32'd0;
    end

    // 這是主要的運算邏輯。
    always @(negedge clk) begin
        // 原始範例中的這個 if 條件可能只是為了避免 X 值的傳播
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