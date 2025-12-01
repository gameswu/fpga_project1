/**
 * PE Controller - Processing Element Array Controller
 * 
 * Description:
 *   Orchestrates 16x16 PE Array for convolution operations.
 *   Implements Weight Stationary dataflow with tiling support.
 *   
 * Features:
 *   - Tiling for Output Channels and Spatial Dimensions
 *   - Weight Stationary dataflow
 *   - Automatic padding handling
 *   - Address generation for Weight and Input memories
 *
 * Author: Auto-generated for fpga_project1
 * Date: 2025-12-01
 */

module pe_controller #(
    parameter ARRAY_DIM = 16,      // PE Array dimension (16x16)
    parameter IFM_H     = 32,      // Input Feature Map Height
    parameter IFM_W     = 32,      // Input Feature Map Width
    parameter OFM_H     = 32,      // Output Feature Map Height
    parameter OFM_W     = 32,      // Output Feature Map Width
    parameter K_H       = 5,       // Kernel Height
    parameter K_W       = 5,       // Kernel Width
    parameter PAD       = 2,       // Padding
    parameter STRIDE    = 1,       // Stride
    parameter CHANNELS  = 32       // Number of Output Channels
) (
    // Clock and Reset
    input  wire        clk,
    input  wire        rst_n,
    
    // Control Interface
    input  wire        start,           // Start convolution operation
    output reg         done,            // Operation complete
    
    // PE Array Control Signals
    output reg         enable,          // Enable PE Array computation
    output reg         acc_clear,       // Clear PE Array accumulators
    output reg         weight_load,     // Load weights into PE Array
    
    // PE Array Data Interface (16x16 array, 8-bit per element)
    output reg  [ARRAY_DIM*8-1:0]      pe_data_in,     // 2048 bits: Input broadcast to columns
    output reg  [ARRAY_DIM*8-1:0]      pe_weight_in,   // 2048 bits: Weight broadcast to rows
    input  wire [ARRAY_DIM*ARRAY_DIM*32-1:0] pe_acc_out,  // 8192 bits: Accumulator outputs
    
    // Weight Memory Interface
    output reg  [15:0] weight_addr,     // Address for Weight Memory
    input  wire [ARRAY_DIM*8-1:0] weight_rdata,  // 128 bits: 16 INT8 weights
    
    // Input Memory Interface
    output reg  signed [15:0] input_ref_y,   // Reference Y coordinate
    output reg  signed [15:0] input_ref_x,   // Reference X coordinate
    input  wire [ARRAY_DIM*8-1:0] input_rdata,  // 128 bits: 16 INT8 pixels
    
    // Output Interface
    output reg         output_valid,    // Output data is valid
    output reg  [ARRAY_DIM*ARRAY_DIM*32-1:0] output_data  // 8192 bits: Final results
);

    // =========================================================================
    // Local Parameters
    // =========================================================================
    
    // Calculate number of tiles
    localparam NUM_CHANNEL_TILES = (CHANNELS + ARRAY_DIM - 1) / ARRAY_DIM;
    localparam NUM_SPATIAL_TILES = ((OFM_H * OFM_W) + ARRAY_DIM - 1) / ARRAY_DIM;
    
    // State Machine States
    localparam STATE_IDLE         = 4'd0;
    localparam STATE_START_TILE   = 4'd1;
    localparam STATE_LOAD_WEIGHT  = 4'd2;
    localparam STATE_WAIT_WEIGHT  = 4'd3;
    localparam STATE_COMPUTE      = 4'd4;
    localparam STATE_WAIT_COMPUTE = 4'd5;
    localparam STATE_READ_OUT     = 4'd6;
    localparam STATE_DONE         = 4'd7;
    
    
    // =========================================================================
    // Internal Registers
    // =========================================================================
    
    reg [3:0] state, next_state;
    
    // Tile counters
    reg [7:0] channel_tile_idx;   // Current output channel tile (0..NUM_CHANNEL_TILES-1)
    reg [7:0] spatial_tile_idx;   // Current spatial tile (0..NUM_SPATIAL_TILES-1)
    
    // Kernel position counters
    reg [7:0] ky;                 // Kernel Y position (0..K_H-1)
    reg [7:0] kx;                 // Kernel X position (0..K_W-1)
    
    // Output position within current tile
    reg [7:0] tile_oy;            // Output Y within tile (0..3)
    reg [7:0] tile_ox;            // Output X within tile (0..3)
    
    // Absolute output position
    reg [7:0] abs_oy;             // Absolute output Y
    reg [7:0] abs_ox;             // Absolute output X
    
    // Input coordinates (can be negative due to padding)
    reg signed [15:0] input_y;
    reg signed [15:0] input_x;
    
    // Wait counter
    reg [3:0] wait_cnt;
    
    
    // =========================================================================
    // State Machine - Sequential Logic
    // =========================================================================
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= STATE_IDLE;
        else
            state <= next_state;
    end
    
    
    // =========================================================================
    // State Machine - Combinational Logic
    // =========================================================================
    
    always @(*) begin
        // Default values
        next_state = state;
        
        case (state)
            STATE_IDLE: begin
                if (start)
                    next_state = STATE_START_TILE;
            end
            
            STATE_START_TILE: begin
                next_state = STATE_LOAD_WEIGHT;
            end
            
            STATE_LOAD_WEIGHT: begin
                next_state = STATE_WAIT_WEIGHT;
            end
            
            STATE_WAIT_WEIGHT: begin
                if (wait_cnt == 0)
                    next_state = STATE_COMPUTE;
            end
            
            STATE_COMPUTE: begin
                next_state = STATE_WAIT_COMPUTE;
            end
            
            STATE_WAIT_COMPUTE: begin
                if (wait_cnt == 0) begin
                    // Check if kernel scan is complete
                    if (kx == K_W - 1 && ky == K_H - 1)
                        next_state = STATE_READ_OUT;
                    else
                        next_state = STATE_LOAD_WEIGHT;
                end
            end
            
            STATE_READ_OUT: begin
                // Check if all tiles are done (check before incrementing)
                if (spatial_tile_idx == NUM_SPATIAL_TILES - 1 && 
                    channel_tile_idx == NUM_CHANNEL_TILES - 1)
                    next_state = STATE_DONE;
                else
                    next_state = STATE_START_TILE;
            end
            
            STATE_DONE: begin
                next_state = STATE_IDLE;
            end
            
            default: begin
                next_state = STATE_IDLE;
            end
        endcase
    end
    
    
    // =========================================================================
    // Counter Updates
    // =========================================================================
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            channel_tile_idx <= 0;
            spatial_tile_idx <= 0;
            ky <= 0;
            kx <= 0;
            wait_cnt <= 0;
        end
        else begin
            case (state)
                STATE_IDLE: begin
                    if (start) begin
                        channel_tile_idx <= 0;
                        spatial_tile_idx <= 0;
                        ky <= 0;
                        kx <= 0;
                    end
                end
                
                STATE_START_TILE: begin
                    ky <= 0;
                    kx <= 0;
                end
                
                STATE_WAIT_WEIGHT: begin
                    if (wait_cnt > 0)
                        wait_cnt <= wait_cnt - 1;
                end
                
                STATE_LOAD_WEIGHT: begin
                    wait_cnt <= 2;  // Wait 2 cycles for weight loading
                end
                
                STATE_COMPUTE: begin
                    wait_cnt <= 1;  // Wait 1 cycle for computation
                end
                
                STATE_WAIT_COMPUTE: begin
                    if (wait_cnt > 0) begin
                        wait_cnt <= wait_cnt - 1;
                    end
                    else begin
                        // Increment kernel position after wait completes
                        if (kx == K_W - 1) begin
                            kx <= 0;
                            if (ky == K_H - 1)
                                ky <= 0;  // Reset for next tile
                            else
                                ky <= ky + 1;
                        end
                        else begin
                            kx <= kx + 1;
                        end
                    end
                end
                
                STATE_READ_OUT: begin
                    // Move to next tile
                    if (spatial_tile_idx == NUM_SPATIAL_TILES - 1) begin
                        spatial_tile_idx <= 0;
                        if (channel_tile_idx < NUM_CHANNEL_TILES - 1)
                            channel_tile_idx <= channel_tile_idx + 1;
                    end
                    else begin
                        spatial_tile_idx <= spatial_tile_idx + 1;
                    end
                end
            endcase
        end
    end
    
    
    // =========================================================================
    // Output Position Calculation
    // =========================================================================
    
    always @(*) begin
        // Calculate absolute output position from spatial tile index
        abs_oy = (spatial_tile_idx * ARRAY_DIM) / OFM_W;
        abs_ox = (spatial_tile_idx * ARRAY_DIM) % OFM_W;
    end
    
    
    // =========================================================================
    // Address Generation and Control Signals
    // =========================================================================
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            enable       <= 0;
            acc_clear    <= 0;
            weight_load  <= 0;
            done         <= 0;
            output_valid <= 0;
            weight_addr  <= 0;
            input_ref_y  <= 0;
            input_ref_x  <= 0;
            pe_data_in   <= 0;
            pe_weight_in <= 0;
            output_data  <= 0;
        end
        else begin
            // Default: clear control signals
            enable       <= 0;
            acc_clear    <= 0;
            weight_load  <= 0;
            done         <= 0;
            output_valid <= 0;
            
            case (state)
                STATE_IDLE: begin
                    // Reset outputs
                    weight_addr  <= 0;
                    input_ref_y  <= 0;
                    input_ref_x  <= 0;
                end
                
                STATE_START_TILE: begin
                    // Clear accumulators at start of new tile
                    acc_clear <= 1;
                end
                
                STATE_LOAD_WEIGHT: begin
                    // Generate weight address
                    // Address = (channel_tile * K_H * K_W * ARRAY_DIM) + (ky * K_W + kx) * ARRAY_DIM
                    weight_addr <= (channel_tile_idx * K_H * K_W * ARRAY_DIM) + 
                                   ((ky * K_W + kx) * ARRAY_DIM);
                    
                    // Load weight data into PE array
                    weight_load  <= 1;
                    pe_weight_in <= weight_rdata;
                end
                
                STATE_COMPUTE: begin
                    // Calculate input coordinate
                    input_y = $signed(abs_oy) * STRIDE + $signed(ky) - PAD;
                    input_x = $signed(abs_ox) * STRIDE + $signed(kx) - PAD;
                    
                    input_ref_y <= input_y;
                    input_ref_x <= input_x;
                    
                    // Enable MAC operation
                    enable <= 1;
                    
                    // Broadcast input data (handle padding in memory controller)
                    pe_data_in <= input_rdata;
                end
                
                STATE_READ_OUT: begin
                    // Latch output data
                    output_valid <= 1;
                    output_data  <= pe_acc_out;
                end
                
                STATE_DONE: begin
                    done <= 1;
                end
            endcase
        end
    end
    
endmodule
