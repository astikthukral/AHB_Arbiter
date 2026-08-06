# -----------------------------------------------------------------------------
# ooc_timing.tcl -- out-of-context synth + impl of amba_arbiter_top, for an
# honest timing report on the arbiter logic alone.
#
# Run:  vivado -mode batch -source D:/Verilog-vitis/Verilog_project/AMBA_arbiter_rev/ooc_timing.tcl
# or from the Vivado Tcl console:
#       source D:/Verilog-vitis/Verilog_project/AMBA_arbiter_rev/ooc_timing.tcl
#
# -mode out_of_context tells synth_design not to insert IBUF/OBUF/BUFG. That
# removes the three costs that produced every remaining failing endpoint in the
# pad-level run:
#   IBUF               ~1.00 ns
#   OBUF               ~2.64 ns
#   BUFG insertion      4.57 ns  (charged to launch on flop->pad paths, with
#                                 nothing on the capture side to cancel it)
# What is left is the arbiter: ~84 LUTs, 19 flops, 8 logic levels worst case.
#
# No bitstream is produced and none can be -- an OOC design has no I/O. Stop at
# route_design; that is where the timing numbers come from.
# -----------------------------------------------------------------------------

set ROOT D:/Verilog-vitis/Verilog_project/AMBA_arbiter_rev
set SRC  $ROOT/AMBA_arbiter_rev.srcs/sources_1/new
set OUT  $ROOT/ooc_out
# set PART xc7a100tcsg324-1
set PART xc7a35tcpg236-1


file mkdir $OUT

# ---- Sources ----------------------------------------------------------------
# Design only. Testbenches and the tie_brak_rr_unit.sv stub are excluded.
read_verilog -sv [list \
    $SRC/rotate_mask_encoder.sv   \
    $SRC/priority_comparator.sv   \
    $SRC/rr_pointer_unit.sv       \
    $SRC/tie_break_rr_unit.sv     \
    $SRC/slot_alternation_ctrl.sv \
    $SRC/lock_ctrl.sv             \
    $SRC/grace_window_timer.sv    \
    $SRC/completion_merge.sv      \
    $SRC/amba_arbiter_top.sv      \
]

read_xdc $ROOT/AMBA_arbiter_rev.srcs/constrs_1/new/amba_arbiter_top.xdc

# ---- Synthesis --------------------------------------------------------------
synth_design -top amba_arbiter_top -part $PART -mode out_of_context

write_checkpoint -force $OUT/post_synth.dcp
report_timing_summary -file $OUT/post_synth_timing.rpt
report_utilization    -file $OUT/post_synth_util.rpt

# ---- Implementation ---------------------------------------------------------
opt_design
place_design
phys_opt_design
route_design

write_checkpoint -force $OUT/post_route.dcp

# ---- Reports ----------------------------------------------------------------
report_timing_summary -delay_type min_max -max_paths 10 \
                      -file $OUT/post_route_timing_summary.rpt
report_timing -setup -max_paths 20 -path_type full_clock_expanded \
              -file $OUT/post_route_setup_paths.rpt
report_utilization -file $OUT/post_route_util.rpt

# ---- Headline numbers to stdout --------------------------------------------
set wns [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
set whs [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
set per [get_property PERIOD [get_clocks clk]]

puts "-----------------------------------------------------------"
puts [format "  Constrained period : %.3f ns  (%.1f MHz)" $per [expr {1000.0/$per}]]
puts [format "  WNS                : %.3f ns" $wns]
puts [format "  WHS                : %.3f ns" $whs]
puts [format "  Implied Fmax       : %.1f MHz" [expr {1000.0/($per - $wns)}]]
puts "-----------------------------------------------------------"
puts "  Reports written to $OUT"
