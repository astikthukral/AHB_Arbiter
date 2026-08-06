# AMBA-Style Four-Master Bus Arbiter

Synthesizable SystemVerilog arbiter with round-robin selection, static priority, nested tie-breaking, absolute lock override, and recovery from abandoned grants — plus a Basys 3 board demonstration wrapper.

Parameterized for `NUM_MASTERS = 4`, `PRI_WIDTH = 3`, `GRACE_W = 4`. Target part `xc7a35tcpg236-1` (Basys 3); previously characterized on `xc7a100tcsg324-1`.

## Results at a Glance

| | Result |
|---|---|
| Arbiter core, out-of-context timing | **WNS +0.421 ns**, 67 LUTs, 19 FF |
| Board demo, implemented | **WNS +1.610 ns**, hold +0.122 ns, 0 / 277 failing endpoints |
| Implied F<sub>max</sub> | ~119 MHz (100 MHz target) |
| Utilization (demo) | 168 LUTs (0.81 %), 134 FF (0.32 %), 34 IOB |
| DRC / routing | 0 violations; 320 / 320 nets routed |
| RTL simulation | 88 slots, 9 scenarios, 0 errors |
| Post-implementation simulation | 88 slots, netlist matches RTL slot for slot |
| Bitstream | generated, 0 warnings |
| Hardware validation | outstanding — requires the board |

Timing closure took WNS from **−12.426 ns / 11 failing endpoints** to the figures above. 

---

## Overview

The arbiter alternates between two slot types:

- **Round-robin slots** — the next requester is chosen by cyclic pointer order.
- **Priority slots** — the highest-priority requesting master wins.

When several requesters share the highest priority, a **second, independent** round-robin pointer breaks the tie within that subset only. If the granted master asserts `LOCK`, the grant is held across a multi-beat sequence and slot alternation freezes until completion. If a grant is issued but the master never starts a transfer, a grace-window timer forces completion so the bus does not stall.

Strict alternation is what makes the design starvation-free: because round-robin slots occur every second slot and the pointer cycles through all N masters, **every requesting master is guaranteed a slot within 2N slots** — eight, for four masters — regardless of how badly it loses on priority.

---

## Repository Layout

```text
AMBA_arbiter_rev/
├── AMBA_arbiter_rev.xpr
├── AMBA_arbiter_rev.srcs/
│   ├── sources_1/new/
│   │   ├── amba_arbiter_top.sv          # arbiter core
│   │   ├── rotate_mask_encoder.sv       #   shared rotate/mask/encode primitive
│   │   ├── rr_pointer_unit.sv           #   main round-robin pointer
│   │   ├── priority_comparator.sv       #   max-priority reduction tree
│   │   ├── tie_break_rr_unit.sv         #   nested tie-break pointer
│   │   ├── slot_alternation_ctrl.sv     #   RR <-> PRIORITY toggle
│   │   ├── lock_ctrl.sv                 #   lock hold and override
│   │   ├── grace_window_timer.sv        #   abandoned-grant recovery
│   │   ├── completion_merge.sv          #   single completion definition
│   │   ├── amba_arbiter_demo_top.sv     # board demo wrapper
│   │   ├── master_model.sv              #   per-master behavioural FSM
│   │   ├── reset_sync.sv                #   async assert / sync deassert
│   │   └── tie_brak_rr_unit.sv          # legacy stub, not in the project
│   ├── sim_1/new/
│   │   ├── tb_amba_arbiter_top.sv               # core integration bench
│   │   ├── tb_amba_arbiter_demo_top.sv          # wrapper, RTL
│   │   ├── tb_amba_arbiter_demo_top_postimpl.sv # wrapper, port-only (netlist)
│   │   └── tb_*.sv                              # per-module unit benches
│   └── constrs_1/new/
│       ├── amba_arbiter_top.xdc         # core characterization (OOC flow)
│       └── basys3_demo.xdc              # board pins + timing (active)
├── ooc_timing.tcl                       # out-of-context synth + impl script
├── arbiter_design_report.tex            # full design & timing-closure report
└── README.md
```

