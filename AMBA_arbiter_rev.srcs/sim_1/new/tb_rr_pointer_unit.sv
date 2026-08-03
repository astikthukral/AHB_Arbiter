`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 22.07.2026 00:44:32
// Design Name: 
// Module Name: tb_rr_pointer_unit
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
// tb_rr_pointer_unit — self-checking testbench for rr_pointer_unit (§2)
// Requires: rr_pointer_unit.sv, rotate_mask_encoder.sv
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_rr_pointer_unit;

    localparam int NUM_MASTERS = 4;
    localparam int PTR_WIDTH   = $clog2(NUM_MASTERS);

    logic                   clk, rst_n;
    logic [NUM_MASTERS-1:0] req_vec;
    logic                   advance;
    logic [NUM_MASTERS-1:0] grant_vec;
    logic                   grant_valid;
    logic [PTR_WIDTH-1:0]   ptr;

    int errors = 0;

    rr_pointer_unit #(.NUM_MASTERS(NUM_MASTERS)) dut (
        .clk(clk), .rst_n(rst_n), .req_vec(req_vec), .advance(advance),
        .grant_vec(grant_vec), .grant_valid(grant_valid), .ptr(ptr)
    );

    always #5 clk = ~clk;

    task automatic chk(input string name, input logic cond);
        if (!cond) begin errors++; $error("FAIL: %s", name); end
        else $display("  ok: %s", name);
    endtask

    initial begin
        clk = 0; rst_n = 0; req_vec = '0; advance = 0;
        @(negedge clk); rst_n = 1;

        // Pointer starts at 0. With all requesting, grant should be master 0.
        req_vec = 4'b1111; advance = 0; @(negedge clk);
        chk("ptr resets to 0",           ptr == 0);
        chk("grant = m0 at ptr0/all-req", grant_vec == 4'b0001);
        chk("grant_valid set",            grant_valid == 1);

        // Non-requesting master at pointer is skipped by the encoder (no special case).
        req_vec = 4'b1010; @(negedge clk);           // m0 not requesting, m1 is
        chk("skip non-req at ptr",       grant_vec == 4'b0010);

        // Advance by exactly one on a qualified completion.
        req_vec = 4'b1111; advance = 1; @(negedge clk); advance = 0;
        chk("ptr advanced to 1",         ptr == 1);
        @(negedge clk);
        chk("grant = m1 at ptr1",        grant_vec == 4'b0010);

        // Grant without completion must NOT advance.
        advance = 0; @(negedge clk);
        chk("no advance w/o completion",  ptr == 1);

        // Sweep the pointer fully around and confirm wrap 3 -> 0.
        advance = 1; @(negedge clk);                 // 1 -> 2
        chk("ptr 2", ptr == 2);
        @(negedge clk);                              // 2 -> 3
        chk("ptr 3", ptr == 3);
        @(negedge clk); advance = 0;                 // 3 -> 0 (wrap)
        chk("ptr wraps to 0", ptr == 0);

        // No requesters -> grant_valid low, no grant.
        req_vec = 4'b0000; @(negedge clk);
        chk("no req -> !grant_valid", grant_valid == 0);
        chk("no req -> no grant",     grant_vec == 4'b0000);

        if (errors == 0) $display("\n[tb_rr_pointer_unit] PASS");
        else             $display("\n[tb_rr_pointer_unit] FAIL (%0d errors)", errors);
        $finish;
    end

endmodule
