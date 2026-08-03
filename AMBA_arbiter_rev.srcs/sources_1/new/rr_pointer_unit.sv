// -----------------------------------------------------------------------------
// rr_pointer_unit  (spec §2 — Main RR pointer)
//
// Holds the main round-robin pointer `rr_ptr` and produces the RR-slot grant by
// instantiating the shared rotate_mask_encoder against the *live request vector*.
//
// Advance discipline (§2): the pointer moves by exactly one position (cyclic)
// if and only if `advance` is asserted. `advance` is qualified by the top level
// to mean: it was an RR-slot AND a grant was issued AND that master's transfer
// completed. Grant-without-completion never advances the pointer.
//
// This unit never reads or writes any other module's state (§8.3). On Priority
// slots the top level simply does not assert `advance`, so the pointer is left
// completely untouched — not frozen as a special case, just not consulted.
// -----------------------------------------------------------------------------

module rr_pointer_unit #(
    parameter int NUM_MASTERS = 4,
    parameter int PTR_WIDTH   = (NUM_MASTERS <= 1) ? 1 : $clog2(NUM_MASTERS)
) (
    input  logic                   clk,
    input  logic                   rst_n,

    input  logic [NUM_MASTERS-1:0] req_vec,     // live request vector
    input  logic                   advance,     // RR-slot & grant & completion (qualified upstream)

    output logic [NUM_MASTERS-1:0] grant_vec,   // one-hot RR grant candidate
    output logic                   grant_valid, // = |req_vec
    output logic [PTR_WIDTH-1:0]   ptr          // current pointer (observability)
);

    logic [PTR_WIDTH-1:0] rr_ptr;

    // Shared primitive: rotate request vector to rr_ptr, leftmost-1 encode, rotate back.
    rotate_mask_encoder #(
        .NUM_MASTERS (NUM_MASTERS),
        .PTR_WIDTH   (PTR_WIDTH)
    ) u_enc (
        .mask_vec    (req_vec),
        .ptr         (rr_ptr),
        .grant_vec   (grant_vec),
        .grant_valid (grant_valid)
    );

    // Advance must move past the actual winner, not just the old pointer: with a
    // sparse req_vec the winning index can differ from rr_ptr, and incrementing
    // rr_ptr itself can leave it parked right back on the winner instead of past it.
    logic [PTR_WIDTH-1:0] winner_idx;
    always_comb begin
        winner_idx = '0;
        for (int i = 0; i < NUM_MASTERS; i++)
            if (grant_vec[i])
                winner_idx = PTR_WIDTH'(i);
    end

    // Advance by exactly one cyclic position past the winner on a qualified
    // completion (§2). Explicit wrap keeps this correct when NUM_MASTERS is not
    // a power of two.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            rr_ptr <= '0;
        else if (advance)
            rr_ptr <= (winner_idx == PTR_WIDTH'(NUM_MASTERS - 1)) ? '0
                                                                  : winner_idx + 1'b1;
    end

    assign ptr = rr_ptr;

endmodule
