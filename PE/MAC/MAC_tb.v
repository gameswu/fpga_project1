`timescale 1ns / 1ps

module MAC_tb;

    // Parameters
    parameter DATA_WIDTH = 8;
    parameter ACC_WIDTH = 32;

    // Inputs
    reg clk;
    reg rst_n;
    reg en;
    reg weight_we;
    reg signed [DATA_WIDTH-1:0] weight_in;
    reg signed [DATA_WIDTH-1:0] feature_in;
    reg signed [ACC_WIDTH-1:0] psum_in;
    reg mode_max;

    // Outputs
    wire signed [DATA_WIDTH-1:0] feature_out;
    wire signed [ACC_WIDTH-1:0] psum_out;

    // Instantiate the Unit Under Test (UUT)
    mac_unit #(
        .DATA_WIDTH(DATA_WIDTH),
        .ACC_WIDTH(ACC_WIDTH)
    ) uut (
        .clk(clk),
        .rst_n(rst_n),
        .en(en),
        .weight_we(weight_we),
        .weight_in(weight_in),
        .feature_in(feature_in),
        .psum_in(psum_in),
        .mode_max(mode_max),
        .feature_out(feature_out),
        .psum_out(psum_out)
    );

    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 100MHz
    end

    // Test Sequence
    initial begin
        // Initialize Inputs
        rst_n = 0;
        en = 0;
        weight_we = 0;
        weight_in = 0;
        feature_in = 0;
        psum_in = 0;
        mode_max = 0;

        // Wait for global reset
        #100;
        @(posedge clk);
        rst_n = 1; // Release reset
        
        // ------------------------------------------------------------
        // Test Case 1: Load Weight
        // ------------------------------------------------------------
        $display("Test Case 1: Loading Weight...");
        @(posedge clk);
        weight_we = 1;
        weight_in = 8'd5; // Weight = 5
        @(posedge clk);
        weight_we = 0;
        
        // ------------------------------------------------------------
        // Test Case 2: Perform MAC operation
        // ------------------------------------------------------------
        $display("Test Case 2: Running MAC Operations...");
        
        // Input 1: Feature = 2, Psum_in = 10
        // Expected: Psum_out = 2 * 5 + 10 = 20
        @(posedge clk);
        en = 1;
        feature_in = 8'd2;
        psum_in = 32'd10;
        
        // Input 2: Feature = 3, Psum_in = 20
        // Expected (next cycle): Psum_out = 3 * 5 + 20 = 35
        @(posedge clk);
        // Capture outputs BEFORE updating inputs for next cycle
        #1; 
        if (psum_out !== 32'd20) 
            $display("[FAIL] Time %t: Expected psum_out=20, got %d", $time, psum_out);
        else 
            $display("[PASS] Time %t: 2 * 5 + 10 = %d", $time, psum_out);
            
        if (feature_out !== 8'd2)
            $display("[FAIL] Time %t: Expected feature_out=2, got %d", $time, feature_out);
        else
            $display("[PASS] Time %t: feature_out passed through correctly", $time);

        // Now update inputs for next cycle
        feature_in = 8'd3;
        psum_in = 32'd20;

        // Check Result 2
        @(posedge clk);
        #1;
        if (psum_out !== 32'd35) 
            $display("[FAIL] Time %t: Expected psum_out=35, got %d", $time, psum_out);
        else 
            $display("[PASS] Time %t: 3 * 5 + 20 = %d", $time, psum_out);

        // Input 3: Feature = -2, Psum_in = 100
        // Expected (next cycle): Psum_out = (-2) * 5 + 100 = 90
        @(posedge clk);
        feature_in = -8'd2;
        psum_in = 32'd100;

        // Check Result 3
        @(posedge clk);
        #1;
        if (psum_out !== 32'd90) 
            $display("[FAIL] Time %t: Expected psum_out=90, got %d", $time, psum_out);
        else 
            $display("[PASS] Time %t: (-2) * 5 + 100 = %d", $time, psum_out);

        // ------------------------------------------------------------
        // Test Case 3: Max Pooling Mode
        // ------------------------------------------------------------
        $display("Test Case 3: Max Pooling Mode...");
        @(posedge clk);
        mode_max = 1;
        feature_in = 8'd50;
        psum_in = 32'd40;
        // Expected: max(50, 40) = 50
        
        @(posedge clk);
        #1;
        // Check result of max(50, 40)
        if (psum_out !== 32'd50)
            $display("[FAIL] Time %t: Expected psum_out=50 (Max), got %d", $time, psum_out);
        else
            $display("[PASS] Time %t: max(50, 40) = %d", $time, psum_out);
            
        // New inputs for Max Pool
        feature_in = 8'd20;
        psum_in = 32'd60;
        // Expected: max(20, 60) = 60
        
        @(posedge clk);
        #1;
        // Check result of max(20, 60)
        if (psum_out !== 32'd60)
            $display("[FAIL] Time %t: Expected psum_out=60 (Max), got %d", $time, psum_out);
        else
            $display("[PASS] Time %t: max(20, 60) = %d", $time, psum_out);

        // ------------------------------------------------------------
        // Test Case 4: Synchronous Reset
        // ------------------------------------------------------------
        $display("Test Case 4: Testing Synchronous Reset...");
        @(posedge clk);
        rst_n = 0; // Assert reset
        @(posedge clk); // Wait for clock edge (synchronous)
        #1;
        if (psum_out !== 0) 
            $display("[FAIL] Reset failed, psum_out = %d", psum_out);
        else 
            $display("[PASS] Reset successful");
        
        $display("--------------------------------");
        $display("Testbench completed.");
        $finish;
    end

endmodule

// ------------------------------------------------------------------
// Mock DSP Macro for Simulation
// ------------------------------------------------------------------
// 如果您还没有在 Vivado 中生成 IP，这个模块可以作为替代进行仿真。
// 如果 Vivado 项目中已经包含了 dsp_macro_0 IP，请注释掉或删除下面的代码，
// 否则可能会报 "Module redefined" 错误。
// ------------------------------------------------------------------
/*
module dsp_macro_0 (
    input CLK,
    input CE,
    input SCLR,
    input signed [17:0] A,
    input signed [17:0] B,
    input signed [47:0] C,
    output reg signed [47:0] P
);
    always @(posedge CLK) begin
        if (SCLR) begin
            P <= 0;
        end else if (CE) begin
            P <= (A * B) + C;
        end
    end
endmodule
*/
