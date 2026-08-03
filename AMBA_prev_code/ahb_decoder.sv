`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11.05.2026 07:04:37
// Design Name: 
// Module Name: ahb_decoder
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module ahb_decoder(
input logic [31:0] HADDR,
output logic [2:0] HSEL
    );
    localparam logic [11:0] RAM_BASE = 12'h000;
    localparam logic [11:0] ROM_BASE = 12'h100;
    localparam logic [11:0] APB_BASE = 12'h400;
    
    
    always_comb 
    begin
    HSEL = 3'b000;
    unique case (HADDR[31:20])
    
    RAM_BASE: HSEL = 3'b001;
    ROM_BASE: HSEL = 3'b010;
    APB_BASE: HSEL = 3'b100;
    default: HSEL = 3'b000;
    endcase
    end
    
endmodule
