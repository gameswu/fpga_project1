`timescale 1ns / 1ps

/**
 * PE Wrapper Testbench - Updated for Block Design with BRAM IPs
 * 
 * Description:
 *   Testbench for Vivado-generated PE_wrapper with external BRAM IPs.
 *   Wrapper port mapping:
 *   - addra_0, dina_0, wea_0: Weight Buffer write interface
 *   - addra_1, dina_1, wea_1: Activation Buffer write interface
 *   - addrb_0, doutb_0: Partial Sum Buffer read interface
 *
 * Author: Modified for BRAM-based design
 * Date: 2025-12-15
 */

module tb_pe_wrapper;

    // =========================================================================
    // Parameters - Small test case for quick verification
    // =========================================================================
    parameter CIN = 16;
    parameter COUT = 10;
    parameter KH = 3;
    parameter KW = 3;
    parameter IN_H = 8;
    parameter IN_W = 8;
    parameter STRIDE = 1;
    parameter PADDING = 1;
    
    parameter OUT_H = (IN_H + 2*PADDING - KH) / STRIDE + 1;
    parameter OUT_W = (IN_W + 2*PADDING - KW) / STRIDE + 1;

    // =========================================================================
    // Signals - Match Vivado wrapper port names
    // =========================================================================
    reg clk_0;
    reg rst_n_0;
    
    // Config Interface
    reg        cfg_we_0;
    reg [3:0]  cfg_addr_0;
    reg [31:0] cfg_wdata_0;
    wire [31:0] cfg_rdata_0;
    
    // Weight Buffer Write Interface (addra_0, dina_0, wea_0)
    reg [15:0]  addra_0;
    reg [127:0] dina_0;
    reg [0:0]   wea_0;
    
    // Activation Buffer Write Interface (addra_1, dina_1, wea_1)
    reg [15:0]  addra_1;
    reg [127:0] dina_1;
    reg [0:0]   wea_1;
    
    // Result Read Interface (addrb_0, doutb_0)
    reg [9:0]   addrb_0;
    wire [511:0] doutb_0;
    
    // =========================================================================
    // DUT Instantiation - Vivado Generated Wrapper
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
        .addrb_0(addrb_0),
        .doutb_0(doutb_0)
    );
    
    // =========================================================================
    // Data Storage for Test Vectors
    // =========================================================================
    reg signed [7:0] weights [0:KH-1][0:KW-1][0:CIN-1][0:COUT-1]·;
    reg signed [7:0] inputs [0:IN_H-1][0:IN_W-1][0:CIN-1];
    reg signed [31:0] golden_output [0:OUT_H-1][0:OUT_W-1][0:COUT-1];
    
    integer i, j, k, l, m, n;
    integer iy, ix;
    integer errors;
    
    // =========================================================================
    // Clock Generation - 100MHz
    // =========================================================================
    initial begin
        clk_0 = 0;
        forever #5 clk_0 = ~clk_0; // 10ns period = 100MHz
    end
    
    // =========================================================================
    // Test Sequence
    // =========================================================================
    initial begin
        // Waveform dump
        $dumpfile("tb_pe_wrapper.vcd");
        $dumpvars(0, tb_pe_wrapper);
        
        $display("========================================");
        $display("PE Wrapper Full Simulation");
        $display("Parameters: CIN=%0d COUT=%0d", CIN, COUT);
        $display("Kernel: %0dx%0d", KH, KW);
        $display("Input: %0dx%0d", IN_H, IN_W);
        $display("Output: %0dx%0d", OUT_H, OUT_W);
        $display("Stride=%0d Padding=%0d", STRIDE, PADDING);
        $display("========================================");
        
        // Initialize signals
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
        addrb_0 = 0;
        errors = 0;
        
        // Reset sequence
        #20;
        rst_n_0 = 1;
        #20;
        
        // =====================================================================
        // Step 1: Initialize Test Data (Random)
        // =====================================================================
        $display("[%t] Step 1: Initializing test data...", $time);
        for (i=0; i<KH; i=i+1)
            for (j=0; j<KW; j=j+1)
                for (k=0; k<CIN; k=k+1)
                    for (l=0; l<COUT; l=l+1)
                        weights[i][j][k][l] = $random % 5;
                        
        for (i=0; i<IN_H; i=i+1)
            for (j=0; j<IN_W; j=j+1)
                for (k=0; k<CIN; k=k+1)
                    inputs[i][j][k] = $random % 5;
        $display("[%t] Data initialization complete", $time);
        
        // =====================================================================
        // Step 2: Compute Golden Reference (Software Model)
        // =====================================================================
        $display("[%t] Step 2: Computing golden reference...", $time);
        for (i=0; i<OUT_H; i=i+1) begin
            for (j=0; j<OUT_W; j=j+1) begin
                for (l=0; l<COUT; l=l+1) begin
                    golden_output[i][j][l] = 0;
                    for (m=0; m<KH; m=m+1) begin
                        for (n=0; n<KW; n=n+1) begin
                            for (k=0; k<CIN; k=k+1) begin
                                iy = i*STRIDE + m - PADDING;
                                ix = j*STRIDE + n - PADDING;
                                
                                if (iy >= 0 && iy < IN_H && ix >= 0 && ix < IN_W) begin
                                    golden_output[i][j][l] = golden_output[i][j][l] + 
                                        (inputs[iy][ix][k] * weights[m][n][k][l]);
                                end
                            end
                        end
                    end
                end
            end
        end
        $display("[%t] Golden reference computed", $time);
        
        // =====================================================================
        // Step 3: Load Weights into Weight Buffer (via addra_0)
        // =====================================================================
        $display("[%t] Step 3: Loading weights...", $time);
        for (i=0; i<KH; i=i+1) begin
            for (j=0; j<KW; j=j+1) begin
                for (l=0; l<COUT; l=l+1) begin
                    // Pack all CIN weights (16 bytes) into one 128-bit word
                    for (k=0; k<CIN; k=k+1) begin
                        dina_0[k*8 +: 8] = weights[i][j][k][l];
                    end
                    // Address: (ky*KW + kx)*16 + output_channel
                    addra_0 = (i*KW + j)*16 + l;
                    wea_0 = 1;
                    #10;
                end
            end
        end
        wea_0 = 0;
        $display("[%t] Weight loading complete", $time);
        
        // =====================================================================
        // Step 4: Load Activations into Activation Buffer (via addra_1)
        // =====================================================================
        $display("[%t] Step 4: Loading activations...", $time);
        for (i=0; i<IN_H; i=i+1) begin
            for (j=0; j<IN_W; j=j+1) begin
                addra_1 = i*IN_W + j;
                for (k=0; k<CIN; k=k+1) begin
                    dina_1[k*8 +: 8] = inputs[i][j][k];
                end
                wea_1 = 1;
                #10;
            end
        end
        wea_1 = 0;
        $display("[%t] Activation loading complete", $time);
        
        // =====================================================================
        // Step 5: Configure PE Controller
        // =====================================================================
        $display("[%t] Step 5: Configuring PE controller...", $time);
        
        // Kernel Dimensions (Address 2)
        cfg_addr_0 = 2;
        cfg_wdata_0 = {20'b0, KH[3:0], 4'b0, KW[3:0]};
        cfg_we_0 = 1;
        #10;
        
        // Input Dimensions (Address 3)
        cfg_addr_0 = 3;
        cfg_wdata_0 = {16'b0, IN_H[7:0], IN_W[7:0]};
        cfg_we_0 = 1;
        #10;
        
        // Stride & Padding (Address 4)
        cfg_addr_0 = 4;
        cfg_wdata_0 = {24'b0, PADDING[3:0], STRIDE[3:0]};
        cfg_we_0 = 1;
        #10;
        
        // Output Dimensions (Address 5)
        cfg_addr_0 = 5;
        cfg_wdata_0 = {16'b0, OUT_H[7:0], OUT_W[7:0]};
        cfg_we_0 = 1;
        #10;
        cfg_we_0 = 0;
        $display("[%t] Configuration complete", $time);
        
        // =====================================================================
        // Step 6: Start Computation
        // =====================================================================
        $display("[%t] Step 6: Starting computation...", $time);
        cfg_addr_0 = 0; // Control register
        cfg_wdata_0 = 1; // Start bit
        cfg_we_0 = 1;
        #10;
        cfg_we_0 = 0;
        
        // Monitor computation status
        $display("[%t] Monitoring computation progress...", $time);
        begin : monitor_loop
            integer monitor_i;
            for (monitor_i = 0; monitor_i < 100; monitor_i = monitor_i + 1) begin
                cfg_addr_0 = 1; // Read status
                #10;
                if (cfg_rdata_0[0]) begin
                    $display("[%t] Computation done! Status=0x%h", $time, cfg_rdata_0);
                    disable monitor_loop;
                end
            end
        end
        
        // =====================================================================
        // Step 7: Wait for Done
        // =====================================================================
        $display("[%t] Step 7: Waiting for completion...", $time);
        wait_for_done();
        $display("[%t] Computation complete!", $time);
        
        // IMPORTANT: Extra delay for BRAM write pipeline to flush
        #500;
        $display("[%t] Pipeline flush complete, starting readback...", $time);
        
        // =====================================================================
        // Step 8: Check Results
        // =====================================================================
        $display("[%t] Step 8: Checking results...", $time);
        check_results();
        
        // =====================================================================
        // Final Report
        // =====================================================================
        $display("========================================");
        if (errors == 0) begin
            $display("*** TEST PASSED ***");
            $display("All %0d output values matched!", OUT_H*OUT_W*COUT);
        end else begin
            $display("*** TEST FAILED ***");
            $display("Total errors: %0d", errors);
        end
        $display("========================================");
        
        #100;
        $finish;
    end
    
    // =========================================================================
    // Task: Wait for Done Signal
    // =========================================================================
    task wait_for_done;
        integer timeout;
        reg done_bit;
        begin
            timeout = 100000;
            done_bit = 0;
            while (!done_bit && timeout > 0) begin
                cfg_addr_0 = 1; // Status register
                #1; // Wait for combinational logic
                done_bit = cfg_rdata_0[0];
                #9; // Complete cycle
                timeout = timeout - 1;
                
                if (timeout % 1000 == 0) begin
                    $display("[%t] Still waiting... (timeout=%0d)", $time, timeout);
                end
            end
            
            if (timeout == 0) begin
                $display("[%t] ERROR: TIMEOUT waiting for done signal", $time);
                $finish;
            end
        end
    endtask
    
    // =========================================================================
    // Task: Check Results Against Golden Reference
    // =========================================================================
    task check_results;
        integer oy, ox, c;
        reg signed [31:0] val;
        integer checked;
        integer nonzero_count;
        begin
            checked = 0;
            nonzero_count = 0;
            for (oy=0; oy<OUT_H; oy=oy+1) begin
                for (ox=0; ox<OUT_W; ox=ox+1) begin
                    // Read from Psum Buffer via addrb_0
                    addrb_0 = oy*OUT_W + ox;
                    #10; // Wait for read
                    #2;  // Extra delay for BRAM output
                    
                    for (c=0; c<COUT; c=c+1) begin
                        val = doutb_0[c*32 +: 32];
                        checked = checked + 1;
                        
                        if (val != 0) nonzero_count = nonzero_count + 1;
                        
                        if (val !== golden_output[oy][ox][c]) begin
                            $display("[%t] ERROR at Out(%0d,%0d) Ch%0d: Expected %0d, Got %0d", 
                                $time, oy, ox, c, golden_output[oy][ox][c], val);
                            errors = errors + 1;
                        end else if (checked <= 10) begin
                            // Print first few matches for verification
                            $display("[%t] MATCH Out(%0d,%0d) Ch%0d: %0d", 
                                $time, oy, ox, c, val);
                        end
                    end
                end
            end
            $display("[%t] Checked %0d output values, %0d non-zero", $time, checked, nonzero_count);
            
            if (nonzero_count == 0) begin
                $display("\n*** CRITICAL ERROR: All outputs are ZERO ***");
                $display("Possible issues:");
                $display("  1. Missing psum_we_delay module - psum_acc_enable needs 2-cycle delay");
                $display("  2. BRAM Port A not connected to pe_top write signals");
                $display("  3. PE controller not executing (check cfg_rdata_0 for done bit)");
                $display("  4. Check Block Design connections for psum_buffer BRAM\n");
            end
        end
    endtask

endmodule
