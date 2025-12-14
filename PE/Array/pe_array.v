/**
 * PE Array (16x16 Systolic Array) - Weight Stationary Version
 * 
 * Description:
 *   16x16 Array of MAC units implementing Weight Stationary dataflow.
 *   Implements Input Skewing (Diagonal Feed) to support vertical systolic accumulation.
 *   
 *   Dataflow:
 *   - Weights: Stationary (Loaded once).
 *   - Inputs: Broadcast to rows, but skewed in time.
 *     Row 0 receives Input[0] at T.
 *     Row 1 receives Input[1] at T+1.
 *     ...
 *     Row 15 receives Input[15] at T+15.
 *   - Partial Sums: Cascade vertically.
 *     Row 0 computes at T, outputs at T+1.
 *     Row 1 adds to Psum at T+1, outputs at T+2.
 *     ...
 *     Row 15 outputs final result at T+16.
 *
 * Author: shealligh
 * Date: 2025-12-11
 */

module pe_array #(
    parameter ARRAY_DIM = 16, // Array Dimension (16x16)
    parameter DATA_WIDTH = 8,
    parameter ACC_WIDTH = 32
)(
    input wire clk,
    input wire rst_n,
    
    // Weight Loading Interface
    input wire weight_write_enable,
    // input wire [3:0] weight_row, // Removed: Loading whole column at once
    input wire [3:0] weight_col,
    input wire [ARRAY_DIM*DATA_WIDTH-1:0] weight_in,
    
    // Data Inputs (Vector of 16 bytes)
    // data_in[0] -> Row 0 (Input Channel 0)
    // ...
    // data_in[15] -> Row 15 (Input Channel 15)
    input wire [ARRAY_DIM*DATA_WIDTH-1:0] data_in,
    
    // Partial Sum Outputs (From Bottom Row)
    output wire [ARRAY_DIM*ACC_WIDTH-1:0] psum_out
);

    // =========================================================================
    // Input Skewing (Delay Lines)
    // =========================================================================
    
    // row_data_in[r] is the skewed input for Row r
    wire signed [DATA_WIDTH-1:0] row_data_in [0:ARRAY_DIM-1];
    
    // Generate delay registers
    genvar i;
    generate
        for (i = 0; i < ARRAY_DIM; i = i + 1) begin : ROW_DELAYS
            if (i == 0) begin
                // Row 0: No delay
                assign row_data_in[i] = data_in[DATA_WIDTH-1:0];
            end else begin
                // Row i: i cycles delay
                reg [DATA_WIDTH-1:0] dly_regs [0:i-1];
                integer k;
                
                always @(posedge clk or negedge rst_n) begin
                    if (!rst_n) begin
                        for (k = 0; k < i; k = k + 1) dly_regs[k] <= 0;
                    end else begin
                        dly_regs[0] <= data_in[i*DATA_WIDTH +: DATA_WIDTH];
                        for (k = 1; k < i; k = k + 1) begin
                            dly_regs[k] <= dly_regs[k-1];
                        end
                    end
                end
                
                assign row_data_in[i] = dly_regs[i-1];
            end
        end
    endgenerate

    // =========================================================================
    // PE Array Instantiation
    // =========================================================================

    // Internal Psum Wires
    // psum_inter[row][col] is input to PE[row][col]
    // psum_inter[row+1][col] is output of PE[row][col]
    wire [ACC_WIDTH-1:0] psum_inter [0:ARRAY_DIM][0:ARRAY_DIM-1];
    
    // Initialize top row psum inputs to 0
    genvar c;
    generate
        for (c = 0; c < ARRAY_DIM; c = c + 1) begin : TOP_ROW
            assign psum_inter[0][c] = {ACC_WIDTH{1'b0}};
        end
    endgenerate
    
    // Instantiate PEs
    genvar r;
    generate
        for (r = 0; r < ARRAY_DIM; r = r + 1) begin : ROWS
            for (c = 0; c < ARRAY_DIM; c = c + 1) begin : COLS
                
                // Weight Load Logic for this PE
                // Load entire column 'weight_col' at once.
                // Each PE in this column takes its slice of weight_in.
                wire pe_load = weight_write_enable && (weight_col == c[3:0]);
                
                mac u_mac (
                    .clk(clk),
                    .rst_n(rst_n),
                    .weight_load(pe_load),
                    // Input Data (Skewed)
                    .data_in(row_data_in[r]),
                    // Weight Data (From common input vector, sliced for this row)
                    .weight_in(weight_in[r*DATA_WIDTH +: DATA_WIDTH]),
                    // Partial Sum Input (From PE above)
                    .psum_in(psum_inter[r][c]),
                    // Partial Sum Output (To PE below)
                    .psum_out(psum_inter[r+1][c])
                );
            end
        end
    endgenerate
    
    // Assign Outputs from bottom row
    generate
        for (c = 0; c < ARRAY_DIM; c = c + 1) begin : OUT_ASSIGN
            assign psum_out[c*ACC_WIDTH +: ACC_WIDTH] = psum_inter[ARRAY_DIM][c];
        end
    endgenerate

endmodule
