// @audit-ok

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
    // assign psum_out = dsp_p[ACC_WIDTH-1:0];

    // Max Pooling Logic
    wire signed [ACC_WIDTH-1:0] feature_in_ext = $signed(feature_in);
    wire signed [ACC_WIDTH-1:0] max_val = (psum_in > feature_in_ext) ? psum_in : feature_in_ext;
    
    // Register for Max Pooling Result to match DSP latency (1 cycle)
    reg signed [ACC_WIDTH-1:0] max_val_reg;
    always @(posedge clk) begin
        if (!rst_n) begin
            max_val_reg <= 0;
        end else if (en) begin
            max_val_reg <= max_val;
        end
    end
    
    assign psum_out = mode_max ? max_val_reg : dsp_p[ACC_WIDTH-1:0];

    // 实例化 Vivado DSP Macro IP
    dsp_macro_0 u_dsp_core (
        .CLK(clk),
        .CEP(en),            // Clock Enable
        .SCLRP(!rst_n),      // Synchronous Clear (注意：IP 通常是高电平复位，这里取反)
        .A(dsp_a),          // Input A
        .B(dsp_b),          // Input B
        .C(dsp_c),          // Input C
        .P(dsp_p)           // Output P = A*B + C
    );

endmodule