---

## Arbiter Core

### Interface

`amba_arbiter_top.sv`

| Signal | Dir / Width | Description |
|---|---|---|
| `clk` | in, 1 | System clock |
| `rst_n` | in, 1 | Active-low reset, asynchronous assertion |
| `REQ` | in, N | One request bit per master |
| `PRI` | in, N×3 | Packed priorities; master *i* at `PRI[i*3 +: 3]` |
| `LOCK` | in, N | Per-master lock request |
| `VALID_XFER` | in, N | The granted master has actually started its transfer |
| `COMPLETE` | in, N | Per-master completion |
| `GRANT` | out, N | One-hot grant |
| `slot_complete` | out, 1 | The shared completion handshake |
| `slot_type` | out, 1 | `0` = round-robin slot, `1` = priority slot |

### Module map

| Module | Role |
|---|---|
| `amba_arbiter_top` | Wires the submodules together and resolves the final grant |
| `rotate_mask_encoder` | Rotates a mask around a pointer, picks the closest set bit in cyclic order. Instantiated **twice** so both pointers are structurally identical by construction |
| `rr_pointer_unit` | Main round-robin pointer; advances only after a completed RR slot, and moves *past the actual winner* rather than merely incrementing |
| `priority_comparator` | Balanced O(log₂N) pairwise reduction tree over **requesting masters only**; emits `tied_mask` and `is_tie` |
| `tie_break_rr_unit` | Second, independent pointer applied to the tied-at-max subset |
| `slot_alternation_ctrl` | Toggles slot type on each completed slot; frozen during a lock |
| `lock_ctrl` | Holds the granted master while `LOCK` is asserted; no privileged re-entry |
| `grace_window_timer` | Bounded window after each grant; forces completion if the transfer never begins |
| `completion_merge` | Merges genuine and forced completion into one `slot_complete` |

`tie_brak_rr_unit.sv` is a legacy stub left in the folder; it is **not** part of the Vivado project. The implemented logic is in `tie_break_rr_unit.sv`.

### How it works

1. `rr_pointer_unit` produces the round-robin candidate from the live `REQ` vector.
2. `priority_comparator` reduces `REQ` and `PRI` to `tied_mask` — the requesters holding the maximum priority.
3. `tie_break_rr_unit` rotates within `tied_mask` to produce the priority-slot grant.
4. `slot_type` selects between the two candidates.
5. `lock_ctrl` overrides both with the latched lock holder, with absolute precedence.
6. `genuine_complete` is the granted master's `COMPLETE`, **suppressed while it still asserts `LOCK`**, so intermediate beats do not end a locked sequence.
7. `grace_window_timer` independently asserts `forced_complete` for an abandoned grant.
8. `completion_merge` ORs the two into `slot_complete` — the **single** definition of "a slot ended". Both pointers, the alternation counter, the lock and the grace timer all key off exactly this signal, so they cannot disagree.

### Guarantees

- **Starvation-free** — every requesting master wins a slot within 2N slots.
- **Priority respected** — the strict maximum wins every priority slot.
- **Fair tie-breaking** — ties rotate within the tied subset; the tie pointer is untouched when a unique maximum exists.
- **Atomic locked sequences** — one lock consumes exactly one slot of alternation.
- **Liveness against absent masters** — a grant that never becomes a transfer is reclaimed after `GRACE_W` cycles.

### Known limitations

Stated precisely, because they are design positions rather than oversights.

- **Turn-based, not time-based.** The bound is on *slots waited*, not wall-clock latency. Turn fairness is not bandwidth fairness: a master with very long transfers can take almost all the bandwidth while receiving only its share of turns. In practice AHB bounds burst length, which is what makes this sufficient.
- **An indefinitely held `LOCK` starves everyone.** `slot_complete` never fires, so the lock never releases. A lock timeout is the highest-value addition the design could take.
- **A started-but-never-completed transfer hangs the arbiter.** `forced_complete` is gated on `!started` by design, so a slow-but-real transfer is never truncated — but the arbiter cannot distinguish "slow" from "dead". Closing this needs a transaction watchdog *and* an abort channel to the master, which is essentially AHB `SPLIT`/`RETRY`.
- **Undocumented assumption:** a master that starts a transfer will finish it.

