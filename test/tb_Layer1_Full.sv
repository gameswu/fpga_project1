`timescale 1ns / 1ps

module tb_Layer1_Full;

    // Instantiate the common testbench setup
    tb_common u_tb_common();

    integer i, j, k;
    reg [31:0] read_val;

    // Verification variables
    integer oy, ox, oc;
    integer errors, total_errors;
    reg signed [7:0] expected_val;
    reg signed [31:0] hw_val;
    integer word_addr;
    
    // Expected output feature map array [OC][H][W]
    reg signed [7:0] expected_ofm [0:31][0:31][0:31];
    
    // Read output feature map array [OC][H][W]
    reg signed [31:0] hw_ofm [0:31][0:31][0:31];

    initial begin
        $display("=======================================================");
        $display("Starting Layer 1 FULL Test (32 Output Channels)");
        $display("Using data from simulator/data/im1/");
        $display("  - Input:  conv1.input.dat (32x32x1)");
        $display("  - Weight: conv1.dat (32x1x5x5)");
        $display("  - Output: conv1.output.dat (32x32x32)");
        $display("=======================================================\n");
        
        u_tb_common.reset_system();

        // ------------------------------------------------------
        // 1. Configure CSRs for Layer 1
        // ------------------------------------------------------
        $display("Configuring Layer 1 parameters...");
        u_tb_common.write_csr(16'h0010, 32); // IFM H
        u_tb_common.write_csr(16'h0014, 32); // IFM W
        u_tb_common.write_csr(16'h0018, 32); // OFM H
        u_tb_common.write_csr(16'h001C, 32); // OFM W
        u_tb_common.write_csr(16'h0020, 1);  // IC = 1
        u_tb_common.write_csr(16'h0024, 32); // OC = 32
        u_tb_common.write_csr(16'h0028, 5);  // KH
        u_tb_common.write_csr(16'h002C, 5);  // KW
        u_tb_common.write_csr(16'h0030, 1);  // Stride
        u_tb_common.write_csr(16'h0034, 2);  // Pad
        u_tb_common.write_csr(16'h0038, 0);  // ReLU En (Disabled)
        u_tb_common.write_csr(16'h003C, 9);  // Quant Shift
        u_tb_common.write_csr(16'h0040, 0);  // Max Pool Disable
        $display("Configuration complete!\n");

        // ------------------------------------------------------
        // 2. Load IFM Data (32x32x1 = 1024 bytes)
        // ------------------------------------------------------
        $display("Loading IFM data...");
`include "ifm_init_full.sv"
        $display("IFM loaded\n");

        // ------------------------------------------------------
        // 3. Load Weight Data (32x1x5x5 = 800 bytes)
        // ------------------------------------------------------
        $display("Loading weight data...");
`include "wgt_init_full.sv"
        $display("Weights loaded\n");

        // ------------------------------------------------------
        // 4. Load Expected Output (32x32x32 = 32768 bytes)
        // ------------------------------------------------------
        $display("Loading expected output data...");
`include "ofm_expected_full.sv"
        $display("Expected output loaded\n");

        // ------------------------------------------------------
        // 5. Start Accelerator
        // ------------------------------------------------------
        $display("========== Starting Computation ==========");
        u_tb_common.write_csr(16'h0000, 1);

        // Wait for Done
        wait(u_tb_common.intr);
        #100;
        $display("========== Computation Complete ==========\n");
        
        // ------------------------------------------------------
        // 6. Read ALL OFM Results (32x32x32 = 32768 int32)
        // ------------------------------------------------------
        $display("========== Reading OFM Results ==========");
        $display("Reading 32768 output values...");
        
        for (oc = 0; oc < 32; oc = oc + 1) begin
            for (oy = 0; oy < 32; oy = oy + 1) begin
                for (ox = 0; ox < 32; ox = ox + 1) begin
                    // OFM layout: CHW format [oc][oy][ox]
                    // Word address = oc*1024 + oy*32 + ox
                    word_addr = oc * 1024 + oy * 32 + ox;
                    u_tb_common.read_ofm_word(word_addr, hw_ofm[oc][oy][ox]);
                end
            end
            
            // Progress indicator
            if (oc % 8 == 7) begin
                $display("  Read channels 0-%0d...", oc);
            end
        end
        $display("OFM reading complete!\n");
        
        // ------------------------------------------------------
        // 7. Verify ALL Results (Channel by Channel)
        // ------------------------------------------------------
        $display("========== Verification Start ==========");
        $display("Verifying all 32 output channels...\n");
        
        total_errors = 0;
        
        for (oc = 0; oc < 32; oc = oc + 1) begin
            errors = 0;
            
            for (oy = 0; oy < 32; oy = oy + 1) begin
                for (ox = 0; ox < 32; ox = ox + 1) begin
                    expected_val = expected_ofm[oc][oy][ox];
                    hw_val = hw_ofm[oc][oy][ox];
                    
                    if (hw_val !== expected_val) begin
                        if (errors < 5) begin
                            $display("  [CH%0d][%0d,%0d] MISMATCH: Expected=%0d, Got=%0d, Diff=%0d",
                                     oc, oy, ox, expected_val, hw_val, hw_val - expected_val);
                        end
                        errors = errors + 1;
                    end
                end
            end
            
            if (errors == 0) begin
                $display("Channel %2d: PASS (1024/1024 correct)", oc);
            end else begin
                $display("Channel %2d: FAIL (%0d/1024 errors)", oc, errors);
                total_errors = total_errors + errors;
            end
        end
        
        // ------------------------------------------------------
        // 8. Final Summary
        // ------------------------------------------------------
        $display("\n========== Final Results ==========");
        if (total_errors == 0) begin
            $display("✓✓✓ ALL TESTS PASSED ✓✓✓");
            $display("All 32 channels matched perfectly!");
            $display("Total: 32768/32768 correct");
        end else begin
            $display("✗✗✗ TEST FAILED ✗✗✗");
            $display("Total errors: %0d/32768 (%0.2f%%)", 
                     total_errors, total_errors * 100.0 / 32768);
        end
        $display("===================================\n");
        
        $finish;
    end

endmodule
