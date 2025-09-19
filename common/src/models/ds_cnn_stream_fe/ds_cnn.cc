#include "models/ds_cnn_stream_fe/ds_cnn.h"
#include <stdio.h>
#include <cstring>
#include "menu.h"
#include "models/ds_cnn_stream_fe/ds_cnn_stream_fe.h"
#include "tflite.h"
#include "models/label/label0_board.h"
#include "models/label/label1_board.h"
#include "models/label/label6_board.h"
#include "models/label/label8_board.h"
#include "models/label/label11_board.h"


// --- Helper function to run inference (Corrected based on tflite.h) ---
static void run_inference(const float* input_data) {
    // CORRECTED: Use the exact function names from tflite.h
    if (input_data) {
        tflite_set_input_float(input_data);
    } else {
        tflite_set_input_zeros();
    }

    // The inference function
    tflite_classify();

    // Get the pointer to the start of the output float array
    float* output_array = tflite_get_output_float();

    printf("Output scores:\n");
    for (int i = 0; i < 12; ++i) {
        // Access each element using the pointer and array index
        float output_val = output_array[i];
        
        uint32_t output_val_as_uint;
        memcpy(&output_val_as_uint, &output_val, sizeof(output_val_as_uint));
        printf("%2d: 0x%08x,\n", i, static_cast<unsigned int>(output_val_as_uint));
    }
}

// --- Menu callback functions (No changes needed) ---
static void do_run_zeros() {
    printf("\nRunning with zeros input...\n");
    run_inference(nullptr);
}

static void do_run_label0() {
    printf("\nRunning with label0...\n");
    run_inference(label0_data);
}

static void do_run_label1() {
    printf("\nRunning with label1...\n");
    run_inference(label1_data);
}

static void do_run_label6() {
    printf("\nRunning with label6...\n");
    run_inference(label6_data);
}

static void do_run_label8() {
    printf("\nRunning with label8...\n");
    run_inference(label8_data);
}

static void do_run_label11() {
    printf("\nRunning with label11...\n");
    run_inference(label11_data);
}


// --- Boilerplate code (No changes needed) ---
static void ds_cnn_stream_fe_init(void) {
  tflite_load_model(ds_cnn_stream_fe, ds_cnn_stream_fe_len);
}

static struct Menu MENU = {
    "Tests for ds_cnn_stream_fe",
    "ds_cnn_stream_fe",
    {
        MENU_ITEM('1', "Run with zeros input", do_run_zeros),
        MENU_ITEM('2', "Run with label0", do_run_label0),
        MENU_ITEM('3', "Run with label1", do_run_label1),
        MENU_ITEM('4', "Run with label6", do_run_label6),
        MENU_ITEM('5', "Run with label8", do_run_label8),
        MENU_ITEM('6', "Run with label11", do_run_label11),
        MENU_END,
    },
};

void ds_cnn_stream_fe_menu() {
  ds_cnn_stream_fe_init();
  menu_run(&MENU);
}