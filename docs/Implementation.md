# Vivado Implementation & Verification Guide

## 1. Vivado 项目设置 (Project Setup)

### 1.1 创建项目
1.  打开 Vivado，创建新项目。
2.  选择目标 FPGA 芯片 (e.g., Xilinx Zynq-7000 or Artix-7)。
3.  将以下目录中的所有 `.v` 文件添加到 Design Sources:
    *   `Controller/`
    *   `PE/Array/`
    *   `PE/MAC/`
    *   `PPU/`
    *   `Interface/`

### 1.2 IP 核配置 (IP Configuration)
本项目依赖 3 个 Block Memory Generator (BRAM) IP 核。由于 `DNN_Top` 已经暴露了 BRAM 接口，您需要在 Top Level (或 Block Design) 中实例化这些 IP 并连接。

#### A. IFM Buffer (输入特征图)
*   **Component Name**: `bram_ifm`
*   **Interface Type**: Native
*   **Memory Type**: True Dual Port RAM (Port A: External, Port B: Controller)
*   **Port A (External)**:
    *   Width: 256 bits
    *   Depth: 2048 (根据资源调整)
    *   **Byte Write Enable**: Checked (必须启用，用于支持 32-bit 粒度写入)
    *   Enable Port Type: Use EN A Pin
*   **Port B (Controller)**:
    *   Width: 256 bits
    *   **Primitives Output Register**: Checked (Latency = 2 cycles)

#### B. Weight Buffer (权重)
*   **Component Name**: `bram_wgt`
*   **Interface Type**: Native
*   **Memory Type**: True Dual Port RAM
*   **Port A (External)**:
    *   Width: 128 bits
    *   Depth: 2048
    *   **Byte Write Enable**: Checked
*   **Port B (Controller)**:
    *   Width: 128 bits
    *   **Primitives Output Register**: Checked (Latency = 2 cycles)

#### C. OFM Buffer (输出特征图)
*   **Component Name**: `bram_ofm`
*   **Interface Type**: Native
*   **Memory Type**: True Dual Port RAM
*   **Port A (External)**:
    *   Width: 512 bits
    *   Depth: 1024
*   **Port B (Controller)**:
    *   Width: 512 bits
    *   **Primitives Output Register**: Checked (Latency = 2 cycles)

### 1.3 顶层连接 (Top Level Integration)
创建一个 Verilog Wrapper (`System_Wrapper.v`) 或使用 Block Design：
1.  实例化 `DNN_Top`。
2.  实例化上述 3 个 BRAM IP。
3.  将 `DNN_Top` 的 `bram_ifm_*` 端口连接到 `bram_ifm` 的 Port A (注意处理 Byte Enable 位宽匹配)。
    *   *注意*: `DNN_Top` 输出的 `bram_ifm_we` 是 32-bit (1 bit per byte)，直接连接到 BRAM 的 `wea`。
4.  将 `DNN_Top` 的 `bram_wgt_*` 连接到 `bram_wgt` 的 Port A。
5.  将 `DNN_Top` 的 `bram_ofm_*` 连接到 `bram_ofm` 的 Port A。

---

## 2. 仿真指南 (Simulation Guide)

为了验证系统功能，提供了 `Interface/DNN_Top_tb.v` 测试平台。该 Testbench 内部包含了行为级 BRAM 模型，因此**不需要** Vivado BRAM IP 即可直接在 ModelSim 或 Vivado Simulator 中运行。

### 2.1 运行仿真
1.  将 `Interface/DNN_Top_tb.v` 添加到 Simulation Sources。
2.  设置 `DNN_Top_tb` 为 Top Module。
3.  运行 Behavioral Simulation。

### 2.2 测试用例说明
Testbench 包含以下测试阶段：

1.  **CSR R/W Test**: 验证配置寄存器的读写功能。
2.  **Memory Access Test**:
    *   通过外部接口向 IFM Buffer 写入数据 (32-bit 模式)。
    *   通过外部接口向 Weight Buffer 写入数据。
    *   验证数据是否正确存入内部宽位宽存储器。
3.  **Full Computation Test (Small Layer)**:
    *   配置层参数 (4x4 IFM, 1x1 Kernel, 32 IC, 16 OC)。
    *   加载 IFM 和 Weight 数据。
    *   启动加速器。
    *   轮询 `Done` 状态。
    *   读取 OFM 结果并校验。

### 2.3 预期结果
控制台应输出类似以下信息：
```text
[PASS] CSR Register Read/Write Test Passed.
[PASS] IFM Memory Write Test Passed.
Starting Accelerator...
Interrupt Received! Accelerator Done.
[PASS] OFM Result at Ch0 is correct: 32
...
All Tests Passed.
```
