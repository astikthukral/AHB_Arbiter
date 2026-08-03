`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 24.07.2026 12:18:56
// Design Name: 
// Module Name: completion_merge
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
// completion_merge  (spec §8 of module_description — Completion glue)
//
// Small combinational glue that ORs the genuine transfer-completion signal with
// grace_window_timer's forced-completion output into ONE `slot_complete` signal.
//
// This is deliberately the single definition of "completion" in the design:
// rr_pointer_unit (§2), tie_break_rr_unit (§3a) and slot_alternation_ctrl (§4)
// all key their advance logic off exactly this signal, so there is one notion of
// completion, not two.
// -----------------------------------------------------------------------------

module completion_merge (
    input  logic genuine_complete, // real transfer completion of the granted master
    input  logic forced_complete,  // grace-window forced completion (§5a)

    output logic slot_complete     // the single shared completion handshake
);

    assign slot_complete = genuine_complete | forced_complete;

endmodule

