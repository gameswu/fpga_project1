/**
 * Testbench for MAC Unit
 * 
 * Description:
 *   Validates the MAC unit functionality including:
 *   - Weight loading
 *   - Accumulation with signed INT8 inputs
 *   - Accumulator clear
 *   - Enable control
 *
 * Author: Auto-generated for fpga_project1
 * Date: 2025-11-24
 */

`timescale 1ns / 1ps
`include "mac.v"

module mac_tb;

    // =========================================================================
    // Testbench Signals
    // =========================================================================
    
    // Clock and Reset
    reg        clk;
    reg        rst_n;
    
    // Control Signals
    reg        enable;
    reg        acc_clear;
    reg        weight_load;
    
    // Data Inputs
    reg signed [7:0]  data_in;
    reg signed [7:0]  weight_in;
    
    // Data Output
    wire signed [31:0] acc_out;
    
    
    // =========================================================================
    // DUT Instantiation
    // =========================================================================
    
    mac dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .enable      (enable),
        .acc_clear   (acc_clear),
        .weight_load (weight_load),
        .data_in     (data_in),
        .weight_in   (weight_in),
        .acc_out     (acc_out)
    );
    
    
    // =========================================================================
    // Clock Generation (100 MHz -> 10ns period)
    // =========================================================================
    
    initial begin
        clk = 0;
        forever #5 clk = ~clk;  // 10ns period
    end
    
    
    // =========================================================================
    // Test Stimulus
    // =========================================================================
    
    initial begin
        // Initialize waveform dump
        $dumpfile("mac_tb.vcd");
        $dumpvars(0, mac_tb);
        
        // Print test header
        $display("========================================");
        $display("  MAC Unit Testbench");
        $display("========================================");
        
        // Initialize signals
        rst_n       = 0;
        enable      = 0;
        acc_clear   = 0;
        weight_load = 0;
        data_in     = 8'sd0;
        weight_in   = 8'sd0;
        
        // Reset sequence
        #20;
        rst_n = 1;
        #10;
        
        // =====================================================================
        // Test 1: Load weight and perform single MAC operation
        // =====================================================================
        $display("\n[TEST 1] Load weight = 3, compute 5 * 3");
        weight_in   = 8'sd3;
        weight_load = 1;
        #10;
        weight_load = 0;
        
        data_in = 8'sd5;
        enable  = 1;
        #10;
        $display("  Expected: 15, Got: %d", acc_out);
        if (acc_out == 32'sd15)
            $display("  [PASS]");
        else
            $display("  [FAIL]");
        
        // =====================================================================
        // Test 2: Accumulate multiple values
        // =====================================================================
        $display("\n[TEST 2] Accumulate: 15 + (10 * 3) = 45");
        data_in = 8'sd10;
        #10;
        $display("  Expected: 45, Got: %d", acc_out);
        if (acc_out == 32'sd45)
            $display("  [PASS]");
        else
            $display("  [FAIL]");
        
        $display("\n[TEST 3] Accumulate: 45 + (-7 * 3) = 24");
        data_in = -8'sd7;
        #10;
        $display("  Expected: 24, Got: %d", acc_out);
        if (acc_out == 32'sd24)
            $display("  [PASS]");
        else
            $display("  [FAIL]");
        
        // =====================================================================
        // Test 4: Clear accumulator
        // =====================================================================
        $display("\n[TEST 4] Clear accumulator");
        acc_clear = 1;
        #10;
        acc_clear = 0;
        $display("  Expected: 0, Got: %d", acc_out);
        if (acc_out == 32'sd0)
            $display("  [PASS]");
        else
            $display("  [FAIL]");
        
        // =====================================================================
        // Test 5: Negative weight
        // =====================================================================
        $display("\n[TEST 5] Load weight = -4, compute 8 * (-4)");
        weight_in   = -8'sd4;
        weight_load = 1;
        #10;
        weight_load = 0;
        
        data_in = 8'sd8;
        #10;
        $display("  Expected: -32, Got: %d", acc_out);
        if (acc_out == -32'sd32)
            $display("  [PASS]");
        else
            $display("  [FAIL]");
        
        // =====================================================================
        // Test 6: Enable control (disable MAC)
        // =====================================================================
        $display("\n[TEST 6] Disable enable signal (should hold)");
        enable  = 0;
        data_in = 8'sd100;  // Large value
        #10;
        $display("  Expected: -32 (unchanged), Got: %d", acc_out);
        if (acc_out == -32'sd32)
            $display("  [PASS]");
        else
            $display("  [FAIL]");
        
        // Re-enable
        enable = 1;
        #10;
        $display("  After re-enable: %d", acc_out);
        if (acc_out == -32'sd32 + (8'sd100 * (-8'sd4)))
            $display("  [PASS]");
        else
            $display("  [FAIL]");
        
        // =====================================================================
        // Test 7: Overflow handling (large accumulation)
        // =====================================================================
        $display("\n[TEST 7] Test INT32 accumulation (prevent overflow)");
        acc_clear = 1;
        #10;
        acc_clear = 0;
        
        weight_in   = 8'sd127;  // Max INT8
        weight_load = 1;
        #10;
        weight_load = 0;
        
        // Accumulate 1000 times: 1000 * (127 * 127) = 16,129,000
        data_in = 8'sd127;
        repeat (1000) begin
            #10;
        end
        $display("  Accumulated 1000x (127*127): %d", acc_out);
        $display("  Expected: 16129000, Got: %d", acc_out);
        if (acc_out == 32'd16129000)
            $display("  [PASS]");
        else
            $display("  [FAIL]");
        
        // =====================================================================
        // Test Complete
        // =====================================================================
        #50;
        $display("\n========================================");
        $display("  Test Complete");
        $display("========================================");
        $finish;
    end
    
    // Timeout watchdog
    initial begin
        #50000;
        $display("\n[ERROR] Testbench timeout!");
        $finish;
    end

endmodule
