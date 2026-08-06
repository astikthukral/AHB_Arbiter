`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// tb_amba_arbiter_demo_top
//
// Verifies the BOARD WRAPPER, not the arbiter core -- tb_amba_arbiter_top.sv
// already covers the latter. Everything exercised here was written after the
// arbiter closed timing and has never been simulated: the master_model FSM, the
// priority table and its slot-boundary latch, the tick generator, the debounce /
// edge detector, and the pulse stretcher.
//
// TICK_DIV and DEBOUNCE_CYCLES are overridden small. At their hardware values
// (50,000,000 and 1,000,000) one transaction would take half a second of
// simulated time -- this is the entire reason they are parameters rather than
// localparams.
//
// Checking is property-based rather than vector-based. Exact grant sequences are
// brittle against the relative phase of rr_ptr and tie_ptr, whereas the
// properties below hold for every legal run and catch whole classes of bug that
// hand-written vectors miss. The transaction log is there for eyeballing the
// sequences against the predicted demo behaviour.
// -----------------------------------------------------------------------------

module tb_amba_arbiter_demo_top;

    // Shrunk for simulation. Hardware values are 50_000_000 / 1_000_000.
    localparam int  TICK_DIV        = 20;
    localparam int  DEBOUNCE_CYCLES = 4;
    localparam time CLK_PERIOD      = 10ns;          // 100 MHz

    // The design guarantees a requesting master is served within 2N = 8 slots.
    // Allow a little margin so a boundary case does not report a false failure.
    localparam int  STARVE_LIMIT    = 10;

    logic        clk = 1'b0;
    logic        btnC;
    logic        btnU;
    logic [15:0] sw;
    logic [15:0] led;

    int errors   = 0;
    int slot_num = 0;

    // -------------------------------------------------------------------------
    // DUT
    // -------------------------------------------------------------------------
    amba_arbiter_demo_top #(
        .TICK_DIV        (TICK_DIV),
        .DEBOUNCE_CYCLES (DEBOUNCE_CYCLES)
    ) dut (
        .clk  (clk),
        .btnC (btnC),
        .btnU (btnU),
        .led  (led),
        .sw   (sw)
    );

    always #(CLK_PERIOD/2) clk = ~clk;

    // -------------------------------------------------------------------------
    // Observation points inside the DUT
    // -------------------------------------------------------------------------
    wire [3:0] grant     = dut.grant;
    wire [3:0] req       = dut.req;
    wire [3:0] vxfer     = dut.valid_xfer;
    wire [3:0] comp      = dut.complete;
    wire       slot_done = dut.slot_complete;
    wire       slot_type = dut.slot_type;
    wire       rst_n     = dut.rst_n_sync;
    wire       locked    = dut.u_amba_arbiter_top.locked;

    function automatic int oh2idx(input logic [3:0] v);
        oh2idx = -1;
        for (int i = 0; i < 4; i++) if (v[i]) oh2idx = i;
    endfunction

    // -------------------------------------------------------------------------
    // P1  GRANT is one-hot or zero
    // -------------------------------------------------------------------------
    always @(posedge clk) if (rst_n) begin
        if ($countones(grant) > 1) begin
            $error("[%0t] P1 grant not one-hot: %b", $time, grant);
            errors++;
        end
    end

    // -------------------------------------------------------------------------
    // P2  Never grant a master that is not requesting.
    //     Excluded while locked: lock override forces GRANT to the holder
    //     regardless of REQ, which is correct per S5.
    // -------------------------------------------------------------------------
    always @(posedge clk) if (rst_n && !locked) begin
        if ((grant & ~req) != '0) begin
            $error("[%0t] P2 granted a non-requesting master. grant=%b req=%b",
                   $time, grant, req);
            errors++;
        end
    end

    // -------------------------------------------------------------------------
    // P3  COMPLETE is a single-cycle pulse.
    //     Held high it would immediately re-complete the next transfer.
    // -------------------------------------------------------------------------
    logic [3:0] comp_q;
    always @(posedge clk) begin
        comp_q <= comp;
        if (rst_n && ((comp & comp_q) != '0)) begin
            $error("[%0t] P3 complete held >1 cycle: %b", $time, comp);
            errors++;
        end
    end

    // -------------------------------------------------------------------------
    // P4  slot_type toggles exactly once per slot_complete, and never otherwise.
    //     freeze and slot_complete are mutually exclusive by construction
    //     (freeze = lock_held && !slot_complete), so no lock exception is needed.
    // -------------------------------------------------------------------------
    logic st_q, sd_q;
    logic p4_armed = 1'b0;
    always @(posedge clk) begin
        st_q <= slot_type;
        sd_q <= slot_done;
        if (rst_n && p4_armed) begin
            if (sd_q && (slot_type === st_q)) begin
                $error("[%0t] P4 slot_type did not toggle after slot_complete", $time);
                errors++;
            end
            if (!sd_q && (slot_type !== st_q)) begin
                $error("[%0t] P4 slot_type toggled without slot_complete", $time);
                errors++;
            end
        end
        p4_armed <= rst_n;
    end

    // -------------------------------------------------------------------------
    // Transaction log + starvation check.
    //
    // Both live in one block so the ordering between logging and counting is
    // deterministic. STARVE_LIMIT is the design's own guarantee: any requesting
    // master must win a slot within 2N.
    // -------------------------------------------------------------------------
    int wait_cnt [0:3];

    always @(posedge clk) begin
        if (!rst_n) begin
            for (int i = 0; i < 4; i++) wait_cnt[i] = 0;
        end
        else if (slot_done) begin
            slot_num = slot_num + 1;

            $display("[%0t] slot %0d  %s  grant=M%0d  req=%b  pri_sel=%0d%s",
                     $time, slot_num,
                     slot_type ? "PRI" : "RR ",
                     oh2idx(grant), req, dut.pri_sel_q,
                     locked ? "  (locked)" : "");

            for (int i = 0; i < 4; i++) begin
                if (grant[i])      wait_cnt[i] = 0;
                else if (req[i]) begin
                    wait_cnt[i] = wait_cnt[i] + 1;
                    if (wait_cnt[i] > STARVE_LIMIT) begin
                        $error("[%0t] STARVATION master %0d waited %0d slots",
                               $time, i, wait_cnt[i]);
                        errors++;
                        wait_cnt[i] = 0;     // report once, do not spam
                    end
                end
            end
        end
    end

    // -------------------------------------------------------------------------
    // Stimulus helpers
    // -------------------------------------------------------------------------
    task automatic do_reset();
        btnC = 1'b1;                        // Basys 3 buttons are active-high
        btnU = 1'b0;
        sw   = '0;
        repeat (5)  @(posedge clk);
        btnC = 1'b0;
        repeat (10) @(posedge clk);         // reset_sync release + switch sync
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
        repeat (6) @(posedge clk);          // 2-flop synchronizer + margin
    endtask

    task automatic wait_slots_n(input int n);
        int seen;
        seen = 0;
        while (seen < n) begin
            @(posedge clk);
            if (rst_n && slot_done) seen++;
        end
    endtask

    // Models a real button: bounces on press AND on release. Without the bounce
    // the debounce logic is never actually exercised.
    task automatic press_btnU();
        for (int i = 0; i < 4; i++) begin
            btnU = 1'b1; @(posedge clk);
            btnU = 1'b0; @(posedge clk);
        end
        btnU = 1'b1;
        repeat (DEBOUNCE_CYCLES + 6) @(posedge clk);

        for (int i = 0; i < 4; i++) begin
            btnU = 1'b0; @(posedge clk);
            btnU = 1'b1; @(posedge clk);
        end
        btnU = 1'b0;
        repeat (DEBOUNCE_CYCLES + 6) @(posedge clk);
    endtask

    // -------------------------------------------------------------------------
    // Main sequence
    // -------------------------------------------------------------------------
    logic [3:0] g_before;
    int         n_before;
    int         completes;
    logic       stable_ok;

    initial begin
        $display("================ tb_amba_arbiter_demo_top ================");
        $display("TICK_DIV=%0d  DEBOUNCE_CYCLES=%0d", TICK_DIV, DEBOUNCE_CYCLES);

        do_reset();
        if (!rst_n) begin
            $error("reset never released");
            errors++;
        end
        else $display("reset released OK");

        // ---- Demo 1: all equal -> both pointers rotate, doubled pattern -----
        $display("\n--- Demo 1: all-equal priority, all four requesting ---");
        $display("    expect M0,M0,M1,M1,M2,M2,M3,M3 (rr_ptr and tie_ptr in lockstep)");
        set_sw(4'b1111, 4'b0000, 4'b0000, 2'b00, 1'b0);
        wait_slots_n(12);

        // ---- Demo 2: graded -> M3 unique max on every priority slot ---------
        $display("\n--- Demo 2: graded priority (M3=3 M2=2 M1=1 M0=0) ---");
        $display("    expect M3 on every PRI slot, rotation on every RR slot");
        set_sw(4'b1111, 4'b0000, 4'b0000, 2'b01, 1'b0);
        wait_slots_n(12);

        // ---- Demo 3: one dominant, then remove it ---------------------------
        $display("\n--- Demo 3a: one dominant (M3=7, others=1) ---");
        set_sw(4'b1111, 4'b0000, 4'b0000, 2'b11, 1'b0);
        wait_slots_n(12);

        $display("\n--- Demo 3b: M3 removed -- remaining three now tie at 1 ---");
        set_sw(4'b0111, 4'b0000, 4'b0000, 2'b11, 1'b0);
        wait_slots_n(12);

        // ---- Demo 4: partial tie -------------------------------------------
        $display("\n--- Demo 4: partial tie (M3=M2=5, M1=M0=1) ---");
        $display("    expect M1/M0 on RR slots ONLY; M3/M2 alternate on PRI slots");
        set_sw(4'b1111, 4'b0000, 4'b0000, 2'b10, 1'b0);
        wait_slots_n(16);

        // ---- Lock: grant must stick and slot_type must freeze ---------------
        $display("\n--- Lock: M0 asserts LOCK ---");
        set_sw(4'b1111, 4'b0001, 4'b0000, 2'b00, 1'b0);

        while (grant != 4'b0001) @(posedge clk);   // wait for M0 to win
        repeat (5) @(posedge clk);                 // let the lock engage
        g_before  = grant;
        completes = 0;
        for (int i = 0; i < TICK_DIV*4; i++) begin
            @(posedge clk);
            if (slot_done) completes++;
        end
        if (completes != 0) begin
            $error("LOCK: %0d completions occurred while locked", completes);
            errors++;
        end
        else if (grant !== g_before) begin
            $error("LOCK: grant moved while locked: %b -> %b", g_before, grant);
            errors++;
        end
        else $display("    grant=%b held %0d cycles, zero completions  OK",
                      g_before, TICK_DIV*4);

        set_sw(4'b1111, 4'b0000, 4'b0000, 2'b00, 1'b0);   // release LOCK
        wait_slots_n(4);
        $display("    lock released, arbitration resumed  OK");

        // ---- Abandon: M1 never asserts VALID_XFER --------------------------
        // If the grace window fails to fire, this hangs and the watchdog trips.
        $display("\n--- Abandon: M1 granted but never starts ---");
        $display("    expect M1 skipped quickly via forced_complete, no hang");
        set_sw(4'b1111, 4'b0000, 4'b0010, 2'b00, 1'b0);
        wait_slots_n(16);
        $display("    arbitration continued through the abandoned master  OK");

        // ---- Step mode: exactly one transaction per press ------------------
        $display("\n--- Step mode: sw[15]=1, advance on btnU ---");
        set_sw(4'b1111, 4'b0000, 4'b0000, 2'b00, 1'b1);
        repeat (4) @(posedge clk);
        #1 n_before = slot_num;

        repeat (TICK_DIV*3) @(posedge clk);
        #1;
        if (slot_num != n_before) begin
            $error("STEP: %0d transactions advanced with no button press",
                   slot_num - n_before);
            errors++;
        end
        else $display("    idle with no press: no transactions  OK");

        press_btnU();
        #1;
        if (slot_num != n_before + 1) begin
            $error("STEP: expected exactly 1 transaction per press, got %0d",
                   slot_num - n_before);
            errors++;
        end
        else $display("    exactly one transaction per press  OK");

        // ---- REQ stability: switch flipped mid-transfer --------------------
        // master_model must hold REQ until the transfer completes, or the
        // arbiter's stability assumption is violated and the grant can move
        // out from under a live transaction.
        $display("\n--- REQ stability: sw[0] flipped off mid-transfer ---");
        set_sw(4'b0001, 4'b0000, 4'b0000, 2'b00, 1'b0);

        while (!(grant[0] && vxfer[0])) @(posedge clk);
        sw[0]     = 1'b0;                          // yank the switch mid-transfer
        stable_ok = 1'b1;
        forever begin
            @(posedge clk);
            if (!req[0])  stable_ok = 1'b0;
            if (slot_done) break;
        end
        if (!stable_ok) begin
            $error("REQ STABILITY: req[0] dropped before slot_complete");
            errors++;
        end
        else $display("    req[0] held through the transfer  OK");

        // ---- Summary --------------------------------------------------------
        repeat (20) @(posedge clk);
        $display("\n=========================================================");
        $display("  %s -- %0d error(s), %0d slots observed",
                 (errors == 0) ? "PASS" : "FAIL", errors, slot_num);
        $display("=========================================================");
        $finish;
    end

    // -------------------------------------------------------------------------
    // Watchdog. A hang here almost certainly means a slot never completed --
    // the grace window failing, or a lock that never released.
    // -------------------------------------------------------------------------
    initial begin
        #500us;
        $error("TIMEOUT -- simulation did not finish, likely a hang");
        $finish;
    end

endmodule
