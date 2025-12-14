/**
 * Weight Buffer
 * 
 * Description:
 *   Dual-port RAM to store weights.
 *   Port A: Write-only (Loader)
 *   Port B: Read-only (Controller)
 *
 * Author: shealligh
 * Date: 2025-12-11
 */

module weight_buffer #(
    parameter DATA_WIDTH = 128,
    parameter ADDR_WIDTH = 16,
    parameter DEPTH = 65536 // 64K words
)(
    input  wire                  clk,
    
    // Port A (Write)
    input  wire                  we_a,
    input  wire [ADDR_WIDTH-1:0] addr_a,
    input  wire [DATA_WIDTH-1:0] wdata_a,
    
    // Port B (Read)
    input  wire [ADDR_WIDTH-1:0] addr_b,
    output reg  [DATA_WIDTH-1:0] rdata_b
);

    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];
    
    // Write Port
    always @(posedge clk) begin
        if (we_a) begin
            mem[addr_a] <= wdata_a;
        end
    end
    
    // Read Port
    always @(posedge clk) begin
        rdata_b <= mem[addr_b];
    end

endmodule
