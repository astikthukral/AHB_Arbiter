`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11.05.2026 06:20:47
// Design Name: 
// Module Name: ahb_mux
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


module ahb_mux#(
parameter NUM_MASTERS=3
    )
   (
    input logic [$clog2(NUM_MASTERS)-1:0] HMASTER,
   
    input logic [31:0] HADDR_M [0:NUM_MASTERS-1],
    input logic [1:0] HTRANS_M [0:NUM_MASTERS-1],
    input logic HWRITE_M [0:NUM_MASTERS-1],
    input logic [31:0] HWDATA_M [0:NUM_MASTERS-1],
    input logic [2:0] HSIZE_M [0:NUM_MASTERS-1],
    input logic [2:0] HBURST_M [0:NUM_MASTERS-1],
       
    output logic [31:0] HADDR,
    output logic [1:0] HTRANS,
    output logic HWRITE,
    output logic [31:0] HWDATA,
    output logic [2:0] HSIZE,
    output logic [2:0] HBURST
   );
   assign HADDR = HADDR_M[HMASTER];
   assign HTRANS = HTRANS_M[HMASTER];
   assign HWRITE = HWRITE_M[HMASTER];
   assign HWDATA = HWDATA_M[HMASTER];
   assign HSIZE = HSIZE_M[HMASTER];
   assign HBURST = HBURST_M[HMASTER]; 
    
endmodule
