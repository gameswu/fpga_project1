`timescale 1ns / 1ps

module tb_Layer7;

    // Instantiate the common testbench setup
    tb_common u_tb_common();

    integer i;
    reg [31:0] read_val;

    initial begin
        $display("Starting Layer 7 (FC) Test...");
        u_tb_common.reset_system();

        // ------------------------------------------------------
        // 1. Configure CSRs for Layer 7
        // ------------------------------------------------------
        // IFM: 1x1x128
        // OFM: 1x1x10
        // Kernel: 1x1
        // Stride: 1, Pad: 0
        // ReLU: 0
        // Shift: 6
        
        u_tb_common.write_csr(16'h0010, 1);  // IFM H
        u_tb_common.write_csr(16'h0014, 1);  // IFM W
        u_tb_common.write_csr(16'h0018, 1);  // OFM H
        u_tb_common.write_csr(16'h001C, 1);  // OFM W
        u_tb_common.write_csr(16'h0020, 128); // IC
        u_tb_common.write_csr(16'h0024, 10); // OC
        u_tb_common.write_csr(16'h0028, 1);  // KH
        u_tb_common.write_csr(16'h002C, 1);  // KW
        u_tb_common.write_csr(16'h0030, 1);  // Stride
        u_tb_common.write_csr(16'h0034, 0);  // Pad
        u_tb_common.write_csr(16'h0038, 0);  // ReLU En
        u_tb_common.write_csr(16'h003C, 6);  // Quant Shift
        u_tb_common.write_csr(16'h0040, 0);  // Max Pool Disable

        // ------------------------------------------------------
        // 2. Initialize Memory
        // ------------------------------------------------------
        $display("Initializing Memory...");
        
        // IFM: 1x1x128 bytes = 128 bytes = 4 256-bit words.
        // 4 * 8 = 32 32-bit words.
        for (i = 0; i < 32; i = i + 1) begin
            u_tb_common.write_ifm_word(i, 32'h08080808); // 8
        end
        
        // Weights: 128 rows (IC). Each row has 10 valid weights (OC).
        // Hardware expects 16 weights per row (128-bit).
        // So we write 128 blocks.
        // Each block: 10 bytes valid, 6 bytes pad.
        // We use Weight = 1.
        
        for (i = 0; i < 128; i = i + 1) begin
            // Row i.
            // Base word address = i * 4 (32-bit words).
            
            // We want to write 10 bytes of 0x01.
            // Word 0: Bytes 0-3 (0x01010101)
            // Word 1: Bytes 4-7 (0x01010101)
            // Word 2: Bytes 8-9 (0x00000101) -> 0x0101 is lower 16 bits. Upper 16 bits 0.
            // Word 3: Bytes 12-15 (0x00000000)
            
            u_tb_common.write_wgt_word(i*4 + 0, 32'h01010101);
            u_tb_common.write_wgt_word(i*4 + 1, 32'h01010101);
            u_tb_common.write_wgt_word(i*4 + 2, 32'h00000101);
            u_tb_common.write_wgt_word(i*4 + 3, 32'h00000000);
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
        // Expected: 8*8 = 64. Shift 6 -> 1.
        // Sum 128 elements = 128.
        // Clipped to 127.
        
        u_tb_common.read_ofm_word(0, read_val);
        $display("OFM[0] = %h (Expected 7F...)", read_val);
        
        $finish;
    end

endmodule