---

## Board Demo Wrapper

`amba_arbiter_demo_top.sv` makes the arbiter observable on a Basys 3.

Its ports are **board resources only** — `clk`, `btnC`, `btnU`, `sw[15:0]`, `led[15:0]`. The arbiter's `REQ`/`PRI`/`GRANT` interface stays entirely internal, which is both what it will be in any real system and what keeps the pad-level timing closable.

### Contents

| Block | Purpose |
|---|---|
| `reset_sync` | Async assert / sync deassert, `ASYNC_REG` — all flops leave reset on the same edge |
| Switch synchronizer | Two flops on `sw[15:0]`; switches are asynchronous and bouncy |
| Tick generator | ~2 Hz single-cycle pulse used as a **clock enable**, not a divided clock, so everything stays in one 100 MHz domain |
| Priority table | Four presets, selector latched at slot boundaries to honour the arbiter's `PRI`-stability contract |
| `master_model` | Per-master FSM: `IDLE` → `ACTIVE` → back on tick, or → `ABANDONED`. Holds `REQ` through a transfer and derives `VALID_XFER`/`COMPLETE` from `GRANT` |
| Debounce + edge detect | `btnU` single-step; one press = one transaction |
| Pulse stretcher | `slot_complete` is a 10 ns pulse — stretched to ~50 ms to be visible |

### Switch and LED map

| Switches | Field |
|---|---|
| `sw[3:0]` | `REQ[3:0]` — master *i* is requesting |
| `sw[7:4]` | `LOCK[3:0]` — master *i* asserts `LOCK` while granted |
| `sw[11:8]` | `ABANDON[3:0]` — master *i* never asserts `VALID_XFER` |
| `sw[13:12]` | Priority preset select |
| `sw[15]` | `0` = free-run at ~2 Hz, `1` = single-step on `btnU` |
| `btnC` | Reset |
| `btnU` | Step (in step mode) |

| LEDs | Shows |
|---|---|
| `led[3:0]` | `GRANT` |
| `led[4]` | `slot_type` (0 = RR, 1 = PRIORITY) |
| `led[5]` | `slot_complete`, stretched |
| `led[15:12]` | `REQ` as seen by the arbiter |

### Priority presets

| `sw[13:12]` | Preset | M3 M2 M1 M0 | Exercises |
|---|---|---|---|
| `00` | All equal | 4 4 4 4 | Full tie — the tie pointer rotates through every requester |
| `01` | Graded | 3 2 1 0 | Unique maximum every priority slot; tie pointer untouched |
| `10` | Partial tie | 5 5 1 1 | `tied_mask` is a strict subset; M1/M0 reach the bus only on RR slots |
| `11` | One dominant | 7 1 1 1 | The starvation-prevention case |

### Demonstrations

1. **Round-robin fairness** — preset `00`, all requesting. Both pointers advance in lockstep, giving `M0,M0,M1,M1,M2,M2,M3,M3`.
2. **Priority ordering** — preset `01`, all requesting. M3 takes every priority slot; RR slots rotate.
3. **Starvation prevention** — preset `11`, all requesting. M3 outranks the others 7-to-1 and takes five of every eight slots, yet M0–M2 **never disappear**. Then drop `sw[3]` and watch the remaining three fall into tie-break rotation.
4. **Tie-break rotation** — preset `10`. M3/M2 alternate on priority slots while M1/M0 appear only on RR slots.
5. **Lock** — set `sw[4]`. When M0 is next granted its LED sticks and `led[4]` stops toggling, because `freeze` holds the alternation. Clear the switch and the walk resumes.
6. **Abandoned grant** — set `sw[8]`. M0 drops out of the rotation and the others keep cycling. The forced completion takes ~5 cycles, so you see the *effect*, not the grant itself — the point being that without the grace window the bus would hang permanently.

