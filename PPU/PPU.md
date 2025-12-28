# Post-Processing Unit (PPU) Design

## 1. 设计目标 (Design Objectives)

PPU 位于 PE Array 输出之后，OFM Buffer 之前。它的主要任务是对 PE Array 计算出的 32-bit 累加结果进行非线性变换和压缩，使其适配下一层网络的输入要求。

### 功能列表
1.  **Activation (激活)**: ReLU ($y = \max(0, x)$)
2.  **Re-quantization (重量化)**: 将 INT32 数据压缩回 INT8。
    *   公式: $y = \text{clamp}(\text{floor}(x / 2^{\text{shift}}), -127, 127)$
    *   实现: 使用算术右移 `>>>` 实现 `floor` 逻辑。
3.  **Passthrough (直通模式)**: 用于中间结果累加（Tiling 过程中），保持 INT32 精度。

*注*: 根据项目需求，Bias 加法和 Batch Normalization 已移除。

## 2. 时序与流水线 (Timing & Pipeline)

**关键问题**: PPU 是否会破坏流水线时序？
**回答**: 不会破坏，但会**增加固定的流水线延迟 (Latency)**。

为了保证高频率运行 (e.g., 200MHz+)，PPU 内部采用全流水线设计。
*   **Stage 1**: Register / Control (1 cycle)
*   **Stage 2**: ReLU & Quantization / Clipping (1 cycle)
*   **Total Latency**: **2 Cycles**

### 对 Controller 的影响
由于 PPU 插入在 `Controller` 的 `psum_deskewed` 和 `OFM Buffer` 之间，Controller 内部用于同步写地址的 `PIPE_DEPTH` 参数必须增加 PPU 的延迟。

*   原 `PIPE_DEPTH` = Skew + Array + De-skew
*   新 `PIPE_DEPTH` = Skew + Array + De-skew + **PPU_LATENCY (2)**

## 3. 接口定义

| 信号名 | 方向 | 位宽 | 描述 |
| :--- | :--- | :--- | :--- |
| clk | Input | 1 | 时钟 |
| rst_n | Input | 1 | 同步复位 |
| en | Input | 1 | 使能信号 |
| **Control** | | | |
| mode_bypass | Input | 1 | 1: 直通 (INT32输出), 0: 处理 (INT8打包输出) |
| relu_en | Input | 1 | ReLU 使能 |
| quant_shift | Input | 4 | 量化右移位数 |
| **Data** | | | |
| psum_in | Input | 512 | 来自 PE Array 的 16x32-bit 数据 |
| result_out | Output | 512 | 处理后的数据 (16x32-bit 或 16x8-bit 扩展) |

*注意*: 为了简化 OFM Buffer 接口，即使是 INT8 结果，我们暂时也将其放在 32-bit 容器的低 8 位中输出，或者打包输出。本设计采用**保持 512-bit 总线宽度**，如果是 INT8 模式，则高 24 位补零或符号扩展，方便写入统一的 OFM Buffer。

## 4. Verilog 实现 (RTL)

见 `PPU.v`。
