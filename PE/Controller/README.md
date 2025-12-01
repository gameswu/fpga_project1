# PE Controller - Processing Element Array Controller

## Overview
The PE Controller orchestrates the operation of the 16x16 PE Array to perform convolution operations. It implements a **Weight Stationary** dataflow, managing the loading of weights, broadcasting of inputs, and accumulation of partial sums. It handles tiling for Output Channels and Spatial Dimensions to map larger convolution layers onto the fixed-size array.

## Module: `pe_controller.v`

### Features
- **Tiling Support**: Breaks down large feature maps and channel depths into 16x16 blocks.
- **Weight Stationary Dataflow**: Maximizes weight reuse by keeping weights static in PEs while streaming inputs.
- **Automatic Padding**: Handles zero-padding logic for boundary pixels.
- **Address Generation**: Generates addresses for Weight and Input memory subsystems.
- **State Machine**: Controls the sequence of operations (Load -> Compute -> Readout).

### Architecture
The controller implements a nested loop structure:
1.  **Tile Loop (Outer)**: Iterates over Output Channel blocks (16 channels) and Spatial blocks (4x4 output pixels).
2.  **Kernel Loop (Inner)**: Iterates over the kernel dimensions ($K_H \times K_W$).

### Interface

| Port Name      | Direction | Width (bits) | Description |
|----------------|-----------|--------------|-------------|
| `clk`          | Input     | 1            | System Clock |
| `rst_n`        | Input     | 1            | Active-low Reset |
| `start`        | Input     | 1            | Start convolution operation |
| `done`         | Output    | 1            | Operation complete |
| `enable`       | Output    | 1            | Enable PE Array computation |
| `acc_clear`    | Output    | 1            | Clear PE Array accumulators |
| `weight_load`  | Output    | 1            | Load weights into PE Array |
| `pe_data_in`   | Output    | 2048         | Input data broadcast to PE Array columns |
| `pe_weight_in` | Output    | 2048         | Weight data broadcast to PE Array rows |
| `pe_acc_out`   | Input     | 8192         | Accumulator output from PE Array |
| `weight_addr`  | Output    | 16           | Address for Weight Memory |
| `weight_rdata` | Input     | 128          | Data from Weight Memory (16 weights) |
| `input_ref_y`  | Output    | 16 (Signed)  | Reference Y coordinate for Input Memory |
| `input_ref_x`  | Output    | 16 (Signed)  | Reference X coordinate for Input Memory |
| `input_rdata`  | Input     | 128          | Data from Input Memory (16 pixels) |
| `output_valid` | Output    | 1            | Output data is valid |
| `output_data`  | Output    | 8192         | Final accumulated results |

### Parameters
The controller is parameterized to support different layer configurations:
- `ARRAY_DIM`: Dimension of the PE Array (default: 16).
- `IFM_H`, `IFM_W`: Input Feature Map dimensions.
- `OFM_H`, `OFM_W`: Output Feature Map dimensions.
- `K_H`, `K_W`: Kernel dimensions (e.g., 5x5).
- `PAD`: Padding size.
- `STRIDE`: Stride value.
- `CHANNELS`: Number of Output Channels.

### Operation Sequence

1.  **Idle**: Waits for `start` signal.
2.  **Start Tile**: Initializes counters for a new output tile (16 Channels x 16 Spatial Pixels).
3.  **Load Weight**:
    *   Fetches 16 weights (one for each active Output Channel) for the current kernel position $(ky, kx)$.
    *   Asserts `weight_load` to store weights in the PE Array.
4.  **Compute**:
    *   Calculates the input coordinate $(oy + ky - pad, ox + kx - pad)$.
    *   Fetches a $4 \times 4$ block of input pixels (16 pixels).
    *   Asserts `enable` to perform MAC operation.
5.  **Wait Compute**: Iterates through all kernel positions $(0..K_H-1, 0..K_W-1)$.
6.  **Read Out**:
    *   Asserts `output_valid` to signal that the PE Array contains valid partial sums for the current tile.
    *   Moves to the next tile (Spatial -> Channel).
7.  **Done**: Asserts `done` when all tiles are processed.

## Testbench: `pe_controller_tb.v`

### Test Coverage
- **Control Logic**: Verifies the state machine transitions.
- **Address Generation**: Checks if correct weight addresses and input coordinates are generated.
- **Padding Handling**: Verifies that out-of-bound input coordinates result in zero-padding (simulated in TB).
- **Integration**: Instantiates `pe_controller` and `pe_array` to verify end-to-end operation.

### Running Simulation

Using Icarus Verilog:
```bash
iverilog -g2012 -o pe_controller_tb.vvp -I ../Array -I ../MAC pe_controller_tb.v pe_controller.v ../Array/pe_array.v ../MAC/mac.v
vvp pe_controller_tb.vvp
```

### Expected Results
The testbench simulates a convolution with constant inputs (1) and weights (1).
- **Center Pixels**: Should accumulate to $5 \times 5 = 25$.
- **Edge Pixels**: Should accumulate to 15 (due to padding).
- **Corner Pixels**: Should accumulate to 9 (due to padding).

The testbench prints "Success: Output is 25" (or similar checks) for valid outputs.
