# Vivado IP Configuration Guide

为了配合 Controller 和 PE Array 的工作，建议在 Vivado 中生成以下 BRAM IP 核。

## 1. Input Feature Map Buffer (IFM Buffer)
用于存储输入特征图数据。
*   **IP Name**: Block Memory Generator
*   **Interface Type**: Native
*   **Memory Type**: Simple Dual Port RAM (or True Dual Port)
*   **Port A (Write)**:
    *   Width: 32 bits (假设外部通过 32位 接口写入，或者根据系统总线调整)
    *   Depth: 根据需求 (e.g., 65536)
*   **Port B (Read - Connected to Controller)**:
    *   **Write Width**: 256 bits (32 channels * 8 bits)
    *   **Read Width**: 256 bits
    *   **Operating Mode**: Read First
    *   **Enable Port Type**: Use ENB Pin
    *   **Output Reset Value**: 0
    *   **Primitives Output Register**: Checked (这是造成 2 cycle latency 的主要原因之一，有助于时序)
    *   **Core Output Register**: Checked (可选，增加一级流水线，总延迟变为 3 cycle，本设计假设总延迟为 2)

## 2. Weight Buffer
用于存储权重数据。
*   **IP Name**: Block Memory Generator
*   **Memory Type**: Simple Dual Port RAM
*   **Port B (Read - Connected to Controller)**:
    *   **Read Width**: 128 bits (16 filters * 8 bits) - *注意：Controller 设计为一次加载一行权重（16个），共加载 32 行*
    *   **Latency**: 2 cycles (Output Registers enabled)

## 3. Output Feature Map Buffer (OFM Buffer)
用于存储部分和 (Partial Sum) 及最终结果。
*   **IP Name**: Block Memory Generator
*   **Memory Type**: True Dual Port RAM
*   **Port A (Write Only - Connected to Controller)**:
    *   **Write Width**: 512 bits (16 channels * 32 bits)
    *   **Enable Port Type**: Use ENA Pin
    *   **Write Enable**: Uncheck "Byte Write Enable" (Use single bit WE). If checked, ensure wrapper drives all bits.
    *   **Operating Mode**: No Change (Write Only)
*   **Port B (Read Only - Shared by Controller and Host)**:
    *   **Read Width**: 512 bits (CRITICAL: Must be 512 bits to support parallel accumulation)
    *   **Latency**: 2 cycles (Output Registers enabled)
    *   **Enable Port Type**: Use ENB Pin
    *   **Operating Mode**: Read First

## 4. FIFO IP (Optional)
本 Controller 设计内部实现了 Skew/De-skew 逻辑，**不需要** 额外的 FIFO IP 来处理脉动阵列的数据对齐。
如果系统接口（如 AXI）与 Controller 之间存在跨时钟域或速率不匹配，可以使用 **FIFO Generator**。
