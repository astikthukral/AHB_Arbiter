`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 06.08.2026 14:57:12
// Design Name: 
// Module Name: master_model
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


module master_model#
(
    parameter int NUM_MASTERS = 4
)(
input logic clk,
input logic rst_n_sync,
input logic [NUM_MASTERS-1:0] grant,
input logic tick,
input logic [NUM_MASTERS-1:0] sw_req,
input logic [NUM_MASTERS-1:0] sw_abandon,

output logic [NUM_MASTERS-1:0] valid_xfer,
output logic [NUM_MASTERS-1:0] req,
output logic [NUM_MASTERS-1:0] complete
    );

    typedef enum logic [1:0] {
        IDLE,
        ACTIVE,
        ABANDONED
    } state_e;

genvar gi;

generate 
    for (gi = 0; gi<NUM_MASTERS; gi=gi+1) begin : g_master
        state_e state,next;

        always_comb begin
            next = state;
            case(state)
                IDLE: begin
                    if(grant[gi] && sw_req[gi])
                    next = sw_abandon[gi] ? ABANDONED : ACTIVE;
                end
                ACTIVE : begin
                    if(tick) 
                    next = IDLE;
                end
                ABANDONED : begin
                    if(!grant[gi])
                    next = IDLE;
                end
                default: next = IDLE;
            endcase
        end

        always_ff@(posedge clk or negedge rst_n_sync) begin
            if(!rst_n_sync)
                state <= IDLE;
            else
                state <= next;
        end

        assign req[gi] = (state == IDLE) ? sw_req[gi] : 1'b1;

        assign valid_xfer[gi] = (state == ACTIVE);

        assign complete[gi] = (state == ACTIVE) && tick;
    end
    endgenerate
endmodule
