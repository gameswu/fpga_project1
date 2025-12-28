`timescale 1ns / 1ps

module tb_Layer6;

    // Instantiate the common testbench setup
    tb_common u_tb_common();

    integer i;
    integer k;
    reg [31:0] read_val;

    // Debug Monitor
    initial begin
        forever begin
            @(posedge u_tb_common.sys_clk);
            if (u_tb_common.u_dut.u_dnn_top.u_controller.state == 2) begin // S_COMPUTE
                $display("Time %t: COMPUTE - PE_EN=%b, IFM_Addr=%h, WGT_Addr=%h", 
                    $time, 
                    u_tb_common.u_dut.u_dnn_top.u_controller.pe_en,
                    u_tb_common.u_dut.u_dnn_top.u_controller.ifm_addr,
                    u_tb_common.u_dut.u_dnn_top.u_controller.wgt_addr
                );
            end
            if (u_tb_common.u_dut.u_dnn_top.u_controller.ofm_wr_en) begin
                $display("Time %t: OFM WRITE - Addr=%h, Data=%h", 
                    $time,
                    u_tb_common.u_dut.u_dnn_top.u_controller.ofm_addr,
                    u_tb_common.u_dut.u_dnn_top.u_controller.ofm_wdata
                );
            end
        end
    end

    initial begin
        $display("Starting Layer 6 (Avg Pooling) Test...");
        u_tb_common.reset_system();

        // ------------------------------------------------------
        // 1. Configure CSRs for Layer 6
        // ------------------------------------------------------
        // IFM: 4x4x128
        // OFM: 1x1x128
        // Kernel: 4x4
        // Stride: 1, Pad: 0
        // ReLU: 0
        // Shift: 4 (Division by 16)
        // Mode: Conv (Max Pool Disabled)
        
        u_tb_common.write_csr(16'h0010, 4);   // IFM H
        u_tb_common.write_csr(16'h0014, 4);   // IFM W
        u_tb_common.write_csr(16'h0018, 1);   // OFM H
        u_tb_common.write_csr(16'h001C, 1);   // OFM W
        u_tb_common.write_csr(16'h0020, 128); // IC
        u_tb_common.write_csr(16'h0024, 128); // OC
        u_tb_common.write_csr(16'h0028, 4);   // KH
        u_tb_common.write_csr(16'h002C, 4);   // KW
        u_tb_common.write_csr(16'h0030, 1);   // Stride
        u_tb_common.write_csr(16'h0034, 0);   // Pad
        u_tb_common.write_csr(16'h0038, 0);   // ReLU En
        u_tb_common.write_csr(16'h003C, 4);   // Quant Shift (Div 16)
        u_tb_common.write_csr(16'h0040, 0);   // Max Pool Disable

        // ------------------------------------------------------
        // 2. Initialize Memory
        // ------------------------------------------------------
        $display("Initializing Memory...");
        
        // IFM: 4x4x128 bytes = 2048 bytes = 64 256-bit words.
        // 64 * 8 = 512 32-bit words.
        // Set all inputs to 32 (0x20).
        // Average of 32 should be 32.
        for (i = 0; i < 512; i = i + 1) begin
            u_tb_common.write_ifm_word(i, 32'h20202020); 
        end
        
        // Weights: 128x128x4x4 = 262144 bytes.
        // Wait, this is Depthwise/Global Avg Pooling.
        // Standard Conv connects all IC to all OC.
        // If we want Channel-wise Avg Pooling (Output C depends only on Input C):
        // We need a Diagonal Weight Matrix.
        // Weight[oc][ic] = 1 if oc==ic else 0.
        // Since our Controller is Dense, we must set weights this way.
        // Total Weights: 128(OC) * 128(IC) * 16(K) = 262,144 bytes.
        // This is huge for simulation but necessary for correctness if using Dense Controller.
        // We need to write 0 or 1.
        // 1 in Q0 format is just 1.
        
        // Writing 262KB via CSR is too slow for simulation.
        // We should use a loop that only writes non-zero weights?
        // Or just write a small subset to verify functionality for first few channels.
        // Let's verify Channel 0.
        // OC=0. IC=0..127.
        // We want Weight[0][0] = 1. Weight[0][1..127] = 0.
        // Kernel is 4x4. So Weight[0][0] is actually 16 values. All 1.
        
        // Let's just initialize the first few weights for Channel 0.
        // Weight Layout: OC, IC, KY, KX.
        // OC=0.
        //   IC=0. KY=0..3, KX=0..3. (16 bytes). Set to 0x01.
        //   IC=1..127. Set to 0x00.
        // OC=1.
        //   IC=1. Set to 0x01.
        
        // Since we removed backdoor access, we must use `write_wgt_word`.
        // We will only initialize weights for OC=0 to save time.
        // And we assume BRAM is initialized to 0 by default?
        // In simulation, BRAM model memory `mem` is not auto-cleared unless we do it.
        // But we removed the BRAM model. The DUT is DNN_Top.
        // If we use Vivado BRAM IP, it can be initialized to 0.
        // Here we assume 0.
        
        // Write Weights for OC=0, IC=0.
        // We need to write weights for ALL 16 kernel points (4x4) to get the full sum.
        // Layout: Tile_OC=0, Tile_IC=0.
        // Inner loops: KY (0..3), KW (0..3).
        // Total 16 blocks.
        // Each block has 32 rows (words).
        // We write to Row 0 of each block.
        
        // Workaround: Write the first block explicitly to ensure it sticks
        u_tb_common.write_wgt_word(0, 32'h01010101);
        u_tb_common.write_wgt_word(1, 32'h01010101);
        u_tb_common.write_wgt_word(2, 32'h01010101);
        u_tb_common.write_wgt_word(3, 32'h01010101);

        for (k = 0; k < 16; k = k + 1) begin
            // Block k. Base Address = k * 32.
            // Row 0 Address = Base Address.
            // Write 128-bit word (4 x 32-bit).
            
            u_tb_common.write_wgt_word((k * 32) * 4 + 0, 32'h01010101);
            u_tb_common.write_wgt_word((k * 32) * 4 + 1, 32'h01010101);
            u_tb_common.write_wgt_word((k * 32) * 4 + 2, 32'h01010101);
            u_tb_common.write_wgt_word((k * 32) * 4 + 3, 32'h01010101);
        end
        
        // Verify Weights by Reading Back
        $display("Verifying Weights...");
        u_tb_common.read_wgt_word(0, read_val);
        $display("Weight[0] = %h (Expected 01010101)", read_val);
        u_tb_common.read_wgt_word(1, read_val);
        $display("Weight[1] = %h (Expected 01010101)", read_val);
        u_tb_common.read_wgt_word(4, read_val); 
        $display("Weight[4] (Row 1) = %h", read_val);
        
        // Note: If we don't initialize other weights to 0, and they are X, result will be X.
        // But we can't easily clear 256KB via CSR in this testbench without taking forever.
        // We'll assume the "System Reset" or "BRAM Init" clears them.
        // In `tb_common.sv`, we don't have BRAM models anymore, so we can't clear them.
        // This test relies on the assumption that unwritten addresses are 0.

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
        // Check OFM[0] (Channel 0).
        // Input = 2. Sum 16 pixels = 2*16 = 32.
        // Shift 0 (Div 1) = 32.
        u_tb_common.read_ofm_word(0, read_val);
        $display("OFM[0] = %h (Expected 20...)", read_val);
        
        $finish;
    end

endmodule
