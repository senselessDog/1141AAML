#ifndef TENSORFLOW_LITE_KERNELS_INTERNAL_REFERENCE_INTEGER_OPS_CONV_H_
#define TENSORFLOW_LITE_KERNELS_INTERNAL_REFERENCE_INTEGER_OPS_CONV_H_
#include <cstdio>
#include <algorithm>

#include "tensorflow/lite/kernels/internal/common.h"
#include "tensorflow/lite/kernels/internal/portable_tensor_utils.h"
#include "perf.h"
#include "cfu.h" // [重要] 記得引入這個才能呼叫 cfu_op0

// ------------------------------------------------------------------
// [CFU Opcodes] 從 functional_cfu_tests.cc 搬過來的定義
// ------------------------------------------------------------------
#define CFU_RESET       1
#define CFU_SET_K       2
#define CFU_SET_M       3
#define CFU_SET_N       4
#define CFU_WRITE_A     5
#define CFU_WRITE_B     6
#define CFU_START_TPU   7
#define CFU_READ_C_3    13 // MSB
#define CFU_READ_C_2    12
#define CFU_READ_C_1    11
#define CFU_READ_C_0    10 // LSB

// 除錯開關：設為 1 開啟，0 關閉
#define ENABLE_DEBUG_PRINT 0
#define ENABLE_DEBUG_PRINT_CAPACITY 1
// 只印出前 N 筆資料，避免洗版
#define DEBUG_LIMIT 5

// 硬體方塊大小 (Tile Size)
#define TILE_SIZE 128

#define MAX_ROW_CAPACITY 512 
#define MAX_COL_CAPACITY 8192
#define MAX_CHANNEL_CAPACITY 2048

namespace im2col_buffers {
    int8_t global_im2col_buffer[MAX_ROW_CAPACITY][MAX_COL_CAPACITY];    // Matrix A
    int8_t global_filter_buffer[MAX_COL_CAPACITY][MAX_CHANNEL_CAPACITY]; // Matrix B
    int32_t global_gemm_output[MAX_ROW_CAPACITY][MAX_CHANNEL_CAPACITY];   // Matrix C
    int32_t global_filter_sums[MAX_CHANNEL_CAPACITY];
}

