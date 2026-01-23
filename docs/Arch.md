# FPGA DNN 加速器架构文档

## 1. 系统概览 (System Overview)

本设计实现了一个基于 FPGA 的深度神经网络 (DNN) 加速器，专为卷积神经网络 (CNN) 推理任务优化。核心架构采用 **32x16 脉动阵列 (Systolic Array)**，配合 **权重复用 (Weight Stationary)** 数据流策略，以最大化片上计算效率并降低存储带宽需求。

### 关键特性
*   **计算阵列**: 32 行 (Input Channels) x 16 列 (Output Channels) PE 阵列。
*   **数据流**: 脉动式 (Systolic) —— 特征图水平流动，部分和垂直累加。
*   **精度**: INT8 输入/权重，INT32 累加。
*   **控制策略**: 基于 Controller 的全局调度，支持 Tiling (分块) 以处理任意规模的网络层。
*   **硬件平台**: Xilinx Zynq-7000 SoC (xc7z020) - PS (ARM Cortex-A9) + PL (FPGA)。
*   **通信接口**: 5× AXI GPIO (32-bit) 实现 PS-PL 数据交换，UART 实现 PC-ARM 通信。

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

### 2.8 Zynq PS-PL 接口 (On-Board Deployment)
*   **平台**: Zynq-7000 SoC (xc7z020) - ARM Cortex-A9 (PS) + FPGA (PL)
*   **通信架构**: PC ↔ UART (115200 baud) ↔ ARM ↔ AXI GPIO ↔ FPGA Accelerator
*   **AXI GPIO 映射** (地址空间 0x41200000-0x41240000):
    *   **GPIO_CMD_ADDR** (0x41200000): 命令地址总线 - CSR寄存器地址、BRAM地址选择
    *   **GPIO_CMD_WDATA** (0x41210000): 命令写数据总线 - 向CSR/BRAM写入32-bit数据
    *   **GPIO_CMD_RDATA** (0x41220000): 命令读数据总线 - 从CSR/BRAM读取32-bit数据
    *   **GPIO_CONTROL** (0x41230000): 控制信号 - 读写使能、操作触发
    *   **GPIO_INTR** (0x41240000): 中断信号 - 计算完成通知

*   **访问协议**:
    1. 写操作: 设置 CMD_ADDR → 设置 CMD_WDATA → 触发 CONTROL 写使能
    2. 读操作: 设置 CMD_ADDR → 触发 CONTROL 读使能 → 从 CMD_RDATA 读取结果
    3. CSR 配置: 通过 CMD_ADDR 选择寄存器偏移，CMD_WDATA 写入配置值
    4. BRAM 访问: 通过 CMD_ADDR 指定BRAM地址，CMD_WDATA/RDATA 进行数据传输

#### 数据格式要求 (Critical)
由于 BRAM 的宽数据路径设计 (256-bit IFM read, 128-bit Weight read)，Host 写入时必须遵循特定的数据布局：

**Weight 数据格式 (Tile Organization)**:
*   硬件期望: 每个卷积核空间位置 $(k_h, k_w)$ 对应一个 **512 字节块** (32 IC rows × 16 OC columns)
*   Tile 分块: OC 按 16 划分 (tile0: OC[0-15], tile1: OC[16-31], ...)
*   Zero Padding: IC < 32 时需补零到 32 行以填满 PE 阵列
*   示例 (Layer1: IC=1, OC=32, Kernel=5×5):
    *   原始大小: 32×1×5×5 = 800 bytes (INT8)
    *   传输大小: 50 kernel points × 512 bytes = **25,600 bytes**
    *   布局: `[tile0_k00, tile1_k00, tile0_k01, tile1_k01, ..., tile0_k44, tile1_k44]`
    *   每个 512-byte 块包含 32×16 矩阵，其中 IC=1 时只有第一行有真实数据，其余 31 行为 0

**IFM 数据格式 (Pixel Expansion)**:
*   硬件期望: Controller 以 256-bit (32 bytes) 为单位读取，对应 32 个并行 IC
*   每个像素占用: **8 个连续的 32-bit words = 32 bytes**
*   数据位置: 仅第一个 word 的 LSB (字节0) 包含像素值，其余 31 字节为 0 (IC padding)
*   示例 (Layer1: 32×32×1 输入图像):
    *   原始大小: 1024 pixels × 1 byte = 1,024 bytes (INT8)
    *   传输大小: 1024 pixels × 32 bytes/pixel = **32,768 bytes**
    *   布局: `[pixel0_word0~7, pixel1_word0~7, ..., pixel1023_word0~7]`
    *   每个 pixel 的 word0[7:0] = 像素值，word0[31:8] 和 word1~7 全为 0

**OFM 数据格式 (Tile-Interleaved)**:
*   硬件输出: Controller 以 tile-interleaved 格式写入 (地址 = $(y×W+x)×num\_tiles + tile$)
*   Host 读取: 通过 32-bit mux 从 512-bit BRAM 读取，地址 $N$ 映射到 512-bit word $N/16$
*   De-Interleave 需求: 验证时需将 tile 格式转换为标准 HWC 格式
*   地址偏移: 实测发现输出有 32 元素偏移 (第一个有效数据在地址 32 而非 0)，验证时需跳过前 32 个 int32

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
├── software\            # On-Board 部署软件
│   ├── uart_sender.py   # PC端: 数据预处理 + UART发送
│   ├── verify_output.py # PC端: OFM验证 (De-interleave + 比对)
│   ├── dnn.c            # ARM端: GPIO驱动 + 加速器控制
│   └── layer1_config.json # 层配置文件
├── simulator\           # PyTorch 高层模型
│   ├── sim.py           # 量化卷积/全连接层实现
│   ├── test.py          # 多层网络测试
│   └── data\            # 测试数据 (im1-im8)
├── test\                # RTL 仿真 Testbench
│   ├── tb_Layer1.sv     # Layer1 硬件仿真
│   └── tb_common.sv     # 通用仿真任务
└── docs\                # 文档
    ├── Arch.md          # 本文档 (架构设计)
    └── Implementation.md # 实现细节
```

---

## 5. On-Board 部署验证结果

**测试配置**:
*   层: Conv1 (32×32×1 → 32×32×32, kernel 5×5, stride 1, pad 2)
*   输入: 真实灰度图像 (`simulator/data/im1/conv1.input.dat`)
*   Golden Reference: PyTorch 生成 (`conv1.output.dat`)

**数据传输量**:
*   Weight: 800 bytes → **25,600 bytes** (tile expansion + zero padding)
*   IFM: 1,024 bytes → **32,768 bytes** (pixel expansion to 32-byte stride)
*   OFM: **131,072 bytes** (32×32×32 int32 = 128KB, tile-interleaved format)

**验证结果**:
```
✓ PERFECT MATCH! FPGA output is identical to golden reference!
统计数据:
  Range: [-123, 109]
  Mean: 1.01, Std: 11.39
  Non-zero: 9124/32768
FPGA 输出与 PyTorch 参考模型 100% 匹配 (32,768 个值全部正确)
```

**关键发现**:
1. **Weight Tile Organization 必不可少**: 必须将 OIHW 格式转换为 32×16 tile 矩阵，每个 kernel point 512 字节
2. **IFM Pixel Expansion 必须精确**: 每个像素必须扩展到 32 字节 (8 words)，第一个字节放数据
3. **OFM 地址偏移**: 硬件输出有 32 元素偏移，验证时需要软件补偿
4. **De-Interleave 逻辑**: OFM 以 tile-interleaved 格式存储，需转换为 HWC 格式进行验证
