// ============================================================================
// softmax.v (「真正的」Lookup Table 版本)
//
// 1. 演算法: 真正的 BRAM (Block RAM) Lookup Table
// 2. 時序: 2-cycle (Cycle 1: 設地址, Cycle 2: 讀資料)
// 3. Q 格式: Q5.26 (frac_shift=26)
// ============================================================================
module softmax (
    input clk,
    input reset,
    
    // --- 控制訊號 ---
    input start_i,           // 啟動訊號
    output reg done_o,       // 完成訊號
    
    // --- 資料訊號 ---
    input [31:0] x_i,        // 輸入 x (Q5.26 格式)
    output reg [31:0] result_o // 輸出 e^x (Q5.26 格式)
);

    // --- 1. 宣告你的 Table (記憶體) ---
    // 這是一個 1024 x 32-bit 的記憶體
    reg [31:0] exp_table [0:65535];

    // --- 2. 初始化你的 Table ---
    // (這會告訴 Vivado 在 `make prog` 時，
    //  去 "exp_lut_q5.26.mem" 檔案讀取 1024 筆資料)
    initial begin
        $readmemh("exp_lut_q5.26.mem", exp_table);
    end

    // "步驟" 計數器
    // 0 = 閒置
    // 1 = 讀取 BRAM (拿資料)
    reg state; // 只需要 1-bit (0 或 1)
    
    // 暫存器: 用來儲存 BRAM 的地址
    reg [15:0] addr_reg;


    // --- 循序 (Sequential) 邏輯 ---
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
                        
                        // --- 1. 取得地址 ---
                        // 我們拿 x_i 的 5 個整數位 和 5 個小數位
                        addr_reg <= x_i[31:16]; 
                        
                        state <= 1;    // 進入 "步驟 1"
                    end
                end

                // 步驟 1: 讀取 BRAM
                1: begin 
                    // --- 2. 查表 ---
                    // 從上一個 cycle 設好的地址 (addr_reg) 讀取資料
                    result_o <= exp_table[addr_reg];
                    
                    done_o <= 1'b1;  // **"寫完就 done=1"**
                    state <= 0;      // 回到閒置
                end
                
                default: state <= 0;
            endcase
        end
    end
    
endmodule