Single-step mode (`sw[15]`) is the better way to study any of these: it lets you read the LEDs one transaction at a time.

---

## Verification

### Testbenches

| Bench | Level | Result |
|---|---|---|
| `tb_amba_arbiter_top.sv` | Arbiter core, RTL | pass |
| `tb_amba_arbiter_demo_top.sv` | Full wrapper, RTL | 88 slots, 9 scenarios, 0 errors |
| `tb_amba_arbiter_demo_top_postimpl.sv` | Implemented netlist | 88 slots, 0 errors |
| `tb_*.sv` | Per-module unit benches | pass |

The post-implementation run matched the RTL run **slot for slot** across all 88 transactions, confirming synthesis and implementation preserved behaviour exactly.

### Property-based checking

Checking is property-based rather than vector-based — exact grant sequences are brittle against the relative phase of the two pointers, while properties hold for every legal run.

| ID | Property |
|---|---|
| P1 | `GRANT` is one-hot or zero |
| P2 | Never grant a non-requesting master (suppressed while locked, where override is correct) |
| P3 | `COMPLETE` is a single-cycle pulse |
| P4 | `slot_type` toggles once per `slot_complete`, never otherwise |
| P5 | `GRANT` is stable within a slot |
| — | **Every requester is served within 2N slots** — the headline fairness guarantee, checked continuously across every scenario |

### Running simulation

**RTL:**

```tcl
set_property top tb_amba_arbiter_demo_top [get_filesets sim_1]
```
Then Flow → Run Simulation → Run Behavioral Simulation.

**Post-implementation.** Parameters cannot be overridden in a netlist — they are baked into the gates at synthesis time — so the netlist must be *built* small:

```tcl
set_property generic {TICK_DIV=20 DEBOUNCE_CYCLES=4} [get_filesets sources_1]
reset_run synth_1
launch_runs impl_1 -jobs 8
wait_on_run impl_1
set_property top tb_amba_arbiter_demo_top_postimpl [get_filesets sim_1]
```

Then Run Post-Implementation Functional Simulation, and revert afterwards:

```tcl
reset_property generic [get_filesets sources_1]
reset_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 8
```

`TICK_DIV` and `DEBOUNCE_CYCLES` are `parameter`, not `localparam`, purely so this is possible. At hardware values a single transaction spans 5×10⁷ cycles.

---

## Constraints and Timing

### Two constraint files

**`basys3_demo.xdc`** — the active set. Pin locations and I/O standards from Digilent's Basys 3 master XDC, plus:

```tcl
set_false_path -from [get_ports {sw[*]}]
set_false_path -from [get_ports btnC]
set_false_path -from [get_ports btnU]
set_false_path -to   [get_ports {led[*]}]
```

Switches and buttons are mechanical and asynchronous; LEDs have no setup/hold relationship to anything. All are handled in RTL by synchronizers. False-pathing states that explicitly rather than leaving them silently unanalysed.

**`amba_arbiter_top.xdc`** — used only by `ooc_timing.tcl` for characterizing the arbiter core. Disable it in the project when building the demo, since its constraints reference ports the wrapper does not expose:

```tcl
set_property is_enabled false [get_files amba_arbiter_top.xdc]
```

### Characterizing the core

```tcl
source ooc_timing.tcl
```

Runs out-of-context synthesis and implementation (no IBUF/OBUF/BUFG inserted), writes reports to `ooc_out/`, and prints WNS, WHS and implied F<sub>max</sub>. This is the right abstraction for a block that will be integrated rather than pinned out.

### Timing progression

| Stage | WNS | TNS | Failing | LUTs |
|---|---|---|---|---|
| Original (4 ns I/O budgets, pblock) | −12.426 | −65.627 | 11 / 30 | 84 |
| I/O max 4 → 1 ns, pblock removed | −5.192 | −22.256 | 6 / 30 | 84 |
| Out-of-context | +0.115 | 0.000 | 0 / 30 | 83 |
| + cheaper `is_tie` | +0.340 | 0.000 | 0 / 30 | 83 |
| + redundant mux removed | +0.373 | 0.000 | 0 / 30 | **69** |
| Ported to `xc7a35tcpg236-1` | +0.421 | 0.000 | 0 / 30 | 67 |
| **Board wrapper, pad level** | **+1.610** | **0.000** | **0 / 277** | 168 |

