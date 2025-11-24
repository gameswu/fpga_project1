/**
 * MAC Unit (Multiply-Accumulate Unit)
 * 
 * Description:
 *   Core computational unit for INT8 inference in DNN accelerator.
 *   Implements: Acc = Acc + (Input * Weight)
 *   
 * Features:
 *   - INT8 signed multiplication
 *   - INT32 accumulation to prevent overflow
 *   - Weight stationary design (weight register for reuse)
 *   - Synchronous reset and enable control
 *
 * Author: gameswu
 * Date: 2025-11-24
 */

module mac (
    // Clock and Reset
    input  wire        clk,           // System clock
    input  wire        rst_n,         // Active-low reset
    
    // Control Signals
    input  wire        enable,        // Enable MAC computation
    input  wire        acc_clear,     // Clear accumulator (synchronous)
    input  wire        weight_load,   // Load new weight into register
    
    // Data Inputs
    input  wire signed [7:0]  data_in,      // Input activation (INT8)
    input  wire signed [7:0]  weight_in,    // Weight data (INT8)
    
    // Data Output
    output reg  signed [31:0] acc_out       // Accumulator output (INT32)
);

    // =========================================================================
    // Internal Registers
    // =========================================================================
    
    // Weight register (stationary weight for reuse)
    reg signed [7:0] weight_reg;
    
    // Accumulator register (32-bit to prevent overflow)
    reg signed [31:0] accumulator;
    
    // Multiplication result (16-bit: 8-bit × 8-bit)
    wire signed [15:0] mult_result;
    
    // Next accumulator value (32-bit)
    wire signed [31:0] acc_next;
    
    
    // =========================================================================
    // Combinational Logic
    // =========================================================================
    
    // Signed multiplication: INT8 × INT8 = INT16
    assign mult_result = data_in * weight_reg;
    
    // Accumulation: INT32 + INT16 = INT32
    assign acc_next = accumulator + {{16{mult_result[15]}}, mult_result};
    
    
    // =========================================================================
    // Sequential Logic - Weight Register
    // =========================================================================
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            weight_reg <= 8'sd0;
        end
        else if (weight_load) begin
            weight_reg <= weight_in;
        end
    end
    
    
    // =========================================================================
    // Sequential Logic - Accumulator
    // =========================================================================
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            accumulator <= 32'sd0;
        end
        else if (acc_clear) begin
            accumulator <= 32'sd0;
        end
        else if (enable) begin
            accumulator <= acc_next;
        end
        // else: hold current value
    end
    
    
    // =========================================================================
    // Output Assignment
    // =========================================================================
    
    always @(*) begin
        acc_out = accumulator;
    end
    
endmodule
