# -----------------------------------------------------------------------------
# amba_arbiter_top.xdc
#
# Timing constraints for amba_arbiter_top (NUM_MASTERS=4, PRI_WIDTH=3 defaults).
#   1. Defines the clock (without it all 19 flops report "no_clock").
#   2. Constrains every data input/output relative to that clock.
#   3. Excludes the asynchronous reset from setup/hold analysis, since rst_n
#      feeds `negedge rst_n` directly and isn't a synchronous data pin.
#
# I/O budget rationale
# --------------------
# The previous 40%/10%-of-period budgets (4.0ns / 1.0ns) were placeholders, and
# they were not survivable: 4ns in + 4ns out of a 10ns period leaves 1.965ns
# inside the chip, while IBUF (~1.00ns) + OBUF (~2.64ns) alone cost 3.64ns
# before a single LUT is placed. Every failing endpoint in the routed report
# touched a package pin; there was not one flop-to-flop setup violation.
#
# 1.0ns models what this block actually connects to: another block on the same
# clock, i.e. one flop's clk-to-q plus a little routing. That is the correct
# budget for an on-chip arbiter. A 4ns budget describes an off-chip
# source-synchronous interface, which this is not.
#
# Only the MAX budget moves (4.0 -> 1.0). The MIN budget stays at 1.0ns, which
# is what it already was, because hold has almost no margin: WHS is 0.076ns on
# REQ[3] -> u_rr/rr_ptr_reg[0]/D, an input path, with six more input paths
# between 0.077ns and 0.217ns behind it. Min input delay is subtracted straight
# out of hold arrival, so lowering it to e.g. 0.2ns would push all seven
# negative and trade a setup problem for a hold problem. Setup and hold read
# the same port through different corners; they are tuned independently.
#
# That razor-thin hold margin is itself an artifact of the same boundary
# asymmetry: set_input_delay models the upstream launch as occurring at the
# ideal clock edge, while the destination flop is charged the full 4.573ns of
# BUFG insertion delay. For two blocks sharing one clock net on one die that
# skew does not exist. Modelling the source clock's latency (set_clock_latency
# -source, or a virtual clock with matching latency) removes the fake hold
# pressure here and the fake setup pressure on the outputs at the same time.
#
# NOTE: this alone does NOT close timing. It fixes the five pad->flop endpoints.
# The pad->pad paths (PRI -> GRANT / slot_complete) and the flop->pad path
# (slot_type) still fail, because:
#   - pad->pad carries IBUF + 8 LUT levels + OBUF with no register in between;
#   - flop->pad is charged the full 4.573ns BUFG clock-insertion delay with
#     nothing on the capture side to compensate it (the destination is a pin).
# Both are boundary problems, not logic problems. Fixing them means not
# implementing this block against pads at all: either synthesize out-of-context
# (-mode out_of_context, no IBUF/OBUF/BUFG inserted), or wrap the core in a
# harness whose registers sit between the arbiter and the pads.
# -----------------------------------------------------------------------------

set CLK_PERIOD_NS 10.000

# On-chip block-to-block budget: upstream flop clk-to-q + short route.
# MAX drives setup (was 4.000 = 40% of period). MIN drives hold and is
# deliberately left at its previous 1.000 -- see the hold note above.
set IO_DELAY_MAX  1.000
set IO_DELAY_MIN  1.000

create_clock -name clk -period $CLK_PERIOD_NS [get_ports clk]

# Asynchronous reset: excluded from setup/hold timing, not from the design.
set_false_path -from [get_ports rst_n]

# ---- Data inputs ------------------------------------------------------------
set data_inputs {REQ[*] PRI[*] LOCK[*] VALID_XFER[*] COMPLETE[*]}
set_input_delay -clock clk -max $IO_DELAY_MAX [get_ports $data_inputs]
set_input_delay -clock clk -min $IO_DELAY_MIN [get_ports $data_inputs]

# ---- Data outputs -----------------------------------------------------------
set data_outputs {GRANT[*] slot_complete slot_type}
set_output_delay -clock clk -max $IO_DELAY_MAX [get_ports $data_outputs]
set_output_delay -clock clk -min $IO_DELAY_MIN [get_ports $data_outputs]

# ---- Placement compaction (Pblock) : REMOVED --------------------------------
# A pblock used to live here. It never took effect. The cell list came from
#   [get_cells -hierarchical -filter {PRIMITIVE_LEVEL==LEAF}]
# which swept up all 36 IBUF/OBUF cells and the BUFG along with the logic.
# Those cannot be placed in a SLICE-only range, so Vivado rewrote the
# assignment (impl log: "[Vivado 12-3520] ... Changing the pblock assignment to
# 'u_sa, u_gr, u_lk, u_rr, and u_tb'") and the region became unsatisfiable --
# the placed result landed at SLICE_X0Y26..X3Y50, entirely outside the
# requested SLICE_X0Y0:SLICE_X9Y19, with routing still at 67-80% of path delay.
#
# The spread placement it was meant to fix is driven by the 36 bonded IOBs that
# have no PACKAGE_PIN constraints: Vivado auto-assigns pins around the die
# perimeter and the placer drags the 84 LUTs out toward them. Constrain the
# pins (and register the boundary) rather than fencing the logic. If a region
# is still wanted afterwards, assign the logic hierarchy only:
#
#   create_pblock pblock_arbiter
#   resize_pblock pblock_arbiter -add {SLICE_X0Y0:SLICE_X9Y19}
#   add_cells_to_pblock pblock_arbiter [get_cells {u_rr u_pc u_tb u_sa u_lk u_gr u_cm}]
