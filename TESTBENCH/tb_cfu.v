`timescale 1ns/10ps
// 根據你的目錄結構，確保路徑正確，或者在編譯指令中指定 include path
// 假設 cfu.v 在 ../proj/lab5_proj/cfu.v (請依實際位置調整)
// 這裡我們通常不需要 include RTL，而是在 makefile 裡一次編譯
`include "cfu.v"
`define CYCLE_TIME 10.0

module tb_cfu;

    // --- 1. 訊號宣告 ---
    reg          clk;
    reg          reset;
    reg          cmd_valid;
    reg  [9:0]   cmd_payload_function_id;
    reg  [31:0]  cmd_payload_inputs_0;
    reg  [31:0]  cmd_payload_inputs_1;
    wire         cmd_ready;
    wire         rsp_valid;
    reg          rsp_ready;
    wire [31:0]  rsp_payload_outputs_0;

    // --- 2. 測試資料儲存區 (對應 C++ 的 const array) ---
    reg [31:0] A_arr [0:63];
    reg [31:0] B_arr [0:63];
    // C_ans 是 16x16 = 256 個 int32
    reg [31:0] C_ans [0:255]; 

    // --- 3. 變數 ---
    integer i;
    reg [31:0] read_val;
    reg [31:0] busy_status;
    reg [31:0] c0, c1, c2, c3;
    integer error_ct;

    // --- 4. 實例化 CFU ---
    Cfu u_cfu (
        .clk                     (clk),
        .reset                   (reset),
        .cmd_valid               (cmd_valid),
        .cmd_ready               (cmd_ready),
        .cmd_payload_function_id (cmd_payload_function_id),
        .cmd_payload_inputs_0    (cmd_payload_inputs_0),
        .cmd_payload_inputs_1    (cmd_payload_inputs_1),
        .rsp_valid               (rsp_valid),
        .rsp_ready               (rsp_ready),
        .rsp_payload_outputs_0   (rsp_payload_outputs_0)
    );

    // --- 5. 時脈產生 ---
    initial clk = 0;
    always #(`CYCLE_TIME/2) clk = ~clk;
    // --- [FIX] 6. 波形錄製設定 ---
    initial begin
        $dumpfile("cfu_debug.vcd"); // 指定波形檔名
        $dumpvars(0, tb_cfu);       // 錄製 tb_cfu 模組下的所有訊號
    end
    // --- 6. 資料初始化 (複製自你的 C Code Case 0) ---
    initial begin
        // === Matrix A (Case 0) ===
        A_arr[0] = 32'h86898a46; A_arr[1] = 32'h15f8083f; A_arr[2] = 32'h00028629; A_arr[3] = 32'h92110612;
        A_arr[4] = 32'h2cff77b3; A_arr[5] = 32'h7b39a3c7; A_arr[6] = 32'ha289108a; A_arr[7] = 32'h580f605c;
        A_arr[8] = 32'h7bd9cf9e; A_arr[9] = 32'h92e3f461; A_arr[10] = 32'h6b765c5e; A_arr[11] = 32'h16d5b2f2;
        A_arr[12] = 32'ha3f03e00; A_arr[13] = 32'hd95a3a88; A_arr[14] = 32'h9cebcdbe; A_arr[15] = 32'h6bb1d2ba;
        A_arr[16] = 32'h4e68b437; A_arr[17] = 32'h700a0f22; A_arr[18] = 32'h6565a14a; A_arr[19] = 32'h2ad0c897;
        A_arr[20] = 32'h9e9dc4d7; A_arr[21] = 32'ha754be67; A_arr[22] = 32'h9d6763ba; A_arr[23] = 32'h5ca8d58f;
        A_arr[24] = 32'h01c973a0; A_arr[25] = 32'h5d21bc00; A_arr[26] = 32'h5baf8cae; A_arr[27] = 32'h3baec582;
        A_arr[28] = 32'ha6ac6f2d; A_arr[29] = 32'ha3a4b030; A_arr[30] = 32'h86adbb7e; A_arr[31] = 32'h22df33b8;
        A_arr[32] = 32'hc385ee3f; A_arr[33] = 32'h7ee5173b; A_arr[34] = 32'h454c135b; A_arr[35] = 32'hd1db8e01;
        A_arr[36] = 32'h5af8c718; A_arr[37] = 32'h6a249ba9; A_arr[38] = 32'hf65ce540; A_arr[39] = 32'h0018e3b9;
        A_arr[40] = 32'h85c11577; A_arr[41] = 32'h23f9c3ee; A_arr[42] = 32'h3aec5ffb; A_arr[43] = 32'h0e5bc72d;
        A_arr[44] = 32'hcd8a128c; A_arr[45] = 32'h80c4848b; A_arr[46] = 32'h88111301; A_arr[47] = 32'hd1e13429;
        A_arr[48] = 32'he47ab66b; A_arr[49] = 32'he961ce2e; A_arr[50] = 32'hc490db04; A_arr[51] = 32'hf9a18856;
        A_arr[52] = 32'h2b5eae06; A_arr[53] = 32'h1edebd9a; A_arr[54] = 32'ha1323806; A_arr[55] = 32'h829625bd;
        A_arr[56] = 32'hf5b06413; A_arr[57] = 32'h77e853d0; A_arr[58] = 32'h3edf597e; A_arr[59] = 32'h5949c42d;
        A_arr[60] = 32'h937e45da; A_arr[61] = 32'h8f9077fe; A_arr[62] = 32'h297e2dbe; A_arr[63] = 32'ha4491f50;

        // === Matrix B (Case 0) ===
        B_arr[0] = 32'h69e499f5; B_arr[1] = 32'h554a8f23; B_arr[2] = 32'h8462d081; B_arr[3] = 32'h96482246;
        B_arr[4] = 32'hb7153071; B_arr[5] = 32'h8790926a; B_arr[6] = 32'he395d4b9; B_arr[7] = 32'h1eb60a84;
        B_arr[8] = 32'hfa99551c; B_arr[9] = 32'h8c50f4e0; B_arr[10] = 32'h9f1db3a7; B_arr[11] = 32'hf5873199;
        B_arr[12] = 32'h65161c73; B_arr[13] = 32'hbf07aab3; B_arr[14] = 32'hcb86780a; B_arr[15] = 32'h4ee6e66e;
        B_arr[16] = 32'h637b99a8; B_arr[17] = 32'h58b17692; B_arr[18] = 32'hb64a332d; B_arr[19] = 32'h030eb955;
        B_arr[20] = 32'h8c8e60f6; B_arr[21] = 32'h966a94e2; B_arr[22] = 32'hd397c5f4; B_arr[23] = 32'h4afe29f9;
        B_arr[24] = 32'heca32115; B_arr[25] = 32'h734aa371; B_arr[26] = 32'h59b186a3; B_arr[27] = 32'hed091872;
        B_arr[28] = 32'h0e59f401; B_arr[29] = 32'hafa23cea; B_arr[30] = 32'h49819f63; B_arr[31] = 32'h85a4f973;
        B_arr[32] = 32'hc5f26563; B_arr[33] = 32'h89a2bcc0; B_arr[34] = 32'h34a44830; B_arr[35] = 32'h7d2912dc;
        B_arr[36] = 32'h71c8e90b; B_arr[37] = 32'h7e5b4491; B_arr[38] = 32'hdc73fbe5; B_arr[39] = 32'hecbfdf70;
        B_arr[40] = 32'h285ce859; B_arr[41] = 32'h75a172c1; B_arr[42] = 32'he54e64a6; B_arr[43] = 32'h5e85e2bd;
        B_arr[44] = 32'h6db9a265; B_arr[45] = 32'h5c3658c9; B_arr[46] = 32'h1ce77a75; B_arr[47] = 32'he2ebc2ba;
        B_arr[48] = 32'h2b7e843e; B_arr[49] = 32'h88d664a2; B_arr[50] = 32'hb357fdf3; B_arr[51] = 32'h3dbf7bc7;
        B_arr[52] = 32'h1893fce9; B_arr[53] = 32'h53a80188; B_arr[54] = 32'h8dd96ca2; B_arr[55] = 32'h26d56bf2;
        B_arr[56] = 32'h11b5e54d; B_arr[57] = 32'hacfac74b; B_arr[58] = 32'h7def7c67; B_arr[59] = 32'hb50d3fd4;
        B_arr[60] = 32'hd6e0a6d2; B_arr[61] = 32'h98a4df15; B_arr[62] = 32'h6d473cdb; B_arr[63] = 32'h9da60e91;

        // === Golden C (Case 0) ===
        C_ans[0] = 32'hfffff0bf; C_ans[1] = 32'hffff99b7; C_ans[2] = 32'hffffdb69; C_ans[3] = 32'h00001902; 
        C_ans[4] = 32'hffff59b7; C_ans[5] = 32'hffff8a82; C_ans[6] = 32'h00007eb6; C_ans[7] = 32'hffffb71a; 
        C_ans[8] = 32'hffffc399; C_ans[9] = 32'h00004c7b; C_ans[10] = 32'hffff8ba4; C_ans[11] = 32'hffff8b32; 
        C_ans[12] = 32'h00004ff4; C_ans[13] = 32'hffff4fce; C_ans[14] = 32'h00006443; C_ans[15] = 32'hffffecf0;
        C_ans[16] = 32'hffff6b6a; C_ans[17] = 32'h00006012; C_ans[18] = 32'hffffd889; C_ans[19] = 32'hffffdb30; 
        C_ans[20] = 32'hfffff5cf; C_ans[21] = 32'hfffff399; C_ans[22] = 32'h0000167c; C_ans[23] = 32'hffffaf72; 
        C_ans[24] = 32'h000043f0; C_ans[25] = 32'h00003bfa; C_ans[26] = 32'h00003c5e; C_ans[27] = 32'hffff9a06; 
        C_ans[28] = 32'h00007e18; C_ans[29] = 32'hffffb93d; C_ans[30] = 32'h00003ce4; C_ans[31] = 32'h000044aa;
        C_ans[32] = 32'h00000baf; C_ans[33] = 32'h0000555c; C_ans[34] = 32'h000028a5; C_ans[35] = 32'h00000f99; 
        C_ans[36] = 32'h00001ec9; C_ans[37] = 32'hffff5860; C_ans[38] = 32'h000062e6; C_ans[39] = 32'hffff99f2; 
        C_ans[40] = 32'hfffffa33; C_ans[41] = 32'h00001c30; C_ans[42] = 32'hffff99af; C_ans[43] = 32'hfffff5a8; 
        C_ans[44] = 32'h0000216b; C_ans[45] = 32'hffff5e5d; C_ans[46] = 32'h000062b6; C_ans[47] = 32'h00003039;
        C_ans[48] = 32'h0000297f; C_ans[49] = 32'h0000c2f3; C_ans[50] = 32'hffffb11b; C_ans[51] = 32'hffff824f; 
        C_ans[52] = 32'h000118a5; C_ans[53] = 32'h0000dd7f; C_ans[54] = 32'hffffc9f8; C_ans[55] = 32'hffffb27e; 
        C_ans[56] = 32'hffff92e3; C_ans[57] = 32'hffff586e; C_ans[58] = 32'h000028e5; C_ans[59] = 32'h00001203; 
        C_ans[60] = 32'h00004a88; C_ans[61] = 32'h00009d4c; C_ans[62] = 32'h00000f85; C_ans[63] = 32'h000080e1;
        C_ans[64] = 32'h0000276b; C_ans[65] = 32'h0000af7f; C_ans[66] = 32'hffff8ef3; C_ans[67] = 32'hffff3e9f; 
        C_ans[68] = 32'h0000cf8d; C_ans[69] = 32'h000084c2; C_ans[70] = 32'h0000174a; C_ans[71] = 32'hffffef3a; 
        C_ans[72] = 32'hffff7050; C_ans[73] = 32'hffff52b4; C_ans[74] = 32'h00000c47; C_ans[75] = 32'hffffcdb6; 
        C_ans[76] = 32'hffffc878; C_ans[77] = 32'h00006cfd; C_ans[78] = 32'h00004d84; C_ans[79] = 32'h00006e95;
        C_ans[80] = 32'h00000160; C_ans[81] = 32'h00003164; C_ans[82] = 32'hffff53a8; C_ans[83] = 32'hffffda56; 
        C_ans[84] = 32'hfffffa2f; C_ans[85] = 32'h0000dc02; C_ans[86] = 32'hffffa85e; C_ans[87] = 32'hffffacfe; 
        C_ans[88] = 32'hffff7d61; C_ans[89] = 32'h00004032; C_ans[90] = 32'h0000456c; C_ans[91] = 32'hffffd1c7; 
        C_ans[92] = 32'hffffb828; C_ans[93] = 32'h00009d20; C_ans[94] = 32'hffff9901; C_ans[95] = 32'hffffe411;
        C_ans[96] = 32'h0000f399; C_ans[97] = 32'hffffc1d1; C_ans[98] = 32'h00006335; C_ans[99] = 32'h00009afb; 
        C_ans[100] = 32'hffffc2fa; C_ans[101] = 32'hffffc79c; C_ans[102] = 32'h000063d0; C_ans[103] = 32'hfffff5d2; 
        C_ans[104] = 32'hffff84d2; C_ans[105] = 32'h00005356; C_ans[106] = 32'hfffef5e4; C_ans[107] = 32'h00005225; 
        C_ans[108] = 32'hffff8156; C_ans[109] = 32'hffffbcdc; C_ans[110] = 32'hffffbb90; C_ans[111] = 32'hffffbf32;
        C_ans[112] = 32'hfffffb74; C_ans[113] = 32'h00003971; C_ans[114] = 32'hffffaa8f; C_ans[115] = 32'h00005407; 
        C_ans[116] = 32'h00000c0c; C_ans[117] = 32'h00008b38; C_ans[118] = 32'hffffd2df; C_ans[119] = 32'hffffaec5; 
        C_ans[120] = 32'hfffff890; C_ans[121] = 32'hffffe83a; C_ans[122] = 32'h00008e45; C_ans[123] = 32'h00004214; 
        C_ans[124] = 32'h0000235b; C_ans[125] = 32'h0000958d; C_ans[126] = 32'hffff3a97; C_ans[127] = 32'hffffe864;
        C_ans[128] = 32'hffffab92; C_ans[129] = 32'h000087ef; C_ans[130] = 32'hffff6b7e; C_ans[131] = 32'h0000063d; 
        C_ans[132] = 32'hfffff2d8; C_ans[133] = 32'h0000642f; C_ans[134] = 32'h000040fc; C_ans[135] = 32'hffff89b0; 
        C_ans[136] = 32'hffffd854; C_ans[137] = 32'hffff96b8; C_ans[138] = 32'hffffd3e3; C_ans[139] = 32'hffff4560; 
        C_ans[140] = 32'hffffea0d; C_ans[141] = 32'hffffeb25; C_ans[142] = 32'h00005a9e; C_ans[143] = 32'hffffb265;
        C_ans[144] = 32'hffff74c8; C_ans[145] = 32'hffffb3b0; C_ans[146] = 32'h00001f9c; C_ans[147] = 32'hffff64b7; 
        C_ans[148] = 32'hffffb094; C_ans[149] = 32'hffffdbad; C_ans[150] = 32'h00001942; C_ans[151] = 32'h000052f5; 
        C_ans[152] = 32'hfffff9d0; C_ans[153] = 32'hfffff047; C_ans[154] = 32'h0000056f; C_ans[155] = 32'hffffa519; 
        C_ans[156] = 32'hffffd620; C_ans[157] = 32'h00001c98; C_ans[158] = 32'h000097e4; C_ans[159] = 32'hffffabd5;
        C_ans[160] = 32'h00009201; C_ans[161] = 32'h00002505; C_ans[162] = 32'h00002034; C_ans[163] = 32'hfffff22c; 
        C_ans[164] = 32'h000056ff; C_ans[165] = 32'hffffc978; C_ans[166] = 32'h00000bc8; C_ans[167] = 32'hffffbe40; 
        C_ans[168] = 32'hffff2062; C_ans[169] = 32'hfffff480; C_ans[170] = 32'hffffb88f; C_ans[171] = 32'h0000466d; 
        C_ans[172] = 32'h00002af3; C_ans[173] = 32'h00006a1e; C_ans[174] = 32'h00000000; C_ans[175] = 32'h00004958;
        C_ans[176] = 32'h00001533; C_ans[177] = 32'hfffff1f0; C_ans[178] = 32'h0000212f; C_ans[179] = 32'hffffcf56; 
        C_ans[180] = 32'h00000087; C_ans[181] = 32'hffffa41c; C_ans[182] = 32'h00002c47; C_ans[183] = 32'h00001d99; 
        C_ans[184] = 32'hffff80a2; C_ans[185] = 32'hffffef48; C_ans[186] = 32'hfffff002; C_ans[187] = 32'h00001fe0; 
        C_ans[188] = 32'hffffc3dd; C_ans[189] = 32'h00005473; C_ans[190] = 32'h00002f01; C_ans[191] = 32'h000015db;
        C_ans[192] = 32'hffff6a95; C_ans[193] = 32'h000015ed; C_ans[194] = 32'h00005213; C_ans[195] = 32'h00001258; 
        C_ans[196] = 32'h000065da; C_ans[197] = 32'h00002fda; C_ans[198] = 32'hffff9797; C_ans[199] = 32'h00003de3; 
        C_ans[200] = 32'h0000418b; C_ans[201] = 32'hffffd6f2; C_ans[202] = 32'h00006eb6; C_ans[203] = 32'hffff835c; 
        C_ans[204] = 32'h00008d6f; C_ans[205] = 32'h00004d2e; C_ans[206] = 32'hfffff8af; C_ans[207] = 32'h0000739a;
        C_ans[208] = 32'h0000f36f; C_ans[209] = 32'hffffa02e; C_ans[210] = 32'h0000257f; C_ans[211] = 32'h0000cd6d; 
        C_ans[212] = 32'h0000419a; C_ans[213] = 32'hffffca8f; C_ans[214] = 32'hffffd7d6; C_ans[215] = 32'hfffff0ff; 
        C_ans[216] = 32'hffffa51b; C_ans[217] = 32'hffff71a3; C_ans[218] = 32'hffffa85e; C_ans[219] = 32'h00004069; 
        C_ans[220] = 32'hffffd8fa; C_ans[221] = 32'h00004bb9; C_ans[222] = 32'hffffb914; C_ans[223] = 32'hffff8517;
        C_ans[224] = 32'hffffffbd; C_ans[225] = 32'hffffc6f2; C_ans[226] = 32'h000018a7; C_ans[227] = 32'hffff908a; 
        C_ans[228] = 32'h00003a29; C_ans[229] = 32'hffff6d0d; C_ans[230] = 32'hffffdca1; C_ans[231] = 32'h00000f27; 
        C_ans[232] = 32'hfffff5d3; C_ans[233] = 32'h0000567a; C_ans[234] = 32'h00002fd7; C_ans[235] = 32'h00002a21; 
        C_ans[236] = 32'hffffbc6b; C_ans[237] = 32'hffffc6de; C_ans[238] = 32'hffffe329; C_ans[239] = 32'h00007b28;
        C_ans[240] = 32'h000036c4; C_ans[241] = 32'h00004fa8; C_ans[242] = 32'hffffb559; C_ans[243] = 32'hffffe7ec; 
        C_ans[244] = 32'h000022da; C_ans[245] = 32'hffffb9ab; C_ans[246] = 32'hffffe875; C_ans[247] = 32'hffffcf0e; 
        C_ans[248] = 32'hffffa05f; C_ans[249] = 32'h00001724; C_ans[250] = 32'h00000148; C_ans[251] = 32'hffffb8d1; 
        C_ans[252] = 32'hffffefe9; C_ans[253] = 32'h00001001; C_ans[254] = 32'h000040c3; C_ans[255] = 32'h00003689;
    end

    // --- 7. 模擬 CFU 操作 Task ---
    task cfu_op;
        input [9:0]  funct3;
        input [31:0] in0;
        input [31:0] in1;
        output [31:0] res;
        begin
            @(posedge clk);
            #1;
            cmd_valid = 1'b1;
            cmd_payload_function_id = funct3;
            cmd_payload_inputs_0 = in0;
            cmd_payload_inputs_1 = in1;
            rsp_ready = 1'b1;

            // 等待 handshake
            wait(cmd_ready === 1'b1);
            
            @(posedge clk); 
            #1;
            cmd_valid = 1'b0;
            
            // 等待回應
            wait(rsp_valid === 1'b1);
            res = rsp_payload_outputs_0;
            
            @(posedge clk);
        end
    endtask

    // --- 8. 主程式 ---
    initial begin
        error_ct = 0;
        
        // Reset
        reset = 1;
        cmd_valid = 0;
        rsp_ready = 0;
        repeat(5) @(posedge clk);
        reset = 0;
        $display("=== [TB] System Reset ===");

        // 1. 寫入 Buffer A
        // cfu_op0(0, index, data)
        for (i = 0; i < 64; i = i + 1) begin
            cfu_op(0, i, A_arr[i], read_val);
            $display("[hAPPEN]  A Array Got: %h", A_arr[i]);
        end
        $display("=== [TB] Matrix A Loaded ===");

        // 2. 寫入 Buffer B
        // cfu_op0(1, index, data)
        for (i = 0; i < 64; i = i + 1) begin
            cfu_op(1, i, B_arr[i], read_val);
            $display("[hAPPEN]  B Array Got: %h", B_arr[i]);
        end
        $display("=== [TB] Matrix B Loaded ===");

        // 3. 啟動 TPU
        // cfu_op0(2, params, N)  where params = (M << 8) | K
        // K=16, M=16, N=16 -> params = (16<<8)|16 = 4112 (0x1010)
        $display("=== [TB] Starting TPU Computation... ===");
        cfu_op(2, 4112, 16, read_val); 

        // 4. 等待 Busy 結束
        busy_status = 1;
        while (busy_status != 0) begin
            #500; // 模擬軟體 polling 的間隔
            cfu_op(3, 0, 0, busy_status);
            $display("[TB] Waiting for TPU... Busy=%b", busy_status);
        end
        $display("=== [TB] TPU Computation Finished ===");

        // 5. 讀取並比對結果
        $display("=== [TB] Verifying Results ===");
        for (i = 0; i < 64; i = i + 1) begin
            // Global Buffer C 的 index i 對應 4 個 int32
            // CFU func3 = 4, 5, 6, 7 分別讀取這 4 個 int32
            
            // C_ans 是一個 flat array [256]，對應關係是:
            // Index 0 (0-3): C_ans[0], C_ans[1], C_ans[2], C_ans[3]
            // ...
            // Index i: C_ans[i*4], C_ans[i*4+1], C_ans[i*4+2], C_ans[i*4+3]

            // Read Word 0
            cfu_op(7, i, 0, c0);
            if (c0 !== C_ans[(i%16)*4+(i/16*4)]) begin
                $display("[ERROR] Mismatch at C[%d][0]. Exp: %h, Got: %h", i, C_ans[(i%16)*4+(i/16*4)], c0);
                error_ct = error_ct + 1;
            end

            // Read Word 1
            cfu_op(6, i, 0, c1);
            if (c1 !== C_ans[(i%16)*4+(i/16*4)+1]) begin
                $display("[ERROR] Mismatch at C[%d][1]. Exp: %h, Got: %h", i, C_ans[(i%16)*4+(i/16*4)+1], c1);
                error_ct = error_ct + 1;
            end

            // Read Word 2
            cfu_op(5, i, 0, c2);
            if (c2 !== C_ans[(i%16)*4+(i/16*4)+2]) begin
                $display("[ERROR] Mismatch at C[%d][2]. Exp: %h, Got: %h", i, C_ans[(i%16)*4+(i/16*4)+2], c2);
                error_ct = error_ct + 1;
            end

            // Read Word 3
            cfu_op(4, i, 0, c3);
            if (c3 !== C_ans[(i%16)*4+(i/16*4)+3]) begin
                $display("[ERROR] Mismatch at C[%d][3]. Exp: %h, Got: %h", i, C_ans[(i%16)*4+(i/16*4)+3], c3);
                error_ct = error_ct + 1;
            end
        end

        if (error_ct == 0) begin
            $display("\n******************************************");
            $display("   CONGRATULATIONS! ALL DATA MATCHED!     ");
            $display("******************************************\n");
        end else begin
            $display("\n******************************************");
            $display("   FAILED! Found %d mismatches.", error_ct);
            $display("******************************************\n");
        end

        #100;
        $finish;
    end

endmodule