# Architecture Design

This document outlines the architecture design of the FPGA project, detailing the key components and their interactions within the system.

## Components
1. **Processing Element (PE)**: The core computational unit responsible for executing instructions and processing data.
2. **Address Generator Unit (AGU)**: Generates memory addresses for data access, ensuring efficient data retrieval and storage.
3. **Activation Buffer**: Temporarily holds activation data during processing to facilitate quick access and reduce latency.
4. **Weight Buffer**: Stores weight data used in computations, allowing for rapid access during
5. **Config Registers**: Hold configuration parameters that dictate the operation of the PE and other components.

## PE Array Architecture (16x16)

The system employs a **16x16 PE Array** (256 MAC units total) utilizing a **Weight Stationary** dataflow to maximize weight reuse and minimize off-chip memory access.

### Design Overview
*   **Dimensions**: 16 Rows × 16 Columns.
*   **Parallelism Strategy**:
    *   **Row Parallelism (Output Channels)**: Each row `i` computes Output Channel `i`.
    *   **Column Parallelism (Spatial Pixels)**: Each column `j` computes Spatial Pixel `j` (e.g., adjacent windows in the input feature map).
*   **Dataflow**:
    *   **Weights**: Pre-loaded into PE registers. Row `i` stores weights for Filter `i`.
    *   **Inputs**: Broadcast from Input Buffer to columns. Column `j` receives Input Window `j`.
    *   **Outputs**: Accumulated locally in INT32, then read out for requantization.

### PE Array Diagram
```mermaid
graph TD
    subgraph "Global Memory"
        DRAM["DRAM (Weights & Activations)"]
    end

    subgraph "On-chip Buffers"
        IB["Input Buffer (Activations)"]
        WB[Weight Buffer]
        OB[Output Buffer]
    end

    DRAM --> IB
    DRAM --> WB
    OB --> DRAM

    subgraph "16x16 PE Array (Weight Stationary)"
        direction TB
        
        IB --"Broadcast Input (16 Pixels)"--> Cols
        WB --"Pre-load Weights (16 Filters)"--> Rows
        
        subgraph "PE Grid"
            direction TB
            R0[Row 0: Filter 0] --- PE0_0[PE 0,0] & PE0_15[... PE 0,15]
            R1[Row 1: Filter 1] --- PE1_0[PE 1,0] & PE1_15[... PE 1,15]
            R15[... Row 15: Filter 15] --- PE15_0[PE 15,0] & PE15_15[... PE 15,15]
        end
    end

    subgraph "Post-Processing"
        PPU[Requantizer Unit]
        note["Shift >> & Clip to INT8"]
    end

    PE0_0 & PE0_15 --> PPU
    PE1_0 & PE1_15 --> PPU
    PE15_0 & PE15_15 --> PPU
    PPU --> OB

    style PE0_0 fill:#f9f,stroke:#333,stroke-width:2px
    style PPU fill:#ff9,stroke:#333,stroke-width:2px
```

## MAC Unit Design

Each Processing Element (PE) contains a MAC unit designed for INT8 inference.

### Specifications
*   **Arithmetic**: INT8 Multiplication, INT32 Accumulation.
*   **Registers**: 
    *   `Weight Reg`: Stores the stationary weight.
    *   `Accumulator`: Stores the 32-bit partial sum.
*   **Logic**: `Acc = Acc + (Input * Weight)`.

### MAC Unit Diagram
```mermaid
graph LR
    subgraph "MAC Unit"
        direction LR
        
        In["Input (INT8)"]
        W_In[Weight Load]
        Ctrl[Control]
        
        W_Reg["Weight Reg (INT8)"]
        Acc_Reg["Accumulator (INT32)"]
        
        Mul((x))
        Add((+))
        
        W_In --"Load"--> W_Reg
        In --> Mul
        W_Reg --> Mul
        
        Mul --"INT16"--> Add
        Acc_Reg --"Sum"--> Add
        Add --"Next Sum"--> Acc_Reg
        
        Out["Output (INT32)"]
        Acc_Reg --> Out
        
        Ctrl --"Reset/En"--> Acc_Reg
        Ctrl --"Write En"--> W_Reg
    end
    
    style Mul fill:#f96,stroke:#333
    style Add fill:#f96,stroke:#333
    style W_Reg fill:#69f,stroke:#333
    style Acc_Reg fill:#69f,stroke:#333
```