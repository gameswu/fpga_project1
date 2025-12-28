`timescale 1ns / 1ps

module tb_Layer3;

    // Instantiate the common testbench setup
    tb_common u_tb_common();

    integer i;
    reg [31:0] read_val;

    initial begin
        $display("Starting Layer 3 Test...");
        u_tb_common.reset_system();

        // ------------------------------------------------------
        // 1. Configure CSRs for Layer 3
        // ------------------------------------------------------
        // IFM: 16x16x32
        // OFM: 16x16x64
        // Kernel: 3x3
        // Stride: 1, Pad: 1
        // ReLU: 1
        // Shift: 8 (Qin=5, Qw=8, Qout=5 => 13-5=8)
        
        u_tb_common.write_csr(16'h0010, 16); // IFM H
        u_tb_common.write_csr(16'h0014, 16); // IFM W
        u_tb_common.write_csr(16'h0018, 16); // OFM H
        u_tb_common.write_csr(16'h001C, 16); // OFM W
        u_tb_common.write_csr(16'h0020, 32); // IC
        u_tb_common.write_csr(16'h0024, 64); // OC
        u_tb_common.write_csr(16'h0028, 3);  // KH
        u_tb_common.write_csr(16'h002C, 3);  // KW
        u_tb_common.write_csr(16'h0030, 1);  // Stride
        u_tb_common.write_csr(16'h0034, 1);  // Pad
        u_tb_common.write_csr(16'h0038, 1);  // ReLU En
        u_tb_common.write_csr(16'h003C, 8);  // Quant Shift
        u_tb_common.write_csr(16'h0040, 0);  // Max Pool Disable

        // ------------------------------------------------------
        // 2. Initialize Memory
        // ------------------------------------------------------
        $display("Initializing Memory...");
        
        // Initialize IFM (16x16x32 bytes = 8192 bytes = 2048 words)
        // Using external interface
        for (i = 0; i < 2048; i = i + 1) begin 
            u_tb_common.write_ifm_word(i, 32'h20202020); // 0x20 = 32
        end
        
        // Initialize Weights
        // Shape: OC=64, IC=32, KH=3, KW=3. Total = 64*32*9 = 18432 bytes.
        // 18432 bytes = 1152 128-bit words.
        // 128-bit word = 4 32-bit words.
        // Total 32-bit words = 1152 * 4 = 4608.
        for (i = 0; i < 4608; i = i + 1) begin
            u_tb_common.write_wgt_word(i, 32'h20202020); // 0x20 = 32
        end

        // ------------------------------------------------------
        // 3. Start Accelerator
        // ------------------------------------------------------
        $display("Starting Accelerator...");
        u_tb_common.write_csr(16'h0000, 1);

        // ------------------------------------------------------
        // 4. Wait for Done
        // ------------------------------------------------------
        wait(u_tb_common.intr);
        $display("Accelerator Done!");
        
        // ------------------------------------------------------
        // 5. Check Results
        // ------------------------------------------------------
        // Expected: 32 * 32 = 1024. Shift 8 -> 4.
        // Sum over IC=32, KH=3, KW=3. Total 32*9 = 288 accumulations.
        // 288 * 4 = 1152.
        // Clipped to 127.
        
        u_tb_common.read_ofm_word(0, read_val);
        $display("OFM[0] = %h (Expected 0000007F due to clipping)", read_val);
        
        if (read_val == 32'h0000007F)
            $display("PASS: OFM[0] matches expected value.");
        else
            $display("FAIL: OFM[0] mismatch.");
        
        $finish;
    end

endmodule
