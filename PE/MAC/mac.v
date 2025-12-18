/**
 * MAC Unit (Multiply-Accumulate Unit) - Behavioral Model for Debug
 * 
 * Description:
 *   Pure Verilog implementation of Psum_out = Psum_in + (Data_in * Weight_reg)
 *   Used to verify logic correctness without DSP IP complexity.
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
    output wire signed [31:0] psum_out      // Partial Sum Output (Registered)
);

    // =========================================================================
    // Behavioral Implementation (Replaces DSP IP)
    // =========================================================================
    
    // 1. Weight Register (Simulates DSP B-Register)
    reg signed [7:0] weight_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            weight_reg <= 8'd0;
        end else if (weight_load) begin
            weight_reg <= weight_in;
        end
    end

    // 2. Multiply-Accumulate Logic with Output Register (Simulates DSP P-Register)
    // Latency: 1 cycle (Input -> Output)
    // Logic: P_next = (A * B_reg) + C
    reg signed [31:0] psum_out_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            psum_out_reg <= 32'd0;
        end else begin
            // Verilog handles sign extension automatically for 'signed' types
            psum_out_reg <= (data_in * weight_reg) + psum_in;
        end
    end

    assign psum_out = psum_out_reg;
    
    // =========================================================================
    // DSP IP Instantiation (Commented Out)
    // =========================================================================

    /*
    mac_dsp_wrapper u_mac_dsp (
        .CLK_0(clk),
        
        // Data Path (Direct connection, no register)
        .A_0(data_in),
        
        // Weight Path (Registered, controlled by weight_load)
        .CEB3_0(weight_load),
        .B_0(weight_in),
        
        // Psum Path (Direct connection, no register)
        .C_0(psum_in),
        
        // Output Path (Registered, always enabled)
        .CEP_0(1'b1),
        .P_0(psum_out), // Connect to 32-bit output
        
        // Reset (Synchronous Clear for P register)
        .SCLRP_0(~rst_n) 
    );
    */

endmodule
