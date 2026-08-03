`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 24.07.2026 12:20:57
// Design Name: 
// Module Name: tb_tie_break_rr_unit
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
// tb_tie_break_rr_unit — self-checking testbench for tie_break_rr_unit (§3a)
// Requires: tie_break_rr_unit.sv, rotate_mask_encoder.sv
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_tie_break_rr_unit;

    localparam int NUM_MASTERS = 4;
    localparam int PTR_WIDTH   = $clog2(NUM_MASTERS);

    logic                   clk, rst_n;
    logic [NUM_MASTERS-1:0] tied_mask;
    logic                   advance;
    logic [NUM_MASTERS-1:0] grant_vec;
    logic                   grant_valid;
    logic [PTR_WIDTH-1:0]   ptr;

    int errors = 0;

    tie_break_rr_unit #(.NUM_MASTERS(NUM_MASTERS)) dut (
        .clk(clk), .rst_n(rst_n), .tied_mask(tied_mask), .advance(advance),
        .grant_vec(grant_vec), .grant_valid(grant_valid), .ptr(ptr)
    );

    always #5 clk = ~clk;

    task automatic chk(input string name, input logic cond);
        if (!cond) begin errors++; $error("FAIL: %s", name); end
        else $display("  ok: %s", name);
    endtask

    initial begin
        clk = 0; rst_n = 0; tied_mask = '0; advance = 0;
        @(negedge clk); rst_n = 1;

        // Tie between m1 and m3; pointer at 0 -> nearest at/after 0 is m1.
        tied_mask = 4'b1010; advance = 0; @(negedge clk);
        chk("ptr resets 0",        ptr == 0);
        chk("tie pick m1 @ptr0",   grant_vec == 4'b0010);
        chk("grant_valid",         grant_valid == 1);

        // Resolve the tie (advance) -> pointer moves one position.
        advance = 1; @(negedge clk); advance = 0;
        chk("ptr -> 1",            ptr == 1);
        @(negedge clk);
        chk("tie pick m3 @ptr1",   grant_vec == 4'b1000);  // nearest at/after 1 is m3

        // A master leaving/joining the tied set needs no special handling:
        // now only m2,m3 tied, pointer at 1 -> nearest is m2.
        tied_mask = 4'b1100; @(negedge clk);
        chk("mask change: pick m2", grant_vec == 4'b0100);

        // Unique winner (mask one-hot) leaves pointer untouched when advance held low.
        tied_mask = 4'b0001; advance = 0; @(negedge clk);
        chk("one-hot mask pick m0", grant_vec == 4'b0001);
        chk("ptr unchanged (=1)",   ptr == 1);

        // Empty tied set -> not valid, no grant.
        tied_mask = 4'b0000; @(negedge clk);
        chk("empty mask: !valid",   grant_valid == 0);
        chk("empty mask: no grant", grant_vec == 0);

        if (errors == 0) $display("\n[tb_tie_break_rr_unit] PASS");
        else             $display("\n[tb_tie_break_rr_unit] FAIL (%0d errors)", errors);
        $finish;
    end

endmodule

