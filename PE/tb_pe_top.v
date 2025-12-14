`timescale 1ns / 1ps

/**
 * PE System Top Level Testbench
 * 
 * Description:
 *   Verifies the full PE System (pe_top) including:
 *   - Configuration via config_regs
 *   - Data loading via weight_buffer and act_buffer
 *   - Convolution execution
 *
 * Author: shealligh
 * Date: 2025-12-11
 */

module tb_pe_top;

    // =========================================================================
    // Parameters
    // =========================================================================
    parameter CIN = 16;
    parameter COUT = 10;
    parameter KH = 5;
    parameter KW = 5;
    parameter IN_H = 10;
    parameter IN_W = 10;
    
    parameter OUT_H = IN_H - KH + 1;
    parameter OUT_W = IN_W - KW + 1;

    // =========================================================================
    // Signals
    // =========================================================================
    reg clk;
    reg rst_n;
    
    // Config
    reg        cfg_we;
    reg [3:0]  cfg_addr;
    reg [31:0] cfg_wdata;
    wire [31:0] cfg_rdata;
    
    // Weight Loader
    reg        weight_load_we;
    reg [15:0] weight_load_addr;
    reg [127:0] weight_load_data;
    
    // Act Loader
    reg        act_load_we;
    reg [15:0] act_load_addr;
    reg [127:0] act_load_data;
    
    // Result
    reg [9:0]   res_addr;
    wire [511:0] res_data;
    
    // =========================================================================
    // DUT Instantiation
    // =========================================================================
    pe_top u_dut (
        .clk(clk),
        .rst_n(rst_n),
        .cfg_we(cfg_we),
        .cfg_addr(cfg_addr),
        .cfg_wdata(cfg_wdata),
        .cfg_rdata(cfg_rdata),
        .weight_load_we(weight_load_we),
        .weight_load_addr(weight_load_addr),
        .weight_load_data(weight_load_data),
        .act_load_we(act_load_we),
        .act_load_addr(act_load_addr),
        .act_load_data(act_load_data),
        .res_addr(res_addr),
        .res_data(res_data)
    );
    
    // =========================================================================
    // Data Generation
    // =========================================================================
    reg signed [7:0] weights [0:KH-1][0:KW-1][0:CIN-1][0:COUT-1];
    reg signed [7:0] inputs [0:IN_H-1][0:IN_W-1][0:CIN-1];
    reg signed [31:0] golden_output [0:OUT_H-1][0:OUT_W-1][0:COUT-1];
    
    integer i, j, k, l, m, n;
    
    // =========================================================================
    // Test Sequence
    // =========================================================================
    initial begin
        $dumpfile("tb_pe_top.vcd");
        $dumpvars(0, tb_pe_top);
        
        clk = 0;
        rst_n = 0;
        cfg_we = 0;
        weight_load_we = 0;
        act_load_we = 0;
        
        #20;
        rst_n = 1;
        #20;
        
        // 1. Initialize Data
        $display("Initializing Data...");
        for (i=0; i<KH; i=i+1)
            for (j=0; j<KW; j=j+1)
                for (k=0; k<CIN; k=k+1)
                    for (l=0; l<COUT; l=l+1)
                        weights[i][j][k][l] = $random % 5;
                        
        for (i=0; i<IN_H; i=i+1)
            for (j=0; j<IN_W; j=j+1)
                for (k=0; k<CIN; k=k+1)
                    inputs[i][j][k] = $random % 5;
                    
        // 2. Compute Golden
        $display("Computing Golden Reference...");
        for (i=0; i<OUT_H; i=i+1) begin
            for (j=0; j<OUT_W; j=j+1) begin
                for (l=0; l<COUT; l=l+1) begin
                    golden_output[i][j][l] = 0;
                    for (m=0; m<KH; m=m+1)
                        for (n=0; n<KW; n=n+1)
                            for (k=0; k<CIN; k=k+1)
                                golden_output[i][j][l] = golden_output[i][j][l] + 
                                    (inputs[i+m][j+n][k] * weights[m][n][k][l]);
                end
            end
        end
        
        // 3. Load Weights
        $display("Loading Weights...");
        // Address mapping must match controller: (ky*KW + kx)*256 + wr*16 + wc
        // But controller reads 32-bit words.
        // Our weight_buffer is 128-bit wide.
        // We write one weight per address (using LSB 8 bits).
        for (i=0; i<KH; i=i+1) begin
            for (j=0; j<KW; j=j+1) begin
                for (l=0; l<COUT; l=l+1) begin // Iterate Output Channels
                    // Pack all CIN weights (16 bytes) into one 128-bit word
                    for (k=0; k<CIN; k=k+1) begin
                        weight_load_data[k*8 +: 8] = weights[i][j][k][l];
                    end
                    // Address maps to the start of the vector (word index)
                    // Controller expects: (ky*KW + kx)*16 + wc
                    // wc corresponds to Output Channel index (l)
                    weight_load_addr = (i*KW + j)*16 + l;
                    weight_load_we = 1;
                    #10;
                end
            end
        end
        weight_load_we = 0;
        
        // 4. Load Inputs
        $display("Loading Inputs...");
        // Address mapping: y*W + x
        // Data: 128-bit vector (16 channels)
        for (i=0; i<IN_H; i=i+1) begin
            for (j=0; j<IN_W; j=j+1) begin
                act_load_addr = i*IN_W + j;
                for (k=0; k<CIN; k=k+1) begin
                    act_load_data[k*8 +: 8] = inputs[i][j][k];
                end
                act_load_we = 1;
                #10;
            end
        end
        act_load_we = 0;
        
        // 5. Configure Registers
        $display("Configuring Registers...");
        // 0x08: Kernel Dims (H=3, W=3) -> 0x0303
        cfg_addr = 2; // Index 2
        cfg_wdata = {20'b0, KH[3:0], 4'b0, KW[3:0]};
        cfg_we = 1;
        #10;
        
        // 0x0C: Input Dims (H=8, W=8) -> 0x0808
        cfg_addr = 3; // Index 3
        cfg_wdata = {16'b0, IN_H[7:0], IN_W[7:0]};
        cfg_we = 1;
        #10;
        cfg_we = 0;
        
        // 6. Start
        $display("Starting System...");
        cfg_addr = 0; // Control
        cfg_wdata = 1; // Start bit
        cfg_we = 1;
        #10;
        cfg_we = 0;
        
        // 7. Wait for Done
        // We can poll status register (Addr 1) or wait for done signal if exposed.
        // pe_top doesn't expose done, but we can peek or poll.
        // Let's poll.
        wait_for_done();
        
        #200;
        
        // 8. Check Results
        $display("Checking Results...");
        check_results();
        
        $finish;
    end
    
    always #5 clk = ~clk;
    
    task wait_for_done;
        integer timeout;
        reg done_bit;
        begin
            timeout = 100000;
            done_bit = 0;
            while (!done_bit && timeout > 0) begin
                cfg_addr = 1; // Status
                #1; // Wait for comb logic
                done_bit = cfg_rdata[0];
                #9; // Complete cycle
                timeout = timeout - 1;
            end
            if (timeout == 0) begin
                $display("TIMEOUT waiting for done");
                $finish;
            end
        end
    endtask
    
    task check_results;
        integer oy, ox, c;
        reg signed [31:0] val;
        begin
            for (oy=0; oy<OUT_H; oy=oy+1) begin
                for (ox=0; ox<OUT_W; ox=ox+1) begin
                    // Read from Psum Buffer via res_data port
                    // Address = oy*IN_W + ox (Same as controller logic)
                    res_addr = oy*IN_W + ox;
                    #10; // Wait for read
                    
                    for (c=0; c<COUT; c=c+1) begin
                        val = res_data[c*32 +: 32];
                        if (val !== golden_output[oy][ox][c]) begin
                            $display("ERROR at Out(%0d, %0d) Ch %0d: Exp %0d, Got %0d", 
                                oy, ox, c, golden_output[oy][ox][c], val);
                        end
                    end
                end
            end
            $display("Result Check Complete.");
        end
    endtask

endmodule
