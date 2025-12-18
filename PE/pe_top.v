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
    
    // Status Signals
    output wire        done,
    
    // =========================================================================
    // External Buffer Interfaces (Connected to BRAM IPs in Block Design)
    // =========================================================================
    
    // Weight Buffer Interface (Controller side - Read only)
    output wire [15:0] weight_mem_addr,
    input  wire [127:0] weight_mem_data,
    
    // Activation Buffer Interface (Controller side - Read only)
    output wire [15:0] input_mem_addr,
    input  wire [127:0] input_mem_data,
    
    // Partial Sum Buffer Interface (Read-Modify-Write with True Dual Port BRAM)
    // Split into Read (Port A) and Write (Port B) for streaming support
    output wire [9:0]  psum_raddr,         // Read Address
    output wire [9:0]  psum_waddr,         // Write Address
    input  wire [511:0] psum_rdata,        // Read data from BRAM
    output wire [511:0] psum_wdata,        // Write data to BRAM
    output wire        psum_wen            // Write enable
);

    // =========================================================================
    // Internal Signals
    // =========================================================================
    
    // Config -> Controller
    wire        start;
    wire        done_int; // Internal done signal
    wire [3:0]  kernel_h, kernel_w;
    wire [7:0]  input_h, input_w;
    wire [7:0]  input_channels, output_channels;
    wire [3:0]  stride, padding;
    wire [7:0]  output_h, output_w;
    
    assign done = done_int; // Output to top level
    
    // Controller -> Array
    wire        weight_write_enable;
    wire [3:0]  weight_col;
    wire [8*16-1:0]  weight_data;
    wire [127:0] pe_data_in;
    wire        pe_data_valid;
    
    // Controller -> BRAM (direct control)
    wire [9:0]  psum_raddr_ctrl;
    wire [9:0]  psum_waddr_ctrl;
    wire        psum_wen_ctrl;
    wire        psum_clear_ctrl;
    wire [511:0] pe_acc_out_buf;  // Buffered PE output from controller
    
    // Array -> Controller
    wire [511:0] pe_acc_out; // 16 * 32 (PE Array output)
    wire        pe_acc_out_valid;
    
    // Accumulator -> BRAM
    wire [511:0] psum_wdata_calc;
    
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
        .done(done_int),
        .kernel_h(kernel_h),
        .kernel_w(kernel_w),
        .input_h(input_h),
        .input_w(input_w),
        .stride(stride),
        .padding(padding),
        .output_h(output_h),
        .output_w(output_w),
        .input_channels(input_channels),
        .output_channels(output_channels)
    );
    
    // =========================================================================
    // PE Controller
    // =========================================================================
    // Controller now directly outputs BRAM control signals
    pe_controller #(
        .ARRAY_DIM(16)
    ) u_controller (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .done(done_int),
        .kernel_h(kernel_h),
        .kernel_w(kernel_w),
        .input_h(input_h),
        .input_w(input_w),
        .input_channels(input_channels),
        .stride(stride),
        .padding(padding),
        .output_h(output_h),
        .output_w(output_w),
        .output_channels(output_channels),
        .weight_write_enable(weight_write_enable),
        .weight_col(weight_col),
        .weight_data(weight_data),
        .pe_data_in(pe_data_in),
        .pe_data_valid(pe_data_valid),
        .psum_raddr(psum_raddr_ctrl),
        .psum_waddr(psum_waddr_ctrl),
        .psum_wen(psum_wen_ctrl),
        .psum_clear(psum_clear_ctrl),
        .pe_acc_out_buf_o(pe_acc_out_buf),
        .pe_acc_out(pe_acc_out),
        .pe_acc_out_valid(pe_acc_out_valid),
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
        .data_valid(pe_data_valid),
        .psum_out(pe_acc_out),
        .psum_out_valid(pe_acc_out_valid)
    );
    
    // =========================================================================
    // Partial Sum Accumulator (Computation Only)
    // =========================================================================
    // Pure combinational logic for accumulation calculation
    // Controller directly manages BRAM timing
    
    psum_accumulator #(
        .ARRAY_DIM(16),
        .ACC_WIDTH(32)
    ) u_psum_acc (
        .acc_clear(psum_clear_ctrl),
        .psum_in(pe_acc_out_buf),  // Use buffered output
        .rdata(psum_rdata),
        .wdata(psum_wdata_calc)
    );
    
    // Connect controller's BRAM control signals directly to top-level ports
    assign psum_raddr = psum_raddr_ctrl;
    assign psum_waddr = psum_waddr_ctrl;
    assign psum_wen = psum_wen_ctrl;
    assign psum_wdata = psum_wdata_calc;

endmodule
