/**
 * Partial Sum Accumulator - Computation Only
 * 
 * Description:
 *   Pure combinational logic for partial sum accumulation.
 *   Control logic (address generation, enable signals) is handled by pe_controller.
 *   
 *   Function:
 *     - If clear=1: output = psum_in (overwrite)
 *     - If clear=0: output = rdata + psum_in (accumulate)
 *
 * Author: shealligh
 * Date: 2025-12-15
 * Modified: 2025-12-16 - Simplified to computation-only module
 */

module psum_accumulator #(
    parameter ARRAY_DIM = 16,
    parameter ACC_WIDTH = 32
)(
    // Control Input
    input wire acc_clear,
    
    // Data Inputs
    input wire [ARRAY_DIM*ACC_WIDTH-1:0] psum_in,  // From PE Array
    input wire [ARRAY_DIM*ACC_WIDTH-1:0] rdata,     // From BRAM
    
    // Data Output
    output wire [ARRAY_DIM*ACC_WIDTH-1:0] wdata     // To BRAM
);

    // Accumulation Logic (Pure Combinational)
    reg [ARRAY_DIM*ACC_WIDTH-1:0] wdata_comb;
    integer i;
    
    always @(*) begin
        for (i = 0; i < ARRAY_DIM; i = i + 1) begin
            if (acc_clear) begin
                // New kernel start: Overwrite
                wdata_comb[i*ACC_WIDTH +: ACC_WIDTH] = psum_in[i*ACC_WIDTH +: ACC_WIDTH];
            end else begin
                // Accumulate
                wdata_comb[i*ACC_WIDTH +: ACC_WIDTH] = rdata[i*ACC_WIDTH +: ACC_WIDTH] + psum_in[i*ACC_WIDTH +: ACC_WIDTH];
            end
        end
    end
    
    // Output Assignment
    assign wdata = wdata_comb;

endmodule
