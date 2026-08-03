// -----------------------------------------------------------------------------
// tie_break_rr_unit  (spec §3a — Nested tie-break RR pointer)
//
// A SECOND, independent round-robin pointer `tie_ptr`, structurally a sibling of
// rr_pointer_unit (§2) rather than a variant of it. It resolves ties among the
// masters that are tied at the maximum priority on a Priority slot, by running
// the same shared rotate_mask_encoder — this time against the *tied-at-max
// subset* (`tied_mask`) supplied by priority_comparator, rather than the raw
// request vector.
//
// Advance discipline (§3a): moves by exactly one cyclic position iff `advance`
// is asserted. `advance` is qualified upstream to mean: it actually resolved a
// tie this cycle AND that master's transfer completed. A unique highest-priority
// requester (no tie) leaves this pointer completely untouched — the top level
// simply does not assert `advance`.
//
// Masks are recomputed fresh each consultation (done in priority_comparator), so
// a master joining/leaving the tied set needs no special handling here — the
// pointer just rotates through cyclic order and the current mask picks whoever
// is eligible now. Kept as a separate instance from §2 to preserve the state
// independence the spec relies on (§8.3).
// -----------------------------------------------------------------------------

module tie_break_rr_unit #(
    parameter int NUM_MASTERS = 4,
    parameter int PTR_WIDTH   = (NUM_MASTERS <= 1) ? 1 : $clog2(NUM_MASTERS)
) (
    input  logic                   clk,
    input  logic                   rst_n,

    input  logic [NUM_MASTERS-1:0] tied_mask,   // currently-tied-at-max subset (§3a)
    input  logic                   advance,     // resolved-a-tie & completion (qualified upstream)

    output logic [NUM_MASTERS-1:0] grant_vec,   // one-hot tie-break grant
    output logic                   grant_valid, // = |tied_mask
    output logic [PTR_WIDTH-1:0]   ptr          // current pointer (observability)
);

    logic [PTR_WIDTH-1:0] tie_ptr;

    // Same rotate/mask primitive as §2, masked against the tied set instead of req.
    rotate_mask_encoder #(
        .NUM_MASTERS (NUM_MASTERS),
        .PTR_WIDTH   (PTR_WIDTH)
    ) u_enc (
        .mask_vec    (tied_mask),
        .ptr         (tie_ptr),
        .grant_vec   (grant_vec),
        .grant_valid (grant_valid)
    );

    // Advance must move past the actual winner, not just the old pointer: when
    // the tied set is sparse, the winning index can differ from tie_ptr, and
    // incrementing tie_ptr itself can leave it parked right back on the winner
    // (re-granting the same master next time instead of cycling to the rest of
    // the tied set).
    logic [PTR_WIDTH-1:0] winner_idx;
    always_comb begin
        winner_idx = '0;
        for (int i = 0; i < NUM_MASTERS; i++)
            if (grant_vec[i])
                winner_idx = PTR_WIDTH'(i);
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            tie_ptr <= '0;
        else if (advance)
            tie_ptr <= (winner_idx == PTR_WIDTH'(NUM_MASTERS - 1)) ? '0
                                                                   : winner_idx + 1'b1;
    end

    assign ptr = tie_ptr;

endmodule
