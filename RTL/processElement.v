module ProcessingElement(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [1:0]  fsm_state,
    
    input  signed [7:0] op_a,    // Input from Left
    input  signed [7:0] op_b,    // Input from Top

    output reg    [7:0] pass_a,  // Pass to Right
    output reg    [7:0] pass_b,  // Pass to Bottom
    
    output wire   [31:0] res_out // Accumulator result
);  
    
    // Internal Registers
    reg [31:0] accumulator;
    
    // Combinational Logic
    wire signed [31:0] mult_result;
    assign mult_result = op_a * op_b;
    assign res_out     = accumulator;

    localparam S_RESET = 2'd0;
    localparam S_CALC  = 2'd1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            accumulator <= 32'd0;
            pass_a      <= 8'd0;
            pass_b      <= 8'd0;
        end else if (fsm_state == S_CALC) begin
            accumulator <= accumulator + mult_result;
            pass_a      <= op_a;
            pass_b      <= op_b;
        end else if (fsm_state == S_RESET) begin
            accumulator <= 32'd0;
        end
        // Note: Logic maintains values if not in CALC or RESET
    end

endmodule