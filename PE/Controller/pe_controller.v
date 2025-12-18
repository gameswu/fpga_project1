/**
 * PE Controller - Streaming Refactor
 * 
 * Description:
 *   Orchestrates 16x16 PE Array for convolution with Weight Stationary dataflow.
 *   Supports fully pipelined (streaming) execution for maximum throughput.
 *   
 *   Pipeline Depth: 4 Cycles
 *   - T0: Address Generation (Input & Psum Read)
 *   - T1-T2: BRAM Read Latency
 *   - T3: Data Registration / Muxing
 *   - T4: MAC Computation & Psum Write Back
 * 
 * Author: shealligh (Refactored by Copilot)
 * Date: 2025-12-16
 */

module pe_controller #(
    parameter ARRAY_DIM = 16,
    parameter MAX_H = 32,
    parameter MAX_W = 32
) (
    input  wire        clk,
    input  wire        rst_n,
    
    // Control Interface
    input  wire        start,
    output reg         done,
    
    // Configuration
    input  wire [3:0]  kernel_h,
    input  wire [3:0]  kernel_w,
    input  wire [7:0]  input_h,
    input  wire [7:0]  input_w,
    input  wire [7:0]  input_channels,
    input  wire [3:0]  stride,
    input  wire [3:0]  padding,
    input  wire [7:0]  output_h,
    input  wire [7:0]  output_w,
    input  wire [7:0]  output_channels,
    
    // PE Array Interface
    output reg         weight_write_enable,
    output reg  [3:0]  weight_col,
    output reg  [ARRAY_DIM*8-1:0]  weight_data,
    output reg  [ARRAY_DIM*8-1:0] pe_data_in,
    output reg         pe_data_valid,
    
    // BRAM Direct Control (psum buffer)
    // Split into Read and Write ports for Dual Port operation
    output wire [9:0]  psum_raddr,
    output wire [9:0]  psum_waddr,
    output wire        psum_wen,
    output wire        psum_clear, // Aligned to Read Data (T3)
    
    output wire [ARRAY_DIM*32-1:0] pe_acc_out_buf_o, // Not used in streaming mode (direct connect)
    input  wire [ARRAY_DIM*32-1:0] pe_acc_out,       // From PE Array
    input  wire        pe_acc_out_valid,             // From PE Array
    
    // External Memory Interface
    output reg  [15:0] weight_mem_addr,
    input  wire [ARRAY_DIM*8-1:0] weight_mem_data,
    
    output wire [15:0] input_mem_addr, // Changed to wire for combinational output
    input  wire [ARRAY_DIM*8-1:0] input_mem_data
);

    // =========================================================================
    // 1. State Definitions
    // =========================================================================
    localparam S_IDLE           = 0;
    localparam S_CALC_BATCHES   = 1;
    localparam S_LOAD_WEIGHTS   = 2;
    localparam S_WAIT_WEIGHTS   = 3;
    localparam S_STREAM_RUN     = 4; // Continuous streaming state
    localparam S_DRAIN_PIPE     = 5; // Wait for pipeline to empty
    localparam S_UPDATE_LOOPS   = 6;
    localparam S_DONE           = 7;
    
    reg [3:0] state;
    
    // =========================================================================
    // 2. Loop Counters
    // =========================================================================
    // Outer Loops (Stationary during stream)
    reg [3:0] ky, kx;
    reg [7:0] oc, ic;
    
    // Inner Loops (Streaming)
    reg [7:0] oy, ox;
    
    // Weight Loading
    reg [3:0] wc;
    
    // Batch Info
    reg [7:0] num_ic_batches;
    reg [7:0] num_oc_batches;
    reg [7:0] oc_batch_size;
    
    // Loop Boundary Flags
    wire ox_last = (ox == output_w - 1);
    wire oy_last = (oy == output_h - 1);
    wire ic_last = (ic + 16 >= input_channels);
    wire oc_last = (oc + 16 >= output_channels);
    wire kx_last = (kx == kernel_w - 1);
    wire ky_last = (ky == kernel_h - 1);
    wire wc_last = (wc == oc_batch_size - 1);
    
    // =========================================================================
    // 3. Address Generation (Combinational - T0)
    // =========================================================================
    
    // Use effective stride to prevent stuck-at-0 issues if config is missing
    wire [3:0] stride_eff = (stride == 0) ? 4'd1 : stride;
    
    // --- Input Address ---
    // Use explicit signed extension for calculation
    wire signed [15:0] iy_calc = $signed({8'b0, oy}) * $signed({12'b0, stride_eff}) + $signed({12'b0, ky}) - $signed({12'b0, padding});
    wire signed [15:0] ix_calc = $signed({8'b0, ox}) * $signed({12'b0, stride_eff}) + $signed({12'b0, kx}) - $signed({12'b0, padding});
    
    // Check bounds (must be non-negative and within dimensions)
    wire input_valid_coord = (!iy_calc[15] && iy_calc < {8'b0, input_h} && 
                              !ix_calc[15] && ix_calc < {8'b0, input_w});
    
    // Calculate address only if valid to avoid overflow/underflow weirdness
    // Use 32-bit arithmetic for intermediate steps
    reg [31:0] input_addr_calc;
    always @(*) begin
        if (input_valid_coord) begin
            input_addr_calc = (iy_calc[15:0] * {24'b0, input_w} + ix_calc[15:0]) * {24'b0, num_ic_batches} + {24'b0, (ic >> 4)};
        end else begin
            input_addr_calc = 0;
        end
    end
    
    wire [15:0] input_addr_next = input_addr_calc[15:0];
    
    // Combinational assignment for input_mem_addr to save 1 cycle latency
    // T0: Addr Valid -> BRAM Sample at T0 Edge -> Data Valid T2 Edge -> Sample T3 Edge
    assign input_mem_addr = input_addr_next;

    // --- Weight Address ---
    wire [15:0] weight_addr_next = ((ky * kernel_w + kx) * output_channels + (oc + wc)) * num_ic_batches + (ic >> 4);
    
    // --- Psum Address (Read) ---
    wire [9:0] psum_raddr_next = (oy * output_w + ox) * num_oc_batches + (oc >> 4);
    
    // =========================================================================
    // 4. Pipeline Control (Shift Registers)
    // =========================================================================
    
    localparam BRAM_LATENCY = 2; 
    localparam PIPE_DEPTH = 21; 
    
    reg [PIPE_DEPTH-1:0] pipe_valid;
    reg [PIPE_DEPTH-1:0] pipe_clear;
    reg [9:0]            pipe_addr [0:PIPE_DEPTH-1];
    
    integer i;
    
    // Pipeline Shift Logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pipe_valid <= 0;
            pipe_clear <= 0;
            for(i=0; i<PIPE_DEPTH; i=i+1) pipe_addr[i] <= 0;
        end else begin
            if (state == S_STREAM_RUN) begin
                pipe_valid <= {pipe_valid[PIPE_DEPTH-2:0], 1'b1};
                pipe_clear <= {pipe_clear[PIPE_DEPTH-2:0], (ky == 0 && kx == 0 && ic == 0)};
                for(i=PIPE_DEPTH-1; i>0; i=i-1) pipe_addr[i] <= pipe_addr[i-1];
                pipe_addr[0] <= psum_raddr_next;
            end else if (state == S_DRAIN_PIPE) begin
                pipe_valid <= {pipe_valid[PIPE_DEPTH-2:0], 1'b0};
                pipe_clear <= {pipe_clear[PIPE_DEPTH-2:0], 1'b0};
                for(i=PIPE_DEPTH-1; i>0; i=i-1) pipe_addr[i] <= pipe_addr[i-1];
                pipe_addr[0] <= 0;
            end else begin
                pipe_valid <= 0;
                pipe_clear <= 0;
            end
        end
    end
    
    // --- Output Assignments (Fixed) ---
    
    // Read Address: T18 (Correct timing for Latency=2 BRAM)
    // pipe_addr[0] is T1. pipe_addr[17] is T18.
    // T18 Read -> T20 Data Valid -> Matches PE Output at T20.
    assign psum_raddr = pipe_addr[17]; 
    
    // Write Address: T20 (Unchanged)
    assign psum_waddr = pipe_addr[19];
    
    // Write Enable: T20
    assign psum_wen = pipe_valid[19];
    
    // Clear Signal: T20
    assign psum_clear = pipe_clear[19]; 
    
    assign pe_acc_out_buf_o = pe_acc_out; 
    
    
    // --- Input Data Pipeline (T0 -> T4) ---
    
    reg [3:0] input_valid_pipe; 
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pe_data_in <= 0;
            pe_data_valid <= 0;
            input_valid_pipe <= 0;
        end else begin
            // Shift input validity
            if (state == S_STREAM_RUN)
                input_valid_pipe <= {input_valid_pipe[2:0], input_valid_coord};
            else if (state == S_DRAIN_PIPE)
                input_valid_pipe <= {input_valid_pipe[2:0], 1'b0};
            else
                input_valid_pipe <= 0;
                
            // T3: Register Data
            // 【关键修复】使用 [2] 而不是 [1]
            // T0(Valid) -> T1(p0) -> T2(p1) -> T3(p2)
            // 在 T3 时钟沿，p[2] 保存的是 T0 时刻的有效性。
            // 之前使用 p[1] 导致最后一个像素（T0有效，T1无效）被误杀为 0。
            if (input_valid_pipe[2]) begin
                pe_data_in <= input_mem_data;
                pe_data_valid <= 1'b1; 
            end else begin
                pe_data_in <= 0; // Zero padding
                pe_data_valid <= 1'b1; 
            end
        end
    end

    // =========================================================================
    // 5. Weight Loading Pipeline (Unchanged)
    // =========================================================================
    reg [2:0] we_pipe;
    reg [3:0] wc_pipe [0:2];
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            we_pipe <= 0;
            weight_write_enable <= 0;
            weight_col <= 0;
            weight_data <= 0;
            for(i=0; i<3; i=i+1) wc_pipe[i] <= 0;
        end else begin
            we_pipe <= {we_pipe[1:0], (state == S_LOAD_WEIGHTS)};
            
            wc_pipe[2] <= wc_pipe[1];
            wc_pipe[1] <= wc_pipe[0];
            wc_pipe[0] <= wc;
            
            weight_write_enable <= we_pipe[2];
            weight_col <= wc_pipe[2];
            weight_data <= weight_mem_data;
        end
    end

    // =========================================================================
    // 6. Main FSM
    // =========================================================================
    
    reg [4:0] drain_cnt;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            done <= 0;
            ky <= 0; kx <= 0;
            oy <= 0; ox <= 0;
            oc <= 0; ic <= 0;
            wc <= 0;
            // input_mem_addr is wire now
            weight_mem_addr <= 0;
            num_ic_batches <= 0;
            num_oc_batches <= 0;
            oc_batch_size <= 0;
            drain_cnt <= 0;
        end else begin
            case (state)
                S_IDLE: begin
                    if (start) begin
                        state <= S_CALC_BATCHES;
                        done <= 0;
                        ky <= 0; kx <= 0;
                        oy <= 0; ox <= 0;
                        oc <= 0; ic <= 0;
                    end
                end
                
                S_CALC_BATCHES: begin
                    num_ic_batches <= (input_channels == 0) ? 1 : ((input_channels + 15) >> 4);
                    num_oc_batches <= (output_channels == 0) ? 1 : ((output_channels + 15) >> 4);
                    state <= S_LOAD_WEIGHTS;
                    wc <= 0;
                    
                    // Calculate current batch size
                    if (oc + 16 <= output_channels) oc_batch_size <= 16;
                    else oc_batch_size <= output_channels - oc;
                end
                
                S_LOAD_WEIGHTS: begin
                    weight_mem_addr <= weight_addr_next;
                    if (wc_last) begin
                        wc <= 0;
                        state <= S_WAIT_WEIGHTS; 
                    end else begin
                        wc <= wc + 1;
                    end
                end
                
                S_WAIT_WEIGHTS: begin
                    if (we_pipe == 0) state <= S_STREAM_RUN;
                end
                
                S_STREAM_RUN: begin
                    // Continuous Streaming
                    // 1. Issue Addresses (Combinational logic drives outputs)
                    // input_mem_addr is now combinational, so no assignment here
                    
                    // 2. Loop Counters
                    if (ox_last) begin
                        ox <= 0;
                        if (oy_last) begin
                            oy <= 0;
                            // Finished the whole image plane for this weight
                            state <= S_DRAIN_PIPE;
                            drain_cnt <= 0;
                        end else begin
                            oy <= oy + 1;
                        end
                    end else begin
                        ox <= ox + 1;
                    end
                end
                
                S_DRAIN_PIPE: begin
                    // Wait for pipeline to empty (PIPE_DEPTH cycles)
                    if (drain_cnt == PIPE_DEPTH + 1) begin
                        state <= S_UPDATE_LOOPS;
                    end else begin
                        drain_cnt <= drain_cnt + 1;
                    end
                end
                
                S_UPDATE_LOOPS: begin
                    // Update Outer Loops
                    if (!ic_last) begin
                        ic <= ic + 16;
                        state <= S_CALC_BATCHES;
                    end else begin
                        ic <= 0;
                        if (!oc_last) begin
                            oc <= oc + 16;
                            state <= S_CALC_BATCHES;
                        end else begin
                            oc <= 0;
                            if (!kx_last) begin
                                kx <= kx + 1;
                                state <= S_CALC_BATCHES;
                            end else begin
                                kx <= 0;
                                if (!ky_last) begin
                                    ky <= ky + 1;
                                    state <= S_CALC_BATCHES;
                                end else begin
                                    state <= S_DONE;
                                end
                            end
                        end
                    end
                end
                
                S_DONE: begin
                    done <= 1;
                    if (!start) state <= S_IDLE;
                end
                
            endcase
        end
    end

endmodule
