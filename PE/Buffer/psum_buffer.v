/**
 * Partial Sum Buffer
 * 
 * Description:
 *   Wide memory to store partial sums for the 16x16 PE Array.
 *   Supports reading and writing 256 x 32-bit values in parallel.
 *   TRUE DUAL-PORT design: separate addresses for accumulation and readout.
 *   
 *   Size: DEPTH x (ARRAY_DIM * ARRAY_DIM * 32) bits
 *
 * Author: shealligh
 * Date: 2025-12-08
 * Modified: 2025-12-15 - Added dual-port support for simultaneous read/write
 */

module psum_buffer #(
    parameter ARRAY_DIM = 16,
    parameter ACC_WIDTH = 32,
    parameter DEPTH = 1024,      // Depth of the buffer (e.g., max spatial pixels)
    parameter ADDR_WIDTH = 10    // log2(DEPTH)
)(
    input wire clk,
    input wire rst_n,
    
    // Port A: Accumulation (Read-Modify-Write during computation)
    input wire acc_enable,       // Enable accumulation
    input wire acc_clear,        // If true, overwrite memory instead of add (start of new kernel)
    input wire [ADDR_WIDTH-1:0] acc_addr,  // Address for accumulation
    input wire [ARRAY_DIM*ACC_WIDTH-1:0] psum_in,  // Input from Array
    
    // Port B: Readout (Independent read port for result extraction)
    input wire [ADDR_WIDTH-1:0] read_addr,  // Address for readout
    output reg [ARRAY_DIM*ACC_WIDTH-1:0] read_data  // Output data
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

    // =========================================================================
    // Port A: Accumulation Pipeline (Read-Modify-Write)
    // =========================================================================
    reg [ADDR_WIDTH-1:0] acc_addr_d1;
    reg acc_enable_d1;
    reg acc_clear_d1;
    reg [ARRAY_DIM*ACC_WIDTH-1:0] psum_in_d1;
    
    // Stage 1: Read for accumulation
    reg [ARRAY_DIM*ACC_WIDTH-1:0] acc_rdata;
    
    always @(posedge clk) begin
        acc_rdata <= mem[acc_addr];
        acc_addr_d1 <= acc_addr;
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
                    wdata[i*ACC_WIDTH +: ACC_WIDTH] = acc_rdata[i*ACC_WIDTH +: ACC_WIDTH] + psum_in_d1[i*ACC_WIDTH +: ACC_WIDTH];
                end
            end
            mem[acc_addr_d1] <= wdata;
        end
    end
    
    // =========================================================================
    // Port B: Independent Read Port (for result extraction)
    // =========================================================================
    always @(posedge clk) begin
        if (!rst_n) begin
            read_data <= 0;
        end else begin
            read_data <= mem[read_addr];
        end
    end

endmodule
