`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 24.07.2026 12:18:12
// Design Name: 
// Module Name: grace_window_timer
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
// grace_window_timer  (spec §5a — Abandoned-grant fix)
//
// Independent of LOCK — gated on VALID_XFER, not on lock assertion. One instance,
// shared across whichever master currently holds the grant (RR or tie-break).
//
// Once a grant is issued to master i, a fixed W-cycle window starts:
//   - If VALID_XFER[i] asserts at any point within the window, the transfer is
//     legitimately underway; the check disengages (`started`) and however long
//     the transfer then takes to COMPLETE is governed entirely by the normal
//     §2/§3a/§4 completion rule. A slow-but-real transfer is never truncated.
//   - If VALID_XFER[i] has NOT asserted by the time the window expires, the grant
//     is treated as abandoned: `forced_complete` pulses, and completion_merge
//     turns that into a slot_complete so the granting pointer/counter advances
//     exactly as on a normal completion (§5a). This can only fire in the window
//     immediately after grant, before any transfer begins — never mid-transfer.
//
// The window restarts whenever the granted master changes (`new_grant`), and
// resets when the grant drops or the slot completes.
// -----------------------------------------------------------------------------

module grace_window_timer #(
    parameter int NUM_MASTERS = 4,
    parameter int W           = 4,                       // grace window length (cycles)
    parameter int CNT_WIDTH   = (W < 1) ? 1 : $clog2(W + 1)
) (
    input  logic                   clk,
    input  logic                   rst_n,

    input  logic [NUM_MASTERS-1:0] grant_vec,     // effective one-hot grant
    input  logic [NUM_MASTERS-1:0] valid_xfer,    // VALID_XFER[i] per master
    input  logic                   slot_complete, // merged completion -> disengage/reset

    output logic                   forced_complete
);

    logic [CNT_WIDTH-1:0]   count;
    logic                   started;      // VALID_XFER seen -> grace disengaged
    logic [NUM_MASTERS-1:0] prev_grant;

    logic grant_active;
    logic granted_vxfer;
    logic new_grant;

    assign grant_active  = |grant_vec;
    assign granted_vxfer = |(grant_vec & valid_xfer);        // granted master driving valid xfer
    assign new_grant     = grant_active && (grant_vec != prev_grant);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            count      <= '0;
            started    <= 1'b0;
            prev_grant <= '0;
        end
        else begin
            prev_grant <= grant_vec;

            if (!grant_active) begin
                // No outstanding grant to watch.
                count   <= '0;
                started <= 1'b0;
            end
            else if (new_grant) begin
                // Fresh grant this cycle: restart the window.
                count   <= '0;
                started <= granted_vxfer;   // 1 only if it starts driving immediately
            end
            else if (slot_complete) begin
                // Slot ended (genuine or forced): disengage and reset.
                count   <= '0;
                started <= 1'b0;
            end
            else begin
                if (granted_vxfer)
                    started <= 1'b1;         // latch: transfer is underway
                if (!started && !granted_vxfer && (count < CNT_WIDTH'(W)))
                    count <= count + 1'b1;   // still waiting for the transfer to start
            end
        end
    end

    // Window fully elapsed with no transfer ever having started -> abandoned grant.
    assign forced_complete = grant_active && !started && !granted_vxfer &&
                             (count >= CNT_WIDTH'(W));

endmodule

