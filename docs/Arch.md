# FPGA DNN 加速器架构文档

## 1. 系统概览 (System Overview)

本设计实现了一个基于 FPGA 的深度神经网络 (DNN) 加速器，专为卷积神经网络 (CNN) 推理任务优化。核心架构采用 **32x16 脉动阵列 (Systolic Array)**，配合 **权重复用 (Weight Stationary)** 数据流策略，以最大化片上计算效率并降低存储带宽需求。

### 关键特性
*   **计算阵列**: 32 行 (Input Channels) x 16 列 (Output Channels) PE 阵列。
*   **数据流**: 脉动式 (Systolic) —— 特征图水平流动，部分和垂直累加。
*   **精度**: INT8 输入/权重，INT32 累加。
*   **控制策略**: 基于 Controller 的全局调度，支持 Tiling (分块) 以处理任意规模的网络层。
*   **硬件平台**: Xilinx FPGA (Vivado Design Suite)。

---

## 2. 核心组件 (Core Components)

### 2.1 Controller (系统控制器)
Controller 是整个加速器的大脑，负责协调数据流动和计算调度。
*   **位置**: `FPGA_DNN\Controller\`
*   **功能**:
    *   **配置解析**: 解析层参数 (H, W, IC, OC, Kernel, Stride, Padding)。
    *   **Tiling 调度**: 将大规模 Tensor 切分为适应 32x16 阵列的小块 (`tile_oc`, `tile_ic`)。
    *   **AGU (地址生成)**: 生成 IFM/Weight/OFM Buffer 的读写地址，处理 Padding 和 2-cycle BRAM 延迟。
    *   **Skew/De-skew**: 
        *   **Input Skew**: 通过移位寄存器组，将并行读取的 32 通道数据转换为阶梯状输入 (Row $i$ 延迟 $i$ 周期)。
        *   **Output De-skew**: 将阵列输出的阶梯状部分和对齐 (Col $j$ 延迟 $15-j$ 周期)，以便并行写入 Buffer。
    *   **Max Pooling**: 支持 Max Pooling 模式，通过配置 PE Array 执行最大值操作而非乘累加。
    *   **复位策略**: 全局采用 **同步复位 (Synchronous Reset)**。

### 2.2 PE Array (处理单元阵列)
*   **位置**: `FPGA_DNN\PE\Array\`
*   **规模**: 32 Rows x 16 Cols。
*   **连接拓扑**:
    *   **Feature**: 从左向右传递 (`feature_out` -> `feature_in`)，每级 1 cycle 延迟。
    *   **Psum**: 从上向下累加 (`psum_out` -> `psum_in`)，每级 1 cycle 延迟。
    *   **Weight**: 列共享总线，行独立写使能 (`weight_we_row`)，支持逐行快速更新。

### 2.3 MAC Unit (乘累加单元)
*   **位置**: `FPGA_DNN\PE\MAC\`
*   **实现**: 显式实例化 Vivado **DSP48 Macro** IP 核。
*   **流水线**: 
    *   输入寄存器 (RTL): 1 cycle。
    *   DSP 计算 (P Register): 1 cycle。
    *   总延迟: 输入到输出需 2 cycles (但在脉动阵列中，Feature Pass-through 仅需 1 cycle)。

### 2.4 Post-Processing Unit (PPU)
*   **位置**: `FPGA_DNN\PPU\`
*   **功能**: 对 PE Array 的输出进行后处理。
    *   **ReLU**: 激活函数 (可选)。
    *   **Quantization**: 将 INT32 累加结果右移 (`quant_shift`)。
    *   **Clipping (Saturation)**: 将移位后的结果饱和截断到 INT8 范围 ([-128, 127])，防止溢出回绕。
    *   **Bypass**: 支持直通模式，用于 Tiling 过程中的中间结果累加。
*   **延迟**: 2 Cycles。

### 2.5 Max Pooling Support
*   **实现**: 在 MAC 单元中集成比较器逻辑。
*   **模式**: 通过 `cfg_is_max_pool` 寄存器启用。
*   **操作**: 当启用时，PE 执行 `Psum_out = Max(Psum_in, Feature_in)`。
*   **应用**: 用于实现 Max Pooling 层 (如 Layer-2)。

### 2.6 Average Pooling Support
*   **实现**: 复用标准卷积路径。
*   **配置**: 
    *   Kernel Size = Pooling Window Size (e.g., 4x4).
    *   Weights = 1 (Identity).
    *   Quant Shift = $\log_2(\text{Window Size})$ (e.g., 4 for 16 elements).
*   **原理**: $\text{Avg} = (\sum x_i) / N$. 卷积计算 $\sum x_i$，PPU Shift 实现 $/N$。

### 2.7 On-chip Buffers (片上缓存)
*   **位置**: `FPGA_DNN\Buffer\`
*   **实现**: Xilinx Block Memory Generator (BRAM)。
*   **配置**:
    *   **IFM Buffer**: Simple Dual Port, 32-bit Write / 256-bit Read (32 channels). Latency = 2.
    *   **Weight Buffer**: Simple Dual Port, 32-bit Write / 128-bit Read (16 filters). Latency = 2.
    *   **OFM Buffer**: True Dual Port, 512-bit Read/Write (16 channels). Latency = 2.
        *   **Port A**: 512-bit Write (Dedicated to Accelerator).
        *   **Port B**: 512-bit Read (Shared by Accelerator Accumulation and Host Read).

---

## 3. 数据流与时序 (Dataflow & Timing)

### 3.1 脉动数据流
为了匹配阵列的脉动特性，输入数据必须经过 **Skew (阶梯化)** 处理：
*   **Row 0**: 在 $t=0$ 时刻输入。
*   **Row 1**: 在 $t=1$ 时刻输入。
*   ...
*   **Row 31**: 在 $t=31$ 时刻输入。

### 3.2 累加流水线 (Accumulation Pipeline)
为了解决 Single-Port BRAM 导致的读写冲突问题，OFM Buffer 升级为 **True Dual Port (512b/512b)** 配置，实现了 **100% 流水线效率**：
*   **Port B (Read)**: 用于读取旧的部分和 (Partial Sum)。
*   **Port A (Write)**: 用于写入更新后的累加值。
*   **时序**: Read @ Cycle $T$, Write @ Cycle $T+4$。由于使用独立端口，读写操作可在同一周期并发执行，无需 Pipeline Stall。

### 3.3 输出延迟 (Latency)
对于第 $j$ 列 (Output Channel $j$)，其最终累加结果有效的时刻 $T_{valid}$ 为：
$$ T_{valid} = (ROWS - 1) + j $$
*   **Col 0**: $31 + 0 = 31$ cycles (相对于 Row 0 数据进入时刻)。
*   **Col 15**: $31 + 15 = 46$ cycles.

Controller 的 **De-skew** 逻辑会补偿这些差异，使得所有 16 列的结果在同一时刻对齐输出。

---

## 4. 目录结构 (Directory Structure)

```
d:\soft\FPGA_DNN\
├── Controller\          # 系统级控制逻辑
│   ├── Controller.v     # FSM, AGU, Skew/De-skew, PPU Integration
│   ├── Controller_tb.v  # 系统级仿真 Testbench
│   └── IP_Config.md     # BRAM IP 配置指南
├── PPU\                 # 后处理单元 (ReLU, Quant)
│   ├── PPU.v            # PPU RTL
│   └── PPU.md           # PPU 设计文档
├── Buffer\              # BRAM IP 生成脚本 (.tcl)
├── PE\                  # 计算核心逻辑
│   ├── Array\           # 32x16 PE 阵列
│   └── MAC\             # DSP48 MAC 单元
└── docs\                # 文档
    └── Arch.md          # 本文档
```
