`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 06.08.2026 23:32:04
// Design Name: 
// Module Name: tb_amba_arbiter_demo_top_postimpl
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
// tb_amba_arbiter_demo_top_postimpl
//
// PORT-ONLY testbench, for post-synthesis / post-implementation simulation.
//
// tb_amba_arbiter_demo_top.sv reads internal nets (dut.grant, dut.slot_complete,
// dut.u_amba_arbiter_top.locked, ...). Synthesis renames, merges and absorbs
// those, so that testbench cannot elaborate against a netlist:
//     ERROR: [VRFC 10-2991] 'grant' is not declared under prefix 'dut'
// This one touches nothing but clk / btnC / btnU / sw / led.
//
// IMPORTANT -- parameters cannot be overridden in a netlist simulation. The
// netlist was elaborated at synthesis time with whatever TICK_DIV and
// DEBOUNCE_CYCLES were then, and those values are baked into the gates. Build
// the netlist with small values first:
//
//     set_property generic {TICK_DIV=20 DEBOUNCE_CYCLES=4} [get_filesets sources_1]
//     reset_run synth_1
//     launch_runs impl_1 -jobs 8
//
// and revert afterwards for the real bitstream. At the hardware value of
// TICK_DIV = 50,000,000 a single transaction is 0.5 s of simulated time.
//
// The localparams below must MATCH those generics. They only size the
// testbench's own waits -- they do not (and cannot) parameterize the DUT.
//
// Observability. Everything needed comes out on the LEDs, because the display
// was built for exactly this:
//     led[3:0]    GRANT
//     led[4]      slot_type
//     led[5]      slot_complete, stretched (too wide to be useful here)
//     led[15:12]  REQ
// Slot boundaries are detected from led[4] toggling: slot_type flips on
// slot_complete && !freeze, and freeze/slot_complete are mutually exclusive by
// construction, so one toggle == one completed slot.
//
// Not checkable from the ports: COMPLETE pulse width, VALID_XFER, and the
// arbiter's internal `locked`. Everything else from the RTL testbench carries
// over.
// -----------------------------------------------------------------------------

module tb_amba_arbiter_demo_top_postimpl;

    // MUST match the generics the netlist was synthesized with.
    localparam int  TICK_DIV        = 20;
    localparam int  DEBOUNCE_CYCLES = 4;
    localparam time CLK_PERIOD      = 10ns;      // 100 MHz

    localparam int  STARVE_LIMIT    = 10;        // guarantee is 2N = 8, plus margin
    localparam time GSR_SETTLE      = 300ns;     // let glbl's GSR pulse clear

    logic        clk = 1'b0;
    logic        btnC;
    logic        btnU;
    logic [15:0] sw;
    logic [15:0] led;

    int   errors    = 0;
    int   slot_num  = 0;
    logic checks_on = 1'b0;      // gate checkers until reset has settled
    logic in_lock   = 1'b0;      // suppress P2 during the lock scenario

    // -------------------------------------------------------------------------
    // DUT -- NO parameter override: the netlist is already elaborated.
    // -------------------------------------------------------------------------
    amba_arbiter_demo_top dut (
        .clk  (clk),
        .btnC (btnC),
        .btnU (btnU),
        .led  (led),
        .sw   (sw)
    );

    always #(CLK_PERIOD/2) clk = ~clk;

    // -------------------------------------------------------------------------
    // Everything observed comes off the LEDs
    // -------------------------------------------------------------------------
    wire [3:0] grant_led = led[3:0];
    wire       stype_led = led[4];
    wire [3:0] req_led   = led[15:12];

    logic [15:0] led_q;
    always @(posedge clk) led_q <= led;

    // One slot_type toggle == one completed slot. On the toggle cycle led_q
    // still holds the state of the slot that just ended, so led_q[3:0] is the
    // master that owned it.
    wire slot_edge = checks_on && (led[4] !== led_q[4]);

    function automatic int oh2idx(input logic [3:0] v);
        oh2idx = -1;
        for (int i = 0; i < 4; i++) if (v[i]) oh2idx = i;
    endfunction

    // -------------------------------------------------------------------------
    // P1  GRANT is one-hot or zero
    // -------------------------------------------------------------------------
    always @(posedge clk) if (checks_on) begin
        if ($countones(grant_led) > 1) begin
            $error("[%0t] P1 grant not one-hot: %b", $time, grant_led);
            errors++;
        end
    end

    // -------------------------------------------------------------------------
    // P2  Never grant a master that is not requesting.
    //     Suppressed during the lock scenario: lock override forces GRANT to the
    //     holder regardless of REQ, which is correct per S5, and `locked` is not
    //     observable from the ports.
    // -------------------------------------------------------------------------
    always @(posedge clk) if (checks_on && !in_lock) begin
        if ((grant_led & ~req_led) != '0) begin
            $error("[%0t] P2 granted a non-requesting master. grant=%b req=%b",
                   $time, grant_led, req_led);
            errors++;
        end
    end

    // -------------------------------------------------------------------------
    // P5  GRANT is stable within a slot.
    //     The arbiter must not re-arbitrate mid-transfer -- the grant may only
    //     move on a slot boundary. Replaces the RTL bench's P3/P4, which needed
    //     internal signals.
    // -------------------------------------------------------------------------
    always @(posedge clk) if (checks_on) begin
        if (!slot_edge && (grant_led !== led_q[3:0]) && (led_q[3:0] !== '0)) begin
            $error("[%0t] P5 grant moved mid-slot: %b -> %b",
                   $time, led_q[3:0], grant_led);
            errors++;
        end
    end

    // -------------------------------------------------------------------------
    // Transaction log + starvation check, in one block so ordering is
    // deterministic. The starvation bound is the design's own guarantee: any
    // requesting master must win a slot within 2N.
    // -------------------------------------------------------------------------
    int wait_cnt [0:3];

    always @(posedge clk) begin
        if (!checks_on) begin
            for (int i = 0; i < 4; i++) wait_cnt[i] = 0;
        end
        else if (slot_edge) begin
            slot_num = slot_num + 1;

            $display("[%0t] slot %0d  %s  grant=M%0d  req=%b",
                     $time, slot_num,
                     led_q[4] ? "PRI" : "RR ",
                     oh2idx(led_q[3:0]), led_q[15:12]);

            // Index led_q directly. A part-select result cannot itself be
            // subscripted -- led_q[3:0][i] is "range is not allowed in a
            // prefix". grant is led[3:0] so bit i is led_q[i]; req is
            // led[15:12] so bit i is led_q[12+i].
            for (int i = 0; i < 4; i++) begin
                if (led_q[i])        wait_cnt[i] = 0;
                else if (led_q[12+i]) begin
                    wait_cnt[i] = wait_cnt[i] + 1;
                    if (wait_cnt[i] > STARVE_LIMIT) begin
                        $error("[%0t] STARVATION master %0d waited %0d slots",
                               $time, i, wait_cnt[i]);
                        errors++;
                        wait_cnt[i] = 0;
                    end
                end
            end
        end
    end

    // -------------------------------------------------------------------------
    // Stimulus helpers
    // -------------------------------------------------------------------------
    task automatic do_reset();
        btnC = 1'b1;                       // Basys 3 buttons are active-high
        btnU = 1'b0;
        sw   = '0;
        #GSR_SETTLE;                       // wait out glbl's global set/reset
        repeat (10) @(posedge clk);
        btnC = 1'b0;
        repeat (20) @(posedge clk);        // reset_sync release + switch sync
        checks_on = 1'b1;
    endtask

    task automatic set_sw(input logic [3:0] r,
                          input logic [3:0] lk,
                          input logic [3:0] ab,
                          input logic [1:0] ps,
                          input logic       step);
        sw        = '0;
        sw[3:0]   = r;
        sw[7:4]   = lk;
        sw[11:8]  = ab;
        sw[13:12] = ps;
        sw[15]    = step;
        repeat (6) @(posedge clk);         // two-flop synchronizer + margin
    endtask

    task automatic wait_slots_n(input int n);
        int seen;
        seen = 0;
        while (seen < n) begin
            @(posedge clk);
            if (slot_edge) seen++;
        end
    endtask

    // Bounces on press AND release -- without that the debounce logic is never
    // actually exercised.
    task automatic press_btnU();
        for (int i = 0; i < 4; i++) begin
            btnU = 1'b1; @(posedge clk);
            btnU = 1'b0; @(posedge clk);
        end
        btnU = 1'b1;
        repeat (DEBOUNCE_CYCLES + 8) @(posedge clk);

        for (int i = 0; i < 4; i++) begin
            btnU = 1'b0; @(posedge clk);
            btnU = 1'b1; @(posedge clk);
        end
        btnU = 1'b0;
        repeat (DEBOUNCE_CYCLES + 8) @(posedge clk);
    endtask

    // -------------------------------------------------------------------------
    // Main sequence
    // -------------------------------------------------------------------------
    logic [3:0] g_before;
    int         n_before;
    int         slots_seen;
    logic       stable_ok;

    initial begin
        $display("========== tb_amba_arbiter_demo_top_postimpl ==========");
        $display("expects a netlist built with TICK_DIV=%0d DEBOUNCE_CYCLES=%0d",
                 TICK_DIV, DEBOUNCE_CYCLES);

        do_reset();
        $display("reset released, checkers armed");

        // ---- Demo 1: all equal ---------------------------------------------
        $display("\n--- Demo 1: all-equal priority, all four requesting ---");
        $display("    expect M0,M0,M1,M1,M2,M2,M3,M3 (rr_ptr and tie_ptr in lockstep)");
        set_sw(4'b1111, 4'b0000, 4'b0000, 2'b00, 1'b0);
        wait_slots_n(12);

        // ---- Demo 2: graded -------------------------------------------------
        $display("\n--- Demo 2: graded priority (M3=3 M2=2 M1=1 M0=0) ---");
        set_sw(4'b1111, 4'b0000, 4'b0000, 2'b01, 1'b0);
        wait_slots_n(12);

        // ---- Demo 3: one dominant, then remove it ---------------------------
        $display("\n--- Demo 3a: one dominant (M3=7, others=1) ---");
        set_sw(4'b1111, 4'b0000, 4'b0000, 2'b11, 1'b0);
        wait_slots_n(12);

        $display("\n--- Demo 3b: M3 removed, remaining three tie at 1 ---");
        set_sw(4'b0111, 4'b0000, 4'b0000, 2'b11, 1'b0);
        wait_slots_n(12);

        // ---- Demo 4: partial tie -------------------------------------------
        $display("\n--- Demo 4: partial tie (M3=M2=5, M1=M0=1) ---");
        $display("    expect M1/M0 on RR slots only");
        set_sw(4'b1111, 4'b0000, 4'b0000, 2'b10, 1'b0);
        wait_slots_n(16);

        // ---- Lock -----------------------------------------------------------
        $display("\n--- Lock: M0 asserts LOCK ---");
        in_lock = 1'b1;
        set_sw(4'b1111, 4'b0001, 4'b0000, 2'b00, 1'b0);

        while (grant_led != 4'b0001) @(posedge clk);
        repeat (8) @(posedge clk);
        g_before   = grant_led;
        slots_seen = 0;
        for (int i = 0; i < TICK_DIV*4; i++) begin
            @(posedge clk);
            if (slot_edge) slots_seen++;
        end
        if (slots_seen != 0) begin
            $error("LOCK: %0d slots completed while locked", slots_seen);
            errors++;
        end
        else if (grant_led !== g_before) begin
            $error("LOCK: grant moved while locked: %b -> %b", g_before, grant_led);
            errors++;
        end
        else $display("    grant=%b held %0d cycles, zero slots  OK",
                      g_before, TICK_DIV*4);

        set_sw(4'b1111, 4'b0000, 4'b0000, 2'b00, 1'b0);
        wait_slots_n(4);
        in_lock = 1'b0;
        $display("    lock released, arbitration resumed  OK");

        // ---- Abandon --------------------------------------------------------
        // If the grace window fails to fire this hangs and the watchdog trips.
        $display("\n--- Abandon: M1 granted but never starts ---");
        set_sw(4'b1111, 4'b0000, 4'b0010, 2'b00, 1'b0);
        wait_slots_n(16);
        $display("    arbitration continued past the abandoned master  OK");

        // ---- Step mode ------------------------------------------------------
        $display("\n--- Step mode: sw[15]=1, advance on btnU ---");
        set_sw(4'b1111, 4'b0000, 4'b0000, 2'b00, 1'b1);
        repeat (8) @(posedge clk);
        #1 n_before = slot_num;

        repeat (TICK_DIV*3) @(posedge clk);
        #1;
        if (slot_num != n_before) begin
            $error("STEP: %0d slots advanced with no button press",
                   slot_num - n_before);
            errors++;
        end
        else $display("    idle with no press: no slots  OK");

        press_btnU();
        #1;
        if (slot_num != n_before + 1) begin
            $error("STEP: expected exactly 1 slot per press, got %0d",
                   slot_num - n_before);
            errors++;
        end
        else $display("    exactly one slot per press  OK");

        // ---- REQ stability --------------------------------------------------
        // master_model must hold REQ until the transfer completes. Visible on
        // led[15:12], so this survives the port-only restriction intact.
        $display("\n--- REQ stability: sw[0] flipped off mid-transfer ---");
        set_sw(4'b0001, 4'b0000, 4'b0000, 2'b00, 1'b0);

        while (grant_led != 4'b0001) @(posedge clk);
        repeat (2) @(posedge clk);
        sw[0]     = 1'b0;                  // yank the switch mid-transfer
        stable_ok = 1'b1;
        // Break BEFORE sampling req. slot_edge is derived from slot_type, which
        // toggles one cycle AFTER slot_complete -- and on that cycle
        // master_model has already returned to IDLE, so req[0] has legitimately
        // fallen. Checking req first would flag that correct behaviour as a
        // failure. The RTL bench saw slot_complete directly and did not have
        // this one-cycle offset.
        forever begin
            @(posedge clk);
            if (slot_edge)   break;             // slot over: req may now drop
            if (!req_led[0]) stable_ok = 1'b0;  // still mid-slot: must be held
        end
        if (!stable_ok) begin
            $error("REQ STABILITY: req[0] dropped before the slot ended");
            errors++;
        end
        else $display("    req[0] held through the transfer  OK");

        // ---- Summary --------------------------------------------------------
        repeat (20) @(posedge clk);
        $display("\n=======================================================");
        $display("  %s -- %0d error(s), %0d slots observed",
                 (errors == 0) ? "PASS" : "FAIL", errors, slot_num);
        $display("=======================================================");
        $finish;
    end

    // -------------------------------------------------------------------------
    // Watchdog. A hang almost certainly means a slot never completed -- the
    // grace window failing, or a lock that never released. It also catches the
    // case where the netlist was built with the hardware TICK_DIV, in which
    // case nothing will complete inside any reasonable simulation window.
    // -------------------------------------------------------------------------
    initial begin
        #2ms;
        $error("TIMEOUT -- no completion. Check the netlist was synthesized with");
        $error("          TICK_DIV=%0d (generics), not the hardware value.", TICK_DIV);
        $finish;
    end

endmodule
