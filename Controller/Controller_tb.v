`timescale 1ns / 1ps

module Controller_tb;

    // ------------------------------------------------------
    // Parameters
    // ------------------------------------------------------
    parameter PE_ROWS = 32;
    parameter PE_COLS = 16;
    
    // ------------------------------------------------------
    // Signals
    // ------------------------------------------------------
    reg clk;
    reg rst_n;
    reg start;
    
    // Config
    reg [15:0] cfg_ifm_h = 4;
    reg [15:0] cfg_ifm_w = 4;
    reg [15:0] cfg_ofm_h = 4;
    reg [15:0] cfg_ofm_w = 4;
    reg [15:0] cfg_ic = 32;
    reg [15:0] cfg_oc = 16;
    reg [3:0]  cfg_kh = 1;
    reg [3:0]  cfg_kw = 1;
    reg [3:0]  cfg_stride = 1;
    reg [3:0]  cfg_pad = 0;
    
    // PPU Config
    reg relu_en;
    reg [4:0] quant_shift;
    reg cfg_is_max_pool;
    
    wire busy;
    wire done;
    
    // PE Interface
    wire pe_en;
    wire mode_max;
    wire [31:0] weight_we_row;
    wire [255:0] feature_to_pe;
    wire [511:0] psum_from_pe;
    
    // Buffer Interfaces
    wire [31:0] ifm_addr;
    wire ifm_rd_en;
    reg  [255:0] ifm_rdata;
    
    wire [31:0] wgt_addr;
    wire wgt_rd_en;
    reg  [127:0] wgt_rdata;
    
    wire [31:0] ofm_addr;
    wire ofm_wr_en;
    wire [31:0] ofm_raddr;
    wire ofm_rd_en;
    reg  [511:0] ofm_rdata;
    wire [511:0] ofm_wdata;

    // ------------------------------------------------------
    // DUT Instantiation
    // ------------------------------------------------------
    controller u_controller (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .cfg_ifm_h(cfg_ifm_h), .cfg_ifm_w(cfg_ifm_w),
        .cfg_ofm_h(cfg_ofm_h), .cfg_ofm_w(cfg_ofm_w),
        .cfg_ic(cfg_ic), .cfg_oc(cfg_oc),
        .cfg_kh(cfg_kh), .cfg_kw(cfg_kw),
        .cfg_stride(cfg_stride), .cfg_pad(cfg_pad),
        .relu_en(relu_en), .quant_shift(quant_shift),
        .cfg_is_max_pool(cfg_is_max_pool),
        .busy(busy), .done(done),
        .pe_en(pe_en),
        .mode_max(mode_max),
        .weight_we_row(weight_we_row),
        .feature_to_pe(feature_to_pe),
        .psum_from_pe(psum_from_pe),
        .ifm_addr(ifm_addr), .ifm_rd_en(ifm_rd_en), .ifm_rdata(ifm_rdata),
        .wgt_addr(wgt_addr), .wgt_rd_en(wgt_rd_en), .wgt_rdata(wgt_rdata),
        .ofm_addr(ofm_addr), .ofm_wr_en(ofm_wr_en), 
        .ofm_raddr(ofm_raddr), .ofm_rd_en(ofm_rd_en),
        .ofm_rdata(ofm_rdata), .ofm_wdata(ofm_wdata)
    );
    
    // Instantiate PE Array to close the loop
    pe_array #(
        .ROWS(PE_ROWS),
        .COLS(PE_COLS),
        .DATA_WIDTH(8),
        .ACC_WIDTH(32)
    ) u_pe_array (
        .clk(clk),
        .rst_n(rst_n),
        .en(pe_en),
        .mode_max(mode_max),
        .weight_we_row(weight_we_row),
        .weight_in_col(wgt_rdata), 
        .feature_in_rows(feature_to_pe),
        .psum_in_cols(512'd0), 
        .feature_out_rows(),
        .psum_out_cols(psum_from_pe)
    );

    // ------------------------------------------------------
    // Mock BRAMs
    // ------------------------------------------------------
    // Simple arrays to simulate memory with 2 cycle latency
    reg [255:0] ifm_mem [0:1023];
    reg [127:0] wgt_mem [0:1023];
    reg [511:0] ofm_mem [0:1023];
    
    // IFM Read Logic
    reg [31:0] ifm_addr_d1;
    always @(posedge clk) begin
        if (rst_n) begin
            ifm_addr_d1 <= ifm_addr;
            ifm_rdata   <= ifm_mem[ifm_addr_d1]; // Latency = 2 (Addr -> D1 -> Data)
        end else begin
            ifm_addr_d1 <= 0;
            ifm_rdata <= 0;
        end
    end
    
    // Weight Read Logic
    reg [31:0] wgt_addr_d1;
    always @(posedge clk) begin
        if (rst_n) begin
            wgt_addr_d1 <= wgt_addr;
            wgt_rdata   <= wgt_mem[wgt_addr_d1];
        end else begin
            wgt_addr_d1 <= 0;
            wgt_rdata <= 0;
        end
    end
    
    // OFM Read Logic
    reg [31:0] ofm_raddr_d1;
    always @(posedge clk) begin
        if (rst_n) begin
            ofm_raddr_d1 <= ofm_raddr;
            ofm_rdata    <= ofm_mem[ofm_raddr_d1];
        end else begin
            ofm_raddr_d1 <= 0;
            ofm_rdata <= 0;
        end
    end
    
    // OFM Write Logic
    always @(posedge clk) begin
        if (ofm_wr_en) begin
            ofm_mem[ofm_addr] <= ofm_wdata;
            $display("Time %t: Write OFM[%d] = %h", $time, ofm_addr, ofm_wdata);
        end
    end

    // ------------------------------------------------------
    // Clock Generation
    // ------------------------------------------------------
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // ------------------------------------------------------
    // Test Sequence
    // ------------------------------------------------------
    integer i;
    initial begin
        // Initialize Memory
        // IFM: All 1s
        for (i=0; i<1024; i=i+1) ifm_mem[i] = {32{8'd1}}; 
        // Weights: All 1s
        for (i=0; i<1024; i=i+1) wgt_mem[i] = {16{8'd1}};
        // OFM: Clear
        for (i=0; i<1024; i=i+1) ofm_mem[i] = 0;
        
        rst_n = 0;
        start = 0;
        relu_en = 1;
        quant_shift = 0;
        cfg_is_max_pool = 0;
        
        #100;
        @(posedge clk);
        rst_n = 1;
        #20;
        
        $display("Starting Controller...");
        start = 1;
        @(posedge clk);
        start = 0;
        
        wait(done);
        $display("Controller Done at time %t", $time);
        
        // Verify Result
        // We did 4x4 IFM, 1x1 Kernel, 32 IC, 16 OC.
        // Each output pixel = 32 * (1 * 1) = 32.
        // PPU: Bias=0, ReLU=1, Shift=0. Result = 32.
        
        #100;
        if (ofm_mem[0] === {16{32'h00000020}})
            $display("[PASS] OFM[0] content matches expected value.");
        else
            $display("[FAIL] OFM[0] = %h", ofm_mem[0]);
            
        $finish;
    end

endmodule
