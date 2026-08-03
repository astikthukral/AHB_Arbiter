# AMBA Arbiter Top

Synthesizable SystemVerilog arbiter core with round-robin selection, priority selection, nested tie-breaking, lock override, and a grace window for abandoned grants.

This repository contains the current Vivado project for `amba_arbiter_top` and its supporting modules. The design is parameterized for `NUM_MASTERS = 4`, `PRI_WIDTH = 3`, and `GRACE_W = 4` by default.

## Overview

The top-level arbiter alternates between two slot types:

- Round-robin slots, where the next requester is chosen by cyclic pointer order.
- Priority slots, where the highest-priority requesting master wins.

When multiple requesters share the highest priority, a second round-robin pointer breaks the tie fairly. If the granted master asserts `LOCK`, the grant is held across a multi-beat sequence and the slot alternation is frozen until completion. If a grant is issued but the master never starts a transfer, the grace-window timer forces completion so the arbiter does not stall indefinitely.

## Repository Layout

```text
AMBA_arbiter_rev/
├── AMBA_arbiter_rev.xpr
├── AMBA_arbiter_rev.srcs/
│   ├── sources_1/
│   │   └── new/
│   │       ├── amba_arbiter_top.sv
│   │       ├── completion_merge.sv
│   │       ├── grace_window_timer.sv
│   │       ├── lock_ctrl.sv
│   │       ├── priority_comparator.sv
│   │       ├── rotate_mask_encoder.sv
│   │       ├── rr_pointer_unit.sv
│   │       ├── slot_alternation_ctrl.sv
│   │       ├── tie_brak_rr_unit.sv
│   │       └── tie_break_rr_unit.sv
│   ├── sim_1/
│   │   └── new/
│   │       ├── rotate_mask_encoder_tb.sv
│   │       ├── tb_amba_arbiter_top.sv
│   │       ├── tb_completion_merge.sv
│   │       ├── tb_grace_window_timer.sv
│   │       ├── tb_lock_ctrl.sv
│   │       ├── tb_priority_comparator.sv
│   │       ├── tb_rr_pointer_unit.sv
│   │       ├── tb_slot_alternation_ctrl.sv
│   │       └── tb_tie_break_rr_unit.sv
│   └── constrs_1/
│       └── new/
│           └── amba_arbiter_top.xdc
└── README.md
```

## Top-Level Interface

The arbiter is implemented in `amba_arbiter_top.sv`.

### Inputs

| Signal | Description |
|---|---|
| `clk` | System clock |
| `rst_n` | Active-low asynchronous reset |
| `REQ[NUM_MASTERS-1:0]` | One request bit per master |
| `PRI[NUM_MASTERS*PRI_WIDTH-1:0]` | Packed per-master priority values |
| `LOCK[NUM_MASTERS-1:0]` | Per-master lock request bits |
| `VALID_XFER[NUM_MASTERS-1:0]` | Indicates that the granted master has actually started a transfer |
| `COMPLETE[NUM_MASTERS-1:0]` | Per-master completion pulse |

### Outputs

| Signal | Description |
|---|---|
| `GRANT[NUM_MASTERS-1:0]` | One-hot grant for the selected master |
| `slot_complete` | Shared completion handshake used by the whole design |
| `slot_type` | Slot selector: `0` = round-robin, `1` = priority |

## Module Map

- `amba_arbiter_top.sv` wires all submodules together and resolves the final grant.
- `rotate_mask_encoder.sv` rotates a mask around a pointer and picks the closest set bit in cyclic order.
- `rr_pointer_unit.sv` holds the main round-robin pointer and advances it only after a completed round-robin slot.
- `priority_comparator.sv` finds the maximum priority among requesting masters and detects ties.
- `tie_break_rr_unit.sv` applies a second round-robin pointer to the tied-at-max subset.
- `slot_alternation_ctrl.sv` toggles between round-robin and priority slots on each completed slot.
- `lock_ctrl.sv` holds the granted master while `LOCK` is asserted and freezes slot alternation during the sequence.
- `grace_window_timer.sv` starts a bounded window after each grant and forces completion if the transfer never begins.
- `completion_merge.sv` merges real completion and forced completion into a single `slot_complete` signal.
- `tie_brak_rr_unit.sv` is a legacy stub file present in the source folder; the implemented tie-break logic is in `tie_break_rr_unit.sv`.

## How It Works

1. `rr_pointer_unit` selects the next requester for round-robin slots.
2. `priority_comparator` finds the highest-priority requesting masters for priority slots.
3. If the highest priority is shared, `tie_break_rr_unit` resolves the tie fairly.
4. `lock_ctrl` overrides the normal selection whenever the granted master asserts `LOCK`.
5. `grace_window_timer` watches for grants that never turn into real transfers and emits `forced_complete` when the window expires.
6. `completion_merge` combines real completion and forced completion into `slot_complete`.
7. `slot_alternation_ctrl` flips the slot type only when the merged completion handshake fires and the slot is not frozen by a lock.

## Simulation

The main integration testbench is `tb_amba_arbiter_top.sv`. It checks:

- round-robin selection and pointer advance
- priority selection with a unique maximum
- priority tie resolution through the nested round-robin pointer
- lock hold behavior across multiple beats
- grace-window completion for an abandoned grant

Additional unit testbenches are provided for the submodules in `AMBA_arbiter_rev.srcs/sim_1/new/`.

### Run in Vivado

1. Open `AMBA_arbiter_rev.xpr` in Vivado.
2. Add or confirm the RTL sources under `AMBA_arbiter_rev.srcs/sources_1/new/`.
3. Add `AMBA_arbiter_rev.srcs/sim_1/new/tb_amba_arbiter_top.sv` as the simulation top.
4. Run behavioral simulation.

You can also run the unit testbenches individually if you want to debug one block at a time.

## Timing Constraints

The active constraint file is `AMBA_arbiter_rev.srcs/constrs_1/new/amba_arbiter_top.xdc`.

It currently:

- defines a 10 ns clock (`100 MHz`) as a starting point
- adds placeholder input and output delays relative to that clock
- excludes `rst_n` from timing analysis with a false path
- applies a Pblock to keep the small arbiter physically compact during implementation

Adjust the clock period and I/O delays to match your target board and interface timing. The constraint file is a practical starting point, not a sign-off set.

## Notes

- This README matches the current arbiter-centric codebase, not the earlier flat `src/` and `tb/` layout.
- The design is intentionally modular so the pointer logic, tie-breaking, lock control, and grace-window behavior can be tested independently.
- If you add new RTL or testbench files, update both the Vivado project and this README tree.
