// ============================================================================
// logistic.v (最終修正版 - 100% 匹配你的演算法)
//
// 1. 演算法: 100% 來自你的 exp_rep (使用 x_3/6)。
// 2. 時序: 100% 使用循序 (Sequential) 狀態機。
// 3. 不使用 $signed，100% 匹配 exp_rep 的 unsigned 邏輯。
// ============================================================================
module logistic (
    input clk,
    input reset,
    
    // --- 控制訊號 ---
    input start_i,           // 來自 Cfu 主模組的 "開始" 訊號
    output reg done_o,       // 告訴 Cfu 主模組 "我算完了"
    
    // --- 資料訊號 ---
    input [31:0] x_i,        // 輸入 -x (Q4.27 格式)
    output reg [31:0] result_o // 輸出 1 / (1 + e^(-x)) (Q4.27 格式)
);

    // Q4.27 格式的常數 (來自你的 `exp_rep` 範例)
    localparam frac_shift   = 27;
    localparam const_1      = (1 << 27);    // 1.0
    localparam TWO_Q27      = (2 << 27);    // 2.0
    // "reciprocal_init = const_1"
    localparam newton_init  = const_1; 

    // "步驟" 計數器
    reg [2:0] state; 

    // --- 管線暫存器 (Registers) ---
    // 這些是 "步驟" 之間的中間值 (y)
    reg [31:0] x_reg;     // -x
    reg [31:0] x2_reg;    // (-x)^2
    reg [31:0] x3_reg;    // (-x)^3
    reg [31:0] exp_reg;   // exp
    reg [31:0] e_plus_1_reg; // e^x + 1

    // --- 循序 (Sequential) 邏輯 ---
    // "在 sequential 裡面寫這些步驟"
    always @(posedge clk) begin
        if (reset) begin
            state <= 0;
            done_o <= 1'b0;
            result_o <= 32'b0;
        end else begin
            
            done_o <= 1'b0; // 預設: "done" 訊號為 0

            case (state)
                
                // 步驟 0: 閒置 (IDLE)
                0: begin
                    if (start_i) begin // "發現 start_i 為 1"
                        x_reg <= x_i;  // 鎖住輸入 x
                        state <= 1;    // 進入 "步驟 1"
                    end
                end

                // 步驟 1: "assign x_2 = (x*x) >> frac_shift"
                1: begin 
                    x2_reg <= (x_reg * x_reg) >>> frac_shift;
                    state <= 2; // 進入 "步驟 2"
                end

                // 步驟 2: "assign x_3 = (x_2*x) >> frac_shift"
                2: begin 
                    x3_reg <= (x2_reg * x_reg) >>> frac_shift;
                    state <= 3; // 進入 "步驟 3"
                end

                // 步驟 3: "assign exp = ..."
                3: begin 
                    exp_reg <= const_1 + x_reg + (x2_reg >>> 1) + (x3_reg / 6);
                    state <= 4; // 進入 "步驟 4"
                end

                // 步驟 4: "assign e_plus_1 = exp + const_1"
                4: begin
                    e_plus_1_reg <= exp_reg + const_1;
                    state <= 5; // 進入 "步驟 5"
                end

                // 步驟 5: "assign reciprocal_approx = ..."
                5: begin 
                    // d' = d*(2-d*e)
                    // d = newton_init
                    // e = e_plus_1_reg
                    result_o <= (newton_init * (TWO_Q27 - ((newton_init * e_plus_1_reg) >>> frac_shift))) >>> frac_shift;
                    
                    done_o <= 1'b1;              // **"寫完就 done=1"**
                    state <= 0;                  // 回到閒置 (步驟 0)
                end
                
                // 預設: 如果 state 跑掉，就回到閒置
                default: state <= 0;
            endcase
        end
    end
endmodule