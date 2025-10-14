// ============================================================================ //
// Filename: controller.v
// Author: [Your Name]
// Description: 這個模組是原始 controller 模組的更名版本。
//              其邏輯與原始範例完全相同。它負責管理分塊策略
//              以及為 Global Buffer 生成地址。
// ============================================================================ //
module controller(
    // --- 埠宣告 ---
    clk,
    rst_n,          // 從 'reset' 更名
    is_busy,        // 從 'busy' 更名
    is_block_done,  // 從 'block_over' 更名
    is_finished,    // 從 'finish' 更名

    // 矩陣維度與區塊資訊
    K_dim,          // 從 'K' 更名
    M_dim,          // 從 'M' 更名
    N_dim,          // 從 'N' 更名
    b_block_idx,    // 從 'cur_block_B' 更名

    // 地址輸出
    A_addr_out,     // 從 'A_index' 更名
    B_addr_out      // 從 'B_index' 更名
);

    // --- 輸入埠 ---
    input           clk;
    input           rst_n;
    input           is_busy;
    input           is_block_done;
    input   [7:0]   K_dim;
    input   [7:0]   M_dim;
    input   [7:0]   N_dim;

    // --- 輸出埠 ---
    output reg         is_finished;
    output reg [7:0]   b_block_idx;
    output      [15:0] A_addr_out;
    output      [15:0] B_addr_out;
    
    // --- 內部暫存器 (已更名) ---
    reg signed [15:0] addr_ptr_a;      // 原名 'count_A'
    reg signed [15:0] addr_ptr_b;      // 原名 'count_B'
    reg [7:0] a_block_total;   // 原名 'num_block_A'
    reg [7:0] a_block_current; // 原名 'cur_block_A'
    reg [7:0] b_block_total;   // 原名 'num_block_B'
    
    // 將內部地址指標連接到輸出埠
    assign A_addr_out = addr_ptr_a;
    assign B_addr_out = addr_ptr_b;

    // --- 邏輯實作 (與原始範例完全相同) ---

    // 這個區塊負責在一個新的矩陣乘法任務開始時，初始化控制器。
    // 它包含了原始範例中不可合成的延遲。
    always @(negedge rst_n or negedge is_busy) begin
        if(is_finished >= 0) begin
            repeat(10) @(negedge clk);
        end else begin
            repeat(3) @(negedge clk);
        end
        #1
        is_finished      = 1'b0;
        addr_ptr_a       = -1;
        addr_ptr_b       = -1;
        a_block_total    = $ceil(M_dim/4.0);
        a_block_current  = 0;
        b_block_total    = $ceil(N_dim/4.0);
        b_block_idx      = 0;
    end

    // 這個區塊負責處理分塊的切換邏輯，如同一個巢狀迴圈控制器。
    // 當 sysArray 完成一個區塊計算時，它就會被觸發。
    always @(posedge is_block_done) begin
        if(a_block_current < a_block_total - 1) begin
            a_block_current = a_block_current + 1;
            addr_ptr_b      = b_block_idx * K_dim - 1;
            addr_ptr_a      = a_block_current * K_dim - 1;
        end
        else if (b_block_idx < b_block_total - 1) begin
            a_block_current = 0;
            b_block_idx     = b_block_idx + 1;
            addr_ptr_b      = b_block_idx * K_dim - 1;
            addr_ptr_a      = a_block_current * K_dim - 1;
        end
        else begin
            is_finished = 1'b1;
        end
    end

    // 這個區塊負責為當前正在處理的區塊，連續不斷地生成讀取地址。
    always @(negedge clk) begin
        if(is_busy && !is_block_done) begin
            if(addr_ptr_a == (a_block_current+1)*K_dim-1 || addr_ptr_a == 16320) begin
                addr_ptr_a = 16320;
            end else begin
                addr_ptr_a = addr_ptr_a + 1;
            end

            if(addr_ptr_b == (b_block_idx+1)*K_dim-1 || addr_ptr_b == 16320) begin
                addr_ptr_b = 16320;
            end else begin
                addr_ptr_b = addr_ptr_b + 1;
            end
        end
    end

endmodule