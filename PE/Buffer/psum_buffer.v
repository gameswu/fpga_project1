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
    
    // Read Port
    input wire [ADDR_WIDTH-1:0] raddr,
    output wire [ARRAY_DIM*ACC_WIDTH-1:0] rdata,
    
    // Write Port
    input wire [ADDR_WIDTH-1:0] waddr,
    input wire [ARRAY_DIM*ACC_WIDTH-1:0] wdata,
    input wire wen
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

    // Read Operation
    reg [ARRAY_DIM*ACC_WIDTH-1:0] rdata_reg;
    
    always @(posedge clk) begin
        rdata_reg <= mem[raddr];
    end
    
    assign rdata = rdata_reg;
    
    // Write Operation
    always @(posedge clk) begin
        if (wen) begin
            mem[waddr] <= wdata;
        end
    end

endmodule
