`timescale 1ns / 1ps

module DNN_Top_tb;

    // ------------------------------------------------------
    // Parameters
    // ------------------------------------------------------
    parameter SYS_CLK_PERIOD = 10; // 100MHz

    // ------------------------------------------------------
    // Signals
    // ------------------------------------------------------
    reg sys_clk;
    reg sys_rst_n;
    
    // External Interface
    reg [31:0] cmd_addr;
    reg [31:0] cmd_wdata;
    wire [31:0] cmd_rdata;
    reg cmd_we;
    reg cmd_re;
    wire intr;

    // BRAM Interface Signals (from DUT to Behavioral Models)
    wire [31:0] bram_ifm_addr;
    wire [255:0] bram_ifm_wdata;
    wire [31:0] bram_ifm_we;
    wire bram_ifm_en;
    reg [255:0] bram_ifm_rdata;

    wire [31:0] bram_wgt_addr;
    wire [127:0] bram_wgt_wdata;
    wire [15:0] bram_wgt_we;
    wire bram_wgt_en;
    reg [127:0] bram_wgt_rdata;

    wire [31:0] bram_ofm_waddr;
    wire [511:0] bram_ofm_wdata;
    wire bram_ofm_we;
    wire bram_ofm_en_a;
    
    wire [31:0] bram_ofm_raddr;
    wire bram_ofm_en_b;
    reg [511:0] bram_ofm_rdata;

    // ------------------------------------------------------
    // DUT Instantiation
    // ------------------------------------------------------
    DNN_Top u_dut (
        .sys_clk(sys_clk),
        .sys_rst_n(sys_rst_n),
        .cmd_addr(cmd_addr),
        .cmd_wdata(cmd_wdata),
        .cmd_rdata(cmd_rdata),
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
    // Behavioral BRAM Models (Simulating IP Cores)
    // ------------------------------------------------------
    // Note: These models simulate the "Internal" view of the BRAMs as seen by DNN_Top.
    // In the real system (DNN_Wrapper), the "External" writes (cmd_we) go to a separate 32-bit port.
    // Here in DNN_Top_tb, we rely on DNN_Top's internal logic to convert cmd_we to bram_ifm_we (256-bit),
    // so we model a single 256-bit wide memory with byte enables.
    
    // IFM BRAM (256-bit, Byte Enable)
    reg [255:0] mem_ifm [0:2047];
    reg [31:0] ifm_addr_pipe;
    reg [255:0] temp_ifm_data;
    integer i;
    
    // Backdoor Write for Testbench (Since DNN_Top no longer muxes writes)
    always @(posedge sys_clk) begin
        if (cmd_we && cmd_addr[31:20] == 12'h001) begin
             // IFM Write: 0x0010_XXXX
             // Addr[19:5] is Word Index (256-bit word)
             // Addr[4:2] is Byte Select (32-bit word inside 256-bit)
             mem_ifm[cmd_addr[19:5]][cmd_addr[4:2]*32 +: 32] <= cmd_wdata;
        end
    end

    always @(posedge sys_clk) begin
        if (!sys_rst_n) begin
            ifm_addr_pipe <= 0;
            bram_ifm_rdata <= 0;
        end else if (bram_ifm_en) begin
            // Internal Read Only
            ifm_addr_pipe <= bram_ifm_addr;
            bram_ifm_rdata <= mem_ifm[ifm_addr_pipe]; // Latency 2 (Addr->Pipe->Data)
        end
    end

    // Weight BRAM (128-bit, Byte Enable)
    reg [127:0] mem_wgt [0:2047];
    reg [31:0] wgt_addr_pipe;
    reg [127:0] temp_wgt_data;
    
    // Backdoor Write for Testbench
    always @(posedge sys_clk) begin
        if (cmd_we && cmd_addr[31:20] == 12'h002) begin
             // WGT Write: 0x0020_XXXX
             // Addr[19:4] is Word Index (128-bit word)
             // Addr[3:2] is Byte Select (32-bit word inside 128-bit)
             mem_wgt[cmd_addr[19:4]][cmd_addr[3:2]*32 +: 32] <= cmd_wdata;
        end
    end

    always @(posedge sys_clk) begin
        if (!sys_rst_n) begin
            wgt_addr_pipe <= 0;
            bram_wgt_rdata <= 0;
        end else if (bram_wgt_en) begin
            // Internal Read Only
            wgt_addr_pipe <= bram_wgt_addr;
            bram_wgt_rdata <= mem_wgt[wgt_addr_pipe]; // Latency 2
        end
    end

    // OFM BRAM (512-bit) - True Dual Port Model
    reg [511:0] mem_ofm [0:1023];
    reg [31:0] ofm_raddr_pipe;
    
    // Port A: Write Only (from Controller)
    always @(posedge sys_clk) begin
        if (bram_ofm_en_a) begin
            if (bram_ofm_we) begin
                mem_ofm[bram_ofm_waddr] <= bram_ofm_wdata;
            end
        end
    end
    
    // Port B: Read Only (from Controller or Host)
    always @(posedge sys_clk) begin
        if (!sys_rst_n) begin
            ofm_raddr_pipe <= 0;
            bram_ofm_rdata <= 0;
        end else if (bram_ofm_en_b) begin
            ofm_raddr_pipe <= bram_ofm_raddr;
            bram_ofm_rdata <= mem_ofm[ofm_raddr_pipe]; // Latency 2
        end
    end

    // ------------------------------------------------------
    // Tasks
    // ------------------------------------------------------
    task write_reg;
        input [31:0] addr;
        input [31:0] data;
        begin
            @(posedge sys_clk);
            #1;
            cmd_addr = addr;
            cmd_wdata = data;
            cmd_we = 1;
            cmd_re = 0;
            @(posedge sys_clk);
            #1;
            cmd_we = 0;
        end
    endtask

    task read_reg;
        input [31:0] addr;
        output [31:0] data;
        begin
            @(posedge sys_clk);
            #1;
            cmd_addr = addr;
            cmd_we = 0;
            cmd_re = 1;
            @(posedge sys_clk);
            #1;
            data = cmd_rdata;
            cmd_re = 0;
        end
    endtask

    task write_mem;
        input [31:0] addr;
        input [31:0] data;
        begin
            write_reg(addr, data);
        end
    endtask

    // ------------------------------------------------------
    // Test Sequence
    // ------------------------------------------------------
    reg [31:0] read_val;
    integer k;

    initial begin
        // Init
        sys_clk = 0;
        sys_rst_n = 0;
        cmd_addr = 0;
        cmd_wdata = 0;
        cmd_we = 0;
        cmd_re = 0;
        
        // Initialize Memories to 0
        for (k=0; k<2048; k=k+1) mem_ifm[k] = 0;
        for (k=0; k<2048; k=k+1) mem_wgt[k] = 0;
        for (k=0; k<1024; k=k+1) mem_ofm[k] = 0;
        
        // Reset
        #100;
        sys_rst_n = 1;
        #20;

        // ------------------------------------------------------
        // Test Case 1: CSR Read/Write
        // ------------------------------------------------------
        $display("--- Test Case 1: CSR Read/Write ---");
        write_reg(32'h0010, 32'd128); // IFM_H
        read_reg(32'h0010, read_val);
        if (read_val === 128) $display("[PASS] IFM_H Write/Read Verified.");
        else $display("[FAIL] IFM_H Expected 128, Got %d", read_val);

        // ------------------------------------------------------
        // Test Case 2: Memory Access (IFM)
        // ------------------------------------------------------
        $display("--- Test Case 2: IFM Memory Access ---");
        // Write to IFM Buffer (Base 0x0010_0000)
        // Write 8 words to fill one 256-bit line at Row 0
        for (k=0; k<8; k=k+1) begin
            // Addr format: 0x0010_0000 + (Row=0 << 5) + (Word=k << 2)
            write_mem(32'h0010_0000 + (k*4), k+1); 
        end
        
        // Check internal memory model
        #20;
        if (mem_ifm[0] === {32'd8, 32'd7, 32'd6, 32'd5, 32'd4, 32'd3, 32'd2, 32'd1})
            $display("[PASS] IFM Internal Memory Content Verified.");
        else
            $display("[FAIL] IFM Mem[0] = %h", mem_ifm[0]);

        // ------------------------------------------------------
        // Test Case 3: Full Computation (Small Layer)
        // ------------------------------------------------------
        $display("--- Test Case 3: Full Computation ---");
        // Config: 4x4 IFM, 1x1 Kernel, 32 IC, 16 OC
        // PPU: ReLU=1, Shift=0
        
        write_reg(32'h0010, 4); // IFM_H
        write_reg(32'h0014, 4); // IFM_W
        write_reg(32'h0018, 4); // OFM_H
        write_reg(32'h001C, 4); // OFM_W
        write_reg(32'h0020, 32); // IC
        write_reg(32'h0024, 16); // OC
        write_reg(32'h0028, 1); // KH
        write_reg(32'h002C, 1); // KW
        write_reg(32'h0030, 1); // Stride
        write_reg(32'h0034, 0); // Pad
        write_reg(32'h0038, 1); // ReLU En
        write_reg(32'h003C, 0); // Quant Shift

        // Initialize IFM Memory (All 1s)
        // 4x4 * 32 IC. Each pixel needs 32 bytes (256 bits).
        // Total 16 pixels. Rows 0 to 15 in IFM Buffer.
        for (k=0; k<16; k=k+1) begin
            mem_ifm[k] = {32{8'd1}}; // 32 channels of value 1
        end

        // Initialize Weight Memory (All 1s)
        // 1x1 Kernel * 32 IC * 16 OC.
        // Tiling: Tile_OC=1 (16), Tile_IC=1 (32).
        // Needs 32 rows in Weight Buffer (one per IC row).
        // Each row is 16 bytes (128 bits) -> 16 OC.
        for (k=0; k<32; k=k+1) begin
            mem_wgt[k] = {16{8'd1}}; // 16 filters of value 1
        end
        
        // Clear OFM Memory
        for (k=0; k<16; k=k+1) mem_ofm[k] = 0;

        // Start Accelerator
        $display("Starting Accelerator...");
        write_reg(32'h0000, 1); // Start

        // Wait for Interrupt
        wait(intr);
        $display("Interrupt Received! Accelerator Done.");
        
        // Verify Results
        // Expected: 32 (Accumulation of 32 ones)
        // Read OFM Buffer via External Interface
        // Addr: 0x0030_0000 (Row 0, Word 0) -> Channel 0
        // read_reg(32'h0030_0000, read_val); // Cannot use read_reg as DNN_Top no longer muxes reads
        
        // Backdoor Read Verification
        read_val = mem_ofm[0][31:0];
        
        if (read_val === 32) 
            $display("[PASS] OFM Result at Ch0 is correct: %d", read_val);
        else 
            $display("[FAIL] OFM Result at Ch0: Expected 32, Got %d", read_val);

        $finish;
    end

    // Enhanced Debug Monitor
    always @(posedge sys_clk) begin
        // Monitor External Interface
        if (cmd_we) begin
            $display("[TB-CMD] Time=%t Write Addr=%h Data=%h Busy=%b", $time, cmd_addr, cmd_wdata, u_dut.busy);
        end
        
        // Monitor BRAM IFM
        if (bram_ifm_en && |bram_ifm_we) begin
            $display("[TB-BRAM-IFM] Time=%t Addr=%h WE=%h Data=%h", $time, bram_ifm_addr, bram_ifm_we, bram_ifm_wdata);
        end
        
        // Monitor Controller State & Counters (Sample every 100 cycles to avoid spam)
        if (u_dut.u_controller.state == 2 && $time % 1000 == 0) begin // State 2 = COMPUTE
             $display("[TB-CTRL-STAT] Time=%t State=%d OY=%d OX=%d KY=%d KW=%d PE_EN=%b", 
                      $time, u_dut.u_controller.state, 
                      u_dut.u_controller.cnt_oy, u_dut.u_controller.cnt_ox,
                      u_dut.u_controller.cnt_ky, u_dut.u_controller.cnt_kw,
                      u_dut.u_controller.pe_en);
        end
        
        if (u_dut.u_controller.state != u_dut.u_controller.next_state) begin
             $display("[TB-CTRL] Time=%t State Change: %d -> %d", $time, u_dut.u_controller.state, u_dut.u_controller.next_state);
        end
    end

    // Clock Gen
    always #(SYS_CLK_PERIOD/2) sys_clk = ~sys_clk;

    // Timeout Watchdog
    initial begin
        #1000000; // 1ms
        $display("[TIMEOUT] Simulation ran too long. Force finish.");
        $finish;
    end

endmodule
