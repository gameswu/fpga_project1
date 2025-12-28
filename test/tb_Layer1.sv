`timescale 1ns / 1ps

module tb_Layer1;

    // Instantiate the common testbench setup
    tb_common u_tb_common();

    integer i, j, k;
    reg [31:0] read_val;

    initial begin
        $display("Starting Layer 1 Test...");
        u_tb_common.reset_system();

        // ------------------------------------------------------
        // 1. Configure CSRs for Layer 1
        // ------------------------------------------------------
        // IFM: 32x32x1
        // OFM: 32x32x32
        // Kernel: 5x5
        // Stride: 1, Pad: 2
        // ReLU: 1
        // Shift: 9 (Qin=7, Qw=7, Qout=5 => 14-5=9)
        
        u_tb_common.write_csr(16'h0010, 32); // IFM H
        u_tb_common.write_csr(16'h0014, 32); // IFM W
        u_tb_common.write_csr(16'h0018, 32); // OFM H
        u_tb_common.write_csr(16'h001C, 32); // OFM W
        u_tb_common.write_csr(16'h0020, 1);  // IC
        u_tb_common.write_csr(16'h0024, 32); // OC
        u_tb_common.write_csr(16'h0028, 5);  // KH
        u_tb_common.write_csr(16'h002C, 5);  // KW
        u_tb_common.write_csr(16'h0030, 1);  // Stride
        u_tb_common.write_csr(16'h0034, 2);  // Pad
        u_tb_common.write_csr(16'h0038, 1);  // ReLU En
        u_tb_common.write_csr(16'h003C, 9);  // Quant Shift
        u_tb_common.write_csr(16'h0040, 0);  // Max Pool Disable

        // ------------------------------------------------------
        // 2. Initialize Memory
        // ------------------------------------------------------
        $display("Initializing Memory...");
        
        // Initialize IFM (32x32x1)
        // We need to initialize 1024 pixels.
        // Each pixel is a 256-bit word in the BRAM (due to fixed SIMD=32 layout).
        // Since IC=1, we only care about the first byte (or first 32-bit word) of each 256-bit entry.
        // The BRAM is 32-bit write width.
        // 256-bit Word Index P corresponds to 32-bit Word Index P*8.
        for (i = 0; i < 1024; i = i + 1) begin
            u_tb_common.write_ifm_word(i * 8, 32'h20202020); // Value = 32 (0x20)
        end
        
        // Initialize Weights
        // Controller expects weights to be laid out with a stride of PE_ROWS (32) words for each kernel point/tile step.
        // Even though IC=1, the controller reads 32 rows.
        // Layout:
        // Loop Tile_OC (0..1)
        //   Loop Tile_IC (0)
        //     Loop KY (0..4)
        //       Loop KW (0..4)
        //         Block of 32 words (128-bit). Only Word 0 is valid for IC=1.
        
        // Total 2 * 1 * 5 * 5 = 50 blocks.
        // Each block is 32 * 128-bit words.
        // We need to write 0x20 to the first word of each block.
        
        // Clear all weights first (optional but good practice)
        // (Assuming TB memory is 0 initialized or we just write what we need)
        
        for (k = 0; k < 50; k = k + 1) begin
            // Address of the valid word for this block
            // Block Index k.
            // Base Address = k * 32 (words).
            // We write to Base Address + 0 (since IC=0 is mapped to Row 0).
            
            // write_wgt_word takes 32-bit word index.
            // 128-bit word index = k * 32.
            // 32-bit word index = (k * 32) * 4.
            
            // We need to write 128-bits of 0x20.
            // That is 4 x 32-bit writes.
            for (j = 0; j < 4; j = j + 1) begin
                u_tb_common.write_wgt_word((k * 32 * 4) + j, 32'h20202020);
            end
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
        // 5. Check Results (Basic)
        // ------------------------------------------------------
        // Read first few OFM words
        // OFM Size: 32x32x32.
        // Just read the first output pixel (channel 0-3).
        u_tb_common.read_ofm_word(0, read_val);
        $display("OFM[0] = %h", read_val);
        
        // Verification Logic:
        // Input = 32 (0x20), Weight = 32 (0x20).
        // Kernel 5x5. Pad 2.
        // At (0,0), valid overlap is 3x3 = 9 pixels.
        // Sum = 9 * (32 * 32) = 9 * 1024 = 9216.
        // Shift = 9.
        // Result = 9216 >> 9 = 18 (0x12).
        // Expected Result = 18 (0x12).
        
        if (read_val == 32'h12) begin
            $display("PASS: OFM[0] matches expected value (18).");
        end else begin
            $display("FAIL: OFM[0] mismatch. Expected 18 (0x12), Got %h", read_val);
        end
        
        $finish;
    end

endmodule
