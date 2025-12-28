`timescale 1ns / 1ps

module PPU_tb;

    parameter NUM_CHANNELS = 16;
    parameter DATA_WIDTH = 32;

    reg clk;
    reg rst_n;
    reg en;
    reg mode_bypass; // Mapped to ~is_last
    reg relu_en;
    reg [4:0] quant_shift;
    
    reg [NUM_CHANNELS*DATA_WIDTH-1:0] psum_in;
    reg [NUM_CHANNELS*DATA_WIDTH-1:0] acc_in; // Added
    
    wire [NUM_CHANNELS*DATA_WIDTH-1:0] result_out;

    // Instantiate the Unit Under Test (UUT)
    ppu #(
        .NUM_CHANNELS(NUM_CHANNELS),
        .DATA_WIDTH(DATA_WIDTH)
    ) uut (
        .clk(clk), 
        .rst_n(rst_n), 
        .en(en), 
        .is_first(1'b1), // Always overwrite for this TB
        .is_last(~mode_bypass), // Bypass=1 -> is_last=0 (Raw). Bypass=0 -> is_last=1 (Quant)
        .relu_en(relu_en), 
        .quant_shift(quant_shift), 
        .psum_in(psum_in), 
        .acc_in(acc_in),
        .result_out(result_out)
    );

    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Helper to pack array into flat vector
    function [NUM_CHANNELS*DATA_WIDTH-1:0] pack_data;
        input integer val;
        integer i;
        reg [NUM_CHANNELS*DATA_WIDTH-1:0] tmp;
        begin
            for (i=0; i<NUM_CHANNELS; i=i+1) begin
                tmp[i*32 +: 32] = val + i; // Different value for each channel
            end
            pack_data = tmp;
        end
    endfunction

    // Helper to unpack and print
    task print_results;
        input [NUM_CHANNELS*DATA_WIDTH-1:0] res;
        integer i;
        reg signed [31:0] val;
        begin
            $display("Time: %t", $time);
            for (i=0; i<4; i=i+1) begin // Print first 4 channels
                val = res[i*32 +: 32];
                $write("Ch%0d: %0d  ", i, val);
            end
            $display("...");
        end
    endtask

    // Helper to check results
    task check_result;
        input integer ch_idx;
        input signed [31:0] expected_val;
        input [NUM_CHANNELS*DATA_WIDTH-1:0] res;
        reg signed [31:0] actual_val;
        begin
            actual_val = res[ch_idx*32 +: 32];
            if (actual_val === expected_val) begin
                $display("[PASS] Ch%0d: Expected %0d, Got %0d", ch_idx, expected_val, actual_val);
            end else begin
                $display("[FAIL] Ch%0d: Expected %0d, Got %0d", ch_idx, expected_val, actual_val);
            end
        end
    endtask

    initial begin
        // Initialize Inputs
        rst_n = 0;
        en = 0;
        mode_bypass = 0;
        relu_en = 0;
        quant_shift = 0;
        psum_in = 0;
        acc_in = 0;

        // Wait 100 ns for global reset to finish
        #100;
        rst_n = 1;
        en = 1;
        
        // -------------------------------------------------
        // Test Case 1: Bypass Mode
        // -------------------------------------------------
        $display("\n--- Test Case 1: Bypass Mode ---");
        mode_bypass = 1;
        psum_in = pack_data(100); // Ch0=100, Ch1=101...
        
        #10; // Wait 1 cycle
        psum_in = pack_data(200);
        
        #10; // Wait 1 cycle (Output of first input should appear after 2 cycles total latency)
        // Check output at T+20 (from input set)
        print_results(result_out); // Should be 100, 101...
        check_result(0, 100, result_out);
        check_result(1, 101, result_out);
        
        #10;
        print_results(result_out); // Should be 200, 201...
        check_result(0, 200, result_out);
        check_result(1, 201, result_out);

        // -------------------------------------------------
        // Test Case 2: Normal Mode (ReLU + Quant)
        // -------------------------------------------------
        $display("\n--- Test Case 2: Normal Mode (ReLU=1, Shift=0) ---");
        mode_bypass = 0;
        relu_en = 1;
        quant_shift = 0;
        
        // Input: -20. Result: -20. ReLU -> 0.
        // Input: 50. Result: 50. ReLU -> 50.
        // Input: 130. Result: 130. Clip -> 127.
        
        psum_in = 0;
        
        // Manually set channels
        psum_in[31:0] = -20;
        psum_in[63:32] = 50;
        psum_in[95:64] = 130;
        
        #10; // Input registered
        psum_in = 0; // Clear inputs
        
        #10; // Pipeline stage 1 -> Stage 2 (Output ready)
        
        print_results(result_out);
        check_result(0, 0, result_out);   // -20 -> 0
        check_result(1, 50, result_out);  // 50 -> 50
        check_result(2, 127, result_out); // 130 -> 127
        
        // -------------------------------------------------
        // Test Case 3: Quantization Shift
        // -------------------------------------------------
        $display("\n--- Test Case 3: Quantization (Shift=2) ---");
        // Shift right by 2 (divide by 4)
        quant_shift = 2;
        relu_en = 1;
        
        // Ch0: 100 >> 2 = 25
        // Ch1: -100 -> ReLU -> 0
        
        psum_in[31:0] = 100;
        psum_in[63:32] = -100;
        
        #10;
        psum_in = 0;
        
        #10;
        print_results(result_out);
        check_result(0, 25, result_out); // 100 >> 2 = 25
        check_result(1, 0, result_out);  // -100 -> 0

        $finish;
    end
      
endmodule
