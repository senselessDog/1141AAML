//=============================================================================
// Submodule: InputShifter
// Description: Handles data shifting for systolic array feeding
//=============================================================================
module InputShifter(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [1:0]  fsm_state,
    input  wire [31:0] mem_data,
    input  wire [7:0]  dim_k, 
    input  wire [31:0] cycle_cnt, 
    output wire [31:0] feed_data
);

    localparam S_IDLE = 2'b0;
    localparam S_LOAD = 2'b1;

    reg [31:0] output_buffer;
    
    // Shift registers for staggering input
    reg [7:0]  stage_0;
    reg [15:0] stage_1;
    reg [23:0] stage_2;
    reg [31:0] stage_3;

    assign feed_data = (fsm_state == S_LOAD) ? output_buffer : 32'b0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stage_0       <= 0;
            stage_1       <= 0;
            stage_2       <= 0;
            stage_3       <= 0;
            output_buffer <= 0;
        end else if (fsm_state == S_IDLE) begin
            stage_0       <= 0;
            stage_1       <= 0;
            stage_2       <= 0;
            stage_3       <= 0;
            output_buffer <= 0;
        end else if (fsm_state == S_LOAD) begin
            if (cycle_cnt < dim_k) begin
                // Load new data and shift
                stage_0 <= mem_data[31:24];
                stage_1 <= {stage_1[7:0],  mem_data[23:16]};
                stage_2 <= {stage_2[15:0], mem_data[15:8]};
                stage_3 <= {stage_3[23:0], mem_data[7:0]};
                
                // Construct output (Byte 0 from New, others from Shift Regs)
                output_buffer <= {mem_data[31:24], stage_1[7:0], stage_2[15:8], stage_3[23:16]}; 
            end else begin
                // Flush shift registers
                stage_0 <= stage_0 << 8;
                stage_1 <= stage_1 << 8;
                stage_2 <= stage_2 << 8;
                stage_3 <= stage_3 << 8;
                
                output_buffer <= {8'b0, stage_1[7:0], stage_2[15:8], stage_3[23:16]}; 
            end
        end
    end
endmodule