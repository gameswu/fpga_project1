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
        end else begin
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
                    // Convolution: Read Input at (oy+ky, ox+kx)
                    // We assume input_mem is large enough.
                    // Address = (oy + ky) * (input_w + kernel_w - 1) + (ox + kx) ?
                    // No, let's assume the memory is organized as a 1D array of vectors.
                    // And the "Stride" is the full input width.
                    // Let's assume the user configures 'input_w' as the OUTPUT width for loop bounds,
                    // but we need the TRUE input width for addressing.
                    // For simplicity in this demo, let's assume Input Width = Output Width + Kernel Width - 1.
                    // Or simpler: Just use a fixed stride or assume Input Width = input_w (and we handle padding/boundary externally).
                    
                    // Let's stick to the simplest valid convolution logic:
                    // We iterate oy, ox. We read Input[oy+ky][ox+kx].
                    // We need to know the stride (Input Width).
                    // Let's assume stride = input_w + kernel_w - 1 (Valid padding).
                    // OR, let's just use (oy+ky) * 256 + (ox+kx) if we assume a large fixed stride?
                    // No, let's use the provided input_w parameter as the stride, assuming it represents the full input width.
                    // And we iterate oy up to (input_h - kernel_h + 1).
                    
                    input_mem_addr <= (oy + ky) * input_w + (ox + kx);
                    
                    // Accumulator Control
                    // We accumulate into (oy, ox)
                    acc_enable_pipe[0] <= 1;
                    acc_addr_pipe[0] <= oy * input_w + ox; // Use same stride for output for now
                    
                    if (ky == 0 && kx == 0) 
                        acc_clear_pipe[0] <= 1;
                    else 
                        acc_clear_pipe[0] <= 0;
                        
                    // Loop Spatial
                    // We iterate up to input_w - kernel_w?
                    // Let's assume the state machine iterates over the VALID output range.
                    // For this specific testbench, we will control input_h/w to be the output size.
                    if (ox == input_w - kernel_w) begin // Simple boundary check for "Valid" convolution
                        ox <= 0;
                        if (oy == input_h - kernel_h) begin
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
