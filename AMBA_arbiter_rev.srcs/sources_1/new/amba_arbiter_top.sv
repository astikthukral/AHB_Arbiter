`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 24.07.2026 12:19:31
// Design Name: 
// Module Name: amba_arbiter_top
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
// amba_arbiter_top  (Top-level integration)
//
// Integrates �1-�8 into the complete AMBA-style arbiter:
//   Round-Robin + Priority + Lock-Override, with a grace window for abandoned
//   grants. Routes REQ/PRI/LOCK/VALID_XFER (and the protocol completion signal),
//   instantiates every sub-module, and muxes the final one-hot GRANT based on
//   the current slot type, with lock_ctrl's override taking absolute precedence.
//
// Grant selection each cycle:
//   RR slot       : GRANT = rr_pointer_unit's rotate/mask grant over REQ.
//   PRIORITY slot : GRANT = unique max requester, or � on a tie � tie_break_rr's
//                   grant over the tied-at-max subset.
//   Locked        : GRANT = the lock holder, regardless of the above (�5).
//
// Completion / advance:
//   genuine_complete = the granted master's COMPLETE, *suppressed while it is
//                      still asserting LOCK* so intermediate beats of a locked
//                      sequence do not end the slot � the sequence ends only when
//                      LOCK drops and COMPLETE asserts (�5).
//   slot_complete    = genuine_complete | grace forced_complete (�5a).
//   On slot_complete the granting pointer/counter advances (�2/�3a/�4): RR slot
//   -> rr_ptr; PRIORITY slot & tie -> tie_ptr; unique-max -> neither pointer,
//   only the alternation toggles. For a locked slot the latched tie-ness
//   (lock_via_tie) steers which pointer advances, since the live priority
//   landscape may have changed by the completing cycle.
//
// Standing assumptions carried from �8: within a single (non-locked) transfer a
// master keeps REQ/PRI stable until it completes; combined with the pointers not
// advancing until completion, the combinational grant is stable across the
// transfer. LOCK is what holds the grant against *changing* conditions.
// -----------------------------------------------------------------------------

module amba_arbiter_top #(
    parameter int NUM_MASTERS = 4,
    parameter int PRI_WIDTH   = 3,
    parameter int GRACE_W     = 4,                        // �5a window length
    parameter int PTR_WIDTH   = (NUM_MASTERS <= 1) ? 1 : $clog2(NUM_MASTERS)
) (
    input  logic                             clk,
    input  logic                             rst_n,

    input  logic [NUM_MASTERS-1:0]           REQ,         // request lines
    input  logic [NUM_MASTERS*PRI_WIDTH-1:0] PRI,         // per-master priority, packed
    input  logic [NUM_MASTERS-1:0]           LOCK,        // lock-hold request per master
    input  logic [NUM_MASTERS-1:0]           VALID_XFER,  // transfer-started per master (�5a)
    input  logic [NUM_MASTERS-1:0]           COMPLETE,    // genuine transfer/beat completion

    output logic [NUM_MASTERS-1:0]           GRANT,       // one-hot grant
    output logic                             slot_complete, // exposed shared handshake
    output logic                             slot_type      // 0 = RR, 1 = PRIORITY (observability)
);

    localparam logic SLOT_RR       = 1'b0;
    localparam logic SLOT_PRIORITY = 1'b1;

    // ---- inter-module nets --------------------------------------------------
    logic [NUM_MASTERS-1:0] rr_grant;
    logic                   rr_valid;

    logic [NUM_MASTERS-1:0] direct_grant;
    logic                   unique_valid;
    logic                   is_tie;
    logic [NUM_MASTERS-1:0] tied_mask;
    logic                   any_req;

    logic [NUM_MASTERS-1:0] tie_grant;
    logic                   tie_valid;

    logic                   locked;
    logic [NUM_MASTERS-1:0] lock_grant_vec;
    logic                   lock_via_tie;
    logic                   freeze;

    logic                   forced_complete;

    // ---- combinational grant selection -------------------------------------
    logic [NUM_MASTERS-1:0] prio_grant;
    logic [NUM_MASTERS-1:0] arb_grant;
    logic [NUM_MASTERS-1:0] eff_grant;

    // Priority-slot grant: tie -> �3a winner, otherwise the unique max.
    //assign prio_grant = is_tie ? tie_grant : direct_grant;

    assign prio_grant = tie_grant;
    // Slot-type mux (RR vs PRIORITY), ignoring lock.
    assign arb_grant  = (slot_type == SLOT_RR) ? rr_grant : prio_grant;

    // Lock override has absolute precedence (�5).
    assign eff_grant  = locked ? lock_grant_vec : arb_grant;
    assign GRANT      = eff_grant;

    // Is the priority grant this cycle happening via a tie? (latched by lock_ctrl)
    logic via_tie;
    assign via_tie = (slot_type == SLOT_PRIORITY) && is_tie;

    // ---- completion path ----------------------------------------------------
    logic genuine_raw;   // granted master's real completion
    logic lock_now;      // granted master still asserting LOCK this cycle
    logic genuine_complete;

    assign genuine_raw      = |(COMPLETE & GRANT);
    assign lock_now         = |(LOCK    & GRANT);
    // Suppress genuine completion while LOCK is asserted: the locked sequence ends
    // only once LOCK drops and the final COMPLETE arrives (�5).
    assign genuine_complete = genuine_raw && !lock_now;

    // ---- advance qualification (�2/�3a/�4) ---------------------------------
    logic tie_ctx;
    logic adv_rr;
    logic adv_tie;

    // For a locked slot the live tie-ness may have changed by completion, so use
    // the latched value; otherwise use the live comparator result.
    assign tie_ctx = locked ? lock_via_tie : is_tie;

    assign adv_rr  = slot_complete && (|GRANT) && (slot_type == SLOT_RR);
    assign adv_tie = slot_complete && (|GRANT) && (slot_type == SLOT_PRIORITY) && tie_ctx;

    // ---- sub-module instances ----------------------------------------------
    rr_pointer_unit #(
        .NUM_MASTERS (NUM_MASTERS),
        .PTR_WIDTH   (PTR_WIDTH)
    ) u_rr (
        .clk         (clk),
        .rst_n       (rst_n),
        .req_vec     (REQ),
        .advance     (adv_rr),
        .grant_vec   (rr_grant),
        .grant_valid (rr_valid),
        .ptr         ()
    );

    priority_comparator #(
        .NUM_MASTERS (NUM_MASTERS),
        .PRI_WIDTH   (PRI_WIDTH)
    ) u_pc (
        .req_vec          (REQ),
        .pri_flat         (PRI),
        .direct_grant_vec (direct_grant),
        .unique_valid     (unique_valid),
        .is_tie           (is_tie),
        .tied_mask        (tied_mask),
        .any_req          (any_req)
    );

    tie_break_rr_unit #(
        .NUM_MASTERS (NUM_MASTERS),
        .PTR_WIDTH   (PTR_WIDTH)
    ) u_tb (
        .clk         (clk),
        .rst_n       (rst_n),
        .tied_mask   (tied_mask),
        .advance     (adv_tie),
        .grant_vec   (tie_grant),
        .grant_valid (tie_valid),
        .ptr         ()
    );

    slot_alternation_ctrl u_sa (
        .clk           (clk),
        .rst_n         (rst_n),
        .slot_complete (slot_complete),
        .freeze        (freeze),
        .slot_type     (slot_type)
    );

    lock_ctrl #(
        .NUM_MASTERS (NUM_MASTERS)
    ) u_lk (
        .clk            (clk),
        .rst_n          (rst_n),
        .eff_grant      (eff_grant),
        .lock_vec       (LOCK),
        .via_tie_in     (via_tie),
        .slot_complete  (slot_complete),
        .locked         (locked),
        .lock_grant_vec (lock_grant_vec),
        .lock_via_tie   (lock_via_tie),
        .freeze         (freeze)
    );

    grace_window_timer #(
        .NUM_MASTERS (NUM_MASTERS),
        .W           (GRACE_W)
    ) u_gr (
        .clk             (clk),
        .rst_n           (rst_n),
        .grant_vec       (GRANT),
        .valid_xfer      (VALID_XFER),
        .slot_complete   (slot_complete),
        .forced_complete (forced_complete)
    );

    completion_merge u_cm (
        .genuine_complete (genuine_complete),
        .forced_complete  (forced_complete),
        .slot_complete    (slot_complete)
    );

endmodule

