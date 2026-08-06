// -----------------------------------------------------------------------------
// priority_comparator  (spec �3 � Priority comparison logic)
//
// Purely combinational. Evaluated only on Priority slots, over *currently
// requesting masters only* � a non-requesting master is never a candidate,
// regardless of its priority value.
//
// It finds the maximum priority value among requesters and reports:
//   - `any_req`          : at least one master is requesting this cycle.
//   - `tied_mask`        : the set of requesters whose priority equals the max.
//   - `is_tie`           : two or more requesters share that max value (�3a is
//                          engaged by the top level).
//   - `unique_valid`     : exactly one requester holds the strict max.
//   - `direct_grant_vec` : one-hot grant for that unique max (valid only when
//                          `unique_valid`); all-zero otherwise.
//
// When `is_tie`, `tied_mask` is handed to tie_break_rr_unit (�3a) to pick the
// winner. When exactly one master holds the max, `tied_mask` is itself already
// one-hot and equals `direct_grant_vec`. There is no separate "full tie" case:
// a tie whose membership happens to equal all requesters is still just a tie.
//
// This block never reads or writes the main RR pointer's state (�3/�8.3).
//
// Implementation: a balanced O(log2 NUM_MASTERS)-deep pairwise reduction tree,
// not two sequential O(NUM_MASTERS) folds (find-max, then find-who's-tied).
// The old two-pass fold made every master's comparison depend on the previous
// one's result *and* chained the second pass behind the first, so it was the
// dominant contributor to this block's combinational depth (STA showed it as
// the deepest path in the whole arbiter).
//
// The tree is built with `generate`/genvar, not procedural for-loops over
// arrays: a genvar-indexed generate loop is fully unrolled into separate
// static hardware at elaboration time by the language definition itself, so
// there's no risk of a synthesis tool leaving behind real dynamic bookkeeping
// logic for what are actually fixed loop bounds (an earlier procedural-array
// version of this tree relied on a tool's constant-folding to remove that
// bookkeeping, and Vivado did not fold it as aggressively as Yosys did,
// making the "optimization" measurably worse in practice). Each tree node
// carries (req, pri, mask) for its subrange, flattened into per-level bit
// vectors the same way pri_flat/tied_mask already are elsewhere in this
// design (node i's slice at bit offset i*WIDTH). Merging two nodes keeps the
// higher-priority side outright, or unions the masks on an exact tie � so the
// final root node's mask/req are identical to what the old fold computed,
// just produced in log2(N) levels instead of ~2*N.
// -----------------------------------------------------------------------------

