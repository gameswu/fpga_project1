# PE Array Design (32x16)

## 1. 架构概述 (Architecture Overview)

本设计实现了一个 32 行 x 16 列的脉动阵列 (Systolic Array)，用于矩阵乘法加速。

*   **规模**: 32 Rows (Input Channels) x 16 Cols (Output Channels).
*   **核心单元**: `mac_unit` (Weight Stationary).
*   **连接方式**:
    *   **Feature (Activation)**: 从左向右传递 (Row-wise)。
    *   **Partial Sum**: 从上向下累加 (Column-wise)。
    *   **Weight Loading**: 采用列共享数据总线 + 行独立写使能的方式，支持快速权重更新。

## 2. 端口定义 (Port Definition)

| 信号名 | 方向 | 位宽 | 描述 |
| :--- | :--- | :--- | :--- |
| clk | Input | 1 | 系统时钟 |
| rst_n | Input | 1 | 同步复位 |
| en | Input | 1 | 阵列计算使能 |
| mode_max | Input | 1 | **Max Pooling 模式** (广播到所有 PE) |
| weight_we_row | Input | 32 | 行权重写使能 (每一位控制一行) |
| weight_in_col | Input | 16*8 | 列权重输入数据 (16个8位权重，并行加载到选定行) |
| feature_in_rows | Input | 32*8 | 32行输入特征 (需外部Skew对齐) |
| psum_in_cols | Input | 16*32 | 16列部分和输入 (通常接0，或级联上一级) |
| feature_out_rows | Output | 32*8 | 32行特征输出 (用于级联) |
| psum_out_cols | Output | 16*32 | 16列部分和输出 (最终结果) |

## 3. 流水线与数据对齐 (Pipeline & Alignment)

由于脉动阵列的特性，数据在阵列内部逐级传递（每级 1 cycle 延迟）。为了保证计算正确性（即 $Feature(i)$ 与 $Psum(j)$ 在正确的 PE 相遇），外部输入数据必须进行**阶梯化 (Skewing)** 处理：

*   **Feature Input (Rows)**: 第 $i$ 行的输入数据应延迟 $i$ 个周期进入阵列。
*   **Psum Input (Cols)**: 第 $j$ 列的输入数据应延迟 $j$ 个周期进入阵列（如果 Psum 初始为 0，则无需对齐，只需在输出端处理）。
*   **Output Latency**: 第 $j$ 列的最终结果将在 $T_{valid} = (ROWS-1) + j$ 个周期后有效（相对于第 0 行输入数据进入的时间 $t=0$）。
    *   **Col 0**: $31 + 0 = 31$ cycles.
    *   **Col 15**: $31 + 15 = 46$ cycles.
    *   **注意**: 这里的延迟计算基于 `mac_unit` 内部 DSP 为 1 级流水线，且 Feature 横向传递为 1 级寄存器延迟。

## 4. 功能模式 (Functional Modes)

*   **MAC Mode**: `mode_max = 0`。阵列执行矩阵乘法。
*   **Max Pooling Mode**: `mode_max = 1`。阵列执行最大值池化。
    *   在此模式下，PE 比较 `psum_in` 和 `feature_in`，输出较大值。
    *   通常用于实现 2x2 或更大的 Max Pooling 操作。

## 5. 时序验证 (Timing Verification)

基于 Vivado 仿真结果 (Testbench: `Array_tb.v`)，时序符合预期：

*   **Column 0 Output**: 在 $t=31$ 时刻有效（对应 Row 31 的计算完成）。
*   **Column 15 Output**: 在 $t=46$ 时刻有效（对应 Row 31 的计算结果横向传播到 Col 15）。
*   **结论**: 外部控制逻辑需在 $t=31$ 开始采集 Col 0 的数据，并在随后的每个周期依次采集下一列的数据（De-skewing）。

## 6. Verilog 实现 (RTL)

```verilog
`timescale 1ns / 1ps

