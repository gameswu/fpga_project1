`timescale 1ns / 1ps

module tb_common;

// Common Testbench Setup for DNN_Wrapper
// Instantiated by specific layer testbenches

reg sys_clk;
reg sys_rst_n;

// External Interface
reg [31:0] cmd_addr;
reg [31:0] cmd_wdata;
wire [31:0] cmd_rdata;
reg cmd_we;
reg cmd_re;
wire intr;

// Clock Generation
initial begin
    sys_clk = 0;
    forever #5 sys_clk = ~sys_clk; // 100MHz
end

// DUT Instantiation
DNN_Wrapper u_dut (
    .sys_clk(sys_clk),
    .sys_rst_n(sys_rst_n),
    .cmd_addr(cmd_addr),
    .cmd_wdata(cmd_wdata),
    .cmd_rdata(cmd_rdata),
    .cmd_we(cmd_we),
    .cmd_re(cmd_re),
    .intr(intr)
);

// Tasks
task write_csr(input [31:0] addr, input [31:0] data);
    begin
        @(posedge sys_clk);
        cmd_addr = addr;
        cmd_wdata = data;
        cmd_we = 1;
        cmd_re = 0;
        @(posedge sys_clk);
        cmd_we = 0;
    end
endtask

task read_csr(input [31:0] addr, output [31:0] data);
    begin
        @(posedge sys_clk);
        cmd_addr = addr;
        cmd_we = 0;
        cmd_re = 1;
        @(posedge sys_clk);
        // Wait for BRAM latency (2 cycles)
        repeat(2) @(posedge sys_clk);
        // Wait for data
        data = cmd_rdata;
        cmd_re = 0;
    end
endtask

// Helper to write 32-bit word to IFM (External Interface)
task write_ifm_word(input [31:0] word_addr, input [31:0] data);
    begin
        // Address mapping: 0x0010_0000 base.
        // word_addr is index of 32-bit word.
        write_csr(32'h00100000 | (word_addr << 2), data);
    end
endtask

// Helper to write 32-bit word to Weight (External Interface)
task write_wgt_word(input [31:0] word_addr, input [31:0] data);
    begin
        write_csr(32'h00200000 | (word_addr << 2), data);
    end
endtask

// Helper to read 32-bit word from Weight (External Interface)
task read_wgt_word(input [31:0] word_addr, output [31:0] data);
    begin
        read_csr(32'h00200000 | (word_addr << 2), data);
    end
endtask

// Helper to read 32-bit word from OFM (External Interface)
task read_ofm_word(input [31:0] word_addr, output [31:0] data);
    begin
        read_csr(32'h00300000 | (word_addr << 2), data);
    end
endtask

// Reset Task
task reset_system;
    begin
        sys_rst_n = 0;
        cmd_we = 0;
        cmd_re = 0;
        cmd_addr = 0;
        cmd_wdata = 0;
        repeat(10) @(posedge sys_clk);
        sys_rst_n = 1;
        repeat(10) @(posedge sys_clk);
    end
endtask

endmodule