namespace tflite {
namespace reference_integer_ops {

inline int32_t GetPixelWithPadding(
    const int8_t* data, const RuntimeShape& shape, 
    int batch, int y, int x, int channel, 
    int height, int width, int32_t offset_val) {
    
    if (x >= 0 && x < width && y >= 0 && y < height) {
        return data[Offset(shape, batch, y, x, channel)] + offset_val;
    }
    return 0; 
}

inline void ConvPerChannel(
    const ConvParams& params, const int32_t* output_multiplier,
    const int32_t* output_shift, const RuntimeShape& input_shape,
    const int8_t* input_data, const RuntimeShape& filter_shape,
    const int8_t* filter_data, const RuntimeShape& bias_shape,
    const int32_t* bias_data, const RuntimeShape& output_shape,
    int8_t* output_data) {
    
  perf_enable_counter(6);

  // ... (Parameters extraction 保持不變) ...
  const int32_t input_offset = params.input_offset;
  const int stride_width = params.stride_width;
  const int stride_height = params.stride_height;
  const int dilation_width_factor = params.dilation_width_factor;
  const int dilation_height_factor = params.dilation_height_factor;
  const int pad_width = params.padding_values.width;
  const int pad_height = params.padding_values.height;
  const int32_t output_offset = params.output_offset;
  const int32_t output_activation_min = params.quantized_activation_min;
  const int32_t output_activation_max = params.quantized_activation_max;

  // ... (Dimensions extraction 保持不變) ...
  const int batches = MatchingDim(input_shape, 0, output_shape, 0);
  const int input_depth = input_shape.Dims(3);
  const int output_depth = MatchingDim(filter_shape, 0, output_shape, 3);
  const int input_height = input_shape.Dims(1);
  const int input_width = input_shape.Dims(2);
  const int filter_height = filter_shape.Dims(1);
  const int filter_width = filter_shape.Dims(2);
  const int filter_input_depth = filter_shape.Dims(3);
  const int output_height = output_shape.Dims(1);
  const int output_width = output_shape.Dims(2);

  const int dim_M = output_height * output_width;                 
  const int dim_K = filter_height * filter_width * input_depth;   
  const int dim_N = output_depth;                                 

  

  #if ENABLE_DEBUG_PRINT
  // 重置 Debug 計數器
  // debug_print_count = 0;
  static int debug_print_count = 0;
  printf("\n=== ConvPerChannel Debug Info ===\n");
  printf("Input Offset: %ld, Output Offset: %ld\n", input_offset, output_offset);
  printf("Dimensions: M=%d, K=%d, N=%d\n", dim_M, dim_K, dim_N);
  #endif
  #if ENABLE_DEBUG_PRINT_CAPACITY
  printf("Layer Dims -> M: %d, K: %d, N: %d\n", dim_M, dim_K, dim_N);
  if (dim_M > MAX_ROW_CAPACITY) printf("!! ERROR: M exceeds capacity !!\n");
  if (dim_K > MAX_COL_CAPACITY) printf("!! ERROR: K exceeds capacity !!\n");
  if (dim_N > MAX_CHANNEL_CAPACITY) printf("!! ERROR: N exceeds capacity !!\n");
  #endif
  for (int batch = 0; batch < batches; ++batch) {
    
    // =================================================================
    // Phase 1: Filter Packing
    // =================================================================

    for (int out_c = 0; out_c < output_depth; ++out_c) {
        int k_iterator = 0;
        int32_t current_filter_sum = 0; 

        for (int fy = 0; fy < filter_height; ++fy) {
            for (int fx = 0; fx < filter_width; ++fx) {
                for (int ic = 0; ic < filter_input_depth; ++ic) {
                    int8_t val = filter_data[Offset(filter_shape, out_c, fy, fx, ic)];
                    #if ENABLE_DEBUG_PRINT
                    if (out_c == 0 && batch == 0) { // 只印第一個 Channel
                         printf("Filter[%d] read at (y=%d,x=%d,ic=%d): %ld\n", out_c, fy, fx, ic, val);
                    }
                    #endif
                    im2col_buffers::global_filter_buffer[k_iterator++][out_c] = val;
                    current_filter_sum += val;
                }
            }
        }
        im2col_buffers::global_filter_sums[out_c] = current_filter_sum;
        
        #if ENABLE_DEBUG_PRINT
        if (out_c < DEBUG_LIMIT) {
            //  printf("Filter[%d] Sum: %ld\n", out_c, current_filter_sum);
        }
        #endif
    }
    // =================================================================
    // Phase 2: im2col Transformation
    // =================================================================
    int current_im2col_row = 0;
    for (int out_y = 0; out_y < output_height; ++out_y) {
        const int in_y_origin = (out_y * stride_height) - pad_height;
        for (int out_x = 0; out_x < output_width; ++out_x) {
            const int in_x_origin = (out_x * stride_width) - pad_width;
            int current_im2col_col = 0;
            
            for (int fy = 0; fy < filter_height; ++fy) {
                const int in_y = in_y_origin + dilation_height_factor * fy;
                for (int fx = 0; fx < filter_width; ++fx) {
                    const int in_x = in_x_origin + dilation_width_factor * fx;
                    for (int ic = 0; ic < input_depth; ++ic) {
                        
                        int8_t val_to_send;
                        if (in_x >= 0 && in_x < input_width && in_y >= 0 && in_y < input_height) {
                             val_to_send = input_data[Offset(input_shape, batch, in_y, in_x, ic)];
                        } else {
                             val_to_send = -input_offset;
                        }
                        #if ENABLE_DEBUG_PRINT
                        if (batch == 0 && out_y == 0 && out_x == 0) {
                            // printf("Input read at Pixel[0,0] (in_y=%d, in_x=%d, ic=%d): %ld\n", in_y, in_x, ic, val_to_send);
                        }
                        #endif
                        im2col_buffers::global_im2col_buffer[current_im2col_row][current_im2col_col++] = val_to_send;
                    }
                }
            }
            current_im2col_row++;
        }
    }
    // =================================================================
    // [NEW] Debug Print Global Buffers
    // =================================================================
    #if ENABLE_DEBUG_PRINT
    // 只針對第一個 Batch 印出，避免洗版
    if (batch == 0) {
        printf("\n=== Global Buffers Check (After Phase 1 & 2) ===\n");
        
        // Print Matrix A (im2col buffer)
        printf("Global Im2Col Buffer (Matrix A) [M=%d, K=%d]:\n", dim_M, dim_K);
        // 只印出前 8 行和前 8 列，避免太大
        int print_m = std::min(dim_M, 8);
        int print_k = std::min(dim_K, 8);
        
        for (int m = 0; m < print_m; ++m) {
            printf("Row %d: ", m);
            for (int k = 0; k < print_k; ++k) {
                printf("%ld ", im2col_buffers::global_im2col_buffer[m][k]);
            }
            printf("\n");
        }

        // Print Matrix B (Filter buffer)
        printf("\nGlobal Filter Buffer (Matrix B) [K=%d, N=%d]:\n", dim_K, dim_N);
        // 只印出前 8 行和前 8 列
        int print_n = std::min(dim_N, 8);
        
        for (int k = 0; k < print_k; ++k) {
            printf("Row %d: ", k);
            for (int n = 0; n < print_n; ++n) {
                printf("%ld ", im2col_buffers::global_filter_buffer[k][n]);
            }
            printf("\n");
        }
        printf("==============================================\n\n");
    }
    #endif
    // =================================================================
    // Phase 3: Hardware Tiling GEMM (含軟體累加)
    // =================================================================
    
    // =================================================================
    // Phase 3: Hardware Tiling GEMM (Correct Vertical Packing)
    // =================================================================
    
    // Init Output Buffer
    for (int m = 0; m < dim_M; ++m) {
        for (int n = 0; n < dim_N; ++n) {
             im2col_buffers::global_gemm_output[m][n] = 0;
        }
    }

    for (int m = 0; m < dim_M; m += TILE_SIZE) {
        for (int n = 0; n < dim_N; n += TILE_SIZE) {
            for (int k = 0; k < dim_K; k += TILE_SIZE) {
                
                cfu_op0(CFU_RESET, 0, 0); 
                cfu_op0(CFU_SET_M, TILE_SIZE, 0);
                cfu_op0(CFU_SET_N, TILE_SIZE, 0);
                cfu_op0(CFU_SET_K, TILE_SIZE, 0);

                #if ENABLE_DEBUG_PRINT
                if (m==0 && n==0 && k==0) printf("--- Sending Tile (0,0) ---\n");
                #endif

                // [FIXED] Send Input A (Vertical Strip Packing)
                // 目標：填寫 K=0 的 4 個 Row，再填寫 K=1 的 4 個 Row...
                int write_idx = 0;
                for (int m_strip = 0; m_strip < TILE_SIZE; m_strip += 4) { 
                    for (int k_idx = 0; k_idx < TILE_SIZE; ++k_idx) {      
                        uint32_t packed_val = 0;
                        #if ENABLE_DEBUG_PRINT
                        int8_t bytes[4];
                        #endif
                        for (int byte = 0; byte < 4; ++byte) {
                            int logical_r = m + m_strip + byte; // Row 變化
                            int logical_c = k + k_idx;          // K (Time) 固定
                            
                            int8_t val = 0;
                            if (logical_r < dim_M && logical_c < dim_K) {
                                val = im2col_buffers::global_im2col_buffer[logical_r][logical_c];
                            }
                            // Pack: MSB (Byte 3) -> Row 0 (top row)
                            packed_val |= ((uint32_t)((uint8_t)val)) << ((3 - byte) * 8);
                            #if ENABLE_DEBUG_PRINT
                            bytes[byte] = val;
                            #endif
                        }
                        cfu_op0(CFU_WRITE_A, write_idx++, packed_val);

                        #if ENABLE_DEBUG_PRINT
                        if (m==0 && n==0 && k==0 && write_idx <= DEBUG_LIMIT) {
                            printf("A_Packed[%d]: %08lX -> [%d, %d, %d, %d]\n", write_idx-1, packed_val, bytes[0], bytes[1], bytes[2], bytes[3]);
                        }
                        #endif
                    }
                }

                // [FIXED] Send Weight B (Vertical Strip Packing)
                // 目標：填寫 K=0 的 4 個 Col，再填寫 K=1 的 4 個 Col...
                write_idx = 0;
                for (int n_strip = 0; n_strip < TILE_SIZE; n_strip += 4) { 
                    for (int k_idx = 0; k_idx < TILE_SIZE; ++k_idx) {      
                        uint32_t packed_val = 0;
                        #if ENABLE_DEBUG_PRINT
                        int8_t bytes[4];
                        #endif
                        for (int byte = 0; byte < 4; ++byte) {
                            int logical_r = k + k_idx;          // K (Time) 固定
                            int logical_c = n + n_strip + byte; // Col 變化
                            
                            int8_t val = 0;
                            if (logical_r < dim_K && logical_c < dim_N) {
                                 val = im2col_buffers::global_filter_buffer[logical_r][logical_c];
                            }
                            // Pack: MSB -> Col 0
                            packed_val |= ((uint32_t)((uint8_t)val)) << ((3 - byte) * 8);
                            #if ENABLE_DEBUG_PRINT
                            bytes[byte] = val;
                            #endif
                        }
                        cfu_op0(CFU_WRITE_B, write_idx++, packed_val);

                        #if ENABLE_DEBUG_PRINT
                        if (m==0 && n==0 && k==0 && write_idx <= DEBUG_LIMIT) {
                            printf("B_Packed[%d]: %08lX -> [%d, %d, %d, %d]\n", write_idx-1, packed_val, bytes[0], bytes[1], bytes[2], bytes[3]);
                        }
                        #endif
                    }
                }

                cfu_op0(CFU_START_TPU, 0, 0);

                // Read & Accumulate
                int buffer_ptr = 0;
                for (int n_blk = 0; n_blk < TILE_SIZE/4; ++n_blk) {
                    int col_base = n_blk * 4;
                    for (int row = 0; row < TILE_SIZE; ++row) {
                        int32_t val3 = cfu_op0(CFU_READ_C_3, buffer_ptr, 0);
                        int32_t val2 = cfu_op0(CFU_READ_C_2, buffer_ptr, 0);
                        int32_t val1 = cfu_op0(CFU_READ_C_1, buffer_ptr, 0);
                        int32_t val0 = cfu_op0(CFU_READ_C_0, buffer_ptr, 0);

                        int real_m = m + row;
                        int real_n_base = n + col_base;

                        // 只有在有效範圍內才累加到 Global Buffer
                        if (real_m < dim_M) {
                            if (real_n_base + 0 < dim_N) im2col_buffers::global_gemm_output[real_m][real_n_base + 0] += val3;
                            if (real_n_base + 1 < dim_N) im2col_buffers::global_gemm_output[real_m][real_n_base + 1] += val2;
                            if (real_n_base + 2 < dim_N) im2col_buffers::global_gemm_output[real_m][real_n_base + 2] += val1;
                            if (real_n_base + 3 < dim_N) im2col_buffers::global_gemm_output[real_m][real_n_base + 3] += val0;
                        }
                        buffer_ptr++;
                    }
                }
            }
        }
    }

    // =================================================================
    // Phase 4: Write Back
    // =================================================================
    for (int out_y = 0; out_y < output_height; ++out_y) {
        for (int out_x = 0; out_x < output_width; ++out_x) {
            for (int out_c = 0; out_c < output_depth; ++out_c) {
                
                int matrix_row = out_x + out_y * output_width;
                int matrix_col = out_c;

                int32_t acc = im2col_buffers::global_gemm_output[matrix_row][matrix_col];

                #if ENABLE_DEBUG_PRINT
                if (debug_print_count < DEBUG_LIMIT) {
                    printf("Pixel[%d,%d,%d]: TPU_Acc=%ld, Offset_Correction=%ld * %ld\n", 
                           out_y, out_x, out_c, acc, input_offset, im2col_buffers::global_filter_sums[out_c]);
                    debug_print_count++;
                }
                #endif

                // [New] 加上修正項
                acc += input_offset * im2col_buffers::global_filter_sums[out_c];

                if (bias_data) {
                    acc += bias_data[out_c];
                }
                acc = MultiplyByQuantizedMultiplier(
                    acc, output_multiplier[out_c], output_shift[out_c]);
                acc += output_offset;
                acc = std::max(acc, output_activation_min);
                acc = std::min(acc, output_activation_max);

                output_data[Offset(output_shape, batch, out_y, out_x, out_c)] =
                    static_cast<int8_t>(acc);
            }
        }
    }

  } // End Batch
  // for (int batch = 0; batch < batches; ++batch) {
  //   for (int out_y = 0; out_y < output_height; ++out_y) {
  //     const int in_y_origin = (out_y * stride_height) - pad_height;
  //     for (int out_x = 0; out_x < output_width; ++out_x) {
  //       const int in_x_origin = (out_x * stride_width) - pad_width;
  //       for (int out_channel = 0; out_channel < output_depth; ++out_channel) {
  //         auto group = out_channel / filters_per_group;
  //         int32_t acc = 0;
  //         for (int filter_y = 0; filter_y < filter_height; ++filter_y) {
  //           const int in_y = in_y_origin + dilation_height_factor * filter_y;
  //           for (int filter_x = 0; filter_x < filter_width; ++filter_x) {
  //             const int in_x = in_x_origin + dilation_width_factor * filter_x;

  //             // Zero padding by omitting the areas outside the image.
  //             const bool is_point_inside_image =
  //                 (in_x >= 0) && (in_x < input_width) && (in_y >= 0) &&
  //                 (in_y < input_height);

  //             if (!is_point_inside_image) {
  //               continue;
  //             }

  //             for (int in_channel = 0; in_channel < filter_input_depth;
  //                  ++in_channel) {
  //               int32_t input_val =
  //                   input_data[Offset(input_shape, batch, in_y, in_x,
  //                                     in_channel + group * filter_input_depth)];
  //               int32_t filter_val = filter_data[Offset(
  //                   filter_shape, out_channel, filter_y, filter_x, in_channel)];
  //               // Accumulate with 32 bits accumulator.
  //               // In the nudging process during model quantization, we force
  //               // real value of 0.0 be represented by a quantized value. This
  //               // guarantees that the input_offset is a int8_t, even though
  //               // it is represented using int32_t. int32_t += int8_t *
  //               // (int8_t - int8_t) so the highest value we can get from each
  //               // accumulation is [-127, 127] * ([-128, 127] -
  //               // [-128, 127]), which is [-32512, 32512]. log2(32512)
  //               // = 14.98, which means we can accumulate at least 2^16
  //               // multiplications without overflow. The accumulator is
  //               // applied to a filter so the accumulation logic will hold as
  //               // long as the filter size (filter_y * filter_x * in_channel)
  //               // does not exceed 2^16, which is the case in all the models
  //               // we have seen so far.
  //               // TODO(b/174275578): Add a check to make sure the
  //               // accumulator depth is smaller than 2^16.
  //               acc += filter_val * (input_val + input_offset);
  //             }
  //           }
  //         }

  //         if (bias_data) {
  //           acc += bias_data[out_channel];
  //         }
  //         acc = MultiplyByQuantizedMultiplier(
  //             acc, output_multiplier[out_channel], output_shift[out_channel]);
  //         acc += output_offset;
  //         acc = std::max(acc, output_activation_min);
  //         acc = std::min(acc, output_activation_max);
  //         output_data[Offset(output_shape, batch, out_y, out_x, out_channel)] =
  //             static_cast<int8_t>(acc);
  //       }
  //     }
  //   }
  // }
  perf_disable_counter(6);
}

inline void ConvPerChannelWithPackedInt4Weights(
    const ConvParams& params, const int32_t* output_multiplier,
    const int32_t* output_shift, const RuntimeShape& input_shape,
    const int8_t* input_data, const RuntimeShape& filter_shape,
    const int8_t* filter_input, int8_t* unpacked_filter_data,
    const RuntimeShape& bias_shape, const int32_t* bias_data,
    const RuntimeShape& output_shape, int8_t* output_data) {
  TFLITE_DCHECK(unpacked_filter_data != nullptr);
  tflite::tensor_utils::UnpackDenseInt4IntoInt8(
      filter_input, filter_shape.FlatSize(), unpacked_filter_data);
  ConvPerChannel(params, output_multiplier, output_shift, input_shape,
                 input_data, filter_shape, unpacked_filter_data, bias_shape,
                 bias_data, output_shape, output_data);
}

// Fixed-point per-channel-quantization convolution reference kernel.
// 16-bit data and 8-bit filter
template <typename AccumScalar>
inline void ConvPerChannel(
    const ConvParams& params, const int32_t* output_multiplier,
    const int32_t* output_shift, const RuntimeShape& input_shape,
    const int16_t* input_data, const RuntimeShape& filter_shape,
    const int8_t* filter_data, const RuntimeShape& bias_shape,
    const AccumScalar* bias_data, const RuntimeShape& output_shape,
    int16_t* output_data) {
  // Get parameters.
  const int stride_width = params.stride_width;
  const int stride_height = params.stride_height;
  const int dilation_width_factor = params.dilation_width_factor;
  const int dilation_height_factor = params.dilation_height_factor;
  const int pad_width = params.padding_values.width;
  const int pad_height = params.padding_values.height;

  // Set min and max value of the output.
  const int32_t output_activation_min = params.quantized_activation_min;
  const int32_t output_activation_max = params.quantized_activation_max;

  // Consistency check.
  TFLITE_DCHECK_LE(output_activation_min, output_activation_max);
  TFLITE_DCHECK_EQ(input_shape.DimensionsCount(), 4);
  TFLITE_DCHECK_EQ(filter_shape.DimensionsCount(), 4);
  TFLITE_DCHECK_EQ(output_shape.DimensionsCount(), 4);
  const int batches = MatchingDim(input_shape, 0, output_shape, 0);
  const int input_depth = input_shape.Dims(3);
  const int output_depth = MatchingDim(filter_shape, 0, output_shape, 3);
  if (bias_data) {
    TFLITE_DCHECK_EQ(bias_shape.FlatSize(), output_depth);
  }

  // Check dimensions of the tensors.
  const int input_height = input_shape.Dims(1);
  const int input_width = input_shape.Dims(2);
  const int filter_height = filter_shape.Dims(1);
  const int filter_width = filter_shape.Dims(2);
  const int filter_input_depth = filter_shape.Dims(3);
  const int groups = input_depth / filter_input_depth;
  TFLITE_DCHECK_EQ(input_depth % filter_input_depth, 0);
  const int filters_per_group = output_depth / groups;
  const int output_height = output_shape.Dims(1);
  const int output_width = output_shape.Dims(2);
  for (int batch = 0; batch < batches; ++batch) {
    for (int out_y = 0; out_y < output_height; ++out_y) {
      const int in_y_origin = (out_y * stride_height) - pad_height;
      for (int out_x = 0; out_x < output_width; ++out_x) {
        const int in_x_origin = (out_x * stride_width) - pad_width;
        for (int out_channel = 0; out_channel < output_depth; ++out_channel) {
          auto group = out_channel / filters_per_group;
          AccumScalar acc = 0;
          for (int filter_y = 0; filter_y < filter_height; ++filter_y) {
            const int in_y = in_y_origin + dilation_height_factor * filter_y;
            for (int filter_x = 0; filter_x < filter_width; ++filter_x) {
              const int in_x = in_x_origin + dilation_width_factor * filter_x;

              // Zero padding by omitting the areas outside the image.
              const bool is_point_inside_image =
                  (in_x >= 0) && (in_x < input_width) && (in_y >= 0) &&
                  (in_y < input_height);

              if (!is_point_inside_image) {
                continue;
              }

              for (int in_channel = 0; in_channel < filter_input_depth;
                   ++in_channel) {
                int32_t input_val =
                    input_data[Offset(input_shape, batch, in_y, in_x,
                                      in_channel + group * filter_input_depth)];
                int32_t filter_val = filter_data[Offset(
                    filter_shape, out_channel, filter_y, filter_x, in_channel)];
                // Accumulate with 64 bits accumulator.
                // int64_t += int8_t * int16_t so the highest value we can
                // get from each accumulation is [-127, 127] * ([-32768,
                // 32767] -
                // [-32768, 32767]), which is [-8322945, 8322945].
                // log2(8322945) = 22.99.
                acc += filter_val * input_val;
              }
            }
          }
          if (bias_data) {
            acc += bias_data[out_channel];
          }
          int32_t scaled_acc = MultiplyByQuantizedMultiplier(
              acc, output_multiplier[out_channel], output_shift[out_channel]);
          scaled_acc = std::max(scaled_acc, output_activation_min);
          scaled_acc = std::min(scaled_acc, output_activation_max);
          output_data[Offset(output_shape, batch, out_y, out_x, out_channel)] =
              static_cast<int16_t>(scaled_acc);
        }
      }
    }
  }
}

}  // namespace reference_integer_ops
}  // namespace tflite

#endif  // TENSORFLOW_LITE_KERNELS_INTERNAL_REFERENCE_INTEGER_OPS_CONV_H_
