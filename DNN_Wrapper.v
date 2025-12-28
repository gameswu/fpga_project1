`timescale 1ns / 1ps

module DNN_Wrapper (
    input wire sys_clk,
    input wire sys_rst_n,
    
    // External Memory Mapped Interface (32-bit)
    input wire [31:0] cmd_addr,
    input wire [31:0] cmd_wdata,
    output reg [31:0] cmd_rdata,
    input wire cmd_we,
    input wire cmd_re,
    output wire intr
);

    // ------------------------------------------------------
    // Internal Signals
    // ------------------------------------------------------
    wire [31:0] top_cmd_rdata;
    
    // BRAM Interface Signals (from DNN_Top)
    wire [31:0] bram_ifm_addr;
    wire [255:0] bram_ifm_wdata;
    wire [31:0] bram_ifm_we;
    wire bram_ifm_en;
    wire [255:0] bram_ifm_rdata;

    wire [31:0] bram_wgt_addr;
    wire [127:0] bram_wgt_wdata;
    wire [15:0] bram_wgt_we;
    wire bram_wgt_en;
    wire [127:0] bram_wgt_rdata;

    wire [31:0] bram_ofm_waddr;
    wire [511:0] bram_ofm_wdata;
    wire bram_ofm_we;
    wire bram_ofm_en_a;
    
    wire [31:0] bram_ofm_raddr;
    wire bram_ofm_en_b;
    wire [511:0] bram_ofm_rdata;

    // ------------------------------------------------------
    // DNN_Top Instantiation
    // ------------------------------------------------------
    DNN_Top u_dnn_top (
        .sys_clk(sys_clk),
        .sys_rst_n(sys_rst_n),
        .cmd_addr(cmd_addr),
        .cmd_wdata(cmd_wdata),
        .cmd_rdata(top_cmd_rdata),
        .cmd_we(cmd_we),
        .cmd_re(cmd_re),
        .intr(intr),
        
        // BRAM Ports
        .bram_ifm_addr(bram_ifm_addr),
        .bram_ifm_wdata(bram_ifm_wdata),
        .bram_ifm_we(bram_ifm_we),
        .bram_ifm_en(bram_ifm_en),
        .bram_ifm_rdata(bram_ifm_rdata),
        
        .bram_wgt_addr(bram_wgt_addr),
        .bram_wgt_wdata(bram_wgt_wdata),
        .bram_wgt_we(bram_wgt_we),
        .bram_wgt_en(bram_wgt_en),
        .bram_wgt_rdata(bram_wgt_rdata),
        
        .bram_ofm_waddr(bram_ofm_waddr),
        .bram_ofm_wdata(bram_ofm_wdata),
        .bram_ofm_we(bram_ofm_we),
        .bram_ofm_en_a(bram_ofm_en_a),
        .bram_ofm_raddr(bram_ofm_raddr),
        .bram_ofm_en_b(bram_ofm_en_b),
        .bram_ofm_rdata(bram_ofm_rdata)
    );

    // ------------------------------------------------------
    // BRAM Instantiations
    // ------------------------------------------------------
    
    // IFM Buffer
    // Port A: External Write (32-bit) - NOT USED HERE because DNN_Top handles muxing
    // Port B: Internal Read (256-bit) - NOT USED HERE because DNN_Top handles muxing
    // Wait, DNN_Top outputs a SINGLE PORT interface (or Port A of a BRAM).
    // But the IP provided is Dual Port with Asymmetric Widths.
    // We need to adapt DNN_Top's output to the IP.
    
    // DNN_Top assumes:
    // Write: 256-bit data, 32-bit byte-enable.
    // Read: 256-bit data.
    // Addr: 32-bit (word aligned for 256-bit words? No, DNN_Top uses word index).
    
    // The IP:
    // Port A: 32-bit Write.
    // Port B: 256-bit Read.
    
    // Since DNN_Top ALREADY muxes the external 32-bit write into a 256-bit write with byte enables,
    // we can connect DNN_Top's output to Port B (Read/Write 256-bit) if the IP supports it?
    // No, the IP definition says:
    // Port A: Write [0:0] wea, [31:0] dina.
    // Port B: Read [255:0] doutb.
    // It seems Port A is Write-Only 32-bit, Port B is Read-Only 256-bit?
    // Or maybe Port A is RW 32-bit, Port B is RW 256-bit?
    // Usually "wea" [0:0] implies full width write.
    
    // If the IP is strictly: Port A (32b Write), Port B (256b Read).
    // Then DNN_Top's logic of generating 256-bit writes is USELESS for this IP.
    // We must bypass DNN_Top's write logic and use the external signals directly for Port A.
    
    // Logic for IFM Buffer:
    // Port A (External Write):
    // - Enable: cmd_we && (cmd_addr in IFM range)
    // - Addr: cmd_addr (need to map to 16-bit word address)
    // - Data: cmd_wdata
    // Port B (Internal Read):
    // - Enable: bram_ifm_en (from DNN_Top, which is actually ctrl_rd_en when busy)
    // - Addr: bram_ifm_addr (from DNN_Top, which is ctrl_ifm_addr when busy)
    // - Data: bram_ifm_rdata (to DNN_Top)
    
    wire ifm_sel = (cmd_addr[31:20] == 12'h001);
    wire [15:0] ifm_addra = cmd_addr[17:2]; // 32-bit word address. 0x0010_0000 -> 0. 0x0010_0004 -> 1.
    
    // Note: DNN_Top outputs 'bram_ifm_addr' which is the 256-bit word index.
    // The IP Port B 'addrb' is [12:0]. 2^13 = 8192. 
    // DNN_Top uses 2K depth. So [10:0] is enough.
    
    ifm_buffer u_ifm_buffer (
      .clka(sys_clk),    // input wire clka
      .ena(ifm_sel && cmd_we),      // input wire ena
      .wea(cmd_we),      // input wire [0 : 0] wea
      .addra(ifm_addra),  // input wire [15 : 0] addra
      .dina(cmd_wdata),    // input wire [31 : 0] dina
      
      .clkb(sys_clk),    // input wire clkb
      .enb(bram_ifm_en),      // input wire enb
      .addrb(bram_ifm_addr[12:0]),  // input wire [12 : 0] addrb
      .doutb(bram_ifm_rdata)  // output wire [255 : 0] doutb
    );

    // WGT Buffer
    // Port A: External Write (32-bit)
    // Port B: Internal Read (128-bit)
    
    wire wgt_sel = (cmd_addr[31:20] == 12'h002);
    wire [13:0] wgt_addra = cmd_addr[15:2]; // 32-bit word address.
    
    wgt_buffer u_wgt_buffer (
      .clka(sys_clk),    // input wire clka
      .ena(wgt_sel && cmd_we),      // input wire ena
      .wea(1'b1),      // input wire [0 : 0] wea
      .addra(wgt_addra),  // input wire [13 : 0] addra
      .dina(cmd_wdata),    // input wire [31 : 0] dina
      
      .clkb(sys_clk),    // input wire clkb
      .enb(bram_wgt_en),      // input wire enb
      .addrb(bram_wgt_addr[11:0]),  // input wire [11 : 0] addrb
      .doutb(bram_wgt_rdata)  // output wire [127 : 0] doutb
    );

    // OFM Buffer
    // Port A: Internal Write (512-bit) - Connected to Controller Write Port
    // Port B: Internal Read (512-bit) OR External Read (32-bit via Mux)
    
    wire ofm_sel = (cmd_addr[31:20] == 12'h003);
    wire [15:0] ofm_host_addr = cmd_addr[17:2]; // 32-bit word address
    wire [11:0] ofm_host_word512_addr = ofm_host_addr[15:4]; // 512-bit word address
    wire [3:0]  ofm_host_sub_word = ofm_host_addr[3:0]; // Sub-word index (0-15)
    
    // Mux for Port B Address and Enable
    // If Busy (Accelerator Running): Use Controller Read Address
    // If Idle: Use Host Address
    wire [11:0] port_b_addr = (intr) ? ofm_host_word512_addr : bram_ofm_raddr[11:0]; // intr=done. Wait, busy signal is internal to Top.
    // We don't have 'busy' here. But we know:
    // If Controller is reading (bram_ofm_en_b=1), it needs the port.
    // If Host is reading (ofm_sel && cmd_re), it needs the port.
    // Priority: Controller (since it runs autonomously). Host should wait or read only when done.
    
    wire [11:0] final_addrb = bram_ofm_en_b ? bram_ofm_raddr[11:0] : ofm_host_word512_addr;
    wire final_enb = bram_ofm_en_b || (ofm_sel && cmd_re);
    
    wire [511:0] ofm_doutb_512;
    
    ofm_buffer u_ofm_buffer (
      .clka(sys_clk),    // input wire clka
      .ena(bram_ofm_en_a),      // input wire ena
      .wea({64{bram_ofm_we}}),      // input wire [0 : 0] wea - Replicated to support Byte Write Enable if enabled in IP
      .addra(bram_ofm_waddr[11:0]),  // input wire [11 : 0] addra
      .dina(bram_ofm_wdata),    // input wire [511 : 0] dina
      .douta(),  // output wire [511 : 0] douta (Unused)
      
      .clkb(sys_clk),    // input wire clkb
      .enb(final_enb),      // input wire enb
      .web(1'b0),      // input wire [0 : 0] web
      .addrb(final_addrb),  // input wire [11 : 0] addrb
      .dinb(512'd0),    // input wire [511 : 0] dinb
      .doutb(ofm_doutb_512)  // output wire [511 : 0] doutb
    );
    
    // Connect Port B output to Controller Read Data
    assign bram_ofm_rdata = ofm_doutb_512;

    // Output Mux for Host Read
    // Select 32-bit slice from 512-bit output
    reg [31:0] ofm_host_rdata;
    always @(*) begin
        ofm_host_rdata = ofm_doutb_512[ofm_host_sub_word*32 +: 32];
    end

    // Output Mux
    always @(*) begin
        if (ofm_sel) cmd_rdata = ofm_host_rdata;
        else cmd_rdata = top_cmd_rdata;
    end

endmodule
