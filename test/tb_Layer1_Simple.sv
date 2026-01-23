`timescale 1ns / 1ps

module tb_Layer1_Simple;

    tb_common u_tb_common();
    
    integer i, oc, oy, ox;
    reg signed [31:0] hw_val;
    integer word_addr;

    initial begin
        $display("=======================================================");
        $display("Layer 1 Simple Test - Data Path Verification");
        $display("=======================================================\n");
        
        u_tb_common.reset_system();

        // Configure
        $display("Configuring...");
        u_tb_common.write_csr(16'h0010, 32); // IFM H
        u_tb_common.write_csr(16'h0014, 32); // IFM W
        u_tb_common.write_csr(16'h0018, 32); // OFM H
        u_tb_common.write_csr(16'h001C, 32); // OFM W
        u_tb_common.write_csr(16'h0020, 1);  // IC
        u_tb_common.write_csr(16'h0024, 32); // OC = 32
        u_tb_common.write_csr(16'h0028, 5);  // KH
        u_tb_common.write_csr(16'h002C, 5);  // KW
        u_tb_common.write_csr(16'h0030, 1);  // Stride
        u_tb_common.write_csr(16'h0034, 2);  // Pad
        u_tb_common.write_csr(16'h0038, 0);  // ReLU
        u_tb_common.write_csr(16'h003C, 9);  // Quant Shift
        u_tb_common.write_csr(16'h0040, 0);  // Max Pool

        // Load IFM: 32x32x1 = 1024 bytes = 256 words
        $display("Loading IFM (1024 bytes = 256 words)...");
        for (i = 0; i < 256; i = i + 1) begin
            u_tb_common.write_ifm_word(i, 32'h01010101); // All pixels = 1
        end
        
        // Load Weights: 32x1x5x5 = 800 bytes = 200 words
        $display("Loading Weights (800 bytes = 200 words)...");
        for (i = 0; i < 200; i = i + 1) begin
            u_tb_common.write_wgt_word(i, 32'h01010101); // All weights = 1
        end

        // Start
        $display("\n========== Starting Computation ==========");
        u_tb_common.write_csr(16'h0000, 1);
        
        // Wait for Done
        wait(u_tb_common.intr);
        $display("Computation Done!\n");
        
        // Read and check some results
        $display("========== Checking Results ==========");
        $display("Reading OFM samples (address, value):");
        
        // Check a few positions across different channels
        // OFM layout: (h * W + w) * 32 + oc for 32-bit word address
        
        $display("\nPosition (0,0) - All channels:");
        for (oc = 0; oc < 32; oc = oc + 1) begin
            word_addr = (0 * 32 + 0) * 32 + oc;
            u_tb_common.read_ofm_word(word_addr, hw_val);
            if (oc < 8) begin
                $display("  CH%2d: addr=%5d, value=%0d (0x%08x)", oc, word_addr, $signed(hw_val[7:0]), hw_val);
            end
        end
        
        $display("\nPosition (15,15) - First 8 channels:");
        for (oc = 0; oc < 8; oc = oc + 1) begin
            word_addr = (15 * 32 + 15) * 32 + oc;
            u_tb_common.read_ofm_word(word_addr, hw_val);
            $display("  CH%2d: addr=%5d, value=%0d (0x%08x)", oc, word_addr, $signed(hw_val[7:0]), hw_val);
        end
        
        $display("\nPosition (31,31) - First 8 channels:");
        for (oc = 0; oc < 8; oc = oc + 1) begin
            word_addr = (31 * 32 + 31) * 32 + oc;
            u_tb_common.read_ofm_word(word_addr, hw_val);
            $display("  CH%2d: addr=%5d, value=%0d (0x%08x)", oc, word_addr, $signed(hw_val[7:0]), hw_val);
        end
        
        $display("\n========== Test Complete ==========");
        $display("Expected: Non-zero values (all inputs=1, weights=1 -> accumulation)");
        $display("If all zeros: computation didn't run or addressing wrong");
        
        $finish;
    end

endmodule
