/**
 * Activation Buffer (Input Buffer)
 * 
 * Description:
 *   Dual-port RAM to store input activations.
 *   Stores vectors of 16 bytes (128 bits) for the PE Array.
 *   
 *   Port A: Write-only (Loader)
 *   Port B: Read-only (Controller)
 *
 * Author: shealligh
 * Date: 2025-12-11
 */

module act_buffer #(
    parameter DATA_WIDTH = 128, // 16 * 8-bit
    parameter ADDR_WIDTH = 16,
    parameter DEPTH = 65536
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
        // Debug Read
        // if (addr_b < 10) // Limit debug
        //     $display("Time %t: act_buffer READ addr=%d data=%h", $time, addr_b, mem[addr_b]);
    end

    // Debug
    // always @(posedge clk) begin
    //     if (we_a) begin
    //         $display("Time %t: act_buffer WRITE addr=%d data=%h", $time, addr_a, wdata_a);
    //     end
    // end

endmodule
