/**
 * Partial Sum Accumulator
 * 
 * Description:
 *   Handles the Read-Modify-Write logic for Partial Sum accumulation.
 *   Designed to work with a simple dual-port or single-port RAM (Read then Write).
 *   
 *   Latency:
 *     Cycle 0: Input Address & Control
 *     Cycle 1: Read Data available from Memory -> Accumulation -> Write Enable/Data to Memory
 *     Cycle 2: Memory Write occurs
 *
 * Author: shealligh
 * Date: 2025-12-15
 */

module psum_accumulator #(
    parameter ARRAY_DIM = 16,
    parameter ACC_WIDTH = 32,
    parameter ADDR_WIDTH = 10
)(
    input wire clk,
    input wire rst_n,
    
    // Control Input (from Controller)
    input wire acc_enable,
    input wire acc_clear,
    input wire [ADDR_WIDTH-1:0] addr_in,
    input wire [ARRAY_DIM*ACC_WIDTH-1:0] psum_in,
    
    // Memory Read Interface
    input wire [ARRAY_DIM*ACC_WIDTH-1:0] rdata, // Data read from memory (corresponding to addr_in from previous cycle)
    
    // Memory Write Interface
    output wire [ADDR_WIDTH-1:0] waddr,
    output wire [ARRAY_DIM*ACC_WIDTH-1:0] wdata,
    output wire wen
);

    // Pipeline Registers
    reg [ADDR_WIDTH-1:0] addr_d1;
    reg acc_enable_d1;
    reg acc_clear_d1;
    reg [ARRAY_DIM*ACC_WIDTH-1:0] psum_in_d1;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            addr_d1 <= 0;
            acc_enable_d1 <= 0;
            acc_clear_d1 <= 0;
            psum_in_d1 <= 0;
        end else begin
            addr_d1 <= addr_in;
            acc_enable_d1 <= acc_enable;
            acc_clear_d1 <= acc_clear;
            psum_in_d1 <= psum_in;
        end
    end
    
    // Accumulation Logic
    reg [ARRAY_DIM*ACC_WIDTH-1:0] wdata_comb;
    integer i;
    
    always @(*) begin
        for (i = 0; i < ARRAY_DIM; i = i + 1) begin
            if (acc_clear_d1) begin
                // New kernel start: Overwrite
                wdata_comb[i*ACC_WIDTH +: ACC_WIDTH] = psum_in_d1[i*ACC_WIDTH +: ACC_WIDTH];
            end else begin
                // Accumulate
                wdata_comb[i*ACC_WIDTH +: ACC_WIDTH] = rdata[i*ACC_WIDTH +: ACC_WIDTH] + psum_in_d1[i*ACC_WIDTH +: ACC_WIDTH];
            end
        end
    end
    
    // Output Assignments
    assign waddr = addr_d1;
    assign wdata = wdata_comb;
    assign wen = acc_enable_d1;

endmodule
