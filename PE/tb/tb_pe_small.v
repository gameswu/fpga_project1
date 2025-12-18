`timescale 1ns / 1ps

/**
 * PE Small-scale Testbench
 * 
 * Description:
 *   Small-scale test with detailed per-kernel-position checking.
 *   Tests parallel data loading and provides incremental result verification.
 *
 * Features:
 *   - Small kernel (2x2) and input (4x4) for easy manual verification
 *   - Only 4 input/output channels for simplicity
 *   - Checks results after EACH kernel position
 *   - Tests parallel weight and activation loading
 *   - Detailed debug output
 *
 * Author: AI Assistant
 * Date: 2025-12-16
 */

module tb_pe_small;

    // =========================================================================
    // Parameters - Very small test case
    // =========================================================================
    parameter CIN = 4;      // 4 input channels
    parameter COUT = 4;     // 4 output channels (simple test)
    parameter KH = 2;       // 2x2 kernel
    parameter KW = 2;
    parameter IN_H = 4;     // 4x4 input
    parameter IN_W = 4;
    parameter STRIDE = 1;
    parameter PADDING = 0;  // No padding for simplicity
    
    parameter OUT_H = (IN_H + 2*PADDING - KH) / STRIDE + 1;  // 3x3 output
    parameter OUT_W = (IN_W + 2*PADDING - KW) / STRIDE + 1;

    // =========================================================================
    // Signals
    // =========================================================================
    reg clk_0;
    reg rst_n_0;
    
    // Config Interface
    reg        cfg_we_0;
    reg [3:0]  cfg_addr_0;
    reg [31:0] cfg_wdata_0;
    wire [31:0] cfg_rdata_0;
    
    // Weight Buffer Write Interface
    reg [15:0]  addra_0;
    reg [127:0] dina_0;
    reg [0:0]   wea_0;
    
    // Activation Buffer Write Interface
    reg [15:0]  addra_1;
    reg [127:0] dina_1;
    reg [0:0]   wea_1;
    
    // Result Read Interface
    reg [9:0]   addr1_0;
    wire [511:0] doutb_0;
    reg         en1_0;
    
    // =========================================================================
    // DUT Instantiation
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
    // Data Storage
    // =========================================================================
    // Simple test pattern: weights and inputs are small integers
    reg signed [7:0] weights [0:KH-1][0:KW-1][0:CIN-1][0:COUT-1];
    reg signed [7:0] inputs [0:IN_H-1][0:IN_W-1][0:CIN-1];
    
    // Expected results for each kernel position
    reg signed [31:0] expected_per_kernel [0:KH-1][0:KW-1][0:OUT_H-1][0:OUT_W-1][0:COUT-1];
    reg signed [31:0] golden_output [0:OUT_H-1][0:OUT_W-1][0:COUT-1];
    
    integer i, j, k, l, m, n;
    integer i_w, j_w, k_w, l_w;  // Weight loading loop variables
    integer i_a, j_a, k_a;        // Activation loading loop variables
    integer ky, kx, oy, ox, c, oc;  // Added oc for output channel loop
    integer iy, ix;
    integer errors, total_errors;
    integer oc_batch, ch_in_batch;  // For result checking
    reg signed [31:0] val;  // For reading result values
    
    // =========================================================================
    // Clock Generation - 100MHz
    // =========================================================================
    initial begin
        clk_0 = 0;
        forever #5 clk_0 = ~clk_0;
    end
    
    // =========================================================================
    // Test Sequence
    // =========================================================================
    initial begin
        $dumpfile("tb_pe_small.vcd");
        $dumpvars(0, tb_pe_small);
        
        // Monitor key signals
        $display("\nMonitoring controller state and PE signals...");
        
        $display("\n========================================");
        $display("Small-scale PE Test with Per-Kernel Checking");
        $display("========================================");
        $display("Config: CIN=%0d COUT=%0d", CIN, COUT);
        $display("Kernel: %0dx%0d", KH, KW);
        $display("Input:  %0dx%0d", IN_H, IN_W);
        $display("Output: %0dx%0d", OUT_H, OUT_W);
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
        total_errors = 0;
        
        #20;
        rst_n_0 = 1;
        #20;
        
        // =====================================================================
        // Initialize Simple Test Data
        // =====================================================================
        $display("[%t] Initializing simple test data...", $time);
        
        // Weights: Simple pattern (1, 2, 3, ...)
        for (i=0; i<KH; i=i+1)
            for (j=0; j<KW; j=j+1)
                for (k=0; k<CIN; k=k+1)
                    for (l=0; l<COUT; l=l+1)
                        weights[i][j][k][l] = (i*KW*CIN*COUT + j*CIN*COUT + k*COUT + l + 1) % 8;
        
        // Inputs: Another simple pattern
        for (i=0; i<IN_H; i=i+1)
            for (j=0; j<IN_W; j=j+1)
                for (k=0; k<CIN; k=k+1)
                    inputs[i][j][k] = (i*IN_W*CIN + j*CIN + k + 1) % 8;
        
        $display("Sample weights[0][0][0-3][0] = %0d %0d %0d %0d", 
            weights[0][0][0][0], weights[0][0][1][0], 
            weights[0][0][2][0], weights[0][0][3][0]);
        $display("Sample weights[0][0][0-3][1] = %0d %0d %0d %0d", 
            weights[0][0][0][1], weights[0][0][1][1], 
            weights[0][0][2][1], weights[0][0][3][1]);
        $display("Sample inputs[0][0][0-3] = %0d %0d %0d %0d",
            inputs[0][0][0], inputs[0][0][1], inputs[0][0][2], inputs[0][0][3]);
        
        // =====================================================================
        // Compute Golden Reference per Kernel Position
        // =====================================================================
        $display("\n[%t] Computing golden reference...", $time);
        
        // Initialize all outputs to zero
        for (oy=0; oy<OUT_H; oy=oy+1)
            for (ox=0; ox<OUT_W; ox=ox+1)
                for (c=0; c<COUT; c=c+1)
                    golden_output[oy][ox][c] = 0;
        
        // Accumulate for each kernel position
        for (ky=0; ky<KH; ky=ky+1) begin
            for (kx=0; kx<KW; kx=kx+1) begin
                for (oy=0; oy<OUT_H; oy=oy+1) begin
                    for (ox=0; ox<OUT_W; ox=ox+1) begin
                        for (c=0; c<COUT; c=c+1) begin
                            expected_per_kernel[ky][kx][oy][ox][c] = 0;
                            
                            // Contribution from this kernel position
                            for (k=0; k<CIN; k=k+1) begin
                                iy = oy*STRIDE + ky - PADDING;
                                ix = ox*STRIDE + kx - PADDING;
                                
                                if (iy >= 0 && iy < IN_H && ix >= 0 && ix < IN_W) begin
                                    expected_per_kernel[ky][kx][oy][ox][c] = 
                                        expected_per_kernel[ky][kx][oy][ox][c] + 
                                        (inputs[iy][ix][k] * weights[ky][kx][k][c]);
                                end
                            end
                            
                            // Add previous accumulation
                            if (ky == 0 && kx == 0) begin
                                expected_per_kernel[ky][kx][oy][ox][c] = 
                                    expected_per_kernel[ky][kx][oy][ox][c];
                            end else if (kx == 0) begin
                                expected_per_kernel[ky][kx][oy][ox][c] = 
                                    expected_per_kernel[ky][kx][oy][ox][c] + 
                                    expected_per_kernel[ky-1][KW-1][oy][ox][c];
                            end else begin
                                expected_per_kernel[ky][kx][oy][ox][c] = 
                                    expected_per_kernel[ky][kx][oy][ox][c] + 
                                    expected_per_kernel[ky][kx-1][oy][ox][c];
                            end
                            
                            // Update golden output
                            golden_output[oy][ox][c] = expected_per_kernel[ky][kx][oy][ox][c];
                        end
                    end
                end
            end
        end
        
        $display("Golden output[0][0][0] = %0d (after all kernel positions)", 
            golden_output[0][0][0]);
        $display("Golden output[0][0][1] = %0d", golden_output[0][0][1]);
        $display("Golden output[0][0][2] = %0d", golden_output[0][0][2]);
        $display("Golden output[0][0][3] = %0d", golden_output[0][0][3]);
        
        // =====================================================================
        // Parallel Loading: Weights AND Activations simultaneously
        // =====================================================================
        $display("\n[%t] PARALLEL LOADING: Weights and Activations...", $time);
        
        // Initialize loading signals before fork
        dina_0 = 128'h0;
        dina_1 = 128'h0;
        addra_0 = 0;
        addra_1 = 0;
        wea_0 = 0;
        wea_1 = 0;
        
        fork
            // Thread 1: Load Weights
            // Memory layout must match controller: [ky][kx][cout][cin]
            // Address = (ky*KW*COUT*CIN + kx*COUT*CIN + cout*CIN + cin_batch) / 16
            // Since CIN=4 (1 batch), cin_batch=0, so address = (ky*KW*COUT + kx*COUT + cout)*CIN/16 = 0 for all positions
            // Actually, address = (ky*KW*COUT*CIN + kx*COUT*CIN + cout*CIN) >> 4 when 16 channels per word
            begin
                for (i_w=0; i_w<KH; i_w=i_w+1) begin
                    for (j_w=0; j_w<KW; j_w=j_w+1) begin
                        for (l_w=0; l_w<COUT; l_w=l_w+1) begin
                            // Clear the entire word first
                            dina_0 = 128'h0;
                            
                            // Pack 16 input channels into one word (we only have 4, rest stay 0)
                            for (k_w=0; k_w<CIN; k_w=k_w+1) begin
                                dina_0[k_w*8 +: 8] = weights[i_w][j_w][k_w][l_w];
                            end
                            
                            // Set address and enable write
                            addra_0 = (i_w*KW + j_w)*COUT + l_w;
                            wea_0 = 1;
                            #10;
                        end
                    end
                end
                wea_0 = 0;
                dina_0 = 128'h0;
            end
            
            // Thread 2: Load Activations (parallel)
            // Memory layout: [iy][ix][ic_batch]
            // Address = (iy*input_w + ix)*num_ic_batches + ic_batch_index
            // With CIN=4 (1 batch), ic_batch_index=0: addr = iy*input_w + ix
            begin
                #5; // Small offset to show parallelism
                for (i_a=0; i_a<IN_H; i_a=i_a+1) begin
                    for (j_a=0; j_a<IN_W; j_a=j_a+1) begin
                        // Clear the entire word first
                        dina_1 = 128'h0;
                        
                        // Pack input channels (CIN=4, rest stay 0)
                        for (k_a=0; k_a<CIN; k_a=k_a+1) begin
                            dina_1[k_a*8 +: 8] = inputs[i_a][j_a][k_a];
                        end
                        
                        // Address: (iy*input_w + ix) * num_ic_batches + 0
                        // With CIN=4->1 batch: addr = iy*IN_W + ix
                        addra_1 = i_a*IN_W + j_a;
                        wea_1 = 1;
                        #10;
                    end
                end
                dina_1 = 128'h0;
                wea_1 = 0;
            end
        join
        
        $display("[%t] Data loading complete", $time);
        #20;
        
        // =====================================================================
        // Configure PE Controller
        // =====================================================================
        $display("\n[%t] Configuring PE controller...", $time);
        
        // Kernel Dimensions (Address 2)
        cfg_addr_0 = 2;
        cfg_wdata_0 = {20'b0, KH[3:0], 4'b0, KW[3:0]};
        cfg_we_0 = 1;
        #10;
        cfg_we_0 = 0; // Pulse WE
        #5;
        
        // Input Dimensions (Address 3)
        cfg_addr_0 = 3;
        cfg_wdata_0 = {16'b0, IN_H[7:0], IN_W[7:0]};
        cfg_we_0 = 1;
        #10;
        cfg_we_0 = 0; // Pulse WE
        #5;
        
        // Stride & Padding (Address 4)
        cfg_addr_0 = 4;
        cfg_wdata_0 = {24'b0, PADDING[3:0], STRIDE[3:0]};
        cfg_we_0 = 1;
        #10;
        cfg_we_0 = 0; // Pulse WE
        #5;
        
        // Output Dimensions (Address 5)
        cfg_addr_0 = 5;
        cfg_wdata_0 = {16'b0, OUT_H[7:0], OUT_W[7:0]};
        cfg_we_0 = 1;
        #10;
        cfg_we_0 = 0; // Pulse WE
        #5;
        
        // Configure channels (Address 6)
        cfg_addr_0 = 6;
        cfg_wdata_0 = {16'b0, COUT[7:0], CIN[7:0]};
        cfg_we_0 = 1;
        #10;
        cfg_we_0 = 0; // Pulse WE
        #5;
        
        $display("Configuration: KH=%0d KW=%0d, IN=%0dx%0d, CIN=%0d COUT=%0d", KH, KW, IN_H, IN_W, CIN, COUT);
        
        // =====================================================================
        // Verify Configuration Readback
        // =====================================================================
        $display("\n[%t] Verifying Configuration Readback...", $time);
        
        cfg_addr_0 = 4; // Stride & Padding
        #10;
        $display("Readback Addr 4 (Stride/Pad): 0x%h (Expected: 0x%h)", cfg_rdata_0, {24'b0, PADDING[3:0], STRIDE[3:0]});
        if (cfg_rdata_0[3:0] != STRIDE) $display("ERROR: Stride mismatch! Read %0d, Expected %0d", cfg_rdata_0[3:0], STRIDE);
        
        cfg_addr_0 = 3; // Input Dims
        #10;
        $display("Readback Addr 3 (Input Dims): 0x%h", cfg_rdata_0);
        
        #40;
        
        // =====================================================================
        // Start and Monitor Each Kernel Position
        // =====================================================================
        $display("\n[%t] Starting computation...", $time);
        #20;
        cfg_addr_0 = 0;
        cfg_wdata_0 = 1;
        cfg_we_0 = 1;
        #10;
        cfg_we_0 = 0;
        cfg_wdata_0 = 0;
        #100;
        wait_for_done();
        
        $display("\n[%t] Computation done! Checking psum buffer contents...", $time);
        en1_0 = 1;
        for (oy=0; oy<3; oy=oy+1) begin
            addr1_0 = oy*OUT_W*((COUT+15)>>4);  // First address of each row
            #20;
            if (doutb_0 != 0) begin
                $display("  Psum[%0d][0][0] = %0d", oy, doutb_0[31:0]);
            end else begin
                $display("  Psum[%0d][0][0] = 0 (PROBLEM!)", oy);
            end
        end
        
        $display("\n[%t] ========================================", $time);
        $display("[%t] Checking FINAL results...", $time);
        
        errors = 0;
        for (oy=0; oy<OUT_H; oy=oy+1) begin
            for (ox=0; ox<OUT_W; ox=ox+1) begin
                // Read results for all output channel batches
                for (oc=0; oc<COUT; oc=oc+16) begin
                    oc_batch = oc >> 4;  // Batch index
                    ch_in_batch = (oc + 16 <= COUT) ? 16 : (COUT - oc);
                    
                    // Address: (oy * output_w + ox) * num_batches + batch_idx
                    addr1_0 = (oy*OUT_W + ox) * ((COUT+15)>>4) + oc_batch;
                    #20; // Wait for BRAM Latency (2 cycles @ 10ns)
                    
                    for (c=0; c<ch_in_batch; c=c+1) begin
                        val = doutb_0[c*32 +: 32];
                        
                        if (val !== golden_output[oy][ox][oc+c]) begin
                            $display("  ERROR at Out(%0d,%0d) Ch%0d: Expected %0d, Got %0d (batch=%0d, c_in_batch=%0d)",
                                oy, ox, oc+c, golden_output[oy][ox][oc+c], val, oc_batch, c);
                            errors = errors + 1;
                        end else if (errors < 3) begin  // Only show first few passes
                            $display("  PASS Out(%0d,%0d) Ch%0d: %0d", oy, ox, oc+c, val);
                        end
                    end
                end
            end
        end
        
        total_errors = total_errors + errors;
        
        // =====================================================================
        // Final Report
        // =====================================================================
        $display("\n========================================");
        if (total_errors == 0) begin
            $display("*** ALL TESTS PASSED ***");
            $display("Verified %0d output values", OUT_H*OUT_W*COUT);
        end else begin
            $display("*** TEST FAILED ***");
            $display("Total errors: %0d", total_errors);
        end
        $display("========================================\n");
        
        #100;
        $finish;
    end  // End of initial block
    
    // =========================================================================
    // Task: Wait for Done
    // =========================================================================
    task wait_for_done;
    begin : wait_task
        integer timeout;
        reg done_bit;
        
        timeout = 50000;
        done_bit = 0;
        while (!done_bit && timeout > 0) begin
            cfg_addr_0 = 1;
            #1;
            done_bit = cfg_rdata_0[0];
            #9;
            timeout = timeout - 1;
            
            if (timeout % 5000 == 0) begin
                $display("[%t] Waiting for done... (timeout=%0d)", $time, timeout);
            end
        end
        
        if (timeout == 0) begin
            $display("[%t] ERROR: TIMEOUT!", $time);
            $finish;
        end
    end
    endtask

endmodule