### What the original violation actually was

Every one of the eleven failing endpoints touched a package pin. **There was not a single flop-to-flop setup violation.** The decisive evidence was a path from `slot_type_reg` to the `slot_type` port containing **one OBUF and zero LUTs** — which still missed by 5.63 ns.

Three causes, none of them the arbiter's logic:

1. **An unsurvivable I/O budget.** 4 ns in + 4 ns out of a 10 ns period leaves 1.965 ns inside the chip, while IBUF (~1.00 ns) + OBUF (~2.64 ns) cost 3.64 ns before a single LUT is placed. The arbiter's own contribution to the 18.39 ns arrival was 0.99 ns — about 5 %.
2. **A pblock that never applied.** Its cell list came from `[get_cells -hierarchical -filter {PRIMITIVE_LEVEL==LEAF}]`, which swept up 36 I/O buffers and the BUFG. Those cannot live in a SLICE-only range, so the region became unsatisfiable — visible *only* as an `INFO` line in the implementation log, never as an error.
3. **The wrong abstraction.** An arbiter is not a chip; its interface never touches a pin in a real system. A related asymmetry compounded it — 4.573 ns of BUFG clock insertion delay charged entirely to the launch side of every flop-to-port path.

### Two RTL findings

**A redundant multiplexer.** The priority-slot grant selected between `tie_grant` and `direct_grant`. But `rotate_mask_encoder` returns the single set bit of a one-hot mask for *any* pointer value, so on the unique-maximum case — where `tied_mask` is already one-hot — the two were identical. The whole selection collapsed to `assign prio_grant = tie_grant;`, removing 14 LUTs (−17 %) and one logic level. Simulation results were bit-identical.

**A cheaper tie test.** `$countones(tied_mask) >= 2` became `|(tied_mask & (tied_mask - 1))`. At N = 4 this changed neither depth nor LUT count — Vivado had already folded the popcount — but different LUT packing gained 0.225 ns, confirmed reproducible by a byte-identical re-run of the unchanged design.

### The measurement that mattered most

Every critical path sits at **13–15 % logic, 85–87 % routing**. That ratio predicted what followed: removing a full LUT level bought only 0.033 ns, because the router handed most of it straight back. Deleting every LUT on the path would recover under 1 ns. Further logic optimization had nowhere to go — and knowing when to stop was worth as much as knowing how to start.

---

## Building

**Board demo:**

```tcl
set_property top amba_arbiter_demo_top [current_fileset]
update_compile_order -fileset sources_1
set_property is_enabled false [get_files amba_arbiter_top.xdc]

launch_runs synth_1 -jobs 8
wait_on_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
```

Bitstream lands at `AMBA_arbiter_rev.runs/impl_1/amba_arbiter_demo_top.bit`.

**Arbiter core characterization:** `source ooc_timing.tcl` (self-contained; does not touch project state).

---

## Documentation

[`arbiter_design_report.tex`](arbiter_design_report.tex) — full report covering the signal flow, the mechanism behind each behavioural claim, the limitations, the verification strategy, the complete timing-closure narrative, and the engineering practices that made the diagnosis possible. Build with `pdflatex` (run twice for the table of contents).

---

## Notes

- Vivado's generated output (`.cache/`, `.runs/`, `.sim/`, `.hw/`, `.ip_user_files/`, `utils_1/`, `ooc_out/`) is git-ignored — all of it is regenerable from the sources and the project file.
- The design is intentionally modular so the pointer logic, tie-breaking, lock control and grace-window behaviour can be tested independently. Each submodule has its own unit testbench.
- If you add RTL or testbench files, update both the Vivado project and this tree.
