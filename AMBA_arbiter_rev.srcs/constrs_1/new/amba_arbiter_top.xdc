# -----------------------------------------------------------------------------
# amba_arbiter_top.xdc
#
# Starter timing constraints for amba_arbiter_top (NUM_MASTERS=4, PRI_WIDTH=3
# defaults). Resolves the "Check Timing" report's no_clock / no_input_delay /
# no_output_delay / unconstrained_internal_endpoints findings by:
#   1. Defining the clock (currently the only thing making all 19 flops
#      "no_clock").
#   2. Constraining every data input/output relative to that clock.
#   3. Excluding the asynchronous reset from setup/hold analysis, since
#      rst_n feeds `negedge rst_n` directly and isn't a synchronous data pin.
#
# Adjust CLK_PERIOD_NS to your real target frequency, and the input/output
# delay budgets to whatever actually drives/receives this block upstream/
# downstream. The values below are placeholder starting points (40%/10% of
# the period), not measured numbers.
# -----------------------------------------------------------------------------

set CLK_PERIOD_NS 10.000
set IO_DELAY_MAX  [expr {$CLK_PERIOD_NS * 0.4}]
set IO_DELAY_MIN  [expr {$CLK_PERIOD_NS * 0.1}]

create_clock -name clk -period $CLK_PERIOD_NS [get_ports clk]

# Asynchronous reset: excluded from setup/hold timing, not from the design.
set_false_path -from [get_ports rst_n]

# ---- Data inputs ------------------------------------------------------------
set data_inputs {REQ[*] PRI[*] LOCK[*] VALID_XFER[*] COMPLETE[*]}
set_input_delay -clock clk -max $IO_DELAY_MAX [get_ports $data_inputs]
set_input_delay -clock clk -min $IO_DELAY_MIN [get_ports $data_inputs]

# ---- Data outputs -------------------------------------------------------
set data_outputs {GRANT[*] slot_complete slot_type}
set_output_delay -clock clk -max $IO_DELAY_MAX [get_ports $data_outputs]
set_output_delay -clock clk -min $IO_DELAY_MIN [get_ports $data_outputs]

# ---- Placement compaction (Pblock) ------------------------------------------
# This is a ~100-LUT / 19-FF design, but without a placement region the placer
# was spreading it across a ~22-row span of the die (observed: SLICE_X0Y56 to
# SLICE_X3Y78), which made every net between pipeline-free logic levels cost
# 0.4-1.9ns of routing -- 80% of the failing paths' delay was routing, not
# logic (Data Path Delay 11.137ns = 2.226ns logic + 8.911ns route). Forcing
# everything into a small, contiguous region should bring per-hop routing
# delay down to something much more typical (~0.3-0.4ns) and is the actual
# fix for that -- no RTL change closes a placement problem.
#
# This is a placement constraint, so it only takes effect during
# Implementation (synthesis ignores it). If SLICE_X0Y0:SLICE_X9Y19 isn't a
# valid/legal region on your part, adjust the range, or delete this block and
# instead draw a Pblock interactively in the Device view (Tools ->
# Floorplanning -> Draw Pblock) and assign all of the design's cells to it.
create_pblock pblock_arbiter
resize_pblock pblock_arbiter -add {SLICE_X0Y0:SLICE_X9Y19}
add_cells_to_pblock pblock_arbiter [get_cells -hierarchical -filter {PRIMITIVE_LEVEL==LEAF}]
