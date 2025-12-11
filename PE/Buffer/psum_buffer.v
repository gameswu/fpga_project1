/**
 * Partial Sum Buffer
 * 
 * Description:
 *   Wide memory to store partial sums for the 16x16 PE Array.
 *   Supports reading and writing 256 x 32-bit values in parallel.
 *   
 *   Size: DEPTH x (ARRAY_DIM * ARRAY_DIM * 32) bits
 *
 * Author: shealligh
 * Date: 2025-12-08
 */

module psum_buffer #(
    parameter ARRAY_DIM = 16,
    parameter ACC_WIDTH = 32,
    parameter DEPTH = 1024,      // Depth of the buffer (e.g., max spatial pixels)
    parameter ADDR_WIDTH = 10    // log2(DEPTH)
)(
    input wire clk,
    input wire rst_n,
    
    // Control
    input wire acc_enable, // Enable accumulation
    input wire acc_clear,  // If true, overwrite memory instead of add (start of new kernel)
    input wire [ADDR_WIDTH-1:0] addr, // Spatial Address
    
    // Input from Array
    input wire [ARRAY_DIM*ACC_WIDTH-1:0] psum_in,
    
    // Output (for final readout)
    output wire [ARRAY_DIM*ACC_WIDTH-1:0] final_out
);

    // Memory Array
    reg [ARRAY_DIM*ACC_WIDTH-1:0] mem [0:DEPTH-1];

    // Initialize memory to 0 for simulation
    integer k;
    initial begin
        for (k = 0; k < DEPTH; k = k + 1) begin
            mem[k] = 0;
        end
    end

    // Pipeline Registers for Read-Add-Write
    reg [ADDR_WIDTH-1:0] addr_d1;
    reg acc_enable_d1;
    reg acc_clear_d1;
    reg [ARRAY_DIM*ACC_WIDTH-1:0] psum_in_d1;
    
    // Stage 1: Read
    reg [ARRAY_DIM*ACC_WIDTH-1:0] rdata;
    
    always @(posedge clk) begin
        rdata <= mem[addr];
        addr_d1 <= addr;
        acc_enable_d1 <= acc_enable;
        acc_clear_d1 <= acc_clear;
        psum_in_d1 <= psum_in;
    end
    
    // Stage 2: Add & Write
    integer i;
    reg [ARRAY_DIM*ACC_WIDTH-1:0] wdata;
    
    always @(posedge clk) begin
        if (acc_enable_d1) begin
            for (i = 0; i < ARRAY_DIM; i = i + 1) begin
                if (acc_clear_d1) begin
                    // New kernel start: Overwrite
                    wdata[i*ACC_WIDTH +: ACC_WIDTH] = psum_in_d1[i*ACC_WIDTH +: ACC_WIDTH];
                end else begin
                    // Accumulate
                    wdata[i*ACC_WIDTH +: ACC_WIDTH] = rdata[i*ACC_WIDTH +: ACC_WIDTH] + psum_in_d1[i*ACC_WIDTH +: ACC_WIDTH];
                end
            end
            mem[addr_d1] <= wdata;
        end
    end
    
    // Output the value (Read mode)
    assign final_out = rdata;

    always @(posedge clk) begin
        if (acc_enable) begin
            //$display("Buffer Write: Addr=%d, DataIn[0]=%d, MemBefore[0]=%d", addr, psum_in[31:0], mem[addr][31:0]);
        end
        // if (addr == 0) begin
        //    $display("Buffer Read: Addr=%d, RData[0]=%d", addr, rdata[31:0]);
        // end
    end

endmodule
