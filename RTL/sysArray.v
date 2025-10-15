// ============================================================================ //
// Filename: sysArray.v
// Description: 它建構了 4x4 的 PE 陣列，
//              並控制計算與結果寫回的時序。
// ============================================================================ //
`include "processElement.v"

module sysArray(
    // --- 埠宣告 ---
    clk,
    rst_n,        

    // 控制信號
    is_busy,        
    is_block_done,  
    is_finished,    

    // 矩陣維度與區塊資訊
    K_dim,          
    M_dim,          
    b_block_idx,    

    // 資料流 & 結果 I/O
    stream_in_A,    
    stream_in_B,    
    C_write_idx,    
    C_write_data    
);

    // --- 參數 & 輸入埠 ---
    parameter ARRAY_DIM = 4;
    input           clk;
    input           rst_n;
    input           is_finished;
    input   [7:0]   K_dim;
    input   [7:0]   M_dim;
    input   [7:0]   b_block_idx;
    input   [31:0]  stream_in_A;
    input   [31:0]  stream_in_B;

    // --- 輸出埠 ---
    output reg          is_busy;
    output reg          is_block_done;
    output      [15:0]  C_write_idx;
    output reg [127:0]  C_write_data;

    // --- 內部連線 & 暫存器 ---
    wire [((ARRAY_DIM-1) * ARRAY_DIM * 8)-1:0] internal_conns_A; 
    wire [((ARRAY_DIM-1) * ARRAY_DIM * 8)-1:0] internal_conns_B; 
    wire [511:0]                              all_pe_results; 

    reg signed [15:0] cycle_counter;
    reg signed [15:0] c_addr_ptr;     
    reg        [15:0] result_read_en; 

    // 將內部地址指標連接到輸出埠
    assign C_write_idx = c_addr_ptr;

    // --- 邏輯實作 ---

    // 這個 generate 區塊負責生成並連接 4x4 的 processElement 陣列
    genvar row, col;
    generate
        for(row=0; row<4; row=row+1) begin
            for(col=0; col<4; col=col+1) begin
                // 實例化 processElement，並連接所有已更名的埠
                if(row > 0 && row < 3 && col > 0 && col < 3) begin
                    processElement pe(.row_idx(row[2:0]), .col_idx(col[2:0]), .clk(clk), .rst_n(rst_n), .is_busy(is_busy), .is_block_done(is_block_done), .stream_in_A(internal_conns_A[(3*row+col)*8-1:(3*row+col-1)*8]), .stream_in_B(internal_conns_B[(4*row+col-3)*8-1:(4*row+col-4)*8]), .read_en(result_read_en[4*row+col]), .stream_out_A(internal_conns_A[(3*row+col+1)*8-1:(3*row+col)*8]), .stream_out_B(internal_conns_B[(4*row+col+1)*8-1:(4*row+col)*8]), .pe_result(all_pe_results[128*row-32*col+127:128*row-32*col+96]));
                end else if(row == 0) begin
                    if(col == 0) begin
                        processElement pe(.row_idx(row[2:0]), .col_idx(col[2:0]), .clk(clk), .rst_n(rst_n), .is_busy(is_busy), .is_block_done(is_block_done), .stream_in_A(stream_in_A[31:24]), .stream_in_B(stream_in_B[31:24]), .read_en(result_read_en[4*row+col]), .stream_out_A(internal_conns_A[(3*row+col+1)*8-1:(3*row+col)*8]), .stream_out_B(internal_conns_B[(4*row+col+1)*8-1:(4*row+col)*8]), .pe_result(all_pe_results[128*row-32*col+127:128*row-32*col+96]));
                    end else if(col == 3) begin
                        processElement pe(.row_idx(row[2:0]), .col_idx(col[2:0]), .clk(clk), .rst_n(rst_n), .is_busy(is_busy), .is_block_done(is_block_done), .stream_in_A(internal_conns_A[(3*row+col)*8-1:(3*row+col-1)*8]), .stream_in_B(stream_in_B[7:0]), .read_en(result_read_en[4*row+col]), .stream_out_A(), .stream_out_B(internal_conns_B[(4*row+col+1)*8-1:(4*row+col)*8]), .pe_result(all_pe_results[128*row-32*col+127:128*row-32*col+96]));
                    end else begin
                        processElement pe(.row_idx(row[2:0]), .col_idx(col[2:0]), .clk(clk), .rst_n(rst_n), .is_busy(is_busy), .is_block_done(is_block_done), .stream_in_A(internal_conns_A[(3*row+col)*8-1:(3*row+col-1)*8]), .stream_in_B(stream_in_B[(3-col+1)*8-1:(3-col)*8]), .read_en(result_read_en[4*row+col]), .stream_out_A(internal_conns_A[(3*row+col+1)*8-1:(3*row+col)*8]), .stream_out_B(internal_conns_B[(4*row+col+1)*8-1:(4*row+col)*8]), .pe_result(all_pe_results[128*row-32*col+127:128*row-32*col+96]));
                    end
                end else if(row == 3) begin
                    if(col == 0) begin
                        processElement pe(.row_idx(row[2:0]), .col_idx(col[2:0]), .clk(clk), .rst_n(rst_n), .is_busy(is_busy), .is_block_done(is_block_done), .stream_in_A(stream_in_A[7:0]), .stream_in_B(internal_conns_B[(4*row+col-3)*8-1:(4*row+col-4)*8]), .read_en(result_read_en[4*row+col]), .stream_out_A(internal_conns_A[(3*row+col+1)*8-1:(3*row+col)*8]), .stream_out_B(), .pe_result(all_pe_results[128*row-32*col+127:128*row-32*col+96]));
                    end else if(col == 3) begin
                        processElement pe(.row_idx(row[2:0]), .col_idx(col[2:0]), .clk(clk), .rst_n(rst_n), .is_busy(is_busy), .is_block_done(is_block_done), .stream_in_A(internal_conns_A[(3*row+col)*8-1:(3*row+col-1)*8]), .stream_in_B(internal_conns_B[(4*row+col-3)*8-1:(4*row+col-4)*8]), .read_en(result_read_en[4*row+col]), .stream_out_A(), .stream_out_B(), .pe_result(all_pe_results[128*row-32*col+127:128*row-32*col+96]));
                    end else begin
                        processElement pe(.row_idx(row[2:0]), .col_idx(col[2:0]), .clk(clk), .rst_n(rst_n), .is_busy(is_busy), .is_block_done(is_block_done), .stream_in_A(internal_conns_A[(3*row+col)*8-1:(3*row+col-1)*8]), .stream_in_B(internal_conns_B[(4*row+col-3)*8-1:(4*row+col-4)*8]), .read_en(result_read_en[4*row+col]), .stream_out_A(internal_conns_A[(3*row+col+1)*8-1:(3*row+col)*8]), .stream_out_B(), .pe_result(all_pe_results[128*row-32*col+127:128*row-32*col+96]));
                    end
                end else if(col == 0) begin
                    processElement pe(.row_idx(row[2:0]), .col_idx(col[2:0]), .clk(clk), .rst_n(rst_n), .is_busy(is_busy), .is_block_done(is_block_done), .stream_in_A(stream_in_A[(3-row+1)*8-1:(3-row)*8]), .stream_in_B(internal_conns_B[(4*row+col-3)*8-1:(4*row+col-4)*8]), .read_en(result_read_en[4*row+col]), .stream_out_A(internal_conns_A[(3*row+col+1)*8-1:(3*row+col)*8]), .stream_out_B(internal_conns_B[(4*row+col+1)*8-1:(4*row+col)*8]), .pe_result(all_pe_results[128*row-32*col+127:128*row-32*col+96]));
                end else begin
                    processElement pe(.row_idx(row[2:0]), .col_idx(col[2:0]), .clk(clk), .rst_n(rst_n), .is_busy(is_busy), .is_block_done(is_block_done), .stream_in_A(internal_conns_A[(3*row+col)*8-1:(3*row+col-1)*8]), .stream_in_B(internal_conns_B[(4*row+col-3)*8-1:(4*row+col-4)*8]), .read_en(result_read_en[4*row+col]), .stream_out_A(), .stream_out_B(internal_conns_B[(4*row+col+1)*8-1:(4*row+col)*8]), .pe_result(all_pe_results[128*row-32*col+127:128*row-32*col+96]));
                end
            end
        end
    endgenerate

    always @(negedge rst_n or negedge is_busy) begin
        cycle_counter  = 0;
        result_read_en = 0;
        if(c_addr_ptr > 0) begin
            repeat(8) @(negedge clk);
        end else begin
            repeat(3) @(negedge clk);
        end
        c_addr_ptr    = -1;
        is_busy       = 1'b1;
        is_block_done = 1'b0;
    end
    
    // 主要時序控制區塊。
    always @(posedge clk) begin
        if(is_busy) begin
            cycle_counter = cycle_counter + 1;
        end
        if(cycle_counter == K_dim + 12) begin
            cycle_counter  = 0;
            result_read_en = 0;
            is_block_done  = 1'b1;
            #1
            is_block_done  = 1'b0;
            if(is_finished) begin
                is_busy = 1'b0;
            end
        end
        if(cycle_counter >= K_dim + 8) begin
            if(c_addr_ptr < 0 || c_addr_ptr < M_dim * (b_block_idx+1) - 1) begin
                c_addr_ptr = c_addr_ptr + 1;
                if((c_addr_ptr % M_dim) % 4 == 0) begin
                    result_read_en = result_read_en + 4'b1111;
                    #1
                    C_write_data <= all_pe_results[127:0];
                end else begin
                    result_read_en = result_read_en << 4;
                    #1
                    if((c_addr_ptr % M_dim) % 4 == 1) begin
                        C_write_data <= all_pe_results[255:128];
                    end else if((c_addr_ptr % M_dim) % 4 == 2) begin
                        C_write_data <= all_pe_results[383:256];
                    end else if((c_addr_ptr % M_dim) % 4 == 3) begin
                        C_write_data <= all_pe_results[511:384];
                    end
                end
            end
        end
    end

endmodule