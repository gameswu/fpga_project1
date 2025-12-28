`timescale 1ns / 1ps

module tb_Layer5;

    // Instantiate the common testbench setup
    tb_common u_tb_common();

    integer i;
    reg [31:0] read_val;

    initial begin
        $display("Starting Layer 5 Test (Stride 2)...");
        u_tb_common.reset_system();

        // ------------------------------------------------------
        // 1. Configure CSRs for Layer 5
        // ------------------------------------------------------
        // IFM: 8x8x64
        // OFM: 4x4x128
        // Kernel: 3x3
        // Stride: 2, Pad: 1
        // ReLU: 1
        // Shift: 8
        
        u_tb_common.write_csr(16'h0010, 8);   // IFM H
        u_tb_common.write_csr(16'h0014, 8);   // IFM W
        u_tb_common.write_csr(16'h0018, 4);   // OFM H
        u_tb_common.write_csr(16'h001C, 4);   // OFM W
        u_tb_common.write_csr(16'h0020, 64);  // IC
        u_tb_common.write_csr(16'h0024, 128); // OC
        u_tb_common.write_csr(16'h0028, 3);   // KH
        u_tb_common.write_csr(16'h002C, 3);   // KW
        u_tb_common.write_csr(16'h0030, 2);   // Stride
        u_tb_common.write_csr(16'h0034, 1);   // Pad
        u_tb_common.write_csr(16'h0038, 1);   // ReLU En
        u_tb_common.write_csr(16'h003C, 8);   // Quant Shift
        u_tb_common.write_csr(16'h0040, 0);   // Max Pool Disable

        // ------------------------------------------------------
        // 2. Initialize Memory
        // ------------------------------------------------------
        $display("Initializing Memory...");
        
        // IFM: 8x8x64 bytes = 4096 bytes = 128 256-bit words.
        // 128 * 8 = 1024 32-bit words.
        for (i = 0; i < 1024; i = i + 1) begin
            u_tb_common.write_ifm_word(i, 32'h10101010); // 16
        end
        
        // Weights: 128x64x3x3 = 73728 bytes = 4608 128-bit words.
        // 4608 * 4 = 18432 32-bit words.
        for (i = 0; i < 18432; i = i + 1) begin
            u_tb_common.write_wgt_word(i, 32'h10101010); // 16
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
        u_tb_common.read_ofm_word(0, read_val);
        $display("OFM[0] = %h", read_val);
        
        $finish;
    end

endmodule
