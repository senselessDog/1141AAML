// ============================================================================ //
// Filename: bufferElement.v
// Author: [Your Name]
// Description: 這個模組是原始 BE 模組的更名版本。
//              其邏輯與原始範例完全相同。
//              它的功能是一個可重置的、單週期的延遲元件。
// ============================================================================ //
module bufferElement(
    // --- 埠宣告 ---
    clk,
    rst_n,          // 從 'reset' 更名

    // 控制信號
    is_busy,        // 從 'busy' 更名
    is_block_done,  // 從 'block_over' 更名

    // 資料 I/O
    data_in,        // 從 'datain' 更名
    data_out        // 從 'dataout' 更名
);

    // --- 輸入埠 ---
    input           clk;
    input           rst_n;
    input           is_busy;
    input           is_block_done;
    input   [7:0]   data_in;

    // --- 輸出埠 ---
    output reg [7:0]   data_out;

    // --- 內部暫存器 (已更名) ---
    // 這個暫存器負責將資料暫存一個週期。
    reg [7:0]   pipe_reg; // 原名 'datain_c'

    // --- 邏輯實作 (與原始範例完全相同) ---

    // 這個區塊負責在需要時清空內部暫存器。
    always @(negedge rst_n or negedge is_busy or posedge is_block_done) begin
        pipe_reg = 8'd0;
    end

    // 這個區塊在時脈的正緣捕捉輸入資料。
    always @(posedge clk) begin
        pipe_reg <= data_in;
    end
    
    // 這個區塊在時脈的負緣將捕捉到的資料送到輸出埠，
    // 從而完成了一個週期的延遲。
    always @(negedge clk) begin
        data_out <= pipe_reg;
    end
    
endmodule