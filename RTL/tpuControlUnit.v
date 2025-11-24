//=============================================================================
// Submodule: TpuControlUnit
// Description: Main FSM and Address Generation
//=============================================================================
module TpuControlUnit
#(
    parameter ADDR_WIDTH = 16
)
(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        trigger,
    input  wire        is_busy,
    input  wire [7:0]  dim_k,
    input  wire [7:0]  dim_m,
    input  wire [7:0]  dim_n,
    input  wire [127:0] res_0,
    input  wire [127:0] res_1,
    input  wire [127:0] res_2,
    input  wire [127:0] res_3,
    
    output wire [1:0]  current_state,
    output wire [1:0]  next_state_logic,
    
    output wire        we_a,
    output wire        we_b,
    output wire        we_c,
    
    output wire [31:0] wdata_a,
    output wire [31:0] wdata_b,
    output wire [127:0] wdata_c,
    
    output wire [ADDR_WIDTH-1:0] addr_a,
    output wire [ADDR_WIDTH-1:0] addr_b,
    output wire [ADDR_WIDTH-1:0] addr_c,
    
    output wire [31:0] timer_out
);

    // State Registers
    reg [1:0] present_state;
    reg [1:0] next_state;

    // Configuration Logic
    reg [2:0] valid_output_rows; 
    reg [7:0] total_blocks_m;
    reg [7:0] total_blocks_n;

    // Counters
    reg [7:0]  blk_idx_m;
    reg [7:0]  blk_idx_n;
    reg [31:0] main_counter;
    reg [31:0] drain_counter; 

    // Address Pointers
    reg [15:0] ptr_a;
    reg [15:0] ptr_b;
    reg [15:0] ptr_c;

    // FSM States
    localparam S_WAIT    = 2'd0;
    localparam S_COMPUTE = 2'd1;
    localparam S_DRAIN   = 2'd2;
    localparam S_DONE    = 2'd3;

    // Assignments
    assign current_state    = present_state;
    assign next_state_logic = next_state;
    assign timer_out        = main_counter;
    
    assign addr_a = (present_state == S_COMPUTE) ? ptr_a : 16'd0;
    assign addr_b = (present_state == S_COMPUTE) ? ptr_b : 16'd0;
    assign addr_c = ptr_c;

    // Write Enables
    assign we_a = 1'b0;
    assign we_b = 1'b0;
    assign we_c = (next_state == S_DRAIN) ? 1'b1 : 1'b0;

    // Data Write Buses (Unused for A/B)
    assign wdata_a = 32'd0;
    assign wdata_b = 32'd0;

    // Mux output data based on drain counter
    assign wdata_c = (!rst_n) ? 128'd0 :
                     (drain_counter == 2'd0) ? res_0 :
                     (drain_counter == 2'd1) ? res_1 :
                     (drain_counter == 2'd2) ? res_2 :
                     (drain_counter == 2'd3) ? res_3 : 128'd0;

    //-------------------------------------------------------------------------
    // FSM Sequential Logic
    //-------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) present_state <= S_WAIT;
        else        present_state <= next_state;
    end

    //-------------------------------------------------------------------------
    // FSM Combinational Logic
    //-------------------------------------------------------------------------
    always @(*) begin
        case (present_state)
            S_WAIT: 
                next_state = (trigger || is_busy) ? S_COMPUTE : S_WAIT;
            
            S_COMPUTE: 
                // K + 6 cycles latency for systolic array fill
                next_state = (main_counter <= (dim_k + 6)) ? S_COMPUTE : S_DRAIN;
            
            S_DRAIN: 
                next_state = (drain_counter < valid_output_rows) ? S_DRAIN : 
                             (blk_idx_n == total_blocks_n) ? S_DONE : S_WAIT;
            
            S_DONE: 
                next_state = S_WAIT;
                
            default: 
                next_state = S_WAIT;
        endcase
    end

    //-------------------------------------------------------------------------
    // Block Calculation Logic
    //-------------------------------------------------------------------------
    always @(*) begin
        total_blocks_m = ((dim_m + 3) >> 2); // ceil(M/4)
        total_blocks_n = ((dim_n + 3) >> 2); // ceil(N/4)
    end

    // Output Rows Calculation
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) valid_output_rows <= 0;
        else if (present_state == is_busy)
            // Determine if we need 1, 2, 3, or 4 rows for the last block
            valid_output_rows <= (blk_idx_m == (total_blocks_m - 1) && dim_m[1:0] != 2'b00) ? dim_m[1:0] : 4;
        else
            valid_output_rows <= valid_output_rows;
    end

    //-------------------------------------------------------------------------
    // Counters
    //-------------------------------------------------------------------------
    
    // Main Cycle Counter
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) main_counter <= 0;
        else begin
            if (present_state == S_COMPUTE) main_counter <= main_counter + 1;
            else main_counter <= 0;
        end
    end

    // M-Dimension Block Index
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) blk_idx_m <= 0;
        else begin
            if (drain_counter == valid_output_rows - 1 && present_state == S_DRAIN) begin
                if (blk_idx_m < total_blocks_m) blk_idx_m <= blk_idx_m + 1;
                else blk_idx_m <= 1; // Reset to 1 for next loop
            end else if (present_state == S_DONE) begin
                blk_idx_m <= 0;
            end
        end
    end

    // N-Dimension Block Index
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) blk_idx_n <= 0;
        else begin
            if (next_state == S_WAIT && blk_idx_m == total_blocks_m && is_busy)
                blk_idx_n <= blk_idx_n + 1;
            else if (present_state == S_DONE)
                blk_idx_n <= 0;
        end
    end

    // Drain Counter (Writing output)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) drain_counter <= 0;
        else if (present_state == S_DRAIN) drain_counter <= drain_counter + 1;
        else drain_counter <= 0;
    end

    //-------------------------------------------------------------------------
    // Address Generation
    //-------------------------------------------------------------------------
    
    // Pointer A
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) ptr_a <= 16'd0;
        else begin
            if (present_state == S_DRAIN) begin
                if (dim_k == 1) ptr_a <= 1;
                else if (next_state == S_WAIT) ptr_a <= ptr_a + 16'd1;
            end 
            else if (present_state == S_WAIT && blk_idx_m == total_blocks_m) begin
                ptr_a <= 0;
            end 
            else if (present_state == S_DONE) begin
                ptr_a <= 16'd0;
            end 
            else if (present_state == S_COMPUTE) begin
                if (main_counter < dim_k - 1) ptr_a <= ptr_a + 16'd1;
            end
        end
    end

    // Pointer B
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) ptr_b <= 0;
        else begin
            if (present_state == S_WAIT && is_busy) begin
                ptr_b <= dim_k * blk_idx_n; // Offset Jump
            end 
            else if (present_state == S_DONE) begin
                ptr_b <= 16'd0;
            end 
            else if (present_state == S_COMPUTE) begin
                if (main_counter < dim_k) ptr_b <= ptr_b + 1;
            end
        end
    end

    // Pointer C
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) ptr_c <= 0;
        else begin
            if (present_state == S_DONE) ptr_c <= 0;
            else if (present_state == S_DRAIN && next_state == S_DRAIN)
                ptr_c <= ptr_c + 1;
        end
    end

endmodule