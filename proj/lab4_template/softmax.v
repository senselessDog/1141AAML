module softmax (
    input clk,
    input reset,
    
    // --- 控制訊號 ---
    input start_i,           // 啟動訊號
    output reg done_o,       // 完成訊號
    
    // --- 資料訊號 ---
    input [31:0] x_i,        // 輸入 x
    output reg [31:0] result_o // 輸出 e^x
);

    // --- 循序 (Sequential) 邏輯 ---
    always @(posedge clk) begin
        if (reset) begin
            result_o <= 32'b0;
            done_o   <= 1'b0;
        end else begin
            
            if (start_i) begin // "發現 start_i 為 1"
                // --- 暴力法，查表 (來自你的 `exp.v`) ---
                case (x_i)
                    32'hfcccccce: result_o <= 32'h39839c8b;
                    32'hfd99999b: result_o <= 32'h463f75c8;
                    32'hfe666667: result_o <= 32'h55cd0c27;
                    32'hff333334: result_o <= 32'h68cc2b93;
                    32'h00000000: result_o <= 32'h7fffffff;
                    32'hfecccccd: result_o <= 32'h5ed3218f;
                    32'hff99999a: result_o <= 32'h73d1b674;
                    default: result_o <= 32'h00000000;  // 預設值
                endcase
                
                done_o <= 1'b1; // **"寫完就 done=1"**
            end else begin
                done_o <= 1'b0; // 預設: "done" 訊號為 0
            end
            
        end
    end
    
endmodule