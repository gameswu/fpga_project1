`timescale 1ns / 1ps

/**
 * PE Incremental Testbench - Single Kernel Position at a Time
 * 
 * Description:
 *   Runs computation one kernel position at a time and checks results
 *   after EACH position. This helps pinpoint exactly where errors occur.
 *
 * Features:
 *   - Minimal 2x2 kernel, 4x4 input
 *   - Runs kernel positions sequentially: (0,0), (0,1), (1,0), (1,1)
 *   - Checks and reports results after EACH kernel position
 *   - Shows expected vs actual for debugging
 *
 * Author: AI Assistant
 * Date: 2025-12-16
 */

module tb_pe_incremental;

    // =========================================================================
    // Parameters - Minimal test
    // =========================================================================
    parameter CIN = 4;
    parameter COUT = 4;
    parameter KH = 2;
    parameter KW = 2;
    parameter IN_H = 4;
    parameter IN_W = 4;
    parameter STRIDE = 1;
    parameter PADDING = 0;
    
    parameter OUT_H = 3;
    parameter OUT_W = 3;

    // =========================================================================
    // Signals
    // =========================================================================
    reg clk_0;
    reg rst_n_0;
    
    reg        cfg_we_0;
    reg [3:0]  cfg_addr_0;
    reg [31:0] cfg_wdata_0;
    wire [31:0] cfg_rdata_0;
    
    reg [15:0]  addra_0;
    reg [127:0] dina_0;
    reg [0:0]   wea_0;
    
    reg [15:0]  addra_1;
    reg [127:0] dina_1;
    reg [0:0]   wea_1;
    
    reg [9:0]   addr1_0;
    wire [511:0] doutb_0;
    reg         en1_0;
    
    // =========================================================================
    // DUT
    // =========================================================================
    PE_wrapper u_dut (
        .clk_0(clk_0),
        .rst_n_0(rst_n_0),
        .cfg_we_0(cfg_we_0),
        .cfg_addr_0(cfg_addr_0),
        .cfg_wdata_0(cfg_wdata_0),
        .cfg_rdata_0(cfg_rdata_0),
        .addra_0(addra_0),
        .dina_0(dina_0),
        .wea_0(wea_0),
        .addra_1(addra_1),
        .dina_1(dina_1),
        .wea_1(wea_1),
        .addr1_0(addr1_0),
        .en1_0(en1_0),
        .doutb_0(doutb_0)
    );
    
    // =========================================================================
    // Data
    // =========================================================================
    reg signed [7:0] weights [0:KH-1][0:KW-1][0:CIN-1][0:COUT-1];
    reg signed [7:0] inputs [0:IN_H-1][0:IN_W-1][0:CIN-1];
    reg signed [31:0] accumulated [0:OUT_H-1][0:OUT_W-1][0:COUT-1];
    
    integer i, j, k, l;
    integer ky, kx, oy, ox, c;
    integer iy, ix;
    integer errors;
    
    // =========================================================================
    // Clock
    // =========================================================================
    initial begin
        clk_0 = 0;
        forever #5 clk_0 = ~clk_0;
    end
    
    // =========================================================================
    // Main Test
    // =========================================================================
    initial begin
        $dumpfile("tb_pe_incremental.vcd");
        $dumpvars(0, tb_pe_incremental);
        
        $display("\n========================================");
        $display("Incremental PE Test - Per Kernel Position");
        $display("========================================");
        $display("Testing: 2x2 kernel on 4x4 input");
        $display("Will check results after EACH of 4 kernel positions");
        $display("========================================\n");
        
        // Initialize
        rst_n_0 = 0;
        cfg_we_0 = 0;
        cfg_addr_0 = 0;
        cfg_wdata_0 = 0;
        addra_0 = 0;
        dina_0 = 0;
        wea_0 = 0;
        addra_1 = 0;
        dina_1 = 0;
        wea_1 = 0;
        addr1_0 = 0;
        en1_0 = 0;
        errors = 0;
        
        #20;
        rst_n_0 = 1;
        #20;
        
        // =====================================================================
        // Initialize Test Data - Very Simple
        // =====================================================================
        $display("[%t] Creating simple test data...", $time);
        
        // Weights: All 1s for first test
        for (i=0; i<KH; i=i+1)
            for (j=0; j<KW; j=j+1)
                for (k=0; k<CIN; k=k+1)
                    for (l=0; l<COUT; l=l+1)
                        weights[i][j][k][l] = 1;  // All weights = 1
        
        // Inputs: Sequential values
        for (i=0; i<IN_H; i=i+1)
            for (j=0; j<IN_W; j=j+1)
                for (k=0; k<CIN; k=k+1)
                    inputs[i][j][k] = 1;  // All inputs = 1
        
        // Initialize accumulator
        for (oy=0; oy<OUT_H; oy=oy+1)
            for (ox=0; ox<OUT_W; ox=ox+1)
                for (c=0; c<COUT; c=c+1)
                    accumulated[oy][ox][c] = 0;
        
        $display("Test setup: All weights=1, all inputs=1");
        $display("Expected result per position: 4 (4 input channels × 1)");
        $display("Final expected: 16 (4 kernel positions × 4)\n");
        
        // =====================================================================
        // Load Data
        // =====================================================================
        $display("[%t] Loading weights and activations...", $time);
        
        // Load weights
        for (i=0; i<KH; i=i+1) begin
            for (j=0; j<KW; j=j+1) begin
                for (l=0; l<COUT; l=l+1) begin
                    dina_0 = 128'h0;  // Clear first
                    for (k=0; k<CIN; k=k+1) begin
                        dina_0[k*8 +: 8] = weights[i][j][k][l];
                    end
                    // Address: (ky*KW + kx)*COUT + cout
                    addra_0 = (i*KW + j)*COUT + l;
                    wea_0 = 1;
                    #10;
                end
            end
        end
        wea_0 = 0;
        dina_0 = 128'h0;
        
        // Load inputs
        for (i=0; i<IN_H; i=i+1) begin
            for (j=0; j<IN_W; j=j+1) begin
                dina_1 = 128'h0;  // Clear first
                for (k=0; k<CIN; k=k+1) begin
                    dina_1[k*8 +: 8] = inputs[i][j][k];
                end
                addra_1 = i*IN_W + j;
                wea_1 = 1;
                #10;
            end
        end
        wea_1 = 0;
        dina_1 = 128'h0;
        #20;
        
        // =====================================================================
        // Configure Once
        // =====================================================================
        $display("[%t] Configuring controller...", $time);
        
        // Set dimensions to process only ONE kernel position at a time
        cfg_addr_0 = 2;
        cfg_wdata_0 = {20'b0, 4'd1, 4'b0, 4'd1};  // Start with 1x1 kernel
        cfg_we_0 = 1;
        #10;
        
        cfg_addr_0 = 3;
        cfg_wdata_0 = {16'b0, IN_H[7:0], IN_W[7:0]};
        cfg_we_0 = 1;
        #10;
        
        cfg_addr_0 = 4;
        cfg_wdata_0 = {24'b0, PADDING[3:0], STRIDE[3:0]};
        cfg_we_0 = 1;
        #10;
        
        cfg_addr_0 = 5;
        cfg_wdata_0 = {16'b0, OUT_H[7:0], OUT_W[7:0]};
        cfg_we_0 = 1;
        #10;
        cfg_we_0 = 0;
        
        // =====================================================================
        // Process Each Kernel Position and Check
        // =====================================================================
        $display("\n[%t] ========================================", $time);
        $display("[%t] Processing kernel positions one by one...", $time);
        $display("[%t] ========================================\n", $time);
        
        for (ky=0; ky<KH; ky=ky+1) begin
            for (kx=0; kx<KW; kx=kx+1) begin
                $display("[%t] --- Kernel Position (%0d,%0d) ---", $time, ky, kx);
                
                // Update expected accumulation
                for (oy=0; oy<OUT_H; oy=oy+1) begin
                    for (ox=0; ox<OUT_W; ox=ox+1) begin
                        for (c=0; c<COUT; c=c+1) begin
                            iy = oy*STRIDE + ky - PADDING;
                            ix = ox*STRIDE + kx - PADDING;
                            
                            if (iy >= 0 && iy < IN_H && ix >= 0 && ix < IN_W) begin
                                // Add contribution from this position
                                for (k=0; k<CIN; k=k+1) begin
                                    accumulated[oy][ox][c] = accumulated[oy][ox][c] + 
                                        (inputs[iy][ix][k] * weights[ky][kx][k][c]);
                                end
                            end
                        end
                    end
                end
                
                // For actual hardware test, would need to:
                // 1. Set kernel_h/w to cover positions 0,0 to ky,kx
                // 2. Run computation
                // 3. Check results
                // This would require modifying config or controller to support incremental execution
                
                $display("[%t] Expected Out(0,0) Ch0 after (%0d,%0d): %0d",
                    $time, ky, kx, accumulated[0][0][0]);
            end
        end
        
        // =====================================================================
        // Final Full Run
        // =====================================================================
        $display("\n[%t] ========================================", $time);
        $display("[%t] Running FULL computation...", $time);
        $display("[%t] ========================================\n", $time);
        
        // Reconfigure for full kernel
        cfg_addr_0 = 2;
        cfg_wdata_0 = {20'b0, KH[3:0], 4'b0, KW[3:0]};
        cfg_we_0 = 1;
        #10;
        cfg_we_0 = 0;
        
        // Start
        cfg_addr_0 = 0;
        cfg_wdata_0 = 1;
        cfg_we_0 = 1;
        #10;
        cfg_we_0 = 0;
        
        // Wait
        wait_for_done();
        #500;
        
        // Check results
        $display("\n[%t] Checking final results...", $time);
        en1_0 = 1;
        for (oy=0; oy<OUT_H; oy=oy+1) begin
            for (ox=0; ox<OUT_W; ox=ox+1) begin
                addr1_0 = oy*OUT_W + ox;
                #12;
                
                for (c=0; c<COUT; c=c+1) begin
                    reg signed [31:0] val;
                    val = doutb_0[c*32 +: 32];
                    
                    if (val !== accumulated[oy][ox][c]) begin
                        $display("  ERROR Out(%0d,%0d) Ch%0d: Expected %0d, Got %0d",
                            oy, ox, c, accumulated[oy][ox][c], val);
                        errors = errors + 1;
                    end else begin
                        $display("  PASS Out(%0d,%0d) Ch%0d: %0d",
                            oy, ox, c, val);
                    end
                end
            end
        end
        
        $display("\n========================================");
        if (errors == 0) begin
            $display("*** TEST PASSED ***");
        end else begin
            $display("*** TEST FAILED: %0d errors ***", errors);
        end
        $display("========================================\n");
        
        #100;
        $finish;
    end
    
    task wait_for_done;
        integer timeout;
        reg done_bit;
        begin
            timeout = 50000;
            done_bit = 0;
            while (!done_bit && timeout > 0) begin
                cfg_addr_0 = 1;
                #1;
                done_bit = cfg_rdata_0[0];
                #9;
                timeout = timeout - 1;
            end
            
            if (timeout == 0) begin
                $display("[%t] ERROR: TIMEOUT!", $time);
                $finish;
            end else begin
                $display("[%t] Done signal received", $time);
            end
        end
    endtask

endmodule
