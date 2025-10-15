// ============================================================================ //
// Filename: buffer.v
// Author: [Your Name]
// Description: 它使用 16 個
//              bufferElement 實例來產生收縮陣列所需的資料歪斜效果。
// ============================================================================ //
`include "bufferElement.v"

module buffer(
    // --- 埠宣告 ---
    clk,
    rst_n,          

    // 控制信號
    is_busy,        
    is_block_done,  

    // 資料 I/O
    data_in,        
    data_out        
);

    // --- 參數 & 輸入埠 ---
    parameter WORD_WIDTH = 4; // 定義 buffer 為 4x4 結構
    input           clk;
    input           rst_n;
    input           is_busy;
    input           is_block_done;
    input   [31:0]  data_in;

    // --- 輸出埠 ---
    output  [31:0]  data_out;

    // --- 內部連線 ---
    // 這些 wire 負責在 bufferElement 實例之間傳遞資料。
    wire [((WORD_WIDTH-1) * WORD_WIDTH * 8)-1:0] internal_connections; 

    // --- 邏輯實作 ---

    // 這個 generate 區塊負責生成 4x4 的 bufferElement 實例網絡。
    // 複雜的 'if-else' 結構定義了資料歪斜的路徑。
    genvar row, col;
    generate
        for(row=0; row<4; row=row+1) begin
            for(col=0; col<4; col=col+1) begin
                // 'be' 是 bufferElement 模組的一個實例。
                // 我們將更名後的控制信號傳遞給每一個元件。
                if(row+col == 3) begin // 這是資料輸入的主對角線
                    if(col == 3) begin
                        bufferElement be(.clk(clk), .rst_n(rst_n), .is_busy(is_busy), .is_block_done(is_block_done), .data_in(data_in[(col+1)*8-1:col*8]), .data_out(data_out[31:24]));
                    end else begin
                        bufferElement be(.clk(clk), .rst_n(rst_n), .is_busy(is_busy), .is_block_done(is_block_done), .data_in(data_in[(col+1)*8-1:col*8]), .data_out(internal_connections[(3*row+col+1)*8-1:(3*row+col)*8]));
                    end
                end else begin // 非對角線上的元件負責傳遞資料
                    if(col == 3) begin
                        bufferElement be(.clk(clk), .rst_n(rst_n), .is_busy(is_busy), .is_block_done(is_block_done), .data_in(internal_connections[(3*row+col)*8-1:(3*row+col-1)*8]), .data_out(data_out[(3-row+1)*8-1:(3-row)*8]));
                    end else if(col == 0) begin
                        bufferElement be(.clk(clk), .rst_n(rst_n), .is_busy(is_busy), .is_block_done(is_block_done), .data_in(8'd0), .data_out(internal_connections[(3*row+col+1)*8-1:(3*row+col)*8]));
                    end else begin
                        bufferElement be(.clk(clk), .rst_n(rst_n), .is_busy(is_busy), .is_block_done(is_block_done), .data_in(internal_connections[(3*row+col)*8-1:(3*row+col-1)*8]), .data_out(internal_connections[(3*row+col+1)*8-1:(3*row+col)*8]));
                    end
                end
            end
        end
    endgenerate

endmodule