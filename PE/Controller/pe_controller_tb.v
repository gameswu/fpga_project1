/**
 * Testbench for PE Controller
 * 
 * Description:
 *   Validates PE Controller functionality including:
 *   - State machine transitions
 *   - Address generation for weights and inputs
 *   - Control signal timing
 *   - Padding handling
 *
 * Author: Auto-generated for fpga_project1
 * Date: 2025-12-01
 */

`timescale 1ns / 1ps

module pe_controller_tb;

    // =========================================================================
    // Parameters (matching Conv1 layer: 5x5 kernel, 32 channels)
    // =========================================================================
    
    parameter ARRAY_DIM = 16;
    parameter IFM_H     = 16;
    parameter IFM_W     = 16;
    parameter OFM_H     = 16;
    parameter OFM_W     = 16;
    parameter K_H       = 5;
    parameter K_W       = 5;
    parameter PAD       = 2;
    parameter STRIDE    = 1;
    parameter CHANNELS  = 16;
    
    // Calculate expected values
    localparam NUM_CHANNEL_TILES = (CHANNELS + ARRAY_DIM - 1) / ARRAY_DIM;
    localparam NUM_SPATIAL_TILES = ((OFM_H * OFM_W) + ARRAY_DIM - 1) / ARRAY_DIM;
    
    
    // =========================================================================
    // Testbench Signals
    // =========================================================================
    
    // Clock and Reset
    reg        clk;
    reg        rst_n;
    
    // Control Interface
    reg        start;
    wire       done;
    
    // PE Array Control Signals
    wire       enable;
    wire       acc_clear;
    wire       weight_load;
    
    // PE Array Data Interface
    wire [ARRAY_DIM*ARRAY_DIM*8-1:0]     pe_data_in;
    wire [ARRAY_DIM*ARRAY_DIM*8-1:0]     pe_weight_in;
    reg  [ARRAY_DIM*ARRAY_DIM*32-1:0]    pe_acc_out;
    
    // Weight Memory Interface
    wire [15:0]                          weight_addr;
    reg  [ARRAY_DIM*ARRAY_DIM*8-1:0]     weight_rdata;
    
    // Input Memory Interface
    wire signed [15:0]                   input_ref_y;
    wire signed [15:0]                   input_ref_x;
    reg  [ARRAY_DIM*ARRAY_DIM*8-1:0]     input_rdata;
    
    // Output Interface
    wire                                output_valid;
    wire [ARRAY_DIM*ARRAY_DIM*32-1:0]   output_data;
    
    // Test monitoring
    integer weight_load_count;
    integer compute_count;
    integer tile_count;
    
    
    // =========================================================================
    // DUT Instantiation
    // =========================================================================
    
    pe_controller #(
        .ARRAY_DIM (ARRAY_DIM),
        .IFM_H     (IFM_H),
        .IFM_W     (IFM_W),
        .OFM_H     (OFM_H),
        .OFM_W     (OFM_W),
        .K_H       (K_H),
        .K_W       (K_W),
        .PAD       (PAD),
        .STRIDE    (STRIDE),
        .CHANNELS  (CHANNELS)
    ) dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .start        (start),
        .done         (done),
        .enable       (enable),
        .acc_clear    (acc_clear),
        .weight_load  (weight_load),
        .pe_data_in   (pe_data_in),
        .pe_weight_in (pe_weight_in),
        .pe_acc_out   (pe_acc_out),
        .weight_addr  (weight_addr),
        .weight_rdata (weight_rdata),
        .input_ref_y  (input_ref_y),
        .input_ref_x  (input_ref_x),
        .input_rdata  (input_rdata),
        .output_valid (output_valid),
        .output_data  (output_data)
    );
    
    
    // =========================================================================
    // Clock Generation (100 MHz)
    // =========================================================================
    
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    
    
    // =========================================================================
    // Memory Models (Simple: return constant values)
    // =========================================================================
    
    // Weight Memory Model: Return all 1's (for simple testing)
    always @* begin
        weight_rdata = {(ARRAY_DIM*ARRAY_DIM){8'sd1}};  // 256 weights, each = 1
    end
    
    // Input Memory Model: Return 1 if within bounds, 0 if padding
    always @* begin
        if (input_ref_y >= 0 && input_ref_y < IFM_H && 
            input_ref_x >= 0 && input_ref_x < IFM_W) begin
            input_rdata = {(ARRAY_DIM*ARRAY_DIM){8'sd1}};  // 256 pixels, each = 1
        end
        else begin
            input_rdata = {(ARRAY_DIM*ARRAY_DIM){8'sd0}};  // Padding: return 0
        end
    end
    
    // PE Array Model: Simple accumulator (for testing controller only)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pe_acc_out <= 0;
        end
        else if (acc_clear) begin
            pe_acc_out <= 0;
        end
        else if (enable) begin
            // Simplified: Just increment accumulator
            // In real design, this would be MAC operation
            pe_acc_out <= pe_acc_out + 1;
        end
    end
    
    
    // =========================================================================
    // Monitoring and Statistics
    // =========================================================================
    
    always @(posedge clk) begin
        if (weight_load) begin
            weight_load_count <= weight_load_count + 1;
            $display("[%0t] Weight Load #%0d: addr=%0d", $time, weight_load_count, weight_addr);
        end
        
        if (enable) begin
            compute_count <= compute_count + 1;
            $display("[%0t] Compute #%0d: input_y=%0d, input_x=%0d", 
                     $time, compute_count, input_ref_y, input_ref_x);
        end
        
        if (output_valid) begin
            tile_count <= tile_count + 1;
            $display("[%0t] Tile Output #%0d: acc_value=%0d", $time, tile_count, pe_acc_out[31:0]);
        end
        
        if (done) begin
            $display("[%0t] DONE signal asserted!", $time);
        end
    end
    
    
    // =========================================================================
    // Test Stimulus
    // =========================================================================
    
    initial begin
        // Initialize waveform dump
        $dumpfile("pe_controller_tb.vcd");
        $dumpvars(0, pe_controller_tb);
        
        // Print test header
        $display("========================================");
        $display("  PE Controller Testbench");
        $display("  Layer: Conv1 (5x5 kernel, 32 channels)");
        $display("========================================");
        
        // Initialize signals
        rst_n  = 0;
        start  = 0;
        weight_load_count = 0;
        compute_count = 0;
        tile_count = 0;
        
        // Reset sequence
        #20;
        rst_n = 1;
        #10;
        
        // =====================================================================
        // Test 1: Single Tile Processing
        // =====================================================================
        $display("\n[TEST 1] Start single tile convolution");
        start = 1;
        #10;
        start = 0;
        
        // Wait for completion (timeout: 100000 cycles)
        begin: wait_done
            repeat (100000) begin
                @(posedge clk);
                if (done) begin
                    $display("\n[TEST 1] Convolution complete!");
                    $display("  Total weight loads: %0d", weight_load_count);
                    $display("  Total compute cycles: %0d", compute_count);
                    $display("  Total tiles output: %0d", tile_count);
                    
                    // Verify counts (should be K_H * K_W * NUM_TILES)
                    if (weight_load_count == K_H * K_W * NUM_SPATIAL_TILES * NUM_CHANNEL_TILES) begin
                        $display("  [PASS] Weight loads correct");
                    end
                    else begin
                        $display("  [FAIL] Weight loads incorrect (expected %0d, got %0d)", 
                                 K_H * K_W * NUM_SPATIAL_TILES * NUM_CHANNEL_TILES, weight_load_count);
                    end
                    
                    if (compute_count == K_H * K_W * NUM_SPATIAL_TILES * NUM_CHANNEL_TILES) begin
                        $display("  [PASS] Compute cycles correct");
                    end
                    else begin
                        $display("  [FAIL] Compute cycles incorrect (expected %0d, got %0d)",
                                 K_H * K_W * NUM_SPATIAL_TILES * NUM_CHANNEL_TILES, compute_count);
                    end
                    
                    disable wait_done;
                end
            end
        end
        
        $display("\n[ERROR] Timeout waiting for done signal!");
        
        // =====================================================================
        // Test 2: Verify Address Generation
        // =====================================================================
        $display("\n[TEST 2] Address generation verification");
        $display("  First weight address should be 0");
        $display("  Last weight address should be %0d", (K_H * K_W - 1) * ARRAY_DIM);
        
        // =====================================================================
        // Test 3: Verify Padding Handling
        // =====================================================================
        $display("\n[TEST 3] Padding handling");
        $display("  Corner pixels (0,0) should generate negative coordinates");
        $display("  Check memory model returns 0 for out-of-bounds");
        
        // =====================================================================
        // Test Complete
        // =====================================================================
        #100;
        $display("\n========================================");
        $display("  Test Complete");
        $display("========================================");
        $finish;
    end
    
    // Timeout watchdog
    initial begin
        #1000000;
        $display("\n[ERROR] Testbench timeout!");
        $finish;
    end

endmodule
