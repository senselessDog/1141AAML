import numpy as np

# 1. Softmax (exp) 使用 Q5.26 格式
INTEGER_BITS = 5
FRACTIONAL_BITS = 26

# 2. 我們使用 10-bit 地址 (5 整數 + 5 小數)
ADDR_BITS_INT = 5
ADDR_BITS_FRAC = 5
TOTAL_ADDR_BITS = ADDR_BITS_INT + ADDR_BITS_FRAC
NUM_ENTRIES = 2**16 # 2**18

# 3. 準備輸出檔案
f = open("exp_lut_q5.26.mem", "w")

print(f"Generating {NUM_ENTRIES} entries for Q5.26...")

for i in range(NUM_ENTRIES):
    # i (10-bit) 就是我們的地址 x_i[30:21]
    
    # 為了計算 "真實" 的 x 值，我們把 10-bit 地址
    # 放回它在 32-bit Q5.26 數字中的 "正確位置"
    # (即 x_i[30:21])
    
    # 16 個 + 16 個 0
    raw_val_32bit = i << 16
    
    # 檢查是否為負數 (第 31 bit)
    if (raw_val_32bit & (1 << 31)):
        # 如果是負數，轉成 python 的負整數
        raw_val_32bit = raw_val_32bit - (1 << 32)

    # 1. 反量化 (Dequantize): 
    # 把 Q5.26 整數轉回 float
    float_x = float(raw_val_32bit) / (2**FRACTIONAL_BITS)
    
    # 2. 核心運算: 
    # (注意: softmax.h 呼叫的是 exp_on_negative_values，
    #  但 softmax.h 也會用它來算正值，
    #  所以我們直接算 e^x)
    float_y = np.exp(float_x)
    
    # 3. 量化 (Quantize) 答案:
    # 把 float 答案轉回 Q5.26 (Q0.31?)
    # ...
    # 
    # 這裡很 tricky。softmax.h 期望 e^x 的
    # 輸出是 Q0.31 格式 (0 個整數位)。
    # 我們就用 Q0.31 格式來儲存。
    
    FRAC_BITS_OUT = 31
    quantized_y = int(round(float_y * (2**FRAC_BITS_OUT)))
    print(f"entry: {i<<16:x}, result: {quantized_y:x}")
    # 處理飽和 (Saturation)
    if quantized_y > 0x7FFFFFFF:
        quantized_y = 0x7FFFFFFF
    
    # 轉成 32-bit 16進位 hex
    hex_y = f"{quantized_y & 0xFFFFFFFF:08x}"
    
    f.write(hex_y + "\n")

print(f"Done. 'exp_lut_q5.26.mem' created.")
f.close()