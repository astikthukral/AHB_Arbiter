`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 24.07.2026 12:17:22
// Design Name: 
// Module Name: lock_ctrl
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
// lock_ctrl  (spec §5 — Lock-hold logic)
//
// Tracks which master (if any) currently holds LOCK and holds the bus with it
// across a multi-beat sequence, overriding priority and round-robin absolutely
// (§5). While locked:
//   - `locked` is asserted and `lock_grant_vec` forces GRANT to the lock holder,
//     so no re-arbitration occurs from any source (including a higher-priority
//     requester arriving mid-lock).
//   - `freeze` holds slot_alternation_ctrl (§4) so the entire sequence counts as
//     one slot. `freeze` drops on the completing cycle so the slot still toggles
//     exactly once when the sequence ends.
//
// Engagement: a lock engages when the *effective* granted master (fed back as
// `eff_grant`) is asserting LOCK and the slot is not already completing. The
// slot type / tie-ness at engagement is latched (`lock_via_tie`) so the top
// level can advance the correct pointer when the locked sequence finally
// completes (the granting pointer advances exactly as on a normal completion).
//
// Release: only on `slot_complete` (§5). Because the engagement path is taken
// only while `lock_held == 0`, a master leaving lock cannot re-engage in the
// same cycle it releases — it must win the next arbitration slot fairly, which
// is exactly the "no privileged re-entry" rule (§5). This module gives the just
// -released master no special path back into lock.
// -----------------------------------------------------------------------------

module lock_ctrl #(
    parameter int NUM_MASTERS = 4
) (
    input  logic                   clk,
    input  logic                   rst_n,

    input  logic [NUM_MASTERS-1:0] eff_grant,     // final (post-override) grant, fed back
    input  logic [NUM_MASTERS-1:0] lock_vec,      // LOCK[i] per master
    input  logic                   via_tie_in,    // current priority grant is via a tie (§3a)
    input  logic                   slot_complete, // merged completion -> releases the lock

    output logic                   locked,        // a lock is currently held
    output logic [NUM_MASTERS-1:0] lock_grant_vec,// one-hot forced grant while locked
    output logic                   lock_via_tie,  // latched tie-ness of the locking slot
    output logic                   freeze         // freeze slot_alternation during the sequence
);

    logic                   lock_held;
    logic [NUM_MASTERS-1:0]  lock_master_oh;
    logic                    held_via_tie;

    // The effective granted master is asserting LOCK this cycle.
    logic lock_req;
    assign lock_req = |(eff_grant & lock_vec);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lock_held      <= 1'b0;
            lock_master_oh <= '0;
            held_via_tie   <= 1'b0;
        end
        else if (lock_held) begin
            // Held: release only when the sequence completes. No re-arbitration.
            if (slot_complete)
                lock_held <= 1'b0;
        end
        else begin
            // Not locked: engage if the granted master asserts LOCK and the slot
            // is not already completing this cycle. No privileged re-entry: this
            // path runs only while lock_held == 0, so it cannot fire on the same
            // cycle a previous lock releases.
            if (lock_req && !slot_complete) begin
                lock_held      <= 1'b1;
                lock_master_oh <= eff_grant;
                held_via_tie   <= via_tie_in;
            end
        end
    end

    assign locked         = lock_held;
    assign lock_grant_vec = lock_held ? lock_master_oh : '0;
    assign lock_via_tie   = held_via_tie;

    // Frozen throughout the sequence, but not on the completing cycle, so the
    // locked sequence consumes exactly one slot of alternation (§4/§5).
    assign freeze = lock_held && !slot_complete;

endmodule
