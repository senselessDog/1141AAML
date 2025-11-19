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
        //----------------------------------------------------------------------
        // Row 0: 頂部邊界的處理單元
        //----------------------------------------------------------------------

        // -- PE (Row 0, Col 0) --
        processElement pe_0_0 (
            .row_idx(3'd0), .col_idx(3'd0), .clk(clk), .rst_n(rst_n), .is_busy(is_busy), .is_block_done(is_block_done), 
            .stream_in_A(stream_in_A[31:24]),
            .stream_in_B(stream_in_B[31:24]),
            .read_en(result_read_en[0]),
            .stream_out_A(internal_conns_A[7:0]),
            .stream_out_B(internal_conns_B[7:0]),
            .pe_result(all_pe_results[127:96])
        );

        // -- PE (Row 0, Col 1) --
        processElement pe_0_1 (
            .row_idx(3'd0), .col_idx(3'd1), .clk(clk), .rst_n(rst_n), .is_busy(is_busy), .is_block_done(is_block_done), 
            .stream_in_A(internal_conns_A[7:0]),
            .stream_in_B(stream_in_B[23:16]),
            .read_en(result_read_en[1]),
            .stream_out_A(internal_conns_A[15:8]),
            .stream_out_B(internal_conns_B[15:8]),
            .pe_result(all_pe_results[95:64])
        );

        // -- PE (Row 0, Col 2) --
        processElement pe_0_2 (
            .row_idx(3'd0), .col_idx(3'd2), .clk(clk), .rst_n(rst_n), .is_busy(is_busy), .is_block_done(is_block_done), 
            .stream_in_A(internal_conns_A[15:8]),
            .stream_in_B(stream_in_B[15:8]),
            .read_en(result_read_en[2]),
            .stream_out_A(internal_conns_A[23:16]),
            .stream_out_B(internal_conns_B[23:16]),
            .pe_result(all_pe_results[63:32])
        );

        // -- PE (Row 0, Col 3) --
        processElement pe_0_3 (
            .row_idx(3'd0), .col_idx(3'd3), .clk(clk), .rst_n(rst_n), .is_busy(is_busy), .is_block_done(is_block_done), 
            .stream_in_A(internal_conns_A[23:16]),
            .stream_in_B(stream_in_B[7:0]),
            .read_en(result_read_en[3]),
            .stream_out_A(), // 右邊界，無水平輸出
            .stream_out_B(internal_conns_B[31:24]),
            .pe_result(all_pe_results[31:0])
        );

        //----------------------------------------------------------------------
        // Row 1: 中間部分的處理單元
        //----------------------------------------------------------------------

        // -- PE (Row 1, Col 0) --
        processElement pe_1_0 (
            .row_idx(3'd1), .col_idx(3'd0), .clk(clk), .rst_n(rst_n), .is_busy(is_busy), .is_block_done(is_block_done), 
            .stream_in_A(stream_in_A[23:16]),
            .stream_in_B(internal_conns_B[7:0]),
            .read_en(result_read_en[4]),
            .stream_out_A(internal_conns_A[31:24]),
            .stream_out_B(internal_conns_B[39:32]),
            .pe_result(all_pe_results[255:224])
        );

        // -- PE (Row 1, Col 1) --
        processElement pe_1_1 (
            .row_idx(3'd1), .col_idx(3'd1), .clk(clk), .rst_n(rst_n), .is_busy(is_busy), .is_block_done(is_block_done), 
            .stream_in_A(internal_conns_A[31:24]),
            .stream_in_B(internal_conns_B[15:8]),
            .read_en(result_read_en[5]),
            .stream_out_A(internal_conns_A[39:32]),
            .stream_out_B(internal_conns_B[47:40]),
            .pe_result(all_pe_results[223:192])
        );

        // -- PE (Row 1, Col 2) --
        processElement pe_1_2 (
            .row_idx(3'd1), .col_idx(3'd2), .clk(clk), .rst_n(rst_n), .is_busy(is_busy), .is_block_done(is_block_done), 
            .stream_in_A(internal_conns_A[39:32]),
            .stream_in_B(internal_conns_B[23:16]),
            .read_en(result_read_en[6]),
            .stream_out_A(internal_conns_A[47:40]),
            .stream_out_B(internal_conns_B[55:48]),
            .pe_result(all_pe_results[191:160])
        );

        // -- PE (Row 1, Col 3) --
        processElement pe_1_3 (
            .row_idx(3'd1), .col_idx(3'd3), .clk(clk), .rst_n(rst_n), .is_busy(is_busy), .is_block_done(is_block_done), 
            .stream_in_A(internal_conns_A[47:40]),
            .stream_in_B(internal_conns_B[31:24]),
            .read_en(result_read_en[7]),
            .stream_out_A(), // 右邊界，無水平輸出
            .stream_out_B(internal_conns_B[63:56]),
            .pe_result(all_pe_results[159:128])
        );

        //----------------------------------------------------------------------
        // Row 2: 中間部分的處理單元
        //----------------------------------------------------------------------

        // -- PE (Row 2, Col 0) --
        processElement pe_2_0 (
            .row_idx(3'd2), .col_idx(3'd0), .clk(clk), .rst_n(rst_n), .is_busy(is_busy), .is_block_done(is_block_done), 
            .stream_in_A(stream_in_A[15:8]),
            .stream_in_B(internal_conns_B[39:32]),
            .read_en(result_read_en[8]),
            .stream_out_A(internal_conns_A[55:48]),
            .stream_out_B(internal_conns_B[71:64]),
            .pe_result(all_pe_results[383:352])
        );

        // -- PE (Row 2, Col 1) --
        processElement pe_2_1 (
            .row_idx(3'd2), .col_idx(3'd1), .clk(clk), .rst_n(rst_n), .is_busy(is_busy), .is_block_done(is_block_done), 
            .stream_in_A(internal_conns_A[55:48]),
            .stream_in_B(internal_conns_B[47:40]),
            .read_en(result_read_en[9]),
            .stream_out_A(internal_conns_A[63:56]),
            .stream_out_B(internal_conns_B[79:72]),
            .pe_result(all_pe_results[351:320])
        );

        // -- PE (Row 2, Col 2) --
        processElement pe_2_2 (
            .row_idx(3'd2), .col_idx(3'd2), .clk(clk), .rst_n(rst_n), .is_busy(is_busy), .is_block_done(is_block_done), 
            .stream_in_A(internal_conns_A[63:56]),
            .stream_in_B(internal_conns_B[55:48]),
            .read_en(result_read_en[10]),
            .stream_out_A(internal_conns_A[71:64]),
            .stream_out_B(internal_conns_B[87:80]),
            .pe_result(all_pe_results[319:288])
        );

        // -- PE (Row 2, Col 3) --
        processElement pe_2_3 (
            .row_idx(3'd2), .col_idx(3'd3), .clk(clk), .rst_n(rst_n), .is_busy(is_busy), .is_block_done(is_block_done), 
            .stream_in_A(internal_conns_A[71:64]),
            .stream_in_B(internal_conns_B[63:56]),
            .read_en(result_read_en[11]),
            .stream_out_A(), // 右邊界，無水平輸出
            .stream_out_B(internal_conns_B[95:88]),
            .pe_result(all_pe_results[287:256])
        );

        //----------------------------------------------------------------------
        // Row 3: 底部邊界的處理單元
        //----------------------------------------------------------------------

        // -- PE (Row 3, Col 0) --
        processElement pe_3_0 (
            .row_idx(3'd3), .col_idx(3'd0), .clk(clk), .rst_n(rst_n), .is_busy(is_busy), .is_block_done(is_block_done), 
            .stream_in_A(stream_in_A[7:0]),
            .stream_in_B(internal_conns_B[71:64]),
            .read_en(result_read_en[12]),
            .stream_out_A(internal_conns_A[79:72]),
            .stream_out_B(), // 底邊界，無垂直輸出
            .pe_result(all_pe_results[511:480])
        );

        // -- PE (Row 3, Col 1) --
        processElement pe_3_1 (
            .row_idx(3'd3), .col_idx(3'd1), .clk(clk), .rst_n(rst_n), .is_busy(is_busy), .is_block_done(is_block_done), 
            .stream_in_A(internal_conns_A[79:72]),
            .stream_in_B(internal_conns_B[79:72]),
            .read_en(result_read_en[13]),
            .stream_out_A(internal_conns_A[87:80]),
            .stream_out_B(), // 底邊界，無垂直輸出
            .pe_result(all_pe_results[479:448])
        );

        // -- PE (Row 3, Col 2) --
        processElement pe_3_2 (
            .row_idx(3'd3), .col_idx(3'd2), .clk(clk), .rst_n(rst_n), .is_busy(is_busy), .is_block_done(is_block_done), 
            .stream_in_A(internal_conns_A[87:80]),
            .stream_in_B(internal_conns_B[87:80]),
            .read_en(result_read_en[14]),
            .stream_out_A(internal_conns_A[95:88]),
            .stream_out_B(), // 底邊界，無垂直輸出
            .pe_result(all_pe_results[447:416])
        );

        // -- PE (Row 3, Col 3) --
        processElement pe_3_3 (
            .row_idx(3'd3), .col_idx(3'd3), .clk(clk), .rst_n(rst_n), .is_busy(is_busy), .is_block_done(is_block_done), 
            .stream_in_A(internal_conns_A[95:88]),
            .stream_in_B(internal_conns_B[95:88]),
            .read_en(result_read_en[15]),
            .stream_out_A(), // 右邊界，無水平輸出
            .stream_out_B(), // 底邊界，無垂直輸出
            .pe_result(all_pe_results[415:384])
        );
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