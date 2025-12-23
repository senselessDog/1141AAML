module SystolicArrayCore(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [1:0]  ctrl_state,
    input  wire [31:0] row_in,
    input  wire [31:0] col_in,
    
    output wire [127:0] row_res_0,
    output wire [127:0] row_res_1,
    output wire [127:0] row_res_2,
    output wire [127:0] row_res_3
);

    localparam MODE_DRAIN = 2'd2;

    // Internal Arrays
    wire [31:0] acc_results [0:15];
    
    // Interconnects
    wire [95:0] h_link; // Horizontal links
    wire [95:0] v_link; // Vertical links

    // Output Mapping (Combines 4x32bit into 128bit bus)
    assign row_res_0 = (ctrl_state == MODE_DRAIN) ? {acc_results[0],  acc_results[1],  acc_results[2],  acc_results[3]}  : 128'b0;
    assign row_res_1 = (ctrl_state == MODE_DRAIN) ? {acc_results[4],  acc_results[5],  acc_results[6],  acc_results[7]}  : 128'b0;
    assign row_res_2 = (ctrl_state == MODE_DRAIN) ? {acc_results[8],  acc_results[9],  acc_results[10], acc_results[11]} : 128'b0;
    assign row_res_3 = (ctrl_state == MODE_DRAIN) ? {acc_results[12], acc_results[13], acc_results[14], acc_results[15]} : 128'b0;

    //-------------------------------------------------------------------------
    // Processing Element Instantiations (4x4 Grid)
    //-------------------------------------------------------------------------
    // Row 0
    ProcessingElement cell_00 (.clk(clk), .rst_n(rst_n), .fsm_state(ctrl_state), .op_a(row_in[31:24]), .op_b(col_in[31:24]), .pass_a(h_link[7:0]),   .pass_b(v_link[7:0]),   .res_out(acc_results[0]));
    ProcessingElement cell_01 (.clk(clk), .rst_n(rst_n), .fsm_state(ctrl_state), .op_a(h_link[7:0]),   .op_b(col_in[23:16]), .pass_a(h_link[15:8]),  .pass_b(v_link[15:8]),  .res_out(acc_results[1]));
    ProcessingElement cell_02 (.clk(clk), .rst_n(rst_n), .fsm_state(ctrl_state), .op_a(h_link[15:8]),  .op_b(col_in[15:8]),  .pass_a(h_link[23:16]), .pass_b(v_link[23:16]), .res_out(acc_results[2]));
    ProcessingElement cell_03 (.clk(clk), .rst_n(rst_n), .fsm_state(ctrl_state), .op_a(h_link[23:16]), .op_b(col_in[7:0]),   .pass_a(),              .pass_b(v_link[31:24]), .res_out(acc_results[3]));

    // Row 1
    ProcessingElement cell_10 (.clk(clk), .rst_n(rst_n), .fsm_state(ctrl_state), .op_a(row_in[23:16]), .op_b(v_link[7:0]),   .pass_a(h_link[31:24]), .pass_b(v_link[39:32]), .res_out(acc_results[4]));
    ProcessingElement cell_11 (.clk(clk), .rst_n(rst_n), .fsm_state(ctrl_state), .op_a(h_link[31:24]), .op_b(v_link[15:8]),  .pass_a(h_link[39:32]), .pass_b(v_link[47:40]), .res_out(acc_results[5]));
    ProcessingElement cell_12 (.clk(clk), .rst_n(rst_n), .fsm_state(ctrl_state), .op_a(h_link[39:32]), .op_b(v_link[23:16]), .pass_a(h_link[47:40]), .pass_b(v_link[55:48]), .res_out(acc_results[6]));
    ProcessingElement cell_13 (.clk(clk), .rst_n(rst_n), .fsm_state(ctrl_state), .op_a(h_link[47:40]), .op_b(v_link[31:24]), .pass_a(),              .pass_b(v_link[63:56]), .res_out(acc_results[7]));

    // Row 2
    ProcessingElement cell_20 (.clk(clk), .rst_n(rst_n), .fsm_state(ctrl_state), .op_a(row_in[15:8]),  .op_b(v_link[39:32]), .pass_a(h_link[55:48]), .pass_b(v_link[71:64]), .res_out(acc_results[8]));
    ProcessingElement cell_21 (.clk(clk), .rst_n(rst_n), .fsm_state(ctrl_state), .op_a(h_link[55:48]), .op_b(v_link[47:40]), .pass_a(h_link[63:56]), .pass_b(v_link[79:72]), .res_out(acc_results[9]));
    ProcessingElement cell_22 (.clk(clk), .rst_n(rst_n), .fsm_state(ctrl_state), .op_a(h_link[63:56]), .op_b(v_link[55:48]), .pass_a(h_link[71:64]), .pass_b(v_link[87:80]), .res_out(acc_results[10]));
    ProcessingElement cell_23 (.clk(clk), .rst_n(rst_n), .fsm_state(ctrl_state), .op_a(h_link[71:64]), .op_b(v_link[63:56]), .pass_a(),              .pass_b(v_link[95:88]), .res_out(acc_results[11]));

    // Row 3
    ProcessingElement cell_30 (.clk(clk), .rst_n(rst_n), .fsm_state(ctrl_state), .op_a(row_in[7:0]),   .op_b(v_link[71:64]), .pass_a(h_link[79:72]), .pass_b(),              .res_out(acc_results[12]));
    ProcessingElement cell_31 (.clk(clk), .rst_n(rst_n), .fsm_state(ctrl_state), .op_a(h_link[79:72]), .op_b(v_link[79:72]), .pass_a(h_link[87:80]), .pass_b(),              .res_out(acc_results[13]));
    ProcessingElement cell_32 (.clk(clk), .rst_n(rst_n), .fsm_state(ctrl_state), .op_a(h_link[87:80]), .op_b(v_link[87:80]), .pass_a(h_link[95:88]), .pass_b(),              .res_out(acc_results[14]));
    ProcessingElement cell_33 (.clk(clk), .rst_n(rst_n), .fsm_state(ctrl_state), .op_a(h_link[95:88]), .op_b(v_link[95:88]), .pass_a(),              .pass_b(),              .res_out(acc_results[15]));

endmodule