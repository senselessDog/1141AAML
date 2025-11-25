/* Copyright 2019 The TensorFlow Authors. All Rights Reserved.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
==============================================================================*/
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

// 硬體方塊大小 (Tile Size)
#define TILE_SIZE 16

#define MAX_ROW_CAPACITY 1024 
#define MAX_COL_CAPACITY 1024 
#define MAX_CHANNEL_CAPACITY 1024

// 使用 "global_" 前綴區分，並放在 namespace 外或專屬 namespace
namespace im2col_buffers {
    int32_t global_im2col_buffer[MAX_ROW_CAPACITY][MAX_COL_CAPACITY];    // Matrix A
    int32_t global_filter_buffer[MAX_COL_CAPACITY][MAX_CHANNEL_CAPACITY]; // Matrix B
    int32_t global_gemm_output[MAX_ROW_CAPACITY][MAX_CHANNEL_CAPACITY];   // Matrix C
}

namespace tflite {
namespace reference_integer_ops {

inline int32_t GetPixelWithPadding(
    const int8_t* data, const RuntimeShape& shape, 
    int batch, int y, int x, int channel, 
    int height, int width, int32_t offset_val) {
    
    // Boundary check (Zero Padding Logic)
    if (x >= 0 && x < width && y >= 0 && y < height) {
        // [Important] 這裡直接處理 input_offset
        return data[Offset(shape, batch, y, x, channel)] + offset_val;
    }
    return 0; // Padding 區域填 0
}
// Fixed-point per-channel-quantization convolution reference kernel.
inline void ConvPerChannel(
    const ConvParams& params, const int32_t* output_multiplier,
    const int32_t* output_shift, const RuntimeShape& input_shape,
    const int8_t* input_data, const RuntimeShape& filter_shape,
    const int8_t* filter_data, const RuntimeShape& bias_shape,
    const int32_t* bias_data, const RuntimeShape& output_shape,
    int8_t* output_data) {
  perf_enable_counter(6);
  // Get parameters.
  const int32_t input_offset = params.input_offset;  // r = s(q - Z)
  const int stride_width = params.stride_width;
  const int stride_height = params.stride_height;
  const int dilation_width_factor = params.dilation_width_factor;
  const int dilation_height_factor = params.dilation_height_factor;
  const int pad_width = params.padding_values.width;
  const int pad_height = params.padding_values.height;
  const int32_t output_offset = params.output_offset;

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
  // if (bias_data) {
  //   TFLITE_DCHECK_EQ(bias_shape.FlatSize(), output_depth);
  // }

  // Check dimensions of the tensors.
  const int input_height = input_shape.Dims(1);
  const int input_width = input_shape.Dims(2);
  const int filter_height = filter_shape.Dims(1);
  const int filter_width = filter_shape.Dims(2);
  const int filter_input_depth = filter_shape.Dims(3);
  // const int groups = input_depth / filter_input_depth;
  TFLITE_DCHECK_EQ(input_depth % filter_input_depth, 0);
  // const int filters_per_group = output_depth / groups;
  const int output_height = output_shape.Dims(1);
  const int output_width = output_shape.Dims(2);

  // 計算矩陣維度 (Matrix Dimensions)
  const int dim_M = output_height * output_width;                 // Total patches
  const int dim_K = filter_height * filter_width * input_depth;   // Kernel Size
  const int dim_N = output_depth;                                 // Output Channels
  for (int batch = 0; batch < batches; ++batch) {
    
    // =================================================================
    // Phase 1: Filter Packing (Weights -> Matrix B)
    // 目標: im2col_buffers::global_filter_buffer [K][N]
    // =================================================================
    // 使用簡單的迴圈結構，不使用複雜的索引計算
    for (int out_c = 0; out_c < output_depth; ++out_c) {
        int k_iterator = 0; // 自動累加，不用算式
        for (int fy = 0; fy < filter_height; ++fy) {
            for (int fx = 0; fx < filter_width; ++fx) {
                for (int ic = 0; ic < filter_input_depth; ++ic) {
                    
                    int32_t val = filter_data[Offset(filter_shape, out_c, fy, fx, ic)];
                    
                    // 填入 Filter Buffer (K x N)
                    // 注意這裡是 [k][n]，直觀對應
                    im2col_buffers::global_filter_buffer[k_iterator][out_c] = val;
                    
                    k_iterator++;
                }
            }
        }
    }

    // =================================================================
    // Phase 2: im2col Transformation (Input -> Matrix A)
    // 目標: im2col_buffers::global_im2col_buffer [M][K]
    // =================================================================
    int current_im2col_row = 0; // 用 Iterator 取代 row = y * w + x

    for (int out_y = 0; out_y < output_height; ++out_y) {
        const int in_y_origin = (out_y * stride_height) - pad_height;
        
        for (int out_x = 0; out_x < output_width; ++out_x) {
            const int in_x_origin = (out_x * stride_width) - pad_width;
            
            int current_im2col_col = 0; // 重置 column iterator

            // 掃描 Patch 體積
            for (int fy = 0; fy < filter_height; ++fy) {
                const int in_y = in_y_origin + dilation_height_factor * fy;
                
                for (int fx = 0; fx < filter_width; ++fx) {
                    const int in_x = in_x_origin + dilation_width_factor * fx;
                    
                    for (int ic = 0; ic < input_depth; ++ic) {
                        
                        // 呼叫 Helper Function，邏輯清晰
                        int32_t pixel_val = GetPixelWithPadding(
                            input_data, input_shape, batch, 
                            in_y, in_x, ic, 
                            input_height, input_width, input_offset
                        );

                        im2col_buffers::global_im2col_buffer[current_im2col_row][current_im2col_col] = pixel_val;
                        
                        current_im2col_col++;
                    }
                }
            }
            current_im2col_row++; // 完成一個 Patch，移動到下一列
        }
    }
    // =================================================================
    // Phase 3: Hardware Tiling GEMM (Matrix Mul with CFU)
    // global_gemm_output = global_im2col_buffer * global_filter_buffer
    // =================================================================
    
    // Tiling Loop: 切割大矩陣成 16x16 小塊
    // m 掃描 Output Pixels (Rows of A, Rows of C)
    for (int m = 0; m < dim_M; m += TILE_SIZE) {
        // n 掃描 Output Channels (Cols of B, Cols of C)
        for (int n = 0; n < dim_N; n += TILE_SIZE) {
            
            // [HARDWARE STEP 1] Reset TPU for new Output Tile
            cfu_op0(CFU_RESET, 0, 0); 
            // 雖然 Lab 說不用處理邊界設定，但為了完整性可以傳送
            // 這裡假設 TPU 內部固定跑 16x16
            cfu_op0(CFU_SET_M, TILE_SIZE, 0);
            cfu_op0(CFU_SET_N, TILE_SIZE, 0);
            cfu_op0(CFU_SET_K, TILE_SIZE, 0);

            // k 掃描 Kernel Depth (Cols of A, Rows of B) - 這是累積方向
            for (int k = 0; k < dim_K; k += TILE_SIZE) {
                
                // [HARDWARE STEP 2] Send Input Tile (Matrix A sub-block)
                // Matrix A 是 [m...m+16][k...k+16]
                // 每次寫入一個 uint32 (包含 4 個 int8) -> 共寫入 16*16/4 = 64 次
                // 注意：TPU 測試代碼是用 A_arr[4][64]，暗示每行 4 byte，共 64 行？
                // 通常 16x16 矩陣有 256 個點。每個點 8 bit。總共 256 bytes = 64 個 uint32。
                
                for (int i = 0; i < 64; ++i) {
                    uint32_t packed_val = 0;
                    // 一個 uint32 塞 4 個 int8 (4個 K 維度)
                    // 這取決於你的 TPU 設計，假設是 row-major 且 4-byte packed in K dimension
                    for (int byte = 0; byte < 4; ++byte) {
                        // 計算真實座標
                        // int r = m + (i / 4);     // 第幾列 (0~15)
                        // int c = k + (i % 4) * 4 + byte; // 第幾行 (每次抓4個) -> 這是假設寫入順序

                        // **如果你的 TPU 寫入順序不同，這裡要調整**
                        // 依照 functional test，A_arr 是一維 64 長度，
                        // 這裡最保險的做法是: 模仿 Test Code 的寫入量，確保送 64 次
                        // 假設 TPU 接收順序是: Row 0 (4 words), Row 1 (4 words)...
                        
                        int logical_r = m + (i / 4); // 0..15
                        int logical_c = k + (i % 4) * 4 + byte; 

                        int8_t val = 0;
                        // Boundary Check (Padding with 0)
                        if (logical_r < dim_M && logical_c < dim_K) {
                            // 注意：im2col_buffer 是 int32 (為了 offset)，要轉回 int8 傳輸
                            printf("Reading im2col_buffer[%d][%d] = %ld\n", logical_r, logical_c,
                                   im2col_buffers::global_im2col_buffer[logical_r][logical_c]);
                            val = (int8_t)im2col_buffers::global_im2col_buffer[logical_r][logical_c];
                        }
                        
                        // Pack into uint32 (Little Endian)
                        packed_val |= ((uint32_t)((uint8_t)val)) << (byte * 8);
                    }
                    cfu_op0(CFU_WRITE_A, i, packed_val);
                }

                // [HARDWARE STEP 3] Send Weight Tile (Matrix B sub-block)
                // Matrix B 是 [k...k+16][n...n+16]
                for (int i = 0; i < 64; ++i) {
                    uint32_t packed_val = 0;
                    for (int byte = 0; byte < 4; ++byte) {
                        // 假設 TPU 接收 Weight 也是 Row-major (K 為 Row, N 為 Col)
                        // 或者是 K 為 Col, N 為 Row? 
                        // 通常: Matrix B [K][N]. 
                        // 假設順序: Row 0 (K=k) 的 16 個 N...
                        
                        int logical_r = k + (i / 4);      // K 維度
                        int logical_c = n + (i % 4) * 4 + byte; // N 維度

                        int8_t val = 0;
                        if (logical_r < dim_K && logical_c < dim_N) {
                            val = (int8_t)im2col_buffers::global_filter_buffer[logical_r][logical_c];
                        }
                        packed_val |= ((uint32_t)((uint8_t)val)) << (byte * 8);
                    }
                    cfu_op0(CFU_WRITE_B, i, packed_val);
                }

                // [HARDWARE STEP 4] Start Compute
                // TPU 會計算 C += A * B
                cfu_op0(CFU_START_TPU, 0, 0);
            }

            // [HARDWARE STEP 5] Read Result Tile (Matrix C sub-block)
            // K 迴圈結束後，Buffer C 裡面已經是完整的 Sum
            // 讀出 16x16 的 int32 結果
            int buffer_ptr = 0;
            for (int block = 0; block < 4; block++) {
                int col_base = 4 * block; // N 維度的偏移
                for (int row = 0; row < 16; row++) { // M 維度
                    // 根據 functional test，一次讀 4 個 int32
                    int32_t val3 = cfu_op0(CFU_READ_C_3, buffer_ptr, 0);
                    int32_t val2 = cfu_op0(CFU_READ_C_2, buffer_ptr, 0);
                    int32_t val1 = cfu_op0(CFU_READ_C_1, buffer_ptr, 0);
                    int32_t val0 = cfu_op0(CFU_READ_C_0, buffer_ptr, 0);

                    // 填回 Global Output Buffer (處理邊界)
                    int real_m = m + row;
                    int real_n_base = n + col_base;

                    if (real_m < dim_M) {
                        if (real_n_base + 0 < dim_N) im2col_buffers::global_gemm_output[real_m][real_n_base + 0] = val3;
                        if (real_n_base + 1 < dim_N) im2col_buffers::global_gemm_output[real_m][real_n_base + 1] = val2;
                        if (real_n_base + 2 < dim_N) im2col_buffers::global_gemm_output[real_m][real_n_base + 2] = val1;
                        if (real_n_base + 3 < dim_N) im2col_buffers::global_gemm_output[real_m][real_n_base + 3] = val0;
                    }
                    buffer_ptr++;
                }
            }
        }
    }

    // =================================================================
    // Phase 4: Write Back (Matrix C -> Output Tensor)
    // 包含 Bias, Requantization, Activation
    // =================================================================
    for (int out_y = 0; out_y < output_height; ++out_y) {
        for (int out_x = 0; out_x < output_width; ++out_x) {
            for (int out_c = 0; out_c < output_depth; ++out_c) {
                
                // 將 (x, y) 映射回 Matrix Row Index
                int matrix_row = out_x + out_y * output_width;
                int matrix_col = out_c;

                int32_t acc = im2col_buffers::global_gemm_output[matrix_row][matrix_col];

                // 標準 TFLite 後處理 (Post-processing)
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
