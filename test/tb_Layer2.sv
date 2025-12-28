`timescale 1ns / 1ps

module tb_Layer2;

    // Instantiate the common testbench setup
    tb_common u_tb_common();

    integer i;
    reg [31:0] read_val;

    initial begin
        $display("Starting Layer 2 (Max Pooling) Test...");
        u_tb_common.reset_system();

        // ------------------------------------------------------
        // 1. Configure CSRs for Layer 2
        // ------------------------------------------------------
        // IFM: 32x32x32
        // OFM: 16x16x32
        // Kernel: 2x2
        // Stride: 2, Pad: 0
        // ReLU: 0
        // Shift: 0 (Pass through)
        // Max Pool: 1
        
        u_tb_common.write_csr(16'h0010, 32); // IFM H
        u_tb_common.write_csr(16'h0014, 32); // IFM W
        u_tb_common.write_csr(16'h0018, 16); // OFM H
        u_tb_common.write_csr(16'h001C, 16); // OFM W
        u_tb_common.write_csr(16'h0020, 1);  // IC (Testing 1 channel)
        u_tb_common.write_csr(16'h0024, 1);  // OC (Testing 1 channel)
        u_tb_common.write_csr(16'h0028, 2);  // KH
        u_tb_common.write_csr(16'h002C, 2);  // KW
        u_tb_common.write_csr(16'h0030, 2);  // Stride
        u_tb_common.write_csr(16'h0034, 0);  // Pad
        u_tb_common.write_csr(16'h0038, 0);  // ReLU En
        u_tb_common.write_csr(16'h003C, 0);  // Quant Shift
        u_tb_common.write_csr(16'h0040, 1);  // Max Pool Enable

        // ------------------------------------------------------
        // 2. Initialize Memory
        // ------------------------------------------------------
        $display("Initializing Memory...");
        
        // IFM: 32x32.
        // We want to test 2x2 max.
        // Row 0: 1 2 ...
        // Row 1: 3 4 ...
        // Max(0,0) should be 4.
        
        // Note: IC=1. But Controller addresses IFM as 256-bit words (32 channels).
        // Pixel (0,0) is at Addr 0. Pixel (0,1) is at Addr 1.
        // We need to write to the first byte of each 256-bit word.
        // write_ifm_word takes 32-bit word index.
        // 256-bit word index P corresponds to 32-bit word index P*8.
        
        // Write Pixel (0,0) = 1
        u_tb_common.write_ifm_word(0 * 8, 32'h00000001); 
        
        // Write Pixel (0,1) = 2
        u_tb_common.write_ifm_word(1 * 8, 32'h00000002);
        
        // Write Pixel (1,0) = 5
        // Row 1 starts at Pixel 32.
        u_tb_common.write_ifm_word(32 * 8, 32'h00000005);
        
        // Write Pixel (1,1) = 6
        u_tb_common.write_ifm_word(33 * 8, 32'h00000006);
        
        // Weights: Dummy
        // Controller loads 32 rows. We should provide them to avoid X.
        for (i = 0; i < 32; i = i + 1) begin
             // Write 128-bit word (4 x 32-bit)
             u_tb_common.write_wgt_word(i*4, 0);
             u_tb_common.write_wgt_word(i*4+1, 0);
             u_tb_common.write_wgt_word(i*4+2, 0);
             u_tb_common.write_wgt_word(i*4+3, 0);
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
        $display("OFM[0] = %h (Expected 06...)", read_val);
        
        $finish;
    end

endmodule
