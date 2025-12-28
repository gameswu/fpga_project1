// @audit-ok

`timescale 1ns / 1ps

module controller (
    input wire clk,
    input wire rst_n,
    input wire start,
    
    // Configuration (Simplified for this implementation)
    // Assuming these are set before start and hold constant
    input wire [15:0] cfg_ifm_h,
    input wire [15:0] cfg_ifm_w,
    input wire [15:0] cfg_ofm_h,
    input wire [15:0] cfg_ofm_w,
    input wire [15:0] cfg_ic,
    input wire [15:0] cfg_oc,
    input wire [3:0]  cfg_kh,
    input wire [3:0]  cfg_kw,
    input wire [3:0]  cfg_stride,
    input wire [3:0]  cfg_pad,
    
    // PPU Configuration
    input wire relu_en,
    input wire [4:0] quant_shift,
    input wire cfg_is_max_pool,
    
    output reg busy,
    output reg done,

    // PE Array Control
    output reg pe_en,
    output wire mode_max,
    output reg [31:0] weight_we_row,
    output wire [255:0] feature_to_pe, // Skewed data to PE
    input wire [511:0] psum_from_pe,   // Skewed data from PE
    
    // IFM Buffer Interface (Read Only)
    output reg [31:0] ifm_addr,
    output reg ifm_rd_en,
    input wire [255:0] ifm_rdata, // 32 * 8bit
    
    // Weight Buffer Interface (Read Only)
    output reg [31:0] wgt_addr,
    output reg wgt_rd_en,
    input wire [127:0] wgt_rdata, // 16 * 8bit
    
    // OFM Buffer Interface (Read/Write for Accumulation)
    output reg [31:0] ofm_addr, // Write Address
    output reg ofm_wr_en,
    output reg [31:0] ofm_raddr, // Read Address
    output reg ofm_rd_en,
    input wire [511:0] ofm_rdata, // 16 * 32bit
    output wire [511:0] ofm_wdata
);

    // ------------------------------------------------------
    // Parameters & Constants
    // ------------------------------------------------------
    localparam S_IDLE        = 3'd0;
    localparam S_LOAD_WGT    = 3'd1;
    localparam S_COMPUTE     = 3'd2;
    localparam S_DRAIN       = 3'd3; // Wait for pipeline to finish
    localparam S_DONE        = 3'd4;

    localparam PE_ROWS = 32;
    localparam PE_COLS = 16;
    localparam BRAM_LATENCY = 2;

    // ------------------------------------------------------
    // Internal Signals
    // ------------------------------------------------------
    reg [2:0] state, next_state;
    
    // Loop Counters
    reg [15:0] cnt_tile_oc;
    reg [15:0] cnt_tile_ic;
    reg [15:0] cnt_oy;
    reg [15:0] cnt_ox;
    reg [3:0]  cnt_ky;
    reg [3:0]  cnt_kw;
    
    // Loop Bounds (Calculated from config)
    wire [15:0] num_tile_oc = (cfg_oc + PE_COLS - 1) / PE_COLS;
    wire [15:0] num_tile_ic = (cfg_ic + PE_ROWS - 1) / PE_ROWS;
    
    // Weight Loading Counter
    reg [5:0] cnt_wgt_row; // 0 to 31

    // Pipeline Control
    reg compute_active;
    reg [7:0] drain_counter;
    
    // Skew/De-skew Registers
    reg [7:0] ifm_skew_regs [PE_ROWS-1:0][PE_ROWS-1:0]; // [Row][Delay] - Optimized later
    // Actually, Row i needs delay i. So we need separate shift registers of different lengths.
    // Or a triangular register array.
    
    reg [31:0] ofm_deskew_regs [PE_COLS-1:0][PE_COLS-1:0]; // [Col][Delay]

    assign mode_max = cfg_is_max_pool;

    // ------------------------------------------------------
    // FSM
    // ------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) state <= S_IDLE;
        else begin
            state <= next_state;
            if (state != next_state) begin
                $display("Time %t: Controller State Transition %d -> %d", $time, state, next_state);
            end
        end
    end

    always @(*) begin
        next_state = state;
        case (state)
            S_IDLE: if (start) next_state = S_LOAD_WGT;
            
            S_LOAD_WGT: begin
                // Load 32 rows of weights
                if (cnt_wgt_row == 0) begin
                     $display("Processing: Tile_OC=%d, Tile_IC=%d, KY=%d, KW=%d", cnt_tile_oc, cnt_tile_ic, cnt_ky, cnt_kw);
                end
                if (cnt_wgt_row == PE_ROWS + BRAM_LATENCY - 1) 
                    next_state = S_COMPUTE;
            end
            
            S_COMPUTE: begin
                // Iterate over Output Feature Map (OX, OY) only
                // KY and KW are now outer loops
                if (cnt_oy == cfg_ofm_h - 1 && cnt_ox == cfg_ofm_w - 1)
                    next_state = S_DRAIN;
            end
            
            S_DRAIN: begin
                // Wait for pipeline flush
                if (drain_counter == 8'd100) begin 
                    // Check Loop Counters
                    if (cnt_kw == cfg_kw - 1 && cnt_ky == cfg_kh - 1 && 
                        cnt_tile_ic == num_tile_ic - 1 && cnt_tile_oc == num_tile_oc - 1)
                        next_state = S_DONE;
                    else
                        next_state = S_LOAD_WGT; // Next Kernel Point or Tile
                end
            end
            
            S_DONE: next_state = S_IDLE;
        endcase
    end

    // ------------------------------------------------------
    // Counters & Loop Logic
    // ------------------------------------------------------
    reg [31:0] wgt_addr_base; // Pointer for weight loading

    always @(posedge clk) begin
        if (!rst_n) begin
            cnt_tile_oc <= 0; cnt_tile_ic <= 0;
            cnt_oy <= 0; cnt_ox <= 0;
            cnt_ky <= 0; cnt_kw <= 0;
            cnt_wgt_row <= 0;
            drain_counter <= 0;
            busy <= 0; done <= 0;
            wgt_addr_base <= 0;
        end else begin
            case (state)
                S_IDLE: begin
                    cnt_tile_oc <= 0; cnt_tile_ic <= 0;
                    cnt_ky <= 0; cnt_kw <= 0;
                    done <= 0;
                    wgt_addr_base <= 0;
                    if (start) busy <= 1;
                end

                S_LOAD_WGT: begin
                    cnt_oy <= 0; cnt_ox <= 0; 
                    // cnt_ky, cnt_kw are preserved
                    if (cnt_wgt_row < PE_ROWS + BRAM_LATENCY)
                        cnt_wgt_row <= cnt_wgt_row + 1;
                end

                S_COMPUTE: begin
                    cnt_wgt_row <= 0;
                    if (pe_en) begin
                        // Innermost: OX
                        if (cnt_ox < cfg_ofm_w - 1) begin
                            cnt_ox <= cnt_ox + 1;
                        end else begin
                            cnt_ox <= 0;
                            // OY
                            if (cnt_oy < cfg_ofm_h - 1) begin
                                cnt_oy <= cnt_oy + 1;
                            end
                        end
                    end
                end

                S_DRAIN: begin
                    drain_counter <= drain_counter + 1;
                    if (next_state == S_LOAD_WGT) begin
                        drain_counter <= 0;
                        wgt_addr_base <= wgt_addr_base + PE_ROWS; // Advance weight pointer
                        
                        // Update Outer Loops: KW -> KY -> Tile_IC -> Tile_OC
                        if (cnt_kw < cfg_kw - 1) begin
                            cnt_kw <= cnt_kw + 1;
                        end else begin
                            cnt_kw <= 0;
                            if (cnt_ky < cfg_kh - 1) begin
                                cnt_ky <= cnt_ky + 1;
                            end else begin
                                cnt_ky <= 0;
                                if (cnt_tile_ic < num_tile_ic - 1) begin
                                    cnt_tile_ic <= cnt_tile_ic + 1;
                                end else begin
                                    cnt_tile_ic <= 0;
                                    if (cnt_tile_oc < num_tile_oc - 1) begin
                                        cnt_tile_oc <= cnt_tile_oc + 1;
                                    end
                                end
                            end
                        end
                    end else if (next_state == S_DONE) begin
                        busy <= 0;
                        done <= 1;
                    end
                end
            endcase
        end
    end

    // ------------------------------------------------------
    // Address Generation (AGU)
    // ------------------------------------------------------
    
    // 1. Weight Address
    // Linear: Base + (Tile_OC * Num_Tile_IC + Tile_IC) * 32_Rows + Row_Index
    // Simplified: Just increment
    always @(posedge clk) begin
        if (!rst_n) begin
            wgt_addr <= 0;
            wgt_rd_en <= 0;
            weight_we_row <= 0;
        end else begin
            wgt_rd_en <= 0;
            weight_we_row <= 0;
            
            if (state == S_LOAD_WGT) begin
                if (cnt_wgt_row < PE_ROWS) begin
                    wgt_rd_en <= 1;
                    // Use linear pointer
                    wgt_addr <= wgt_addr_base + cnt_wgt_row;
                end
                
                // Handle Latency: Data arrives 2 cycles later
                // Cycle 0: Addr 0
                // Cycle 1: Addr 1
                // Cycle 2: Data 0 arrives -> Write to Row 0
                if (cnt_wgt_row >= BRAM_LATENCY && cnt_wgt_row < PE_ROWS + BRAM_LATENCY) begin
                    weight_we_row[cnt_wgt_row - BRAM_LATENCY] <= 1;
                    
                    // Debug: Print Row 0 data for the first Tile (Tile_OC=0, Tile_IC=0)
                    // This covers all 16 kernel points (KY=0..3, KW=0..3)
                    if ((cnt_tile_oc == 0) && (cnt_tile_ic == 0)) begin
                        $display("Time %t: Load Wgt [OC=0, IC=0, KY=%d, KW=%d] Row=%d Data=%h", $time, cnt_ky, cnt_kw, cnt_wgt_row - BRAM_LATENCY, wgt_rdata);
                    end
                end
            end
        end
    end

    // 2. IFM Address
    // Addr = (iy * W + ix) * (IC/32) + Tile_IC
    // iy = oy * stride + ky - pad
    // ix = ox * stride + kx - pad
    reg signed [15:0] cur_iy, cur_ix;
    reg valid_coord;
    
    always @(*) begin
        cur_iy = cnt_oy * cfg_stride + cnt_ky - cfg_pad;
        cur_ix = cnt_ox * cfg_stride + cnt_kw - cfg_pad; // Note: using cnt_kw (kernel x)
        
        if (cur_iy >= 0 && cur_iy < cfg_ifm_h && cur_ix >= 0 && cur_ix < cfg_ifm_w)
            valid_coord = 1;
        else
            valid_coord = 0;
    end

    // ------------------------------------------------------
    // Pipeline Control (100% Efficiency for True Dual Port)
    // ------------------------------------------------------
    // Removed throttling logic. pe_en is active during S_COMPUTE.
    
    always @(posedge clk) begin
        if (!rst_n) begin
            ifm_addr <= 0;
            ifm_rd_en <= 0;
            pe_en <= 0;
        end else begin
            ifm_rd_en <= 0;
            pe_en <= 0;
            
            if (state == S_LOAD_WGT && cnt_wgt_row == PE_ROWS + BRAM_LATENCY - 1) begin
                pe_en <= 1;
            end else if (state == S_COMPUTE) begin 
                pe_en <= 1; // Enable PE Array (100% Duty Cycle)
                
                if (valid_coord) begin
                    ifm_rd_en <= 1;
                    // Simplified addressing: Row-Major
                    ifm_addr <= (cur_iy * cfg_ifm_w + cur_ix) * num_tile_ic + cnt_tile_ic;
                end else begin
                    // Padding: Don't read, inject 0s later
                    ifm_rd_en <= 0;
                end
            end else if (state == S_DRAIN) begin
                pe_en <= 1; // Keep shifting out results
            end
        end
    end

    // ------------------------------------------------------
    // Input Skew Logic (32 Channels)
    // ------------------------------------------------------
    // Row i needs delay i.
    // We use a shift register array.
    // ifm_rdata arrives 2 cycles after address.
    // We need to handle the "valid_coord" logic (Padding) here too.
    // Since "valid_coord" was calculated at Addr stage, we need to delay it by 2 cycles.
    
    reg [1:0] valid_pipe;
    always @(posedge clk) valid_pipe <= {valid_pipe[0], valid_coord};
    wire data_valid = valid_pipe[1]; // Aligned with ifm_rdata

    genvar i, d;
    generate
        for (i = 0; i < PE_ROWS; i = i + 1) begin : IN_SKEW_ROW
            // Shift register of length i
            // If i=0, direct connection.
            // If i>0, registers.
            
            if (i == 0) begin
                assign feature_to_pe[7:0] = (data_valid) ? ifm_rdata[7:0] : 8'd0;
            end else begin
                reg [7:0] shift_reg [i-1:0];
                integer k;
                always @(posedge clk) begin
                    if (!rst_n) begin
                        for (k = 0; k < i; k = k + 1) shift_reg[k] <= 0;
                    end else if (pe_en) begin
                        shift_reg[0] <= (data_valid) ? ifm_rdata[(i+1)*8-1 : i*8] : 8'd0;
                        for (k = 1; k < i; k = k + 1) begin
                            shift_reg[k] <= shift_reg[k-1];
                        end
                    end
                end
                assign feature_to_pe[(i+1)*8-1 : i*8] = shift_reg[i-1];
            end
        end
    endgenerate

    // ------------------------------------------------------
    // Output De-Skew Logic (16 Columns)
    // ------------------------------------------------------
    // Col j arrives with delay j (relative to Col 0).
    // We want to align them.
    // Col 0 needs delay 15.
    // Col 15 needs delay 0.
    // Delay = (PE_COLS - 1) - j.
    
    wire [511:0] psum_deskewed;
    
    generate
        for (i = 0; i < PE_COLS; i = i + 1) begin : OUT_DESKEW_COL
            localparam DELAY = (PE_COLS - 1) - i;
            
            if (DELAY == 0) begin
                assign psum_deskewed[(i+1)*32-1 : i*32] = psum_from_pe[(i+1)*32-1 : i*32];
            end else begin
                reg [31:0] shift_reg [DELAY-1:0];
                integer k;
                always @(posedge clk) begin
                    if (!rst_n) begin
                        for (k = 0; k < DELAY; k = k + 1) shift_reg[k] <= 0;
                    end else if (pe_en) begin
                        shift_reg[0] <= psum_from_pe[(i+1)*32-1 : i*32];
                        for (k = 1; k < DELAY; k = k + 1) begin
                            shift_reg[k] <= shift_reg[k-1];
                        end
                    end
                end
                assign psum_deskewed[(i+1)*32-1 : i*32] = shift_reg[DELAY-1];
            end
        end
    endgenerate

    // ------------------------------------------------------
    // Output Buffer Management (Accumulation & PPU)
    // ------------------------------------------------------
    
    localparam PPU_LATENCY = 2;
    // Total Pipeline Depth = Skew + Array + De-skew + PPU
    // Skew(0) + Array(32) + De-skew(15) = 47. + PPU(2) = 49.
    localparam PIPE_DEPTH = PE_ROWS + PE_COLS - 1 + PPU_LATENCY; 
    
    reg [31:0] addr_pipe [PIPE_DEPTH:0];
    reg        we_pipe   [PIPE_DEPTH:0];
    reg        first_tile_pipe [PIPE_DEPTH:0];
    reg        last_tile_pipe  [PIPE_DEPTH:0];
    reg        first_run_pipe  [PIPE_DEPTH:0]; // Tracks (Tile_IC=0, KY=0, KW=0)
    reg        last_run_pipe   [PIPE_DEPTH:0]; // Tracks (Tile_IC=Last, KY=Last, KW=Last)
    
    integer pipe_idx;
    
    // Pipeline Shift Logic
    // Note: We shift EVERY cycle. pe_en acts as the data valid signal.
    always @(posedge clk) begin
        if (!rst_n) begin
            for (pipe_idx = 0; pipe_idx <= PIPE_DEPTH; pipe_idx = pipe_idx + 1) begin
                addr_pipe[pipe_idx] <= 0;
                we_pipe[pipe_idx]   <= 0;
                first_tile_pipe[pipe_idx] <= 0;
                last_tile_pipe[pipe_idx]  <= 0;
                first_run_pipe[pipe_idx]  <= 0;
                last_run_pipe[pipe_idx]   <= 0;
            end
        end else begin
            // Input Stage (0)
            addr_pipe[0] <= (cnt_oy * cfg_ofm_w + cnt_ox) * num_tile_oc + cnt_tile_oc;
            
            // Inject Valid/Invalid based on pe_en
            // If pe_en=1, we push a valid task. If pe_en=0, we push a bubble.
            // FIX: pe_en is now pre-asserted in S_LOAD_WGT. We must only push valid task in S_COMPUTE.
            // But pe_en is high in S_COMPUTE.
            // The issue might be that pe_en is high for 1 cycle, but we need to capture the correct loop counters.
            // Loop counters update at the END of S_COMPUTE (or during).
            // In S_COMPUTE, cnt_ox/oy update.
            // We capture the CURRENT counters.
            
            we_pipe[0]   <= (state == S_COMPUTE); // Only valid in COMPUTE phase
            
            first_tile_pipe[0] <= (cnt_tile_ic == 0);
            last_tile_pipe[0]  <= (cnt_tile_ic == num_tile_ic - 1);
            first_run_pipe[0]  <= (cnt_tile_ic == 0 && cnt_ky == 0 && cnt_kw == 0);
            last_run_pipe[0]   <= (cnt_tile_ic == num_tile_ic - 1 && cnt_ky == cfg_kh - 1 && cnt_kw == cfg_kw - 1);
            
            // Shift Stages
            for (pipe_idx = 1; pipe_idx <= PIPE_DEPTH; pipe_idx = pipe_idx + 1) begin
                addr_pipe[pipe_idx] <= addr_pipe[pipe_idx-1];
                we_pipe[pipe_idx]   <= we_pipe[pipe_idx-1];
                first_tile_pipe[pipe_idx] <= first_tile_pipe[pipe_idx-1];
                last_tile_pipe[pipe_idx]  <= last_tile_pipe[pipe_idx-1];
                first_run_pipe[pipe_idx]  <= first_run_pipe[pipe_idx-1];
                last_run_pipe[pipe_idx]   <= last_run_pipe[pipe_idx-1];
            end
        end
    end
    
    // ------------------------------------------------------
    // Read Logic (for Accumulation)
    // ------------------------------------------------------
    // Read Address must be sent BRAM_LATENCY cycles before data is needed at PPU.
    // PPU Input is at stage: PIPE_DEPTH - PPU_LATENCY.
    // Read Address Stage: PIPE_DEPTH - PPU_LATENCY - BRAM_LATENCY.
    localparam READ_STAGE = PIPE_DEPTH - PPU_LATENCY - BRAM_LATENCY;
    
    always @(posedge clk) begin
         // If we need to write later, and it's NOT the first run (Overwrite), we must read the old value.
         // Note: we_pipe[READ_STAGE] indicates a valid task is at the read stage.
         if (we_pipe[READ_STAGE] && !first_run_pipe[READ_STAGE]) begin
             ofm_rd_en <= 1;
             ofm_raddr <= addr_pipe[READ_STAGE];
         end else begin
             ofm_rd_en <= 0;
             ofm_raddr <= 0;
         end
    end

    // ------------------------------------------------------
    // PPU Instantiation
    // ------------------------------------------------------
    wire [511:0] ppu_out;
    
    // Data for PPU arrives at PIPE_DEPTH - PPU_LATENCY
    wire is_first_run_at_ppu = first_run_pipe[PIPE_DEPTH - PPU_LATENCY];
    wire is_last_run_at_ppu  = last_run_pipe[PIPE_DEPTH - PPU_LATENCY];
    
    ppu #(
        .NUM_CHANNELS(PE_COLS),
        .DATA_WIDTH(32)
    ) u_ppu (
        .clk(clk),
        .rst_n(rst_n),
        .en(pe_en), 
        .is_first(is_first_run_at_ppu), 
        .is_last(is_last_run_at_ppu),   
        .relu_en(relu_en),
        .quant_shift(quant_shift),
        .mode_max(cfg_is_max_pool), // Pass Max Pool config
        .psum_in(psum_deskewed),
        .acc_in(ofm_rdata),             
        .result_out(ppu_out)
    );

    assign ofm_wdata = ppu_out;
    
    // ------------------------------------------------------
    // Write Logic
    // ------------------------------------------------------
    always @(posedge clk) begin
        ofm_addr  <= addr_pipe[PIPE_DEPTH];
        ofm_wr_en <= we_pipe[PIPE_DEPTH];
    end
    
    assign ofm_wdata = ppu_out;

endmodule