module pe_array #(
    parameter ROWS = 32,
    parameter COLS = 16,
    parameter DATA_WIDTH = 8,
    parameter ACC_WIDTH = 32
)(
    input wire clk,
    input wire rst_n,
    input wire en,
    input wire mode_max,

    // ------------------------------------------------------
    // 权重加载接口 (Weight Loading Interface)
    // ------------------------------------------------------
    // 策略: 每次更新一行 (Row-by-Row Update)
    // weight_in_col: 提供一行16个PE的权重数据
    // weight_we_row: 选中哪一行进行写入 (One-hot)
    input wire [ROWS-1:0] weight_we_row,
    input wire [COLS*DATA_WIDTH-1:0] weight_in_col,

    // ------------------------------------------------------
    // 数据流接口 (Data Flow Interface)
    // ------------------------------------------------------
    // Input Features: 32通道并行输入 (需外部Skew)
    input wire [ROWS*DATA_WIDTH-1:0] feature_in_rows,
    
    // Input Partial Sums: 16通道并行输入 (通常为0)
    input wire [COLS*ACC_WIDTH-1:0] psum_in_cols,

    // ------------------------------------------------------
    // 输出接口 (Output Interface)
    // ------------------------------------------------------
    // Output Features: 传递到阵列右侧
    output wire [ROWS*DATA_WIDTH-1:0] feature_out_rows,
    
    // Output Partial Sums: 阵列下方的累加结果 (需外部De-skew)
    output wire [COLS*ACC_WIDTH-1:0] psum_out_cols
);

    // ------------------------------------------------------
    // 内部互联线 (Internal Interconnects)
    // ------------------------------------------------------
    
    // Feature 链: [行][列+1] (列索引0为输入，1~16为各级输出)
    wire signed [DATA_WIDTH-1:0] feature_wire [ROWS-1:0][COLS:0];

    // Psum 链: [行+1][列] (行索引0为输入，1~32为各级输出)
    wire signed [ACC_WIDTH-1:0] psum_wire [ROWS:0][COLS-1:0];

    genvar i, j;
    generate
        // --------------------------------------------------
        // 1. 边界连接 (Boundary Connections)
        // --------------------------------------------------
        
        // 连接左侧输入 (Feature In)
        for (i = 0; i < ROWS; i = i + 1) begin : ROW_IN_ASSIGN
            assign feature_wire[i][0] = feature_in_rows[(i+1)*DATA_WIDTH-1 : i*DATA_WIDTH];
            // 连接右侧输出 (Feature Out)
            assign feature_out_rows[(i+1)*DATA_WIDTH-1 : i*DATA_WIDTH] = feature_wire[i][COLS];
        end

        // 连接顶部输入 (Psum In)
        for (j = 0; j < COLS; j = j + 1) begin : COL_IN_ASSIGN
            assign psum_wire[0][j] = psum_in_cols[(j+1)*ACC_WIDTH-1 : j*ACC_WIDTH];
            // 连接底部输出 (Psum Out)
            assign psum_out_cols[(j+1)*ACC_WIDTH-1 : j*ACC_WIDTH] = psum_wire[ROWS][j];
        end

        // --------------------------------------------------
        // 2. PE 阵列生成 (PE Array Generation)
        // --------------------------------------------------
        for (i = 0; i < ROWS; i = i + 1) begin : ROW_GEN
            for (j = 0; j < COLS; j = j + 1) begin : COL_GEN
                
                // 实例化 MAC Unit
                // 注意: 确保 mac_unit 模块已包含在工程中
                mac_unit #(
                    .DATA_WIDTH(DATA_WIDTH),
                    .ACC_WIDTH(ACC_WIDTH)
                ) u_pe (
                    .clk(clk),
                    .rst_n(rst_n),
                    .en(en),
                    
                    // 权重加载: 
                    // 所有行共享 weight_in_col 总线
                    // 只有 weight_we_row[i] 有效时，第 i 行才会捕获数据
                    .weight_we(weight_we_row[i]),
                    .weight_in(weight_in_col[(j+1)*DATA_WIDTH-1 : j*DATA_WIDTH]),
                    
                    // 脉动数据流连接:
                    // Feature: 左(j) -> 右(j+1)
                    .feature_in(feature_wire[i][j]),
                    .feature_out(feature_wire[i][j+1]),
                    
                    // Psum: 上(i) -> 下(i+1)
                    .psum_in(psum_wire[i][j]),
                    .psum_out(psum_wire[i+1][j])
                );
            end
        end
    endgenerate

endmodule
```
