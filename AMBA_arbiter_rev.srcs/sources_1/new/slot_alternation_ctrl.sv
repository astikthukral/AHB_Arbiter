`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 24.07.2026 12:15:05
// Design Name: 
// Module Name: slot_alternation_ctrl
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
// -----------------------------------------------------------------------------
// slot_alternation_ctrl  (spec §4 — Slot alternation)
//
// Holds the single alternation state `slot_type` in {RR, PRIORITY}. It strictly
// toggles RR -> PRIORITY -> RR -> ... , independent of which master either
// pointer actually selects (§4).
//
// Timing rule: the toggle happens only when the current slot's granted transfer
// has *completed* — i.e. on `slot_complete` (the single merged completion signal
// from completion_merge). Grant alone never toggles it.
//
// Lock freeze (§5): while a locked sequence is in progress, `freeze` is asserted
// by lock_ctrl and the counter is held — the entire locked sequence counts as
// one slot of whichever type originally granted it. lock_ctrl deasserts `freeze`
// on the completing cycle so the sequence still consumes exactly one slot.
//
// `slot_type` is the only cross-module coupling the three pointers share (§8.3):
// it tells the top level which of rr_pointer_unit / (priority path) may drive
// the grant this cycle.
// -----------------------------------------------------------------------------

module slot_alternation_ctrl (
    input  logic clk,
    input  logic rst_n,

    input  logic slot_complete,  // merged completion (genuine or grace-forced)
    input  logic freeze,         // hold slot_type during a locked sequence (§5)

    output logic slot_type       // 0 = RR slot, 1 = PRIORITY slot
);

    // Named for readability; slot_type is a single bit.
    localparam logic SLOT_RR       = 1'b0;
    localparam logic SLOT_PRIORITY = 1'b1;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            slot_type <= SLOT_RR;                 // start on an RR slot
        else if (slot_complete && !freeze)
            slot_type <= ~slot_type;              // strict alternation on completion
    end

endmodule
