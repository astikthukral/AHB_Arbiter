`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 24.07.2026 12:24:17
// Design Name: 
// Module Name: tb_lock_ctrl
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
// tb_lock_ctrl - self-checking testbench for lock_ctrl (§5)
// Requires: lock_ctrl.sv
//
// Drives eff_grant / lock_vec / slot_complete directly (in the full design
// eff_grant is fed back from the top-level grant mux).
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_lock_ctrl;

    localparam int NUM_MASTERS = 4;

    logic                   clk, rst_n;
    logic [NUM_MASTERS-1:0] eff_grant;
    logic [NUM_MASTERS-1:0] lock_vec;
    logic                   via_tie_in;
    logic                   slot_complete;
    logic                   locked;
    logic [NUM_MASTERS-1:0] lock_grant_vec;
    logic                   lock_via_tie;
    logic                   freeze;

    int errors = 0;

    lock_ctrl #(.NUM_MASTERS(NUM_MASTERS)) dut (
        .clk(clk), .rst_n(rst_n),
        .eff_grant(eff_grant), .lock_vec(lock_vec), .via_tie_in(via_tie_in),
        .slot_complete(slot_complete),
        .locked(locked), .lock_grant_vec(lock_grant_vec),
        .lock_via_tie(lock_via_tie), .freeze(freeze)
    );

    always #5 clk = ~clk;

    task automatic chk(input string name, input logic cond);
        if (!cond) begin errors++; $error("FAIL: %s", name); end
        else $display("  ok: %s", name);
    endtask

    initial begin
        clk = 0; rst_n = 0;
        eff_grant = '0; lock_vec = '0; via_tie_in = 0; slot_complete = 0;
        @(negedge clk); rst_n = 1;
        chk("reset -> !locked", locked == 0);

        // Master 1 granted and asserts LOCK (via a tie) -> engages next cycle.
        eff_grant = 4'b0010; lock_vec = 4'b0010; via_tie_in = 1; slot_complete = 0;
        @(negedge clk);
        chk("engaged: locked",        locked == 1);
        chk("engaged: hold m1",       lock_grant_vec == 4'b0010);
        chk("engaged: via_tie latched", lock_via_tie == 1);
        chk("engaged: freeze",        freeze == 1);

        // A higher-priority master now requests + locks, but LOCK is absolute:
        // the bus stays with m1, no re-arbitration.
        eff_grant = 4'b1000; lock_vec = 4'b1000; slot_complete = 0;
        @(negedge clk);
        chk("mid-lock: still m1",     lock_grant_vec == 4'b0010);
        chk("mid-lock: still locked", locked == 1);
        chk("mid-lock: still frozen", freeze == 1);

        // Sequence completes: on the completing cycle freeze drops so the slot
        // still toggles once; the lock releases the following cycle.
        slot_complete = 1; #1;
        chk("completing cycle: freeze low", freeze == 0);
        @(negedge clk); slot_complete = 0;
        chk("released: !locked",      locked == 0);
        chk("released: no hold",      lock_grant_vec == 0);

        // No privileged re-entry: after release the just-locked master must be
        // granted again (eff_grant) to re-lock; simply asserting LOCK is not enough.
        eff_grant = 4'b0000; lock_vec = 4'b0010; slot_complete = 0;
        @(negedge clk);
        chk("no grant -> no relock",  locked == 0);

        // Grant it fairly again -> re-locks normally.
        eff_grant = 4'b0010; lock_vec = 4'b0010; via_tie_in = 0;
        @(negedge clk);
        chk("fair re-grant relocks",  locked == 1);
        chk("relock via_tie=0",       lock_via_tie == 0);

        if (errors == 0) $display("\n[tb_lock_ctrl] PASS");
        else             $display("\n[tb_lock_ctrl] FAIL (%0d errors)", errors);
        $finish;
    end

endmodule

