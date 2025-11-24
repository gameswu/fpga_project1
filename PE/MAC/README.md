# MAC Unit - Multiply-Accumulate Unit

## Overview
Core computational unit for INT8 DNN inference accelerator. Implements the fundamental MAC operation: **Accumulator = Accumulator + (Input × Weight)**.

## Module: `mac_unit.v`

### Features
- **INT8 Signed Multiplication**: 8-bit × 8-bit → 16-bit product
- **INT32 Accumulation**: 32-bit accumulator prevents overflow during convolution
- **Weight Stationary Design**: Local weight register enables efficient weight reuse
- **Synchronous Control**: Reset, clear, enable, and weight load signals

### Architecture
```
Input (INT8) ──┐
               ├──> [×] ──> [+] ──> Accumulator (INT32) ──> Output
Weight Reg ────┘              ↑
                              │
                         Feedback Loop
```

### Interface

| Port Name    | Direction | Width | Description                          |
|--------------|-----------|-------|--------------------------------------|
| `clk`        | Input     | 1     | System clock                         |
| `rst_n`      | Input     | 1     | Active-low asynchronous reset        |
| `enable`     | Input     | 1     | Enable MAC operation                 |
| `acc_clear`  | Input     | 1     | Clear accumulator (synchronous)      |
| `weight_load`| Input     | 1     | Load weight into weight register     |
| `data_in`    | Input     | 8     | Input activation (signed INT8)       |
| `weight_in`  | Input     | 8     | Weight data (signed INT8)            |
| `acc_out`    | Output    | 32    | Accumulator output (signed INT32)    |

### Operation Sequence

1. **Weight Loading Phase**:
   ```
   weight_load = 1
   weight_in = <desired_weight>
   (wait 1 clock cycle)
   weight_load = 0
   ```

2. **Accumulation Phase**:
   ```
   enable = 1
   data_in = <input_value>
   (each clock cycle: acc = acc + data_in * weight_reg)
   ```

3. **Clear Accumulator**:
   ```
   acc_clear = 1
   (wait 1 clock cycle)
   acc_clear = 0
   ```

### Timing Diagram
```
Clock     : ____╱‾╲_╱‾╲_╱‾╲_╱‾╲_╱‾╲_╱‾╲_╱‾╲_
weight_load: ______╱‾‾‾╲_____________________
weight_in  : ------< W >---------------------
enable     : __________╱‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
data_in    : ----------<D1><D2><D3><D4>-----
acc_out    : ----------<0><W*D1><+W*D2><...>
```

## Testbench: `mac_unit_tb.v`

### Test Coverage
1. **Basic MAC Operation**: Single multiply-accumulate
2. **Multiple Accumulation**: Sequential MAC operations
3. **Signed Arithmetic**: Negative inputs and weights
4. **Accumulator Clear**: Reset functionality
5. **Enable Control**: Hold accumulator when disabled
6. **Overflow Prevention**: Large accumulation stress test (1000 iterations)

### Running Simulation

Using Icarus Verilog:
```bash
cd PE/MAC
iverilog -o mac_unit_sim mac_unit.v mac_unit_tb.v
vvp mac_unit_sim
gtkwave mac_unit_tb.vcd  # View waveforms
```

Using ModelSim/QuestaSim:
```bash
vlog mac_unit.v mac_unit_tb.v
vsim -c mac_unit_tb -do "run -all; quit"
```

### Expected Results
All 7 tests should PASS:
- Test 1: Single MAC (5 × 3 = 15)
- Test 2: Accumulation (15 + 10×3 = 45)
- Test 3: Negative input (45 + (-7)×3 = 24)
- Test 4: Clear (0)
- Test 5: Negative weight (8 × (-4) = -32)
- Test 6: Enable control (hold value)
- Test 7: Large accumulation (prevent overflow)

## Design Rationale

### Why INT32 Accumulator?
- **Convolution requires many accumulations**: A 3×3 kernel has 9 MACs, 5×5 has 25 MACs
- **INT8 × INT8 = INT16**: Intermediate product is 16 bits
- **Summing multiple INT16 values**: Can exceed 16-bit range
- **32-bit provides headroom**: Can accumulate ~65,536 products before overflow risk

### Why Weight Stationary?
- **Weight reuse**: In CNNs, same filter kernel slides across entire input feature map
- **Bandwidth optimization**: Load weight once, reuse for H×W input pixels
- **Matches documented architecture**: Per design specification in `docs/Arch.md`

## Resource Utilization (Estimated)

**Xilinx 7-series FPGA**:
- **DSP48E1 Slices**: 1 (for 8×8 signed multiplication)
- **Registers**: ~50 (weight reg: 8 bits, accumulator: 32 bits, control)
- **LUTs**: ~20 (control logic, muxes)

**For 16×16 PE Array**:
- Total DSP: 256
- Total Registers: ~12,800
- Total LUTs: ~5,120

## Integration Notes

When integrating into PE Array:
1. **Control FSM**: Centralized controller manages `weight_load`, `enable`, `acc_clear`
2. **Weight Distribution**: Weight buffer broadcasts to entire row
3. **Input Broadcast**: Input buffer broadcasts to entire column
4. **Output Collection**: Use output bus or shift register to collect partial sums

## References
- Architecture Design: `docs/Arch.md`
- Python Simulator: `simulator/sim.py` (reference INT8 computation logic)
