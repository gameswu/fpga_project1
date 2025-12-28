// @audit-ok

`timescale 1ns / 1ps

module ppu #(
    parameter NUM_CHANNELS = 16,
    parameter DATA_WIDTH = 32
)(
    input wire clk,
    input wire rst_n,
    input wire en,
    
    // Control Flags
    input wire is_first,        // 1: Ignore acc_in (Overwrite), 0: Add acc_in (Accumulate)
    input wire is_last,         // 1: Apply ReLU+Quant, 0: Output Raw Sum
    
    // Configuration
    input wire relu_en,
    input wire [4:0] quant_shift,
    input wire mode_max, // Added for Max Pooling
    
    // Data Streams
    input wire [NUM_CHANNELS*DATA_WIDTH-1:0] psum_in, // From PE Array
    input wire [NUM_CHANNELS*DATA_WIDTH-1:0] acc_in,  // From OFM Buffer (Old Sum)
    
    // Output
    output wire [NUM_CHANNELS*DATA_WIDTH-1:0] result_out
);

    // Unpack inputs
    wire signed [31:0] psum [NUM_CHANNELS-1:0];
    wire signed [31:0] acc  [NUM_CHANNELS-1:0];
    
    genvar i;
    generate
        for (i = 0; i < NUM_CHANNELS; i = i + 1) begin : UNPACK
            assign psum[i] = psum_in[(i+1)*32-1 : i*32];
            assign acc[i]  = acc_in[(i+1)*32-1 : i*32];
        end
    endgenerate

    // ------------------------------------------------------
    // Pipeline Stage 1: Accumulation
    // ------------------------------------------------------
    reg signed [31:0] stage1_sum [NUM_CHANNELS-1:0];
    reg stage1_is_last;
    reg stage1_relu;
    reg [4:0] stage1_shift;
    reg stage1_mode_max;
    
    integer k;
    always @(posedge clk) begin
        if (!rst_n) begin
            for (k=0; k<NUM_CHANNELS; k=k+1) stage1_sum[k] <= 0;
            stage1_is_last <= 0;
            stage1_relu <= 0;
            stage1_shift <= 0;
            stage1_mode_max <= 0;
        end else if (en) begin
            // Pass control signals
            stage1_is_last <= is_last;
            stage1_relu    <= relu_en;
            stage1_shift   <= quant_shift;
            stage1_mode_max <= mode_max;
            
            for (k=0; k<NUM_CHANNELS; k=k+1) begin
                if (is_first)
                    stage1_sum[k] <= psum[k];
                else begin
                    if (mode_max)
                        stage1_sum[k] <= (psum[k] > acc[k]) ? psum[k] : acc[k];
                    else
                        stage1_sum[k] <= psum[k] + acc[k];
                end
            end
        end
    end

    // ------------------------------------------------------
    // Pipeline Stage 2: ReLU & Quantization
    // ------------------------------------------------------
    reg [NUM_CHANNELS*32-1:0] stage2_out;
    
    // Temporary variables
    reg signed [31:0] val;
    reg signed [31:0] q_val;
    
    always @(posedge clk) begin
        if (!rst_n) begin
            stage2_out <= 0;
        end else if (en) begin
            for (k=0; k<NUM_CHANNELS; k=k+1) begin
                val = stage1_sum[k];
                
                if (!stage1_is_last) begin
                    // Not last: Output Raw Sum (INT32)
                    stage2_out[k*32 +: 32] <= val;
                end else begin
                    // Last: Apply ReLU + Quant
                    
                    // 1. ReLU
                    if (stage1_relu && val < 0) 
                        val = 0;
                        
                    // 2. Quantization (Shift)
                    q_val = val >>> stage1_shift;
                    
                    // 3. Clip to INT8 (-127 to 127)
                    if (q_val > 127) q_val = 127;
                    else if (q_val < -127) q_val = -127;
                    
                    stage2_out[k*32 +: 32] <= q_val; 
                end
            end
        end
    end

    assign result_out = stage2_out;

endmodule
