/* Copyright 2020 The TensorFlow Authors. All Rights Reserved.

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
#ifndef TENSORFLOW_LITE_KERNELS_INTERNAL_REFERENCE_LEAKY_RELU_H_
#define TENSORFLOW_LITE_KERNELS_INTERNAL_REFERENCE_LEAKY_RELU_H_

#include <stdio.h>

#include <algorithm>
#include <limits>

#include "cfu.h"
#include "tensorflow/lite/kernels/internal/common.h"

namespace tflite {
namespace reference_ops {

inline void LeakyRelu(const tflite::LeakyReluParams& params,
                      const RuntimeShape& input_shape, const float* input_data,
                      const RuntimeShape& output_shape, float* output_data) {
  const int flat_size = MatchingFlatSize(input_shape, output_shape);
  for (int i = 0; i < flat_size; ++i) {
    const float val = input_data[i];
    // Note that alpha might be > 1 or < 0, so we don't use std::max here.
    output_data[i] = val > 0 ? val : val * params.alpha;
  }
}

inline void CfuSetShift(int32_t shift) { cfu_op1(/* funct7= */ 1, shift, 0); }

// Compute MultiplyByQuantizedMultiplier using CFU
// Must call CfuSetShift first with the appropriate shift value
inline int32_t CfuMultiplyByQuantizedMultiplier(int32_t input,
                                                int32_t multiplier) {
  return cfu_op1(/* funct7= */ 0, input, multiplier);
}

template <typename T>
inline void QuantizeLeakyRelu(const LeakyReluParams& params,
                              const RuntimeShape& input_shape,
                              const T* input_data,
                              const RuntimeShape& output_shape,
                              T* output_data) {
  const int flat_size = MatchingFlatSize(input_shape, output_shape);
  static const int32_t quantized_min = std::numeric_limits<T>::min();
  static const int32_t quantized_max = std::numeric_limits<T>::max();

  for (int i = 0; i < flat_size; ++i) {
    const int32_t input_value = input_data[i] - params.input_offset;

    int32_t multiplier, shift;
    if (input_value >= 0) {
      multiplier = params.output_multiplier_identity;
      shift = params.output_shift_identity;
    } else {
      multiplier = params.output_multiplier_alpha;
      shift = params.output_shift_alpha;
    }

    // Two CFU calls: set shift, then compute
    CfuSetShift(shift);
    int32_t quantized_result =
        CfuMultiplyByQuantizedMultiplier(input_value, multiplier);

    // Add output offset and clamp
    int32_t unclamped_output = params.output_offset + quantized_result;
    const T clamped_output =
        std::min(quantized_max, std::max(quantized_min, unclamped_output));
    output_data[i] = static_cast<T>(clamped_output);
  }
}

template <typename T>
inline void QuantizeLeakyReluOptimized(const LeakyReluParams& params,
                                       const RuntimeShape& input_shape,
                                       const T* input_data,
                                       const RuntimeShape& output_shape,
                                       T* output_data) {
  const int flat_size = MatchingFlatSize(input_shape, output_shape);
  static const int32_t quantized_min = std::numeric_limits<T>::min();
  static const int32_t quantized_max = std::numeric_limits<T>::max();

  // Process in two passes: first positive (including zero), then negative
  // This minimizes shift register updates

  // Pass 1: Positive values (input >= input_offset means input_value >= 0)
  CfuSetShift(params.output_shift_identity);
  for (int i = 0; i < flat_size; ++i) {
    const int32_t input_value = input_data[i] - params.input_offset;
    if (input_value >= 0) {
      int32_t quantized_result = CfuMultiplyByQuantizedMultiplier(
          input_value, params.output_multiplier_identity);
      int32_t unclamped_output = params.output_offset + quantized_result;
      output_data[i] = static_cast<T>(
          std::min(quantized_max, std::max(quantized_min, unclamped_output)));
    }
  }

  // Pass 2: Negative values
  CfuSetShift(params.output_shift_alpha);
  for (int i = 0; i < flat_size; ++i) {
    const int32_t input_value = input_data[i] - params.input_offset;
    if (input_value < 0) {
      int32_t quantized_result = CfuMultiplyByQuantizedMultiplier(
          input_value, params.output_multiplier_alpha);
      int32_t unclamped_output = params.output_offset + quantized_result;
      output_data[i] = static_cast<T>(
          std::min(quantized_max, std::max(quantized_min, unclamped_output)));
    }
  }
}

//============================================================================//
// Alternative: Software fallback for comparison/debugging
//============================================================================//
template <typename T>
inline void QuantizeLeakyReluSoftware(const LeakyReluParams& params,
                                      const RuntimeShape& input_shape,
                                      const T* input_data,
                                      const RuntimeShape& output_shape,
                                      T* output_data) {
  const int flat_size = MatchingFlatSize(input_shape, output_shape);
  static const int32_t quantized_min = std::numeric_limits<T>::min();
  static const int32_t quantized_max = std::numeric_limits<T>::max();

  for (int i = 0; i < flat_size; ++i) {
    const int32_t input_value = input_data[i] - params.input_offset;

    int32_t multiplier, shift;
    if (input_value >= 0) {
      multiplier = params.output_multiplier_identity;
      shift = params.output_shift_identity;
    } else {
      multiplier = params.output_multiplier_alpha;
      shift = params.output_shift_alpha;
    }

    // Use TFLite's software implementation
    int32_t quantized_result =
        MultiplyByQuantizedMultiplier(input_value, multiplier, shift);

    int32_t unclamped_output = params.output_offset + quantized_result;
    const T clamped_output =
        std::min(quantized_max, std::max(quantized_min, unclamped_output));
    output_data[i] = static_cast<T>(clamped_output);
  }
}

}  // namespace reference_ops
}  // namespace tflite

#endif  // TENSORFLOW_LITE_KERNELS_INTERNAL_REFERENCE_LEAKY_RELU_H_