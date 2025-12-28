// @audit-ok

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
                    .mode_max(mode_max),
                    
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