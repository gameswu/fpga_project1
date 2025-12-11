`timescale 1ns / 1ps

/**
 * System Testbench for 16x16 Systolic Array Convolution
 * 
 * Description:
 *   Verifies the full system: Controller + PE Array + MACs.
 *   Performs a simple convolution operation.
 *   
 *   Scenario:
 *   - Input Image: 16x16 (Single Channel for simplicity of addressing)
 *   - Kernel: 1x1 (Simplest case to verify data flow)
 *   - Weights: All 1s.
 *   - Inputs: All 1s.
 *   - Expected Output: 16 (since dot product of 16 inputs * 1 weight is not what happens here).
 *     Wait, 16x16 array computes 16 output channels? Or 16 output pixels?
 *     
 *     Architecture Mapping:
 *     - Rows (0..15): Input Channels (Cin) or Kernel Rows.
 *     - Cols (0..15): Output Channels (Cout) or Output Pixels.
 *     
 *     Let's assume:
 *     - Rows = Input Channels (Cin = 16).
 *     - Cols = Output Channels (Cout = 16).
 *     - Input Vector: 16 values (one for each Cin).
 *     - Weight Matrix: 16x16 (Cin x Cout).
 *     - Output Vector: 16 values (one for each Cout).
 *     
 *     Operation:
 *     - Load 16x16 Weights.
 *     - Stream Input Vectors.
 *     - Each Input Vector produces an Output Vector (Dot Product).
 *     
 *     Test Case:
 *     - Weights[r][c] = 1 for all r,c.
 *     - Input[r] = 1 for all r.
 *     - Output[c] = Sum(Input[r] * Weight[r][c]) = Sum(1*1) over 16 rows = 16.
 *
 * Author: shealligh
 * Date: 2025-12-11
 */

module tb_system_16x16;

    // =========================================================================
    // Signals
    // =========================================================================
    reg clk;
    reg rst_n;
    reg start;
    wire done;
    
    // Configuration
    reg [3:0] kernel_h = 1;
    reg [3:0] kernel_w = 1;
    reg [7:0] input_h = 4; // Stream 4 vectors
    reg [7:0] input_w = 1; // 1D stream
    
    // Interconnects
    wire weight_we;
    wire [3:0] weight_row;
    wire [3:0] weight_col;
    wire [7:0] weight_data;
    wire [16*8-1:0] pe_data_in;
    
    wire acc_enable;
    wire acc_clear;
    wire [9:0] acc_addr;
    wire [16*32-1:0] pe_acc_out;
    
    wire [15:0] weight_mem_addr;
    reg [31:0] weight_mem_data;
    
    wire [15:0] input_mem_addr;
    reg [16*8-1:0] input_mem_data;
    
    // =========================================================================
    // Instantiations
    // =========================================================================
    
    pe_controller #(
        .ARRAY_DIM(16)
    ) u_controller (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .done(done),
        .kernel_h(kernel_h),
        .kernel_w(kernel_w),
        .input_h(input_h),
        .input_w(input_w),
        .weight_we(weight_we),
        .weight_row(weight_row),
        .weight_col(weight_col),
        .weight_data(weight_data),
        .pe_data_in(pe_data_in),
        .acc_enable(acc_enable),
        .acc_clear(acc_clear),
        .acc_addr(acc_addr),
        .pe_acc_out(pe_acc_out),
        .weight_mem_addr(weight_mem_addr),
        .weight_mem_data(weight_mem_data),
        .input_mem_addr(input_mem_addr),
        .input_mem_data(input_mem_data)
    );
    
    pe_array #(
        .ARRAY_DIM(16),
        .DATA_WIDTH(8),
        .ACC_WIDTH(32)
    ) u_array (
        .clk(clk),
        .rst_n(rst_n),
        .weight_we(weight_we),
        .weight_row(weight_row),
        .weight_col(weight_col),
        .weight_in(weight_data),
        .data_in(pe_data_in),
        .psum_out(pe_acc_out)
    );
    
    // =========================================================================
    // Memory Models
    // =========================================================================
    
    // Weight Memory (Always returns 1)
    always @(posedge clk) begin
        weight_mem_data <= 32'h00000001; // Just 1 in lower byte
    end
    
    // Input Memory (Ramp Pattern)
    // Addr 0 -> All 1s
    // Addr 1 -> All 2s
    // ...
    integer k;
    initial begin
        input_mem_data = 0; // Initialize to avoid X
    end
    always @(posedge clk) begin
        for (k=0; k<16; k=k+1) begin
            input_mem_data[k*8 +: 8] <= (input_mem_addr[7:0] + 1);
        end
    end
    
    // =========================================================================
    // Clock & Reset
    // =========================================================================
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    
    initial begin
        $dumpfile("tb_system_16x16.vcd");
        $dumpvars(0, tb_system_16x16);
        
        rst_n = 0;
        start = 0;
        #20;
        rst_n = 1;
        #20;
        
        $display("Starting 16x16 Systolic Test...");
        start = 1;
        #10;
        start = 0;
        
        // Wait for done
        wait(done);
        #100;
        
        $display("Test Completed.");
        $finish;
    end
    
    // =========================================================================
    // Result Monitor
    // =========================================================================
    
    reg [31:0] expected_val;
    reg [31:0] sample_cnt = 0;
    
    always @(posedge clk) begin
        if (acc_enable) begin
            sample_cnt <= sample_cnt + 1;
            expected_val = 16 * (sample_cnt + 1);
            
            $display("Time %t: Output Valid. Checking for %d...", $time, expected_val);
            
            for (k=0; k<16; k=k+1) begin
                if (pe_acc_out[k*32 +: 32] !== expected_val) begin
                    $display("  Col %d FAIL: Expected %d, Got %d", k, expected_val, $signed(pe_acc_out[k*32 +: 32]));
                end
            end
            if (pe_acc_out[0 +: 32] == expected_val) $display("  Sample Col 0 PASS: %d", expected_val);
        end
    end
    
    // Timeout
    initial begin
        #50000;
        $display("TIMEOUT");
        $finish;
    end

endmodule
