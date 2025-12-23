`include "sysArray.v"
`include "processElement.v"
`include "InputShifter.v"
`include "tpuControlUnit.v"
module TPU 
#(
    parameter ADDR_BITS = 16
)
(
    input  clk,
    input  rst_n,

    input          in_valid,
    input  [7:0]   K,
    input  [7:0]   M,
    input  [7:0]   N,
    output reg     busy,

    output         A_wr_en,
    output [ADDR_BITS-1:0] A_index,
    output [31:0]  A_data_in,
    input  [31:0]  A_data_out,

    output         B_wr_en,
    output [ADDR_BITS-1:0] B_index,
    output [31:0]  B_data_in,
    input  [31:0]  B_data_out,

    output         C_wr_en,
    output [ADDR_BITS-1:0] C_index,
    output [127:0] C_data_in,
    input  [127:0] C_data_out
);

    //=========================================================================
    // Internal Signals & Registers
    //=========================================================================
    
    // Latched Dimensions
    reg [7:0] r_dim_k, r_dim_m, r_dim_n;

    // FSM State Signals
    wire [1:0] curr_state, next_state;
    
    // Global Cycle Counter
    wire [31:0] global_timer;

    // Data Buses for Systolic Array
    wire [31:0]  horizontal_feed;
    wire [31:0]  vertical_feed;

    // Partial Sum Results
    wire [127:0] result_row_0, result_row_1, result_row_2, result_row_3;

    // State Encoding
    localparam ST_IDLE    = 2'd0;
    localparam ST_LOAD    = 2'd1;
    localparam ST_EXEC    = 2'd2;
    localparam ST_DONE    = 2'd3;

    //=========================================================================
    // Busy Signal Logic
    //=========================================================================
    // Note: Controlled directly here to minimize latency loopback issues
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy <= 1'b0;
        end else if (in_valid) begin
            busy <= 1'b1;
        end else if (next_state == ST_DONE) begin
            busy <= 1'b0;
        end
    end

    //=========================================================================
    // Parameter Latching
    //=========================================================================
    always @(posedge clk) begin
        if (K > 0) begin
            r_dim_k <= K;
            r_dim_m <= M;
            r_dim_n <= N;
        end
    end

    //=========================================================================
    // Module Instantiations
    //=========================================================================

    // 1. Input Feeder for Matrix A (Horizontal)
    InputShifter feeder_a (
        .clk(clk),
        .rst_n(rst_n),
        .fsm_state(curr_state),
        .mem_data(A_data_out),
        .dim_k(r_dim_k), 
        .cycle_cnt(global_timer),
        .feed_data(horizontal_feed)
    );

    // 2. Input Feeder for Matrix B (Vertical)
    InputShifter feeder_b (
        .clk(clk),
        .rst_n(rst_n),
        .fsm_state(curr_state),
        .mem_data(B_data_out),
        .dim_k(r_dim_k),
        .cycle_cnt(global_timer),
        .feed_data(vertical_feed)
    );

    // 3. Main Systolic Array Core
    SystolicArrayCore core (
        .clk(clk),
        .rst_n(rst_n),
        .ctrl_state(curr_state),
        .row_in(horizontal_feed),
        .col_in(vertical_feed),
        .row_res_0(result_row_0),
        .row_res_1(result_row_1),
        .row_res_2(result_row_2),
        .row_res_3(result_row_3)
    );

    // 4. Main Controller (FSM & Memory Interface)
    TpuControlUnit #(.ADDR_WIDTH(ADDR_BITS)) main_ctrl (
        .clk(clk),
        .rst_n(rst_n),
        .trigger(in_valid),
        .is_busy(busy),
        .dim_k(r_dim_k),
        .dim_m(r_dim_m),
        .dim_n(r_dim_n),
        .res_0(result_row_0),
        .res_1(result_row_1),
        .res_2(result_row_2),
        .res_3(result_row_3),
        .current_state(curr_state),
        .next_state_logic(next_state),
        .we_a(A_wr_en),
        .we_b(B_wr_en),
        .we_c(C_wr_en),
        .wdata_a(A_data_in),
        .wdata_b(B_data_in),
        .wdata_c(C_data_in),
        .addr_a(A_index),
        .addr_b(B_index),
        .addr_c(C_index),
        .timer_out(global_timer)
    );

endmodule