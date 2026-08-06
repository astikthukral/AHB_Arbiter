    `timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 03.08.2026 20:36:19
// Design Name: 
// Module Name: reset_sync
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


module reset_sync#(
    parameter int STAGES = 2
)
(
    input logic arst_n,
    input logic clk,
    output logic rst_n
    );

    (*ASYNC_REG ="TRUE"*) logic [STAGES-1:0] sync_q;

    always_ff @(posedge clk or negedge arst_n) begin   //async assert being done here
        if(!arst_n) begin
            sync_q <= '0;
        end else begin
            sync_q <= (sync_q <<1) | 1'b1;
        end
    end

    assign rst_n = sync_q[STAGES-1];
endmodule
