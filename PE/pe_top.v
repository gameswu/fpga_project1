/**
 * PE System Top Level
 * 
 * Description:
 *   Integrates the PE Controller, PE Array, and Configuration Registers.
 *   Buffers are external (connected via BRAM IPs in Block Design).
 *   Provides computation engine with external memory interfaces.
 *
 * Author: shelligh
 * Date: 2025-12-11
 * Modified: 2025-12-15 - Externalized buffers to Block Design BRAM IPs
 */

module pe_top (
    input  wire        clk,
    input  wire        rst_n,
    
    // =========================================================================
    // Configuration Interface (32-bit)
    // =========================================================================
    input  wire        cfg_we,
    input  wire [3:0]  cfg_addr,
    input  wire [31:0] cfg_wdata,
    output wire [31:0] cfg_rdata,
    
    // =========================================================================
    // External Buffer Interfaces (Connected to BRAM IPs in Block Design)
    // =========================================================================
    
    // Weight Buffer Interface (Controller side - Read only)
    output wire [15:0] weight_mem_addr,
    input  wire [127:0] weight_mem_data,
    
    // Activation Buffer Interface (Controller side - Read only)
    output wire [15:0] input_mem_addr,
    input  wire [127:0] input_mem_data,
    
    // Partial Sum Buffer Interface (Write-only for final results)
    output wire [9:0]  psum_waddr,         // Write address
    output wire [511:0] psum_wdata,        // Write data (final results from PE array)
    output wire        psum_wen            // Write enable
);

    // =========================================================================
    // Internal Signals
    // =========================================================================
    
    // Config -> Controller
    wire        start;
    wire        done;
    wire [3:0]  kernel_h, kernel_w;
    wire [7:0]  input_h, input_w;
    wire [3:0]  stride, padding;
    wire [7:0]  output_h, output_w;
    
    // Controller -> Array
    wire        weight_write_enable;
    wire [3:0]  weight_col;
    wire [8*16-1:0]  weight_data;
    wire [127:0] pe_data_in;
    
    // Controller -> Psum
    wire        psum_acc_enable;
    wire        psum_acc_clear;
    wire [9:0]  psum_acc_addr;
    
    // Array -> Psum accumulator
    wire [511:0] pe_acc_out; // 16 * 32 (PE Array output)
    
    // =========================================================================
    // Module Instantiations
    // =========================================================================
    
    // 1. Configuration Registers
    config_regs u_config (
        .clk(clk),
        .rst_n(rst_n),
        .reg_write(cfg_we),
        .reg_addr(cfg_addr),
        .reg_wdata(cfg_wdata),
        .reg_rdata(cfg_rdata),
        .start(start),
        .done(done),
        .kernel_h(kernel_h),
        .kernel_w(kernel_w),
        .input_h(input_h),
        .input_w(input_w),
        .stride(stride),
        .padding(padding),
        .output_h(output_h),
        .output_w(output_w)
    );
    
    // =========================================================================
    // PE Controller
    // =========================================================================
    // Note: Buffers are external BRAM IPs connected via top-level ports
    pe_controller #(
        .ARRAY_DIM(16)
    ) u_controller (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .done(done),
        .kernel_h(kernel_h),
        .kernel_w(kernel_w),
        .input_h(input_h),
        .input_w(input_w),
        .stride(stride),
        .padding(padding),
        .output_h(output_h),
        .output_w(output_w),
        .weight_write_enable(weight_write_enable),
        .weight_col(weight_col),
        .weight_data(weight_data),
        .pe_data_in(pe_data_in),
        .acc_enable(psum_acc_enable),
        .acc_clear(psum_acc_clear),
        .acc_addr(psum_acc_addr),
        .pe_acc_out(pe_acc_out),
        .weight_mem_addr(weight_mem_addr),
        .weight_mem_data(weight_mem_data),
        .input_mem_addr(input_mem_addr),
        .input_mem_data(input_mem_data)
    );
    
    // 5. PE Array
    pe_array #(
        .ARRAY_DIM(16),
        .DATA_WIDTH(8),
        .ACC_WIDTH(32)
    ) u_array (
        .clk(clk),
        .rst_n(rst_n),
        .weight_write_enable(weight_write_enable),
        .weight_col(weight_col),
        .weight_in(weight_data),
        .data_in(pe_data_in),
        .psum_out(pe_acc_out)
    );
    
    // =========================================================================
    // =========================================================================
    // Partial Sum Output Logic
    // =========================================================================
    // PE array already performs accumulation internally via MAC psum_in/out chain.
    // Here we just write the final results to external BRAM.
    // Add pipeline delay to match timing requirements.
    
    reg [9:0]   psum_addr_d1, psum_addr_d2;
    reg         psum_enable_d1, psum_enable_d2;
    reg [511:0] psum_data_d1, psum_data_d2;
    
    always @(posedge clk) begin
        if (!rst_n) begin
            psum_addr_d1 <= 0;
            psum_addr_d2 <= 0;
            psum_enable_d1 <= 0;
            psum_enable_d2 <= 0;
            psum_data_d1 <= 0;
            psum_data_d2 <= 0;
        end else begin
            // 2-stage pipeline for timing
            psum_addr_d1 <= psum_acc_addr;
            psum_enable_d1 <= psum_acc_enable;
            psum_data_d1 <= pe_acc_out;
            
            psum_addr_d2 <= psum_addr_d1;
            psum_enable_d2 <= psum_enable_d1;
            psum_data_d2 <= psum_data_d1;
        end
    end
    
    // Connect to external BRAM (delayed signals)
    assign psum_waddr = psum_addr_d2;
    assign psum_wdata = psum_data_d2;
    assign psum_wen = psum_enable_d2;

endmodule
