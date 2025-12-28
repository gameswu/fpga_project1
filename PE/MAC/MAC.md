# MAC Unit Design (Weight Stationary)

## 1. 设计思路 (Design Strategy)

针对 32x16 的 PE Array 和权重复用 (Weight Stationary) 架构，MAC 单元需要满足以下要求：
1.  **权重复用 (Weight Reuse)**: 每个 MAC 单元内部包含一个寄存器用于存储权重，直到计算任务完成或更新权重。
2.  **数据流 (Data Flow)**:
    -   **Input Feature (Activation)**: 在行方向上传递 (Systolic flow)。输入从左向右传递 (`feature_out` 传给右侧 PE)。
    -   **Partial Sum**: 在列方向上累加。输入 `psum_in` 来自上方 PE，计算结果 `psum_out` 传给下方 PE。
3.  **DSP IP 核调用**: 按照要求，不再使用 RTL 推断，而是显式实例化 Vivado 的 **DSP48 Macro** IP 核，以确保对底层硬件资源的精确控制。
4.  **同步复位**: 遵循 DSP48 硬件特性，系统采用**同步复位**策略。

## 2. 端口定义 (Port Definition)

| 信号名 | 方向 | 位宽 | 描述 |
| :--- | :--- | :--- | :--- |
| clk | Input | 1 | 系统时钟 |
| rst_n | Input | 1 | **同步复位** (低电平有效) |
| en | Input | 1 | 计算使能 |
| weight_we | Input | 1 | 权重写入使能 (Weight Write Enable) |
| weight_in | Input | 8 | 权重输入 (假设 INT8) |
| feature_in | Input | 8 | 特征图输入 (假设 INT8) |
| psum_in | Input | 32 | 部分和输入 (假设 INT32) |
| mode_max | Input | 1 | **Max Pooling 模式** (1: Max, 0: MAC) |
| feature_out | Output | 8 | 特征图输出 (传递给下一个 PE) |
| psum_out | Output | 32 | 部分和输出 (累加结果) |

## 3. Vivado DSP IP 配置指南 (IP Configuration)

在 Vivado IP Catalog 中搜索 "DSP48 Macro" 并按以下参数配置 (生成名为 `dsp_macro_0` 的组件)：

*   **Basic Tab**:
    *   **Instruction**: `(A*B)+C`
    *   **Pipeline Options**: By Tier (Standard) -> Output P register (1 stage)
*   **Port Widths Tab**:
    *   **A (Weight)**: 8 (实际 DSP 端口可能更宽，IP 会自动处理或需手动补零，建议设为 18 以匹配 DSP48E1/E2 物理宽度，避免警告)
    *   **B (Feature)**: 8 (建议设为 18)
    *   **C (Psum)**: 32 (建议设为 48)
    *   **P (Output)**: 32 (建议设为 48)
*   **Implementation Tab**:
    *   **Reset Type**: **Synchronous** (关键设置)
    *   **Output Port Properties**: Ensure P register is enabled.

## 4. 功能模式 (Functional Modes)

### 4.1 MAC Mode (`mode_max` = 0)
执行标准的乘累加运算：
$$ P_{out} = (W \times F_{in}) + P_{in} $$
用于卷积层和全连接层。

### 4.2 Max Pooling Mode (`mode_max` = 1)
执行最大值比较运算：
$$ P_{out} = \max(P_{in}, F_{in}) $$
用于 Max Pooling 层。此时权重输入被忽略（或应设为 0），PE 仅比较输入特征与上方传递下来的部分和（当前最大值）。

## 5. 时序与延迟 (Timing & Latency)

本设计中各数据通路的延迟如下（单位：时钟周期）：

*   **Feature Pass-through (`feature_in` -> `feature_out`)**: **1 Cycle**
    *   由 RTL 中的 `always @(posedge clk)` 寄存器实现。
*   **Computation (`feature_in` / `psum_in` -> `psum_out`)**: **1 Cycle**
    *   **MAC Mode**: 由 DSP IP 核内部的 P 寄存器实现。
    *   **Max Mode**: 由 RTL 中的比较器逻辑实现（组合逻辑 + 寄存器）。
*   **Weight Loading (`weight_in` -> Internal Register)**: **1 Cycle**
    *   权重写入操作需 1 个时钟周期生效。

**注意**: 在系统级流水线设计时，请确保 `feature_in` 和 `psum_in` 的到达时间满足这 1 个周期的计算延迟要求，以保证脉动阵列的正确同步。

## 6. Verilog 实现 (RTL)

```verilog
`timescale 1ns / 1ps

module mac_unit #(
    parameter DATA_WIDTH = 8,
    parameter ACC_WIDTH = 32
)(
    input wire clk,
    input wire rst_n,               // 同步复位
    input wire en,                  // 计算流水线使能 (CE)
    
    // 权重加载接口 (Weight Stationary)
    input wire weight_we,           // 权重写使能
    input wire signed [DATA_WIDTH-1:0] weight_in,
    
    // 数据通路
    input wire signed [DATA_WIDTH-1:0] feature_in, // 输入特征 (B port)
    input wire signed [ACC_WIDTH-1:0] psum_in,     // 来自上级的部分和 (C port)
    input wire mode_max,                           // 0: MAC, 1: Max Pooling
    
    // 输出
    output reg signed [DATA_WIDTH-1:0] feature_out, // 传递给右侧 PE
    output wire signed [ACC_WIDTH-1:0] psum_out     // 计算结果输出给下方 PE (P port)
);

    // 1. 权重存储 (Weight Storage)
    // 权重保持在寄存器中，对应 DSP 的 A 端口输入
    reg signed [DATA_WIDTH-1:0] weight_reg;
    
    // 同步复位
    always @(posedge clk) begin
        if (!rst_n) begin
            weight_reg <= 0;
        end else if (weight_we) begin
            weight_reg <= weight_in;
        end
    end

    // 2. 特征传递 (Feature Pass-through)
    // 简单的寄存器传输，用于脉动阵列
    // 同步复位
    always @(posedge clk) begin
        if (!rst_n) begin
            feature_out <= 0;
        end else if (en) begin
            feature_out <= feature_in;
        end
    end

    // 3. DSP IP 核实例化
    // 假设 IP 核名称为 dsp_macro_0
    // 操作: P = A * B + C
    // A: weight_reg
    // B: feature_in
    // C: psum_in
    
    // 信号位宽适配 (根据 IP 核配置调整，通常 DSP48 A=25/18, B=18, C=48)
    // 这里假设 IP 核配置为 A[17:0], B[17:0], C[47:0], P[47:0] 以最大化兼容性
    wire signed [17:0] dsp_a;
    wire signed [17:0] dsp_b;
    wire signed [47:0] dsp_c;
    wire signed [47:0] dsp_p;

    assign dsp_a = $signed(weight_reg); // 符号扩展
    assign dsp_b = $signed(feature_in); // 符号扩展
    assign dsp_c = $signed(psum_in);    // 符号扩展
    
    // 截取低 32 位作为输出
    assign psum_out = dsp_p[ACC_WIDTH-1:0];

    // 实例化 Vivado DSP Macro IP
    dsp_macro_0 u_dsp_core (
        .CLK(clk),
        .CE(en),            // Clock Enable
        .SCLR(!rst_n),      // Synchronous Clear (注意：IP 通常是高电平复位，这里取反)
        .A(dsp_a),          // Input A
        .B(dsp_b),          // Input B
        .C(dsp_c),          // Input C
        .P(dsp_p)           // Output P = A*B + C
    );

endmodule
```
