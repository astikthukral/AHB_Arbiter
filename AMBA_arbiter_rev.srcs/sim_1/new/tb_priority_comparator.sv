`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 24.07.2026 12:23:32
// Design Name: 
// Module Name: tb_priority_comparator
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
// tb_priority_comparator — self-checking testbench for priority_comparator (§3)
// Requires: priority_comparator.sv
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_priority_comparator;

    localparam int NUM_MASTERS = 4;
    localparam int PRI_WIDTH   = 3;

    logic [NUM_MASTERS-1:0]           req_vec;
    logic [NUM_MASTERS*PRI_WIDTH-1:0] pri_flat;
    logic [NUM_MASTERS-1:0]           direct_grant_vec;
    logic                             unique_valid;
    logic                             is_tie;
    logic [NUM_MASTERS-1:0]           tied_mask;
    logic                             any_req;

    int errors = 0;

    priority_comparator #(.NUM_MASTERS(NUM_MASTERS), .PRI_WIDTH(PRI_WIDTH)) dut (
        .req_vec(req_vec), .pri_flat(pri_flat),
        .direct_grant_vec(direct_grant_vec), .unique_valid(unique_valid),
        .is_tie(is_tie), .tied_mask(tied_mask), .any_req(any_req)
    );

    // Pack four 3-bit priorities (m3,m2,m1,m0).
    function automatic logic [NUM_MASTERS*PRI_WIDTH-1:0] pk(
        input logic [2:0] p0, p1, p2, p3);
        pk = {p3, p2, p1, p0};
    endfunction

    task automatic chk(input string name, input logic cond);
        if (!cond) begin errors++; $error("FAIL: %s", name); end
        else $display("  ok: %s", name);
    endtask

    initial begin
        // No requesters.
        req_vec = 4'b0000; pri_flat = pk(3,3,3,3); #1;
        chk("no req: any_req=0",   any_req == 0);
        chk("no req: !unique",     unique_valid == 0);
        chk("no req: !tie",        is_tie == 0);
        chk("no req: no grant",    direct_grant_vec == 0);

        // Unique strict max: m2 has pri 5, others lower.
        req_vec = 4'b1111; pri_flat = pk(1,2,5,3); #1;   // m0=1,m1=2,m2=5,m3=3
        chk("unique max m2: any",    any_req == 1);
        chk("unique max m2: unique", unique_valid == 1);
        chk("unique max m2: !tie",   is_tie == 0);
        chk("unique max m2: grant",  direct_grant_vec == 4'b0100);

        // Non-requesting master with higher priority is NOT a candidate.
        req_vec = 4'b0011; pri_flat = pk(2,4,7,7); #1;   // m2,m3 have 7 but don't request
        chk("high-pri non-req ignored: unique", unique_valid == 1);
        chk("high-pri non-req ignored: grant m1", direct_grant_vec == 4'b0010);

        // Two-way tie at max (m1,m3 both 6), others lower & requesting.
        req_vec = 4'b1111; pri_flat = pk(1,6,2,6); #1;   // m0=1,m1=6,m2=2,m3=6
        chk("tie m1/m3: is_tie",     is_tie == 1);
        chk("tie m1/m3: !unique",    unique_valid == 0);
        chk("tie m1/m3: no direct",  direct_grant_vec == 0);
        chk("tie m1/m3: tied_mask",  tied_mask == 4'b1010);

        // Full tie: all requesters share the same priority.
        req_vec = 4'b1111; pri_flat = pk(4,4,4,4); #1;
        chk("full tie: is_tie",      is_tie == 1);
        chk("full tie: tied=all",    tied_mask == 4'b1111);

        // Single requester -> trivially unique, tied_mask is its one-hot.
        req_vec = 4'b0100; pri_flat = pk(0,0,0,0); #1;
        chk("single req: unique",    unique_valid == 1);
        chk("single req: grant",     direct_grant_vec == 4'b0100);
        chk("single req: tied=grant",tied_mask == 4'b0100);

        if (errors == 0) $display("\n[tb_priority_comparator] PASS");
        else             $display("\n[tb_priority_comparator] FAIL (%0d errors)", errors);
        $finish;
    end

endmodule
