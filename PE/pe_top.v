/**
 * PE System Top Level
 * 
 * Description:
 *   Integrates the PE Controller, PE Array, Buffers, and Configuration Registers.
 *   Provides a unified interface for configuration and data loading.
 *
 * Author: shelligh
 * Date: 2025-12-11
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
    // Weight Loader Interface
    // =========================================================================
    input  wire        weight_load_we,
    input  wire [15:0] weight_load_addr,
    input  wire [127:0] weight_load_data,
    
    // =========================================================================
    // Activation Loader Interface
    // =========================================================================
    input  wire        act_load_we,
    input  wire [15:0] act_load_addr,
    input  wire [127:0] act_load_data,
    
    // =========================================================================
    // Result Interface (Partial Sum Buffer Readout)
    // =========================================================================
    // For simplicity, we expose the buffer read port directly or via a bus?
    // Let's expose a simple read port for the testbench.
    input  wire [9:0]   res_addr,
    output wire [511:0] res_data // 16 * 32-bit
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
    
    // Controller -> Buffers
    wire [15:0] weight_mem_addr;
    wire [16*8-1:0] weight_mem_data;
    
    wire [15:0] input_mem_addr;
    wire [127:0] input_mem_data;
    
    // Controller -> Array
    wire        weight_write_enable;
    wire [3:0]  weight_col;
    wire [8*16-1:0]  weight_data;
    wire [127:0] pe_data_in;
    
    // Controller -> Psum Buffer
    wire        acc_enable;
    wire        acc_clear;
    wire [9:0]  acc_addr;
    
    // Mux for Psum Buffer Address
    wire [9:0]  psum_buf_addr;
    assign psum_buf_addr = (done) ? res_addr : acc_addr;

    // Array -> Psum Buffer
    wire [511:0] pe_acc_out; // 16 * 32
    
    // Psum Buffer -> Array (Feedback? No, Psum Buffer is the accumulator)
    // The array outputs psum_out. The buffer accumulates it.
    // Wait, the array is Weight Stationary. It produces partial sums.
    // The buffer reads old psum, adds new psum, writes back.
    // The buffer logic is inside psum_buffer.v.
    
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
    
    // 2. Weight Buffer
    weight_buffer #(
        .DATA_WIDTH(128),
        .ADDR_WIDTH(16),
        .DEPTH(65536)
    ) u_weight_buf (
        .clk(clk),
        .we_a(weight_load_we),
        .addr_a(weight_load_addr),
        .wdata_a(weight_load_data),
        .addr_b(weight_mem_addr),
        .rdata_b(weight_mem_data)
    );
    
    // 3. Activation Buffer
    act_buffer #(
        .DATA_WIDTH(128),
        .ADDR_WIDTH(16),
        .DEPTH(65536)
    ) u_act_buf (
        .clk(clk),
        .we_a(act_load_we),
        .addr_a(act_load_addr),
        .wdata_a(act_load_data),
        .addr_b(input_mem_addr),
        .rdata_b(input_mem_data)
    );
    
    // 4. PE Controller
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
        .acc_enable(acc_enable),
        .acc_clear(acc_clear),
        .acc_addr(acc_addr),
        .pe_acc_out(pe_acc_out), // This is actually INPUT to controller? No, controller doesn't take psum.
                                 // Controller generates addresses.
                                 // Wait, pe_controller definition has 'input [..] pe_acc_out'.
                                 // Let's check pe_controller.v again.
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
    
    // 6. Partial Sum Buffer
    psum_buffer #(
        .ARRAY_DIM(16),
        .ACC_WIDTH(32),
        .DEPTH(1024)
    ) u_psum_buf (
        .clk(clk),
        .rst_n(rst_n),
        .acc_enable(acc_enable),
        .acc_clear(acc_clear),
        .addr(psum_buf_addr),
        .psum_in(pe_acc_out),
        .final_out(res_data)
    );
    
    // Note: pe_controller has an input 'pe_acc_out'.
    // In the previous testbench, it was connected to the array output.
    // But the controller doesn't seem to USE it?
    // Let's check pe_controller.v.
    // It has: input wire [ARRAY_DIM*32-1:0] pe_acc_out
    // But inside the module, is it used?
    // I suspect it's unused or used for monitoring.
    // I'll connect it to pe_acc_out (from array) just in case.

endmodule