module priority_comparator #(
    parameter int NUM_MASTERS = 4,
    parameter int PRI_WIDTH   = 3
) (
    input  logic [NUM_MASTERS-1:0]            req_vec,
    input  logic [NUM_MASTERS*PRI_WIDTH-1:0]  pri_flat,   // per-master priority, packed

    output logic [NUM_MASTERS-1:0]            direct_grant_vec, // one-hot when unique max
    output logic                              unique_valid,     // exactly one master at max
    output logic                              is_tie,           // >= 2 masters at max
    output logic [NUM_MASTERS-1:0]            tied_mask,        // requesters at max (subset for �3a)
    output logic                              any_req
);

    localparam int LEVELS = (NUM_MASTERS <= 1) ? 0 : $clog2(NUM_MASTERS);

    // Elaboration-time-only helper: how many live nodes remain at a given
    // level (level 0 = NUM_MASTERS leaves, halving � rounded up � each level).
    // Only ever called with genvar/localparam arguments below, so every call
    // resolves to a constant at elaboration; it generates no hardware itself.
    function automatic int count_at_level(input int level);
        int c;
        c = NUM_MASTERS;
        for (int k = 0; k < level; k++) c = (c + 1) / 2;
        count_at_level = c;
    endfunction

    // Per level, a flat bit-vector of node fields (same flatten convention as
    // pri_flat/tied_mask: node i's slice sits at bit offset i*WIDTH). Only
    // the first count_at_level(L) slots of level L are ever driven/read.
    wire [NUM_MASTERS-1:0]             req_lvl  [0:LEVELS];
    wire [NUM_MASTERS*PRI_WIDTH-1:0]   pri_lvl  [0:LEVELS];
    wire [NUM_MASTERS*NUM_MASTERS-1:0] mask_lvl [0:LEVELS];

    genvar gi, gl;

    // Leaves: one node per master.
    generate
        for (gi = 0; gi < NUM_MASTERS; gi = gi + 1) begin : g_leaf
            assign req_lvl[0][gi] = req_vec[gi];
            assign pri_lvl[0][gi*PRI_WIDTH +: PRI_WIDTH] = pri_flat[gi*PRI_WIDTH +: PRI_WIDTH];
            assign mask_lvl[0][gi*NUM_MASTERS +: NUM_MASTERS] =
                req_vec[gi] ? (NUM_MASTERS'(1) << gi) : '0;
        end
    endgenerate

    // Pairwise-merge levels until one node remains: the higher live priority
    // wins outright; an exact tie unions both masks. An unpaired trailing
    // node (odd count at this level) carries straight through unmerged.
    generate
        for (gl = 0; gl < LEVELS; gl = gl + 1) begin : g_level
            localparam int CUR_N  = count_at_level(gl);
            localparam int NEXT_N = (CUR_N + 1) / 2;

            for (gi = 0; gi < NEXT_N; gi = gi + 1) begin : g_node
                if (2*gi + 1 < CUR_N) begin : g_pair
                    wire                   a_req  = req_lvl[gl][2*gi];
                    wire [PRI_WIDTH-1:0]   a_pri  = pri_lvl[gl][(2*gi)*PRI_WIDTH +: PRI_WIDTH];
                    wire [NUM_MASTERS-1:0] a_mask = mask_lvl[gl][(2*gi)*NUM_MASTERS +: NUM_MASTERS];
                    wire                   b_req  = req_lvl[gl][2*gi+1];
                    wire [PRI_WIDTH-1:0]   b_pri  = pri_lvl[gl][(2*gi+1)*PRI_WIDTH +: PRI_WIDTH];
                    wire [NUM_MASTERS-1:0] b_mask = mask_lvl[gl][(2*gi+1)*NUM_MASTERS +: NUM_MASTERS];

                    assign req_lvl[gl+1][gi] = a_req | b_req;

                    assign pri_lvl[gl+1][gi*PRI_WIDTH +: PRI_WIDTH] =
                        (a_req && (!b_req || a_pri >= b_pri)) ? a_pri : b_pri;

                    assign mask_lvl[gl+1][gi*NUM_MASTERS +: NUM_MASTERS] =
                        !a_req             ? b_mask :
                        !b_req             ? a_mask :
                        (a_pri > b_pri)    ? a_mask :
                        (b_pri > a_pri)    ? b_mask :
                                             (a_mask | b_mask);
                end
                else begin : g_pass
                    assign req_lvl[gl+1][gi] = req_lvl[gl][2*gi];
                    assign pri_lvl[gl+1][gi*PRI_WIDTH +: PRI_WIDTH] =
                        pri_lvl[gl][(2*gi)*PRI_WIDTH +: PRI_WIDTH];
                    assign mask_lvl[gl+1][gi*NUM_MASTERS +: NUM_MASTERS] =
                        mask_lvl[gl][(2*gi)*NUM_MASTERS +: NUM_MASTERS];
                end
            end
        end
    endgenerate

    assign any_req   = req_lvl[LEVELS][0];
    assign tied_mask = mask_lvl[LEVELS][0 +: NUM_MASTERS];

     assign is_tie       = |(tied_mask & (tied_mask - 1'b1));
    assign unique_valid = any_req && !is_tie;

    // Unique max: tied_mask is already one-hot and IS the grant. Otherwise none.
    assign direct_grant_vec = unique_valid ? tied_mask : '0;

endmodule
