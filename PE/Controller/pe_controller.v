/**
 * PE Controller - Processing Element Array Controller
 * 
 * Description:
 *   Orchestrates 16x16 PE Array for convolution operations.
 *   Implements Weight Stationary dataflow (Spatial Parallelism).
 *   
 *   Dataflow:
 *   1. Iterate over Output Tiles (Spatial).
 *   2. Iterate over Kernel (ky, kx) and Input Channels.
 *   3. Load Weight (Broadcast to all PEs).
 *   4. Load Input Tile (16x16 spatial patch).
 *   5. PEs accumulate: Acc += Input * Weight.
 *   6. Repeat for all ky, kx, Cin.
 *   7. Output final result.
 *
 *   Buffer Note:
 *   The "Buffer" for accumulating partial sums across the kernel/channel 
 *   dimensions is the internal Accumulator register within each MAC unit.
 *   This allows "same position needs to add" without external buffering
 *   until the full kernel window is processed.
 *
 * Author: shealligh
 * Date: 2025-12-08
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
    
    // Configuration (Variable Sizes)
    input  wire [3:0]  kernel_h,
    input  wire [3:0]  kernel_w,
    input  wire [7:0]  input_h,
    input  wire [7:0]  input_w,
    input  wire [3:0]  stride,
    input  wire [3:0]  padding,
    input  wire [7:0]  output_h,
    input  wire [7:0]  output_w,
    
    // PE Array Interface
    output reg         weight_write_enable,
    output reg  [3:0]  weight_col,
    output reg  [ARRAY_DIM*8-1:0]  weight_data,
    output reg  [ARRAY_DIM*8-1:0] pe_data_in, // Broadcast to rows
    
    // Accumulator / Buffer Interface
    output reg         acc_enable,
    output reg         acc_clear,
    output reg  [9:0]  acc_addr,
    input  wire [ARRAY_DIM*32-1:0] pe_acc_out, // From Array (Bottom)
    
    // External Memory Interface (Simplified)
    output reg  [15:0] weight_mem_addr,
    input  wire [ARRAY_DIM*8-1:0] weight_mem_data,
    
    output reg  [15:0] input_mem_addr,
    input  wire [ARRAY_DIM*8-1:0] input_mem_data // Vector of 16 bytes
);

    // State Machine
    localparam S_IDLE = 0;
    localparam S_LOAD_WEIGHT_INIT = 1;
    localparam S_LOAD_WEIGHT_LOOP = 2;
    localparam S_STREAM_INIT = 3;
    localparam S_STREAM_RUN = 4;
    localparam S_NEXT_KERNEL = 5;
    localparam S_DONE = 6;
    localparam S_LOAD_WEIGHT_WAIT = 7;
    
    reg [2:0] state;
    
    // Output Dimensions (defined by input_h/w in this controller version)
    // Ideally, input_h/w should be output_h/w, and we read from (oy+ky, ox+kx)
    // Let's assume the configured input_h/w are actually the OUTPUT dimensions we want to iterate over.
    
    // Loop Counters
    reg [3:0] ky, kx;
    reg [7:0] oy, ox; // Output Y, Output X
    
    // Weight Loading Counters
    reg [3:0] wc;
    
    // Pipeline Delay Logic
    // Array Latency = 16 cycles (1 reg per row)
    // Memory Read Latency = 1 cycle (Addr->Mem->Reg)
    // Total Latency = 17 cycles.
    // We need index 18 (depth 19) to align T+1 to T+19.
    reg [18:0] acc_enable_pipe;
    reg [18:0] acc_clear_pipe;
    reg [9:0]  acc_addr_pipe [0:18];
    reg [4:0]  drain_cnt;
    reg zero_input;
    reg zero_input_d1;
    
    // Weight Loading Pipeline
    reg [3:0] wc_d1, wc_d2;
    reg we_d1, we_d2;
    reg [1:0] load_wait_cnt;

    integer p;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc_enable_pipe <= 0;
            acc_clear_pipe <= 0;
            for (p=0; p<19; p=p+1) acc_addr_pipe[p] <= 0;
            
            we_d1 <= 0; we_d2 <= 0;
            wc_d1 <= 0; wc_d2 <= 0;
            zero_input <= 0;
            zero_input_d1 <= 0;
        end else begin
            zero_input_d1 <= zero_input;
            
            // Shift Register for Accumulator
            for (p=18; p>0; p=p-1) begin
                acc_enable_pipe[p] <= acc_enable_pipe[p-1];
                acc_clear_pipe[p] <= acc_clear_pipe[p-1];
                acc_addr_pipe[p] <= acc_addr_pipe[p-1];
            end
            
            // Pipeline for Weight Loading
            // Input to d1 comes from current state (wr, wc)
            // Only valid during LOAD_WEIGHT_LOOP
            we_d1 <= (state == S_LOAD_WEIGHT_LOOP);
            wc_d1 <= wc;
            
            we_d2 <= we_d1;
            wc_d2 <= wc_d1;
        end
    end
    
    // Output the delayed signals
    always @(*) begin
        acc_enable = acc_enable_pipe[18]; // Delayed by 18 cycles relative to pipe[0] (Total 19 from start)
        acc_clear = acc_clear_pipe[18];
        acc_addr = acc_addr_pipe[18];
    end
    
    // Drive Weight Outputs from Pipeline
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            weight_write_enable <= 0;
            weight_col <= 0;
            weight_data <= 0;
        end else begin
            weight_write_enable <= we_d2;
            weight_col <= wc_d2;
            weight_data <= weight_mem_data; // Captures full column
        end
    end
    
    // Continuous Data Capture
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) pe_data_in <= 0;
        else if (zero_input_d1) pe_data_in <= 0;
        else pe_data_in <= input_mem_data;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            done <= 0;
            ky <= 0; kx <= 0;
            oy <= 0; ox <= 0;
            wc <= 0;
            drain_cnt <= 0;
            load_wait_cnt <= 0;
            weight_mem_addr <= 0;
            input_mem_addr <= 0;
        end else begin
            // Defaults
            // weight_write_enable <= 0; // Removed, driven by separate block
            // done <= 0; // Removed to allow sticky done
            
            // Default pipe input (0 unless overridden)
            acc_enable_pipe[0] <= 0;
            acc_clear_pipe[0] <= 0;
            acc_addr_pipe[0] <= 0;
            
            // Default zero_input (cleared unless set)
            // Wait, zero_input is a register, it holds value.
            // But we want it to be controlled by state machine for the NEXT cycle.
            // So we should set it in the state machine.
            // But here we are inside the always block.
            // Let's set default to 0.
            zero_input <= 0;
            
            case (state)
                S_IDLE: begin
                    if (start) begin
                        state <= S_LOAD_WEIGHT_INIT;
                        ky <= 0; kx <= 0;
                        done <= 0; // Clear done on start
                    end
                end
                
                // -------------------------------------------------------------
                // 1. Load Weights for current (ky, kx) slice
                // -------------------------------------------------------------
                S_LOAD_WEIGHT_INIT: begin
                    wc <= 0;
                    state <= S_LOAD_WEIGHT_LOOP;
                end
                
                S_LOAD_WEIGHT_LOOP: begin
                    // Fetch weight from memory (Column-wise)
                    weight_mem_addr <= (ky * kernel_w + kx) * 16 + wc;
                    
                    // Outputs are driven by pipeline registers
                    
                    if (wc == 15) begin
                        wc <= 0;
                        state <= S_LOAD_WEIGHT_WAIT; // Wait for pipeline to drain
                        load_wait_cnt <= 0;
                    end else begin
                        wc <= wc + 1;
                    end
                end
                
                S_LOAD_WEIGHT_WAIT: begin
                    // Wait 2 cycles for pipeline to finish writing weights
                    if (load_wait_cnt == 2) begin
                        state <= S_STREAM_INIT;
                    end else begin
                        load_wait_cnt <= load_wait_cnt + 1;
                    end
                end
                
                // -------------------------------------------------------------
                // 2. Stream Input Image (Iterate over Output Pixels)
                // -------------------------------------------------------------
                S_STREAM_INIT: begin
                    oy <= 0; ox <= 0;
                    state <= S_STREAM_RUN;
                end
                
                S_STREAM_RUN: begin
                    // Drive Inputs
                    // Convolution: Read Input at (oy*stride + ky - padding, ox*stride + kx - padding)
                    
                    // Calculate signed coordinates
                    // We use 16-bit signed arithmetic
                    // iy = oy * stride + ky - padding
                    // ix = ox * stride + kx - padding
                    
                    // Note: Verilog handles signed arithmetic if operands are signed.
                    // Or we can manually handle it.
                    // Let's use a temporary variable or expression.
                    // Since we are inside a procedural block, we can't declare wires.
                    // But we can use automatic variables or just expressions.
                    
                    // Let's use a large enough vector to hold the result and check MSB for negative.
                    // oy (8b) * stride (4b) -> 12b. + ky (4b) -> 13b. - padding (4b) -> 14b signed.
                    
                    reg signed [15:0] iy_s;
                    reg signed [15:0] ix_s;
                    
                    iy_s = $signed({8'b0, oy}) * $signed({12'b0, stride}) + $signed({12'b0, ky}) - $signed({12'b0, padding});
                    ix_s = $signed({8'b0, ox}) * $signed({12'b0, stride}) + $signed({12'b0, kx}) - $signed({12'b0, padding});
                    
                    if (iy_s >= 0 && iy_s < $signed({8'b0, input_h}) && ix_s >= 0 && ix_s < $signed({8'b0, input_w})) begin
                        input_mem_addr <= iy_s * input_w + ix_s;
                        zero_input <= 0;
                    end else begin
                        input_mem_addr <= 0;
                        zero_input <= 1;
                    end
                    
                    // Debug
                    // $display("Time %t: oy=%d ox=%d ky=%d kx=%d -> iy=%d ix=%d (Valid: %b) Addr=%d Zero=%b", 
                    //     $time, oy, ox, ky, kx, iy_s, ix_s, 
                    //     (iy_s >= 0 && iy_s < $signed({8'b0, input_h}) && ix_s >= 0 && ix_s < $signed({8'b0, input_w})),
                    //     (iy_s * input_w + ix_s), zero_input);
                    
                    // Accumulator Control
                    // We accumulate into (oy, ox)
                    acc_enable_pipe[0] <= 1;
                    acc_addr_pipe[0] <= oy * output_w + ox; // Use output_w for stride
                    
                    if (ky == 0 && kx == 0) 
                        acc_clear_pipe[0] <= 1;
                    else 
                        acc_clear_pipe[0] <= 0;
                        
                    // Loop Spatial
                    // Iterate over Output Dimensions
                    if (ox == output_w - 1) begin
                        ox <= 0;
                        if (oy == output_h - 1) begin
                            state <= S_NEXT_KERNEL;
                        end else begin
                            oy <= oy + 1;
                        end
                    end else begin
                        ox <= ox + 1;
                    end
                end
                
                // -------------------------------------------------------------
                // 3. Next Kernel Slice
                // -------------------------------------------------------------
                S_NEXT_KERNEL: begin
                    acc_enable_pipe[0] <= 0; // Ensure disabled
                    
                    // Wait for pipeline to drain?
                    // The controller moves to LOAD_WEIGHT immediately.
                    // But the array is still processing the last 16 inputs.
                    // We need to wait 16 cycles before starting the next kernel load?
                    // Actually, loading weights doesn't affect the pipeline flow IF we don't overwrite weights being used.
                    // But we ARE overwriting weights.
                    // So we MUST wait for the pipeline to drain (16 cycles).
                    
                    if (drain_cnt == 20) begin
                        drain_cnt <= 0;
                        if (kx == kernel_w - 1) begin
                            kx <= 0;
                            if (ky == kernel_h - 1) begin
                                state <= S_DONE;
                            end else begin
                                ky <= ky + 1;
                                state <= S_LOAD_WEIGHT_INIT;
                            end
                        end else begin
                            kx <= kx + 1;
                            state <= S_LOAD_WEIGHT_INIT;
                        end
                    end else begin
                        drain_cnt <= drain_cnt + 1;
                    end
                end
                
                S_DONE: begin
                    done <= 1;
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule
