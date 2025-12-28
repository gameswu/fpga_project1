// @audit-ok

`timescale 1ns / 1ps

module DNN_Top (
    input wire sys_clk,
    input wire sys_rst_n,
    
    // External Memory Mapped Interface (32-bit)
    input wire [31:0] cmd_addr,
    input wire [31:0] cmd_wdata,
    output reg [31:0] cmd_rdata,
    input wire cmd_we,
    input wire cmd_re,
    output wire intr,

    // BRAM Ports (To be connected to IP)
    // IFM BRAM (Port A)
    output wire [31:0] bram_ifm_addr,
    output wire [255:0] bram_ifm_wdata,
    output wire [31:0] bram_ifm_we,
    output wire bram_ifm_en,
    input wire [255:0] bram_ifm_rdata,
    
    // Weight BRAM (Port A)
    output wire [31:0] bram_wgt_addr,
    output wire [127:0] bram_wgt_wdata,
    output wire [15:0] bram_wgt_we,
    output wire bram_wgt_en,
    input wire [127:0] bram_wgt_rdata,
    
    // OFM BRAM (Port A - Write)
    output wire [31:0] bram_ofm_waddr,
    output wire [511:0] bram_ofm_wdata,
    output wire bram_ofm_we,
    output wire bram_ofm_en_a,
    
    // OFM BRAM (Port B - Read)
    output wire [31:0] bram_ofm_raddr,
    output wire bram_ofm_en_b,
    input wire [511:0] bram_ofm_rdata
);

    // ------------------------------------------------------
    // Internal Signals
    // ------------------------------------------------------
    wire busy;
    wire done;
    wire mode_max; // Added missing signal
    reg start_reg;
    
    // Configuration Registers
    reg [15:0] cfg_ifm_h, cfg_ifm_w;
    reg [15:0] cfg_ofm_h, cfg_ofm_w;
    reg [15:0] cfg_ic, cfg_oc;
    reg [3:0]  cfg_kh, cfg_kw;
    reg [3:0]  cfg_stride, cfg_pad;
    reg        cfg_relu_en;
    reg [4:0]  cfg_quant_shift;
    reg        cfg_is_max_pool;

    // Controller Interface
    wire [31:0] ctrl_ifm_addr;
    wire ctrl_ifm_rd_en;
    wire [255:0] ctrl_ifm_rdata;
    
    wire [31:0] ctrl_wgt_addr;
    wire ctrl_wgt_rd_en;
    wire [127:0] ctrl_wgt_rdata;
    
    wire [31:0] ctrl_ofm_addr;
    wire ctrl_ofm_wr_en;
    wire [31:0] ctrl_ofm_raddr;
    wire ctrl_ofm_rd_en;
    wire [511:0] ctrl_ofm_rdata;
    wire [511:0] ctrl_ofm_wdata;
    
    wire pe_en;
    wire [31:0] weight_we_row;
    wire [255:0] feature_to_pe;
    wire [511:0] psum_from_pe;

    // ------------------------------------------------------
    // Register File & Command Decoder
    // ------------------------------------------------------
    // Address Map:
    // 0x00: Control (Start)
    // 0x04: Status (Busy, Done)
    // 0x10+: Configs
    
    always @(posedge sys_clk) begin
        if (!sys_rst_n) begin
            start_reg <= 0;
            cfg_ifm_h <= 0; cfg_ifm_w <= 0;
            cfg_ofm_h <= 0; cfg_ofm_w <= 0;
            cfg_ic <= 0; cfg_oc <= 0;
            cfg_kh <= 0; cfg_kw <= 0;
            cfg_stride <= 0; cfg_pad <= 0;
            cfg_relu_en <= 0; cfg_quant_shift <= 0;
            cfg_is_max_pool <= 0;
        end else begin
            // Auto-clear start
            if (start_reg) start_reg <= 0;
            
            // CSR Write (Only if address is in CSR range 0x0000_XXXX)
            if (cmd_we && !busy && cmd_addr[31:16] == 16'h0000) begin
                case (cmd_addr[15:0])
                    16'h0000: start_reg <= cmd_wdata[0];
                    16'h0010: cfg_ifm_h <= cmd_wdata[15:0];
                    16'h0014: cfg_ifm_w <= cmd_wdata[15:0];
                    16'h0018: cfg_ofm_h <= cmd_wdata[15:0];
                    16'h001C: cfg_ofm_w <= cmd_wdata[15:0];
                    16'h0020: cfg_ic <= cmd_wdata[15:0];
                    16'h0024: cfg_oc <= cmd_wdata[15:0];
                    16'h0028: cfg_kh <= cmd_wdata[3:0];
                    16'h002C: cfg_kw <= cmd_wdata[3:0];
                    16'h0030: cfg_stride <= cmd_wdata[3:0];
                    16'h0034: cfg_pad <= cmd_wdata[3:0];
                    16'h0038: cfg_relu_en <= cmd_wdata[0];
                    16'h003C: cfg_quant_shift <= cmd_wdata[4:0];
                    16'h0040: cfg_is_max_pool <= cmd_wdata[0];
                endcase
            end
        end
    end
    
    // Read Logic
    always @(*) begin
        cmd_rdata = 32'd0;
        if (cmd_re) begin
            // CSR Read
            if (cmd_addr[31:16] == 16'h0000) begin
                case (cmd_addr[15:0])
                    16'h0000: cmd_rdata = {31'd0, start_reg};
                    16'h0004: cmd_rdata = {30'd0, done, busy};
                    16'h0010: cmd_rdata = {16'd0, cfg_ifm_h};
                    16'h0014: cmd_rdata = {16'd0, cfg_ifm_w};
                    16'h0018: cmd_rdata = {16'd0, cfg_ofm_h};
                    16'h001C: cmd_rdata = {16'd0, cfg_ofm_w};
                    16'h0020: cmd_rdata = {16'd0, cfg_ic};
                    16'h0024: cmd_rdata = {16'd0, cfg_oc};
                    16'h0028: cmd_rdata = {28'd0, cfg_kh};
                    16'h002C: cmd_rdata = {28'd0, cfg_kw};
                    16'h0030: cmd_rdata = {28'd0, cfg_stride};
                    16'h0034: cmd_rdata = {28'd0, cfg_pad};
                    16'h0038: cmd_rdata = {31'd0, cfg_relu_en};
                    16'h003C: cmd_rdata = {27'd0, cfg_quant_shift};
                    16'h0040: cmd_rdata = {31'd0, cfg_is_max_pool};
                endcase
            end
            // Buffer Read handled in Wrapper
        end
    end
    
    assign intr = done;

    // ------------------------------------------------------
    // BRAM Ports (Direct Connection to Controller)
    // ------------------------------------------------------
    // IFM BRAM (Port A)
    assign bram_ifm_addr = ctrl_ifm_addr;
    assign bram_ifm_wdata = 256'd0; // Controller does not write IFM
    assign bram_ifm_we = 32'd0;
    assign bram_ifm_en = ctrl_ifm_rd_en;
    assign ctrl_ifm_rdata = bram_ifm_rdata;
    
    // Weight BRAM (Port A)
    assign bram_wgt_addr = ctrl_wgt_addr;
    assign bram_wgt_wdata = 128'd0; // Controller does not write WGT
    assign bram_wgt_we = 16'd0;
    assign bram_wgt_en = ctrl_wgt_rd_en;
    assign ctrl_wgt_rdata = bram_wgt_rdata;
    
    // OFM BRAM (Port A - Write)
    assign bram_ofm_waddr = ctrl_ofm_addr;
    assign bram_ofm_wdata = ctrl_ofm_wdata;
    assign bram_ofm_we = ctrl_ofm_wr_en;
    assign bram_ofm_en_a = ctrl_ofm_wr_en;
    
    // OFM BRAM (Port B - Read)
    assign bram_ofm_raddr = ctrl_ofm_raddr;
    assign bram_ofm_en_b = ctrl_ofm_rd_en;
    assign ctrl_ofm_rdata = bram_ofm_rdata;

    // ------------------------------------------------------
    // Module Instantiations
    // ------------------------------------------------------
    
    controller u_controller (
        .clk(sys_clk),
        .rst_n(sys_rst_n),
        .start(start_reg),
        .cfg_ifm_h(cfg_ifm_h), .cfg_ifm_w(cfg_ifm_w),
        .cfg_ofm_h(cfg_ofm_h), .cfg_ofm_w(cfg_ofm_w),
        .cfg_ic(cfg_ic), .cfg_oc(cfg_oc),
        .cfg_kh(cfg_kh), .cfg_kw(cfg_kw),
        .cfg_stride(cfg_stride), .cfg_pad(cfg_pad),
        .relu_en(cfg_relu_en), .quant_shift(cfg_quant_shift),
        .cfg_is_max_pool(cfg_is_max_pool),
        .busy(busy), .done(done),
        .pe_en(pe_en),
        .mode_max(mode_max),
        .weight_we_row(weight_we_row),
        .feature_to_pe(feature_to_pe),
        .psum_from_pe(psum_from_pe),
        .ifm_addr(ctrl_ifm_addr), .ifm_rd_en(ctrl_ifm_rd_en), .ifm_rdata(ctrl_ifm_rdata),
        .wgt_addr(ctrl_wgt_addr), .wgt_rd_en(ctrl_wgt_rd_en), .wgt_rdata(ctrl_wgt_rdata),
        .ofm_addr(ctrl_ofm_addr), .ofm_wr_en(ctrl_ofm_wr_en), 
        .ofm_raddr(ctrl_ofm_raddr), .ofm_rd_en(ctrl_ofm_rd_en),
        .ofm_rdata(ctrl_ofm_rdata), .ofm_wdata(ctrl_ofm_wdata)
    );
    
    pe_array #(
        .ROWS(32), .COLS(16), .DATA_WIDTH(8), .ACC_WIDTH(32)
    ) u_pe_array (
        .clk(sys_clk), .rst_n(sys_rst_n), .en(pe_en), .mode_max(mode_max),
        .weight_we_row(weight_we_row), .weight_in_col(ctrl_wgt_rdata),
        .feature_in_rows(feature_to_pe), .psum_in_cols(512'd0),
        .feature_out_rows(), .psum_out_cols(psum_from_pe)
    );
    
    // ------------------------------------------------------
    // BRAM Ports (Direct Connection to Controller)
    // ------------------------------------------------------
    // IFM BRAM (Port A)
    assign bram_ifm_addr = ctrl_ifm_addr;
    assign bram_ifm_wdata = 256'd0; // Controller does not write IFM
    assign bram_ifm_we = 32'd0;
    assign bram_ifm_en = ctrl_ifm_rd_en;
    assign ctrl_ifm_rdata = bram_ifm_rdata;
    
    // Weight BRAM (Port A)
    assign bram_wgt_addr = ctrl_wgt_addr;
    assign bram_wgt_wdata = 128'd0; // Controller does not write WGT
    assign bram_wgt_we = 16'd0;
    assign bram_wgt_en = ctrl_wgt_rd_en;
    assign ctrl_wgt_rdata = bram_wgt_rdata;
    
    // OFM BRAM (Port A - Write)
    assign bram_ofm_waddr = ctrl_ofm_addr;
    assign bram_ofm_wdata = ctrl_ofm_wdata;
    assign bram_ofm_we = ctrl_ofm_wr_en;
    assign bram_ofm_en_a = ctrl_ofm_wr_en;
    
    // OFM BRAM (Port B - Read)
    assign bram_ofm_raddr = ctrl_ofm_raddr;
    assign bram_ofm_en_b = ctrl_ofm_rd_en;
    assign ctrl_ofm_rdata = bram_ofm_rdata;
    // assign ofm_bram_rdata = bram_ofm_rdata; // Removed unused signal

endmodule
