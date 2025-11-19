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
    generate
        //----------------------------------------------------------------------
        // Row 0
        //----------------------------------------------------------------------
        // be(0,0): 來自左邊界的 0，傳給右邊
        bufferElement be_0_0 (.clk(clk), .rst_n(rst_n), .is_busy(is_busy), .is_block_done(is_block_done), 
            .data_in(8'd0), 
            .data_out(internal_connections[7:0]));
        // be(0,1): 來自左邊，傳給右邊
        bufferElement be_0_1 (.clk(clk), .rst_n(rst_n), .is_busy(is_busy), .is_block_done(is_block_done), 
            .data_in(internal_connections[7:0]), 
            .data_out(internal_connections[15:8]));
        // be(0,2): 來自左邊，傳給右邊
        bufferElement be_0_2 (.clk(clk), .rst_n(rst_n), .is_busy(is_busy), .is_block_done(is_block_done), 
            .data_in(internal_connections[15:8]), 
            .data_out(internal_connections[23:16]));
        // be(0,3): *** 對角線 *** 接收外部輸入，輸出到最終 data_out
        bufferElement be_0_3 (.clk(clk), .rst_n(rst_n), .is_busy(is_busy), .is_block_done(is_block_done), 
            .data_in(data_in[31:24]), 
            .data_out(data_out[31:24]));

        //----------------------------------------------------------------------
        // Row 1
        //----------------------------------------------------------------------
        // be(1,0): 來自左邊界的 0，傳給右邊
        bufferElement be_1_0 (.clk(clk), .rst_n(rst_n), .is_busy(is_busy), .is_block_done(is_block_done), 
            .data_in(8'd0), 
            .data_out(internal_connections[31:24]));
        // be(1,1): 來自左邊，傳給右邊
        bufferElement be_1_1 (.clk(clk), .rst_n(rst_n), .is_busy(is_busy), .is_block_done(is_block_done), 
            .data_in(internal_connections[31:24]), 
            .data_out(internal_connections[39:32]));
        // be(1,2): *** 對角線 *** 接收外部輸入，傳給右邊
        bufferElement be_1_2 (.clk(clk), .rst_n(rst_n), .is_busy(is_busy), .is_block_done(is_block_done), 
            .data_in(data_in[23:16]), 
            .data_out(internal_connections[47:40]));
        // be(1,3): 來自左邊，輸出到最終 data_out
        bufferElement be_1_3 (.clk(clk), .rst_n(rst_n), .is_busy(is_busy), .is_block_done(is_block_done), 
            .data_in(internal_connections[47:40]), 
            .data_out(data_out[23:16]));

        //----------------------------------------------------------------------
        // Row 2
        //----------------------------------------------------------------------
        // be(2,0): 來自左邊界的 0，傳給右邊
        bufferElement be_2_0 (.clk(clk), .rst_n(rst_n), .is_busy(is_busy), .is_block_done(is_block_done), 
            .data_in(8'd0), 
            .data_out(internal_connections[55:48]));
        // be(2,1): *** 對角線 *** 接收外部輸入，傳給右邊
        bufferElement be_2_1 (.clk(clk), .rst_n(rst_n), .is_busy(is_busy), .is_block_done(is_block_done), 
            .data_in(data_in[15:8]), 
            .data_out(internal_connections[63:56]));
        // be(2,2): 來自左邊，傳給右邊
        bufferElement be_2_2 (.clk(clk), .rst_n(rst_n), .is_busy(is_busy), .is_block_done(is_block_done), 
            .data_in(internal_connections[63:56]), 
            .data_out(internal_connections[71:64]));
        // be(2,3): 來自左邊，輸出到最終 data_out
        bufferElement be_2_3 (.clk(clk), .rst_n(rst_n), .is_busy(is_busy), .is_block_done(is_block_done), 
            .data_in(internal_connections[71:64]), 
            .data_out(data_out[15:8]));

        //----------------------------------------------------------------------
        // Row 3
        //----------------------------------------------------------------------
        // be(3,0): *** 對角線 *** 接收外部輸入，傳給右邊
        bufferElement be_3_0 (.clk(clk), .rst_n(rst_n), .is_busy(is_busy), .is_block_done(is_block_done), 
            .data_in(data_in[7:0]), 
            .data_out(internal_connections[79:72]));
        // be(3,1): 來自左邊，傳給右邊
        bufferElement be_3_1 (.clk(clk), .rst_n(rst_n), .is_busy(is_busy), .is_block_done(is_block_done), 
            .data_in(internal_connections[79:72]), 
            .data_out(internal_connections[87:80]));
        // be(3,2): 來自左邊，傳給右邊
        bufferElement be_3_2 (.clk(clk), .rst_n(rst_n), .is_busy(is_busy), .is_block_done(is_block_done), 
            .data_in(internal_connections[87:80]), 
            .data_out(internal_connections[95:88]));
        // be(3,3): 來自左邊，輸出到最終 data_out
        bufferElement be_3_3 (.clk(clk), .rst_n(rst_n), .is_busy(is_busy), .is_block_done(is_block_done), 
            .data_in(internal_connections[95:88]), 
            .data_out(data_out[7:0]));
    endgenerate

endmodule