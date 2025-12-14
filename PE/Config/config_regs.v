/**
 * Configuration Registers
 * 
 * Description:
 *   Stores configuration parameters for the PE Controller.
 *   Accessible via a simple 32-bit register interface.
 *
 * Address Map:
 *   0x00: Control Register
 *         Bit 0: Start (RW, Auto-clears or Pulse?) -> Let's make it a pulse generator or level.
 *                Controller expects a 'start' signal.
 *   0x04: Status Register (RO)
 *         Bit 0: Done
 *   0x08: Kernel Dimensions
 *         Bits 3:0   -> Kernel Width (KW)
 *         Bits 7:4   -> Reserved
 *         Bits 11:8  -> Kernel Height (KH)
 *   0x0C: Input Dimensions
 *         Bits 7:0   -> Input Width (W)
 *         Bits 15:8  -> Input Height (H)
 *
 * Author: shealligh
 * Date: 2025-12-11
 */

module config_regs (
    input  wire        clk,
    input  wire        rst_n,
    
    // Register Interface
    input  wire        reg_write,
    input  wire [3:0]  reg_addr, // 4-bit address for few registers
    input  wire [31:0] reg_wdata,
    output reg  [31:0] reg_rdata,
    
    // Hardware Interface (To Controller)
    output reg         start,
    input  wire        done,
    
    output reg  [3:0]  kernel_h,
    output reg  [3:0]  kernel_w,
    output reg  [7:0]  input_h,
    output reg  [7:0]  input_w,
    output reg  [3:0]  stride,
    output reg  [3:0]  padding
);

    // Internal storage
    reg [31:0] ctrl_reg;
    // status_reg is purely combinational from inputs
    reg [31:0] kernel_dim_reg;
    reg [31:0] input_dim_reg;
    reg [31:0] param_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ctrl_reg       <= 0;
            kernel_dim_reg <= 0;
            input_dim_reg  <= 0;
            param_reg      <= 0;
            
            start    <= 0;
            kernel_h <= 0;
            kernel_w <= 0;
            input_h  <= 0;
            input_w  <= 0;
            stride   <= 0;
            padding  <= 0;
        end else begin
            // Auto-clear start after 1 cycle (Pulse)
            if (start) start <= 0;
            
            if (reg_write) begin
                case (reg_addr)
                    4'h0: begin // Control
                        if (reg_wdata[0]) start <= 1;
                    end
                    // 4'h1: Status is RO
                    4'h2: begin // Kernel Dims (Addr 0x08 -> Index 2 if word addressed, let's assume byte addr >> 2)
                        kernel_dim_reg <= reg_wdata;
                        kernel_w <= reg_wdata[3:0];
                        kernel_h <= reg_wdata[11:8];
                    end
                    4'h3: begin // Input Dims (Addr 0x0C -> Index 3)
                        input_dim_reg <= reg_wdata;
                        input_w <= reg_wdata[7:0];
                        input_h <= reg_wdata[15:8];
                    end
                    4'h4: begin // Stride & Padding (Addr 0x10 -> Index 4)
                        param_reg <= reg_wdata;
                        stride    <= reg_wdata[3:0];
                        padding   <= reg_wdata[7:4];
                    end
                endcase
            end
        end
    end
    
    // Read Logic
    always @(*) begin
        case (reg_addr)
            4'h0: reg_rdata = {31'b0, start}; // Reflects current state
            4'h1: reg_rdata = {31'b0, done};
            4'h2: reg_rdata = kernel_dim_reg;
            4'h3: reg_rdata = input_dim_reg;
            4'h4: reg_rdata = param_reg;
            default: reg_rdata = 32'd0;
        endcase
    end

endmodule
