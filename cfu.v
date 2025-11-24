`include "RTL/TPU.v"
`include "RTL/global_buffer_bram.v"

module Cfu
#(
    parameter ADDR_BITS = 12,
    parameter DATA_BITS = 32,
    parameter C_BITS    = 128,
    
    // Finite State Machine States
    parameter ST_IDLE       = 4'd0,
    parameter ST_DECODE     = 4'd1,
    parameter ST_HANDSHAKE  = 4'd2, 
    parameter ST_CLEANUP    = 4'd3, 
    parameter ST_READ_C0    = 4'd4, 
    parameter ST_READ_C1    = 4'd5, 
    parameter ST_READ_C2    = 4'd6, 
    parameter ST_READ_C3    = 4'd7, 
    parameter ST_EXECUTE    = 4'd8  
)(
    input              cmd_valid,
    output reg         cmd_ready,
    input      [9:0]   cmd_payload_function_id,
    input      [31:0]  cmd_payload_inputs_0,
    input      [31:0]  cmd_payload_inputs_1,
    output reg         rsp_valid,
    input              rsp_ready,
    output reg [31:0]  rsp_payload_outputs_0,
    input              reset,
    input              clk
);

  //===========================================================================
  // Signal Declarations
  //===========================================================================

  // System & Operation Signals
  reg  soft_rst_n;
  reg  tpu_trigger;           
  reg  [31:0] dim_k, dim_m, dim_n;
  wire [6:0]  func_code;      

  // Hardware Status
  wire is_busy;               
  reg  [3:0]  curr_state;
  reg  [31:0] perf_counter;   

  // Memory Interface Signals (Read Data)
  wire [31:0]       rdata_a, rdata_b;
  wire [C_BITS-1:0] rdata_c;
  
  // TPU-Side Memory Controls (Driven by TPU hardware)
  wire tpu_we_a, tpu_we_b, tpu_we_c;
  wire [ADDR_BITS-1:0] tpu_addr_a, tpu_addr_b, tpu_addr_c;
  wire [31:0]       tpu_wdata_a, tpu_wdata_b;
  wire [C_BITS-1:0] tpu_wdata_c;

  // CPU-Side Memory Controls (Driven by Software commands)
  reg  cpu_we_a, cpu_we_b, cpu_we_c;
  reg  [ADDR_BITS-1:0] cpu_addr_a, cpu_addr_b, cpu_addr_c;
  reg  [31:0]          cpu_wdata_a, cpu_wdata_b;
  reg  [C_BITS-1:0]    cpu_wdata_c; // Placeholder for C write (unused)

  // Multiplexed Signals (Final signals sent to BRAM)
  wire final_we_a, final_we_b, final_we_c;
  wire [ADDR_BITS-1:0] final_addr_a, final_addr_b, final_addr_c;
  wire [31:0]       final_wdata_a, final_wdata_b;
  wire [C_BITS-1:0] final_wdata_c;

  //===========================================================================
  // Logic Implementation
  //===========================================================================

  // Decode Operation Code
  assign func_code = cmd_payload_function_id[9:3];

  // Memory Muxing Logic:
  // If TPU is busy, it owns the memory. Otherwise, CPU owns it.
  assign final_we_a = (is_busy) ? tpu_we_a : cpu_we_a;
  assign final_we_b = (is_busy) ? tpu_we_b : cpu_we_b;
  assign final_we_c = (is_busy) ? tpu_we_c : cpu_we_c;

  assign final_addr_a = (is_busy) ? tpu_addr_a : cpu_addr_a;
  assign final_addr_b = (is_busy) ? tpu_addr_b : cpu_addr_b;
  assign final_addr_c = (is_busy) ? tpu_addr_c : cpu_addr_c;

  // Data Input Muxing:
  // If triggered, data might come from TPU logic (originally: in_valid ? A_data_in : ...)
  assign final_wdata_a = (tpu_trigger) ? tpu_wdata_a : cpu_wdata_a;
  assign final_wdata_b = (tpu_trigger) ? tpu_wdata_b : cpu_wdata_b;
  assign final_wdata_c = (is_busy)     ? tpu_wdata_c : cpu_wdata_c;

  //===========================================================================
  // Module Instantiation
  //===========================================================================

  global_buffer_bram #(.ADDR_BITS(ADDR_BITS), .DATA_BITS(DATA_BITS)) 
  ram_a (
    .clk(clk), .rst_n(reset), .ram_en(1'b1),
    .wr_en(final_we_a), .index(final_addr_a), .data_in(final_wdata_a), .data_out(rdata_a)
  );

  global_buffer_bram #(.ADDR_BITS(ADDR_BITS), .DATA_BITS(DATA_BITS)) 
  ram_b (
    .clk(clk), .rst_n(reset), .ram_en(1'b1),
    .wr_en(final_we_b), .index(final_addr_b), .data_in(final_wdata_b), .data_out(rdata_b)
  );

  global_buffer_bram #(.ADDR_BITS(ADDR_BITS), .DATA_BITS(C_BITS)) 
  ram_c (
    .clk(clk), .rst_n(reset), .ram_en(1'b1),
    .wr_en(final_we_c), .index(final_addr_c), .data_in(final_wdata_c), .data_out(rdata_c)
  );

  TPU core_unit (
    .clk(clk),
    .rst_n(soft_rst_n),
    .in_valid(tpu_trigger),
    .K(dim_k), .M(dim_m), .N(dim_n),
    .busy(is_busy),
    .A_wr_en(tpu_we_a), .A_index(tpu_addr_a), .A_data_in(tpu_wdata_a), .A_data_out(rdata_a),
    .B_wr_en(tpu_we_b), .B_index(tpu_addr_b), .B_data_in(tpu_wdata_b), .B_data_out(rdata_b),
    .C_wr_en(tpu_we_c), .C_index(tpu_addr_c), .C_data_in(tpu_wdata_c), .C_data_out(rdata_c)
  );

  //===========================================================================
  // Finite State Machine
  //===========================================================================
  
  // Next State Logic
  always @(negedge clk) begin
    if (reset) begin
      curr_state   <= ST_IDLE;
      perf_counter <= 32'd0;
    end else begin
      case(curr_state)
        ST_IDLE: begin
          if (cmd_valid) curr_state <= ST_DECODE;
          else           curr_state <= ST_IDLE;
        end

        ST_DECODE: begin
          // Decodes the op and jumps to appropriate read/wait state
          if      (func_code == 7'd10) curr_state <= ST_READ_C0;
          else if (func_code == 7'd11) curr_state <= ST_READ_C1;
          else if (func_code == 7'd12) curr_state <= ST_READ_C2;
          else if (func_code == 7'd13) curr_state <= ST_READ_C3;
          else if (func_code == 7'd7)  curr_state <= ST_EXECUTE;
          else                         curr_state <= ST_HANDSHAKE;
        end

        ST_HANDSHAKE: begin 
          if (rsp_ready) curr_state <= ST_CLEANUP;
          else           curr_state <= ST_HANDSHAKE;
        end

        ST_CLEANUP: begin   
          curr_state <= ST_IDLE;
        end

        // Read Latency States
        ST_READ_C0: begin
          if (rsp_ready) curr_state <= ST_CLEANUP; else curr_state <= ST_READ_C3; 
        end
        ST_READ_C1: begin
          if (rsp_ready) curr_state <= ST_CLEANUP; else curr_state <= ST_READ_C3;
        end
        ST_READ_C2: begin
          if (rsp_ready) curr_state <= ST_CLEANUP; else curr_state <= ST_READ_C3;
        end
        ST_READ_C3: begin
          if (rsp_ready) curr_state <= ST_CLEANUP; else curr_state <= ST_READ_C3;
        end

        ST_EXECUTE: begin 
          if (is_busy) begin
            perf_counter <= perf_counter + 1;
            curr_state   <= ST_EXECUTE;
          end else begin
            curr_state   <= ST_HANDSHAKE;
          end
        end
        
        default: curr_state <= ST_IDLE;
      endcase
    end
  end

  // Output Control Logic
  always @(posedge clk) begin
    // Default values
    soft_rst_n <= 1'b1;

    case(curr_state)
      ST_IDLE: begin
        cmd_ready   <= 1'b0;
        rsp_valid   <= 1'b0;
        tpu_trigger <= 1'b0;
      end

      ST_DECODE: begin
        cmd_ready <= 1'b1; // ACK the command
        
        case (func_code)
          7'd1: begin // Reset
            soft_rst_n <= 1'b0;
            dim_k <= 'bx; dim_m <= 'bx; dim_n <= 'bx;
          end
          7'd2: dim_k <= cmd_payload_inputs_0; // Set K
          7'd3: dim_m <= cmd_payload_inputs_0; // Set M
          7'd4: dim_n <= cmd_payload_inputs_0; // Set N

          7'd5: begin // Set Buffer A (CPU Write)
            cpu_addr_a  <= cmd_payload_inputs_0[ADDR_BITS-1:0];
            cpu_wdata_a <= cmd_payload_inputs_1;
            cpu_we_a    <= 1'b1;
          end
          
          7'd6: begin // Set Buffer B (CPU Write)
            cpu_we_a    <= 1'b0; 
            cpu_addr_b  <= cmd_payload_inputs_0[ADDR_BITS-1:0];
            cpu_wdata_b <= cmd_payload_inputs_1;
            cpu_we_b    <= 1'b1;
          end
          
          7'd7: begin // Start TPU
            cpu_we_a    <= 1'b0;
            cpu_we_b    <= 1'b0;
            tpu_trigger <= 1'b1;
          end
          
          // For Reads (10-13), CPU sets address but clears WE
          7'd10, 7'd11, 7'd12, 7'd13: begin
            cpu_we_c    <= 1'b0;
            cpu_addr_c  <= cmd_payload_inputs_0[ADDR_BITS-1:0];
          end
        endcase
      end

      ST_HANDSHAKE: begin 
        cmd_ready <= 1'b0;
        rsp_valid <= 1'b1;
      end

      ST_CLEANUP: begin   
        cmd_ready <= 1'b0;
        rsp_valid <= 1'b0;
      end

      // Output Latching
      ST_READ_C0: begin 
        rsp_payload_outputs_0 <= rdata_c[31:0];
        cmd_ready <= 1'b0; rsp_valid <= 1'b1;
      end
      ST_READ_C1: begin 
        rsp_payload_outputs_0 <= rdata_c[63:32];
        cmd_ready <= 1'b0; rsp_valid <= 1'b1;
      end
      ST_READ_C2: begin 
        rsp_payload_outputs_0 <= rdata_c[95:64];
        cmd_ready <= 1'b0; rsp_valid <= 1'b1;
      end
      ST_READ_C3: begin 
        rsp_payload_outputs_0 <= rdata_c[127:96];
        cmd_ready <= 1'b0; rsp_valid <= 1'b1;
      end

      ST_EXECUTE: begin 
        tpu_trigger <= 1'b0; 
        cmd_ready   <= 1'b0;
        rsp_valid   <= 1'b0;
        rsp_payload_outputs_0 <= perf_counter;
      end

    endcase
  end

endmodule