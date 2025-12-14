`timescale 1ns / 1ps

/**
 * Advanced Convolution Testbench
 * 
 * Description:
 *   Verifies the 16x16 Systolic Array performing a real 2D Convolution.
 *   
 *   Features:
 *   - Customizable Kernel Size (Kh, Kw).
 *   - Customizable Input Size (H, W).
 *   - Customizable Channels (Cin=16, Cout=16 fixed by hardware).
 *   - Automatic Golden Reference Calculation.
 *   - Random Data Initialization.
 *
 * Author: shealligh
 * Date: 2025-12-11
 */

module tb_conv_16x16;

    // =========================================================================
    // Parameters
    // =========================================================================
    parameter CIN = 10;
    parameter COUT = 10;
    parameter KH = 3;
    parameter KW = 3;
    parameter IN_H = 8;
    parameter IN_W = 8;
    
    // Output Dimensions (Valid Convolution)
    parameter OUT_H = IN_H - KH + 1;
    parameter OUT_W = IN_W - KW + 1;

    // =========================================================================
    // Signals
    // =========================================================================
    reg clk;
    reg rst_n;
    reg start;
    wire done;
    
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
    wire [31:0] weight_mem_data_wire;
    
    wire [15:0] input_mem_addr;
    wire [16*8-1:0] input_mem_data_wire;
    
    // =========================================================================
    // Data Storage (Testbench Memory)
    // =========================================================================
    
    // Weights: [Kh][Kw][Cout][Cin]
    // Flattened for memory: Addr = (ky*KW + kx)*256 + cout*16 + cin
    // But our controller uses: (ky*KW + kx)*256 + wr*16 + wc
    // Where wr=Cin, wc=Cout? Or wr=Row(Cin), wc=Col(Cout).
    // Let's assume Row=Cin, Col=Cout.
    reg signed [7:0] weights [0:KH-1][0:KW-1][0:CIN-1][0:COUT-1];
    
    // Inputs: [H][W][Cin]
    // Memory: Addr = y*W + x. Data = Vector of Cin bytes.
    reg signed [7:0] inputs [0:IN_H-1][0:IN_W-1][0:CIN-1];
    
    // Golden Output: [OutH][OutW][Cout]
    reg signed [31:0] golden_output [0:OUT_H-1][0:OUT_W-1][0:COUT-1];
    
    // =========================================================================
    // Memory Models
    // =========================================================================
    
    // Weight Memory Read
    reg [31:0] r_weight_data;
    integer block, offset, k_idx, wr_idx, wc_idx, ky_idx, kx_idx;
    
    always @(posedge clk) begin
        block = weight_mem_addr / 256;
        offset = weight_mem_addr % 256;
        wr_idx = offset / 16;
        wc_idx = offset % 16;
        
        ky_idx = block / KW;
        kx_idx = block % KW;
        
        if (ky_idx < KH && kx_idx < KW && wr_idx < CIN && wc_idx < COUT)
            r_weight_data <= weights[ky_idx][kx_idx][wr_idx][wc_idx];
        else
            r_weight_data <= 0;
    end
    assign weight_mem_data_wire = r_weight_data;
    
    // Input Memory Read
    reg [16*8-1:0] r_input_data;
    integer y_idx, x_idx, c_idx;
    
    always @(posedge clk) begin
        y_idx = input_mem_addr / IN_W;
        x_idx = input_mem_addr % IN_W;
        
        if (y_idx < IN_H && x_idx < IN_W) begin
            for (c_idx=0; c_idx<CIN; c_idx=c_idx+1) begin
                r_input_data[c_idx*8 +: 8] <= inputs[y_idx][x_idx][c_idx];
            end
        end else begin
            r_input_data <= 0;
        end
    end
    assign input_mem_data_wire = r_input_data;

    // =========================================================================
    // DUT Instantiation
    // =========================================================================
    
    pe_controller #(
        .ARRAY_DIM(16)
    ) u_controller (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .done(done),
        .kernel_h(KH[3:0]),
        .kernel_w(KW[3:0]),
        .input_h(IN_H[7:0]), // Note: Controller interprets this as Input Size
        .input_w(IN_W[7:0]),
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
        .weight_mem_data(weight_mem_data_wire),
        .input_mem_addr(input_mem_addr),
        .input_mem_data(input_mem_data_wire)
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
    // Partial Sum Buffer (Accumulator)
    // =========================================================================
    
    wire [16*32-1:0] buffer_out; // Not used for checking, we peek memory
    
    psum_buffer #(
        .ARRAY_DIM(16),
        .ACC_WIDTH(32),
        .DEPTH(1024)
    ) u_buffer (
        .clk(clk),
        .rst_n(rst_n),
        .acc_enable(acc_enable),
        .acc_clear(acc_clear),
        .addr(acc_addr),
        .psum_in(pe_acc_out),
        .final_out(buffer_out)
    );
    
    // =========================================================================
    // Test Logic
    // =========================================================================
    
    integer i, j, k, l, m, n;
    
    initial begin
        $dumpfile("tb_conv_16x16.vcd");
        $dumpvars(0, tb_conv_16x16);
        
        // 1. Initialize Data
        $display("Initializing Data...");
        
        // Random Weights
        for (i=0; i<KH; i=i+1) begin
            for (j=0; j<KW; j=j+1) begin
                for (k=0; k<CIN; k=k+1) begin
                    for (l=0; l<COUT; l=l+1) begin
                        weights[i][j][k][l] = $random % 5; // Small values to avoid overflow
                    end
                end
            end
        end
        
        // Random Inputs
        for (i=0; i<IN_H; i=i+1) begin
            for (j=0; j<IN_W; j=j+1) begin
                for (k=0; k<CIN; k=k+1) begin
                    inputs[i][j][k] = $random % 5;
                end
            end
        end
        
        // 2. Compute Golden Reference
        $display("Computing Golden Reference...");
        for (i=0; i<OUT_H; i=i+1) begin
            for (j=0; j<OUT_W; j=j+1) begin
                for (l=0; l<COUT; l=l+1) begin
                    golden_output[i][j][l] = 0;
                    // Convolution Sum
                    for (m=0; m<KH; m=m+1) begin
                        for (n=0; n<KW; n=n+1) begin
                            for (k=0; k<CIN; k=k+1) begin
                                golden_output[i][j][l] = golden_output[i][j][l] + 
                                    (inputs[i+m][j+n][k] * weights[m][n][k][l]);
                            end
                        end
                    end
                end
            end
        end
        
        // 3. Run Simulation
        clk = 0;
        rst_n = 0;
        start = 0;
        #20;
        rst_n = 1;
        #20;
        
        $display("Starting Convolution...");
        start = 1;
        #10;
        start = 0;
        
        wait(done);
        #200;
        
        $display("Simulation Done. Checking Results...");
        
        for (oy_chk=0; oy_chk<OUT_H; oy_chk=oy_chk+1) begin
            for (ox_chk=0; ox_chk<OUT_W; ox_chk=ox_chk+1) begin
                for (c_chk=0; c_chk<COUT; c_chk=c_chk+1) begin
                        $display("Checking Out(%0d, %0d) Ch %0d: Expected %0d, Got %0d", 
                        oy_chk, ox_chk, c_chk, golden_output[oy_chk][ox_chk][c_chk], $signed(u_buffer.mem[oy_chk*IN_W + ox_chk][c_chk*32 +: 32]));
                    if (u_buffer.mem[oy_chk*IN_W + ox_chk][c_chk*32 +: 32] !== golden_output[oy_chk][ox_chk][c_chk]) begin
                        $display("ERROR at Out(%0d, %0d) Ch %0d: Exp %0d, Got %0d", 
                            oy_chk, ox_chk, c_chk, golden_output[oy_chk][ox_chk][c_chk], $signed(u_buffer.mem[oy_chk*IN_W + ox_chk][c_chk*32 +: 32]));
                    end
                end
            end
        end
        
        $display("Result Check Complete.");
        $finish;
    end
    
    always #5 clk = ~clk;
    
    // =========================================================================
    // Result Checker (Moved to Initial Block)
    // =========================================================================
    
    integer oy_chk, ox_chk, c_chk;
    // Old on-the-fly checker removed.
    
    // Timeout
    initial begin
        #1000000;
        $display("TIMEOUT");
        $finish;
    end

endmodule
