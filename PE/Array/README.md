# PE Array - Processing Element Array

## Overview
The PE Array is the core computational engine of the accelerator, consisting of a 16x16 grid of Processing Elements (PEs). It implements a **Weight Stationary** dataflow to maximize weight reuse and minimize off-chip memory bandwidth.

## Module: `pe_array.v`

### Architecture
*   **Dimensions**: 16 Rows × 16 Columns (256 PEs total).
*   **Parallelism**:
    *   **Row Parallelism**: Each row corresponds to a different Output Channel (Filter).
    *   **Column Parallelism**: Each column corresponds to a different Spatial Pixel (Input Window).
*   **Dataflow**:
    *   **Weights**: Unique weight input for each PE (256 total). External logic (Controller) handles broadcasting to rows if needed.
    *   **Inputs**: Unique data input for each PE (256 total). External logic (Controller) handles broadcasting to columns if needed.
    *   **Outputs**: 256 Accumulators output in parallel.

### Interface

| Port Name     | Direction | Width (bits) | Description |
|---------------|-----------|--------------|-------------|
| `clk`         | Input     | 1            | System Clock |
| `rst_n`       | Input     | 1            | Active-low Reset |
| `enable`      | Input     | 1            | Enable computation (MAC) |
| `acc_clear`   | Input     | 1            | Clear all accumulators |
| `weight_load` | Input     | 1            | Load weights into PEs |
| `data_in`     | Input     | 2048 (256*8) | Input activations (256 bytes), one per PE |
| `weight_in`   | Input     | 2048 (256*8) | Weights (256 bytes), one per PE |
| `acc_out`     | Output    | 8192 (256*32)| Accumulator outputs (flattened) |

### Operation
1.  **Weight Loading**:
    *   Assert `weight_load`.
    *   Provide 256 weights on `weight_in`. `weight_in` is flattened row-major: Row 0 (Cols 0..15), Row 1...
    *   Weights are latched into the MAC units of each PE.
2.  **Computation**:
    *   Assert `enable`.
    *   Provide 256 inputs on `data_in`. `data_in` is flattened row-major.
    *   Each PE(i, j) computes: `Acc += Input(i,j) * Weight(i,j)`.
3.  **Readout**:
    *   Read `acc_out` which contains all 256 partial sums.

## Testbench: `pe_array_tb.v`
Verifies the connectivity and basic operation of the array.
*   Loads unique weights to each row.
*   Broadcasts unique inputs to each column.
*   Checks if `PE(i, j)` computes `Weight(i) * Input(j)`.
