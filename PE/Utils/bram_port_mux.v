`timescale 1ns / 1ps
/**
 * BRAM Port Multiplexer
 * 
 * Description:
 *   Simple 2-to-1 Mux for BRAM Address and Control signals.
 *   Used to share a BRAM port between the PE Controller (during run) 
 *   and an External Interface (when idle).
 *
 * Logic:
 *   if (sel == 1) -> Select Port 1 (External / Idle)
 *   else          -> Select Port 0 (PE / Run)
 *
 * Author: Copilot
 * Date: 2025-12-16
 */

module bram_port_mux #(
    parameter ADDR_WIDTH = 10
)(
    // Select Signal (1 = External, 0 = PE)
    // Connect to 'done' signal from PE Controller
    input  wire                  sel,
    
    // Port 0 Input (From PE Controller)
    input  wire [ADDR_WIDTH-1:0] addr0,
    input  wire                  en0,  // Optional: Read Enable
    
    // Port 1 Input (From External / Testbench)
    input  wire [ADDR_WIDTH-1:0] addr1,
    input  wire                  en1,
    
    // Muxed Output (To BRAM Port)
    output wire [ADDR_WIDTH-1:0] addr_out,
    output wire                  en_out
);

    assign addr_out = (sel) ? addr1 : addr0;
    assign en_out   = (sel) ? en1   : en0;

endmodule
