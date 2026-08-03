`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 24.07.2026 12:26:26
// Design Name: 
// Module Name: tb_amba_arbiter_top
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
// tb_amba_arbiter_top — self-checking integration testbench (§9)
// Requires all RTL: amba_arbiter_top.sv, rr_pointer_unit.sv, priority_comparator.sv,
//   tie_break_rr_unit.sv, slot_alternation_ctrl.sv, lock_ctrl.sv,
//   grace_window_timer.sv, completion_merge.sv, rotate_mask_encoder.sv
//
// Walks a full alternation sequence and exercises: RR selection + advance,
// Priority unique max, Priority tie via the nested pointer, absolute LOCK
// override with a frozen slot and multi-beat completion, and the grace-window
// abandoned-grant path.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_amba_arbiter_top;

    localparam int N         = 4;
    localparam int PRI_WIDTH  = 3;
    localparam int GRACE_W    = 4;

    localparam logic SLOT_RR       = 1'b0;
    localparam logic SLOT_PRIORITY = 1'b1;

    logic                     clk, rst_n;
    logic [N-1:0]             REQ;
    logic [N*PRI_WIDTH-1:0]   PRI;
    logic [N-1:0]             LOCK;
    logic [N-1:0]             VALID_XFER;
    logic [N-1:0]             COMPLETE;
    logic [N-1:0]             GRANT;
    logic                     slot_complete;
    logic                     slot_type;

    int errors = 0;

    amba_arbiter_top #(.NUM_MASTERS(N), .PRI_WIDTH(PRI_WIDTH), .GRACE_W(GRACE_W)) dut (
        .clk(clk), .rst_n(rst_n),
        .REQ(REQ), .PRI(PRI), .LOCK(LOCK), .VALID_XFER(VALID_XFER), .COMPLETE(COMPLETE),
        .GRANT(GRANT), .slot_complete(slot_complete), .slot_type(slot_type)
    );

    always #5 clk = ~clk;

    // Pack four 3-bit priorities: {m3,m2,m1,m0}
    function automatic logic [N*PRI_WIDTH-1:0] pk(input logic [2:0] p0,p1,p2,p3);
        pk = {p3,p2,p1,p0};
    endfunction

    task automatic chk(input string name, input logic cond);
        if (!cond) begin errors++; $error("FAIL: %s", name); end
        else $display("  ok: %s", name);
    endtask

    // Check the combinational grant for the currently-applied inputs.
    task automatic expect_grant(input string name, input logic [N-1:0] val);
        #1; chk(name, GRANT == val);
    endtask

    // Complete a normal (non-locked) transfer for master m: assert its
    // VALID_XFER + COMPLETE for one cycle, advance a clock, then clear.
    task automatic complete_xfer(input logic [N-1:0] m);
        VALID_XFER = m; COMPLETE = m; LOCK = '0;
        @(negedge clk);
        COMPLETE = '0; VALID_XFER = '0;
    endtask

    int guard;

    initial begin
        clk = 0; rst_n = 0;
        REQ = '0; PRI = pk(0,0,0,0); LOCK = '0; VALID_XFER = '0; COMPLETE = '0;
        @(negedge clk); rst_n = 1; #1;
        chk("reset: slot=RR", slot_type == SLOT_RR);

        // ---- S1: RR slot, ptr0, all request -> grant m0, then advance ----
        REQ = 4'b1111; PRI = pk(0,0,0,0);
        expect_grant("S1 RR grant m0", 4'b0001);
        complete_xfer(4'b0001);
        #1; chk("S1 -> slot PRIORITY", slot_type == SLOT_PRIORITY);

        // ---- S2: PRIORITY slot, unique max = m2 -> direct grant ----
        REQ = 4'b1111; PRI = pk(1,2,5,3);         // m2 strictly highest
        expect_grant("S2 unique max m2", 4'b0100);
        complete_xfer(4'b0100);
        #1; chk("S2 -> slot RR", slot_type == SLOT_RR);

        // ---- S3: RR slot, ptr advanced to 1 -> grant m1 ----
        REQ = 4'b1111; PRI = pk(0,0,0,0);
        expect_grant("S3 RR grant m1", 4'b0010);
        complete_xfer(4'b0010);
        #1; chk("S3 -> slot PRIORITY", slot_type == SLOT_PRIORITY);

        // ---- S4: PRIORITY tie {m1,m3}, tie_ptr0 -> m1 ----
        REQ = 4'b1111; PRI = pk(1,6,2,6);         // m1,m3 tied at 6
        expect_grant("S4 tie -> m1", 4'b0010);
        complete_xfer(4'b0010);
        #1; chk("S4 -> slot RR", slot_type == SLOT_RR);

        // ---- S5: RR slot, ptr=2 -> grant m2 ----
        REQ = 4'b1111; PRI = pk(0,0,0,0);
        expect_grant("S5 RR grant m2", 4'b0100);
        complete_xfer(4'b0100);
        #1; chk("S5 -> slot PRIORITY", slot_type == SLOT_PRIORITY);

        // ---- S6: PRIORITY tie {m1,m3} again, tie_ptr now 1 -> m3 ----
        REQ = 4'b1111; PRI = pk(1,6,2,6);
        expect_grant("S6 tie -> m3 (tie_ptr advanced)", 4'b1000);
        complete_xfer(4'b1000);
        #1; chk("S6 -> slot RR", slot_type == SLOT_RR);

        // ---- S7: RR slot, ptr=3 -> grant m3, which LOCKs the bus ----
        REQ = 4'b1111; PRI = pk(0,0,0,0);
        expect_grant("S7 RR grant m3", 4'b1000);
        // Start the locked transfer (VALID_XFER up, LOCK up), engage the lock.
        LOCK = 4'b1000; VALID_XFER = 4'b1000; COMPLETE = '0;
        @(negedge clk); #1;
        chk("S7 lock engaged, hold m3", GRANT == 4'b1000);
        chk("S7 slot frozen at RR",     slot_type == SLOT_RR);

        // Higher-priority requester arrives mid-lock: must be ignored (absolute).
        REQ = 4'b1111; PRI = pk(7,0,0,0);          // m0 now top priority
        #1; chk("S7 lock ignores higher pri", GRANT == 4'b1000);

        // Intermediate beat completes but LOCK still held -> slot must NOT end.
        COMPLETE = 4'b1000;
        @(negedge clk); COMPLETE = '0; #1;
        chk("S7 mid-beat: still locked", GRANT == 4'b1000);
        chk("S7 mid-beat: still RR",     slot_type == SLOT_RR);

        // Final beat: release LOCK and complete -> lock releases, rr_ptr advances.
        LOCK = '0; COMPLETE = 4'b1000;
        @(negedge clk); COMPLETE = '0; VALID_XFER = '0; #1;
        chk("S7 lock released -> slot PRIORITY", slot_type == SLOT_PRIORITY);

        // ---- S8: PRIORITY slot, unique m0, but grant is ABANDONED (no VALID_XFER) ----
        REQ = 4'b0001; PRI = pk(0,0,0,0); LOCK = '0; VALID_XFER = '0; COMPLETE = '0;
        expect_grant("S8 grant m0", 4'b0001);
        // Never assert VALID_XFER -> grace window must force completion.
        guard = 0;
        while (slot_type == SLOT_PRIORITY && guard < 2*GRACE_W + 4) begin
            @(negedge clk); guard++;
        end
        #1; chk("S8 grace forced completion -> slot RR", slot_type == SLOT_RR);
        chk("S8 forced within grace window", guard <= GRACE_W + 3);

        repeat (2) @(negedge clk);
        if (errors == 0) $display("\n[tb_amba_arbiter_top] PASS");
        else             $display("\n[tb_amba_arbiter_top] FAIL (%0d errors)", errors);
        $finish;
    end

endmodule

