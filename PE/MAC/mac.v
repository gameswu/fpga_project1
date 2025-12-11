/**
 * MAC Unit (Multiply-Accumulate Unit) - Weight Stationary Version
 * 
 * Description:
 *   Core computational unit for INT8 inference.
 *   Supports Weight Stationary dataflow with external Partial Sum accumulation.
 *   
 *   Operation:
 *   Psum_out = Psum_in + (Data_in * Weight_reg)
 *   
 * Features:
 *   - INT8 signed multiplication
 *   - INT32 accumulation
 *   - Weight stationary design (weight register for reuse)
 *   - External Partial Sum chaining/buffering support
 *
 * Author: gameswu
 * Date: 2025-11-24
 */

module mac (
    // Clock and Reset
    input  wire        clk,           // System clock
    input  wire        rst_n,         // Active-low reset
    
    // Control Signals
    input  wire        weight_load,   // Load new weight into register
    
    // Data Inputs
    input  wire signed [7:0]  data_in,      // Input activation (INT8)
    input  wire signed [7:0]  weight_in,    // Weight data (INT8)
    input  wire signed [31:0] psum_in,      // Partial Sum Input (from Buffer)
    
    // Data Output
    output reg  signed [31:0] psum_out      // Partial Sum Output (to Buffer)
);

    // =========================================================================
    // Internal Registers
    // =========================================================================
    
    // Weight register (stationary weight for reuse)
    reg signed [7:0] weight_reg;
    
    // Multiplication result
    wire signed [15:0] mult_result;
    
    
    // =========================================================================
    // Combinational Logic
    // =========================================================================
    
    // Signed multiplication: INT8 × INT8 = INT16
    assign mult_result = data_in * weight_reg;
    
    
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
    // Sequential Logic - Computation Pipeline
    // =========================================================================
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            psum_out <= 32'sd0;
        end
        else begin
            // Calculate and register output
            // Psum_out = Psum_in + (Input * Weight)
            psum_out <= psum_in + {{16{mult_result[15]}}, mult_result};
        end
    end
    
endmodule
