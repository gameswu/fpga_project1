/**
 * PE Array (16x16 Systolic-like Array)
 * 
 * Description:
 *   16x16 Array of MAC units implementing Weight Stationary dataflow.
 *   
 * Architecture:
 *   - Rows: 16 Rows.
 *   - Columns: 16 Columns.
 *   - Weights: Unique weight for each PE.
 *   - Inputs: Unique input for each PE.
 *   - Outputs: 256 Accumulators (16x16), output in parallel.
 *
 * Dataflow:
 *   1. Weight Load: Assert weight_load. Provide 256 weights (one per PE).
 *      Weights are latched into MAC units.
 *   2. Compute: Assert enable. Provide 256 inputs (one per PE).
 *      Each PE(i,j) computes: Acc += Input(i,j) * Weight(i,j).
 *   3. Repeat Compute for all input channels/kernel pixels.
 *   4. Readout: Read acc_out.
 *
 * Author: shealligh
 * Date: 2025-11-24
 */

module pe_array #(
    parameter ARRAY_DIM = 16, // Array Dimension (16x16)
    parameter DATA_WIDTH = 8,
    parameter ACC_WIDTH = 32
)(
    input wire clk,
    input wire rst_n,
    
    // Global Control Signals
    input wire enable,          // Enable computation in all PEs
    input wire acc_clear,       // Clear accumulators in all PEs
    input wire weight_load,     // Load weights into all PEs
    
    // Data Inputs
    // Unique data for each PE
    // Width: 16 * 16 * 8 = 2048 bits
    input wire [ARRAY_DIM*ARRAY_DIM*DATA_WIDTH-1:0] data_in, 
    
    // Weight Inputs
    // Unique weight for each PE
    // Width: 16 * 16 * 8 = 2048 bits
    input wire [ARRAY_DIM*ARRAY_DIM*DATA_WIDTH-1:0] weight_in,
    
    // Outputs
    // All 256 Accumulators output in parallel
    // Width: 16 * 16 * 32 = 8192 bits
    // Layout: Row 0 (Cols 0..15), Row 1 (Cols 0..15), ...
    output wire [ARRAY_DIM*ARRAY_DIM*ACC_WIDTH-1:0] acc_out
);

    // Generate variable
    genvar i, j;
    
    generate
        for (i = 0; i < ARRAY_DIM; i = i + 1) begin : ROW
            for (j = 0; j < ARRAY_DIM; j = j + 1) begin : COL
                
                // Calculate indices for flattened arrays
                // Weight index depends on Row (i) and Column (j)
                localparam W_IDX = (i * ARRAY_DIM + j) * DATA_WIDTH;
                
                // Data index depends on Row (i) and Column (j)
                localparam D_IDX = (i * ARRAY_DIM + j) * DATA_WIDTH;
                
                // Output index depends on Row (i) and Column (j)
                // Flattened as Row-Major: (Row * Width + Col)
                localparam OUT_IDX = (i * ARRAY_DIM + j) * ACC_WIDTH;
                
                // Instantiate MAC Unit
                mac u_mac (
                    .clk(clk),
                    .rst_n(rst_n),
                    .enable(enable),
                    .acc_clear(acc_clear),
                    .weight_load(weight_load),
                    // Input Data for PE(i,j)
                    .data_in(data_in[D_IDX +: DATA_WIDTH]),
                    // Weight Data for PE(i,j)
                    .weight_in(weight_in[W_IDX +: DATA_WIDTH]),
                    // Accumulator Output
                    .acc_out(acc_out[OUT_IDX +: ACC_WIDTH])
                );
            end
        end
    endgenerate

endmodule
