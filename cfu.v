`include "RTL/TPU.v"
`include "RTL/global_buffer_bram.v"

module Cfu
#(
    parameter ADDR_BITS = 12,
    parameter DATA_BITS = 32,
    parameter C_BITS    = 128,
    
    // Finite State Machine States (TPU)
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
  // Global Instruction Decoding & State Tracking
  //===========================================================================
  wire [2:0] funct3 = cmd_payload_function_id[2:0];
  wire [6:0] funct7 = cmd_payload_function_id[9:3];

  // Op0 = TPU, Op1 = ReLU
  // 這些選擇訊號只在 cmd_valid 為 High 時有效
  wire tpu_sel_comb  = (funct3 == 3'd0);
  wire relu_sel_comb = (funct3 == 3'd1);

  // 1. Command Dispatch: 只把 valid 訊號送給被選中的模組
  wire tpu_cmd_valid  = cmd_valid && tpu_sel_comb;
  wire relu_cmd_valid = cmd_valid && relu_sel_comb;

  // 內部訊號宣告
  reg         tpu_cmd_ready;
  reg         tpu_rsp_valid;
  reg  [31:0] tpu_rsp_payload;

  wire        relu_cmd_ready;
  reg         relu_rsp_valid;
  reg  [31:0] relu_rsp_payload;

  //===========================================================================
  // 重要修正：記憶當前任務
  //===========================================================================
  reg ongoing_job_is_relu;

  always @(posedge clk) begin
    if (reset) begin
        ongoing_job_is_relu <= 1'b0;
    end else if (cmd_valid && cmd_ready) begin
        // 當 Handshake 成功時，鎖存當下的 funct3
        // 這樣在 CPU 等待回應期間，我們才知道該聽誰的 response
        ongoing_job_is_relu <= relu_sel_comb;
    end
  end

  //===========================================================================
  // PART 1: TPU Implementation (CFU_OP0)
  //===========================================================================
  // ... (保留原本 TPU 的邏輯變數宣告) ...
  reg  soft_rst_n;
  reg  tpu_trigger;           
  reg  [31:0] dim_k, dim_m, dim_n;
  wire [6:0]  func_code;      
  wire is_busy;               
  reg  [3:0]  curr_state;
  reg  [31:0] perf_counter;   
  wire [31:0]       rdata_a, rdata_b;
  wire [C_BITS-1:0] rdata_c;
  wire tpu_we_a, tpu_we_b, tpu_we_c;
  wire [ADDR_BITS-1:0] tpu_addr_a, tpu_addr_b, tpu_addr_c;
  wire [31:0]       tpu_wdata_a, tpu_wdata_b;
  wire [C_BITS-1:0] tpu_wdata_c;
  reg  cpu_we_a, cpu_we_b, cpu_we_c;
  reg  [ADDR_BITS-1:0] cpu_addr_a, cpu_addr_b, cpu_addr_c;
  reg  [31:0]          cpu_wdata_a, cpu_wdata_b;
  reg  [C_BITS-1:0]    cpu_wdata_c; 
  wire final_we_a, final_we_b, final_we_c;
  wire [ADDR_BITS-1:0] final_addr_a, final_addr_b, final_addr_c;
  wire [31:0]       final_wdata_a, final_wdata_b;
  wire [C_BITS-1:0] final_wdata_c;

  // --- Logic Implementation (TPU) ---
  assign func_code = funct7;
  assign final_we_a = (is_busy) ? tpu_we_a : cpu_we_a;
  assign final_we_b = (is_busy) ? tpu_we_b : cpu_we_b;
  assign final_we_c = (is_busy) ? tpu_we_c : cpu_we_c;
  assign final_addr_a = (is_busy) ? tpu_addr_a : cpu_addr_a;
  assign final_addr_b = (is_busy) ? tpu_addr_b : cpu_addr_b;
  assign final_addr_c = (is_busy) ? tpu_addr_c : cpu_addr_c;
  assign final_wdata_a = (tpu_trigger) ? tpu_wdata_a : cpu_wdata_a;
  assign final_wdata_b = (tpu_trigger) ? tpu_wdata_b : cpu_wdata_b;
  assign final_wdata_c = (is_busy)     ? tpu_wdata_c : cpu_wdata_c;

  // --- Module Instantiation (TPU) ---
  global_buffer_bram #(.ADDR_BITS(ADDR_BITS), .DATA_BITS(DATA_BITS)) 
  ram_a (.clk(clk), .rst_n(reset), .ram_en(1'b1), .wr_en(final_we_a), .index(final_addr_a), .data_in(final_wdata_a), .data_out(rdata_a));

  global_buffer_bram #(.ADDR_BITS(ADDR_BITS), .DATA_BITS(DATA_BITS)) 
  ram_b (.clk(clk), .rst_n(reset), .ram_en(1'b1), .wr_en(final_we_b), .index(final_addr_b), .data_in(final_wdata_b), .data_out(rdata_b));

  global_buffer_bram #(.ADDR_BITS(ADDR_BITS), .DATA_BITS(C_BITS)) 
  ram_c (.clk(clk), .rst_n(reset), .ram_en(1'b1), .wr_en(final_we_c), .index(final_addr_c), .data_in(final_wdata_c), .data_out(rdata_c));

  TPU core_unit (
    .clk(clk), .rst_n(soft_rst_n), .in_valid(tpu_trigger),
    .K(dim_k), .M(dim_m), .N(dim_n), .busy(is_busy),
    .A_wr_en(tpu_we_a), .A_index(tpu_addr_a), .A_data_in(tpu_wdata_a), .A_data_out(rdata_a),
    .B_wr_en(tpu_we_b), .B_index(tpu_addr_b), .B_data_in(tpu_wdata_b), .B_data_out(rdata_b),
    .C_wr_en(tpu_we_c), .C_index(tpu_addr_c), .C_data_in(tpu_wdata_c), .C_data_out(rdata_c)
  );

  // --- Finite State Machine (TPU) ---
  always @(negedge clk) begin
    if (reset) begin
      curr_state   <= ST_IDLE;
      perf_counter <= 32'd0;
    end else begin
      case(curr_state)
        ST_IDLE: begin
          // 使用 gated valid signal
          if (tpu_cmd_valid) curr_state <= ST_DECODE;
          else               curr_state <= ST_IDLE;
        end
        ST_DECODE: begin
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
        ST_CLEANUP: begin curr_state <= ST_IDLE; end
        ST_READ_C0: begin if (rsp_ready) curr_state <= ST_CLEANUP; else curr_state <= ST_READ_C3; end
        ST_READ_C1: begin if (rsp_ready) curr_state <= ST_CLEANUP; else curr_state <= ST_READ_C3; end
        ST_READ_C2: begin if (rsp_ready) curr_state <= ST_CLEANUP; else curr_state <= ST_READ_C3; end
        ST_READ_C3: begin if (rsp_ready) curr_state <= ST_CLEANUP; else curr_state <= ST_READ_C3; end
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

  // Output Control Logic (TPU)
  always @(posedge clk) begin
    soft_rst_n <= 1'b1;
    case(curr_state)
      ST_IDLE: begin
        tpu_cmd_ready <= 1'b0; tpu_rsp_valid <= 1'b0; tpu_trigger <= 1'b0;
      end
      ST_DECODE: begin
        tpu_cmd_ready <= 1'b1; // ACK
        case (func_code)
          7'd1: begin soft_rst_n <= 1'b0; dim_k <= 'bx; dim_m <= 'bx; dim_n <= 'bx; end
          7'd2: dim_k <= cmd_payload_inputs_0; 
          7'd3: dim_m <= cmd_payload_inputs_0; 
          7'd4: dim_n <= cmd_payload_inputs_0; 
          7'd5: begin cpu_addr_a <= cmd_payload_inputs_0[ADDR_BITS-1:0]; cpu_wdata_a <= cmd_payload_inputs_1; cpu_we_a <= 1'b1; end
          7'd6: begin cpu_we_a <= 1'b0; cpu_addr_b <= cmd_payload_inputs_0[ADDR_BITS-1:0]; cpu_wdata_b <= cmd_payload_inputs_1; cpu_we_b <= 1'b1; end
          7'd7: begin cpu_we_a <= 1'b0; cpu_we_b <= 1'b0; tpu_trigger <= 1'b1; end
          7'd10, 7'd11, 7'd12, 7'd13: begin cpu_we_c <= 1'b0; cpu_addr_c <= cmd_payload_inputs_0[ADDR_BITS-1:0]; end
        endcase
      end
      ST_HANDSHAKE: begin tpu_cmd_ready <= 1'b0; tpu_rsp_valid <= 1'b1; end
      ST_CLEANUP:   begin tpu_cmd_ready <= 1'b0; tpu_rsp_valid <= 1'b0; end
      ST_READ_C0:   begin tpu_rsp_payload <= rdata_c[31:0]; tpu_cmd_ready <= 1'b0; tpu_rsp_valid <= 1'b1; end
      ST_READ_C1:   begin tpu_rsp_payload <= rdata_c[63:32]; tpu_cmd_ready <= 1'b0; tpu_rsp_valid <= 1'b1; end
      ST_READ_C2:   begin tpu_rsp_payload <= rdata_c[95:64]; tpu_cmd_ready <= 1'b0; tpu_rsp_valid <= 1'b1; end
      ST_READ_C3:   begin tpu_rsp_payload <= rdata_c[127:96]; tpu_cmd_ready <= 1'b0; tpu_rsp_valid <= 1'b1; end
      ST_EXECUTE:   begin tpu_trigger <= 1'b0; tpu_cmd_ready <= 1'b0; tpu_rsp_valid <= 1'b0; tpu_rsp_payload <= perf_counter; end
    endcase
  end

  //===========================================================================
  // PART 2: ReLU / Quantized Multiplier Implementation (CFU_OP1)
  //===========================================================================
  reg signed [7:0] stored_shift;
  assign relu_cmd_ready = ~relu_rsp_valid; // Simple handshake
  
  // Logic
  wire signed [31:0] relu_input_val  = cmd_payload_inputs_0;
  wire signed [31:0] relu_multiplier = cmd_payload_inputs_1;
  wire signed [7:0] shift = stored_shift;
  wire shift_is_left = (shift > 0);
  wire [4:0] left_shift = shift_is_left ? shift[4:0] : 5'd0;
  wire [4:0] right_shift = shift_is_left ? 5'd0 : (-shift[4:0]);
  wire signed [31:0] input_shifted = relu_input_val <<< left_shift;
  wire signed [63:0] product = $signed(input_shifted) * $signed(relu_multiplier);
  wire signed [63:0] nudge = 64'sh40000000;
  wire signed [63:0] sum = product + nudge;
  wire signed [31:0] high_mul = sum >>> 31; 
  wire [31:0] mask = (32'd1 << right_shift) - 32'd1;
  wire [31:0] remainder = high_mul & mask;
  wire [31:0] threshold = mask >> 1;
  wire [31:0] threshold_adjusted = threshold + ((high_mul < 0) ? 32'd1 : 32'd0);
  wire signed [31:0] quotient_raw = high_mul >>> right_shift;
  wire round_up = (right_shift > 0) && (remainder > threshold_adjusted);
  wire signed [31:0] final_result = quotient_raw + (round_up ? 32'd1 : 32'd0);

  // ReLU State Machine
  always @(posedge clk) begin
    if (reset) begin
      relu_rsp_valid    <= 1'b0;
      relu_rsp_payload  <= 32'd0;
      stored_shift      <= 8'd0;
    end else if (relu_rsp_valid) begin
      // Wait for handshake response (rsp_ready)
      if (rsp_ready) relu_rsp_valid <= 1'b0;
    end else if (relu_cmd_valid) begin // Check gated valid
      relu_rsp_valid <= 1'b1;
      case (funct7)
        7'd0: relu_rsp_payload <= final_result;
        7'd1: begin stored_shift <= cmd_payload_inputs_0[7:0]; relu_rsp_payload <= 32'd0; end
        default: relu_rsp_payload <= 32'd0;
      endcase
    end
  end

  //===========================================================================
  // FINAL OUTPUT MUX
  //===========================================================================
  always @(*) begin
    // Cmd Ready 必須依據 "當下的輸入" 決定
    if (relu_sel_comb) begin
        cmd_ready = relu_cmd_ready;
    end else begin
        cmd_ready = tpu_cmd_ready;
    end

    // Rsp Valid/Payload 必須依據 "剛才執行的工作 (State)" 決定
    if (ongoing_job_is_relu) begin
        rsp_valid             = relu_rsp_valid;
        rsp_payload_outputs_0 = relu_rsp_payload;
    end else begin
        rsp_valid             = tpu_rsp_valid;
        rsp_payload_outputs_0 = tpu_rsp_payload;
    end
  end

endmodule