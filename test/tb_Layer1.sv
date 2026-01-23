`timescale 1ns / 1ps

module tb_Layer1;

    // Instantiate the common testbench setup
    tb_common u_tb_common();

    integer i, j, k;
    reg [31:0] read_val;

    // Verification variables
    integer oy, ox, oc, word_idx, byte_offset;
    integer errors;
    reg [7:0] expected_result;
    reg signed [31:0] result_ch;
    
    // Input feature map array for reference
    reg [7:0] ifm_data [0:31][0:31];
    
    // Expected output feature map array (from conv1.output.dat)
    reg [7:0] expected_ofm [0:31][0:31];
    
    // Read output feature map array (from hardware)
    reg [31:0] hw_ofm [0:31][0:31];

    initial begin
        $display("=======================================================");
        $display("Starting Layer 1 Test with Real Data...");
        $display("Using data from simulator/data/im1/conv1.input.dat");
        $display("Using weights from simulator/data/parameters/conv1.dat");
        $display("=======================================================\n");
        
        // Load expected output values from conv1.output.dat (Channel 0)
`include "ofm_expected.sv"
        
        u_tb_common.reset_system();

        // ------------------------------------------------------
        // 1. Configure CSRs for Layer 1
        // ------------------------------------------------------
        // IFM: 32x32x1
        // OFM: 32x32x32
        // Kernel: 5x5
        // Stride: 1, Pad: 2
        // ReLU: 0 (Disable for testing)
        // Shift: 5 (Based on data analysis)
        
        $display("Configuring Layer 1 parameters...");
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
        u_tb_common.write_csr(16'h0038, 0);  // ReLU En
        u_tb_common.write_csr(16'h003C, 9);  // Quant Shift
        u_tb_common.write_csr(16'h0040, 0);  // Max Pool Disable

        // ------------------------------------------------------
        // 2. Initialize Memory with Real Data
        // ------------------------------------------------------
        $display("Loading IFM data from conv1.input.dat...");
        
        // Load IFM data into BRAM and reference array (from generated file)
`include "ifm_init.sv"
        
        $display("Loading weight data from conv1.dat...");
        
        // Initialize Weights with real data
`include "wgt_init.sv"

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
        // 5. Read All Results from OFM Buffer
        // ------------------------------------------------------
        $display("\n========== Reading OFM Data ==========");
        $display("Reading all 1024 positions from hardware...");
        
        for (oy = 0; oy < 32; oy = oy + 1) begin
            for (ox = 0; ox < 32; ox = ox + 1) begin
                // OFM address calculation for channel 0
                byte_offset = (oy * 32 + ox) * 32 + 0;  // Channel 0
                u_tb_common.read_ofm_word(byte_offset, hw_ofm[oy][ox-1]);
            end
        end
        $display("OFM data read complete!\n");
        
        // ------------------------------------------------------
        // 6. Verify Results (All Positions, Channel 0)
        // ------------------------------------------------------
        $display("========== Verification Start ==========");
        $display("Checking all 1024 positions of Channel 0");
        errors = 0;
        
        for (oy = 0; oy < 32; oy = oy + 1) begin
            for (ox = 0; ox < 32; ox = ox + 1) begin
                // Get expected value from loaded data
                expected_result = expected_ofm[oy][ox];
                result_ch = hw_ofm[oy][ox];
                
                if (result_ch[7:0] != expected_result) begin
                    $display("[FAIL] Pos(%2d,%2d): expected=%0d (0x%02x) got=%0d (0x%02x)", 
                             oy, ox, expected_result, expected_result, result_ch[7:0], result_ch[7:0]);
                    errors = errors + 1;
                end else if ((oy % 8 == 0 && ox % 8 == 0) || 
                            (oy == 0 && ox < 4) || (oy == 31 && ox >= 28)) begin
                    // Print some sample passes (corners and grid points)
                    $display("[PASS] Pos(%2d,%2d): expected=%0d (0x%02x) got=%0d (0x%02x)", 
                             oy, ox, expected_result, expected_result, result_ch[7:0], result_ch[7:0]);
                end
            end
        end
        
        $display("\n========== Verification Summary ==========");
        if (errors == 0) begin
            $display("ALL TESTS PASSED! (32×32 = 1024 positions checked)");
        end else begin
            $display("TESTS FAILED: %0d errors out of 1024 total checks", errors);
        end
        $display("==========================================\n");
        
        $finish;
    end

endmodule
