// ============================================================================ //
// Filename: TPU.v
// Description: 這是 TPU 的頂層模組。它負責實例化並連接所有子模組
//              (controller, buffer, sysArray)，形成完整的加速器。
// ============================================================================ //
`include "controller.v"
`include "buffer.v"
`include "sysArray.v"

module TPU(
    clk,
    rst_n,
    in_valid,
    K,
    M,
    N,
    busy,
    A_wr_en,
    A_index,
    A_data_in,
    A_data_out,
    B_wr_en,
    B_index,
    B_data_in,
    B_data_out,
    C_wr_en,
    C_index,
    C_data_in,
    C_data_out
);

    input           clk;
    input           rst_n;
    input           in_valid;
    input   [7:0]   K;
    input   [7:0]   M;
    input   [7:0]   N;
    output reg         busy;
    output          A_wr_en;
    output  [15:0]  A_index;
    output  [31:0]  A_data_in;
    input   [31:0]  A_data_out;
    output          B_wr_en;
    output  [15:0]  B_index;
    output  [31:0]  B_data_in;
    input   [31:0]  B_data_out;
    output          C_wr_en;
    output  [15:0]  C_index;
    output  [127:0] C_data_in;
    input   [127:0] C_data_out;

    // --- 內部連線 ---
    wire         internal_busy;
    wire         internal_block_done;
    wire         internal_finished;
    wire [31:0]  internal_delayed_A;
    wire [31:0]  internal_delayed_B;
    wire [7:0]   internal_b_block_idx;
    
    // 用於儲存 K, M, N 維度的暫存器，供內部模組使用。
    reg [7:0]   k_dim_reg;
    reg [7:0]   m_dim_reg;
    reg [7:0]   n_dim_reg;


    // --- 模組實例化 ---
    // 負責將我們客製化命名後的模組建立出來並連接。

    // 1. 控制器 (大腦)
    controller u_controller(
        .clk(clk),
        .rst_n(rst_n),
        .is_busy(internal_busy),             // 連接到 sysArray 的忙碌狀態
        .is_block_done(internal_block_done), // 連接到 sysArray 的區塊完成狀態
        .K_dim(k_dim_reg),
        .M_dim(m_dim_reg),
        .N_dim(n_dim_reg),
        .is_finished(internal_finished),     // 控制器發出任務全部結束的信號
        .b_block_idx(internal_b_block_idx),  // 控制器提供當前 B 矩陣的區塊索引
        .A_addr_out(A_index),                // 控制器驅動 A_index 輸出
        .B_addr_out(B_index)                 // 控制器驅動 B_index 輸出
    );

    // 2. A 矩陣的資料緩衝器
    buffer u_bufferA(
        .clk(clk),
        .rst_n(rst_n),
        .is_busy(internal_busy),
        .is_block_done(internal_block_done),
        .data_in(A_data_out),       // 從 Global Buffer A 接收原始資料
        .data_out(internal_delayed_A) // 輸出歪斜後的資料給 sysArray
    );

    // 3. B 矩陣的資料緩衝器
    buffer u_bufferB(
        .clk(clk),
        .rst_n(rst_n),
        .is_busy(internal_busy),
        .is_block_done(internal_block_done),
        .data_in(B_data_out),       // 從 Global Buffer B 接收原始資料
        .data_out(internal_delayed_B) // 輸出歪斜後的資料給 sysArray
    );

    // 4. 收縮陣列 (主生產線)
    sysArray u_sysArray(
        .clk(clk),
        .rst_n(rst_n),
        .is_busy(internal_busy),
        .is_block_done(internal_block_done),
        .is_finished(internal_finished),
        .K_dim(k_dim_reg),
        .M_dim(m_dim_reg),
        .b_block_idx(internal_b_block_idx),
        .stream_in_A(internal_delayed_A),    // 從 bufferA 接收歪斜資料
        .stream_in_B(internal_delayed_B),    // 從 bufferB 接收歪斜資料
        .C_write_idx(C_index),            // sysArray 驅動 C_index 輸出
        .C_write_data(C_data_in)          // sysArray 驅動 C_data_in 輸出
    );

    // 根據原始範例的邏輯，這些輸出被賦予固定值。
    assign A_wr_en = 1'b0; // 只對 A 進行讀取
    assign B_wr_en = 1'b0; // 只對 B 進行讀取
    assign C_wr_en = 1'b1; // C 的寫入由 sysArray 透過 C_data_in 的時序來控制

    assign A_data_in = 32'd0; // 不對 A 進行寫入
    assign B_data_in = 32'd0; // 不對 B 進行寫入

    // 這個區塊負責在 'in_valid' 為高電位時，捕捉矩陣維度 (K, M, N)。
    always @(posedge in_valid) begin
        if(K > 0) begin
            k_dim_reg = K;
            m_dim_reg = M;
            n_dim_reg = N;
        end
    end
    //為了初始化busy，避免RTL error
    initial begin
        busy = 0;
    end
    //新的開始刷新busy
    always @(negedge clk) begin
        busy <= internal_busy;
    end
    

endmodule