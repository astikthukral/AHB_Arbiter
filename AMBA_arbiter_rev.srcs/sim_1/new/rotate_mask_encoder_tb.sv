`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 21.07.2026 17:17:24
// Design Name: 
// Module Name: rotate_mask_encoder_tb
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
// tb_rotate_mask_encoder
//
// Exhaustive, self-checking testbench for rotate_mask_encoder.
//
// For small NUM_MASTERS (default 4), every possible mask_vec (2^N combinations,
// including mask_vec = 0) is applied against every possible ptr (0..N-1) —
// that's the full input space of a purely combinational module, so "exhaustive"
// here really does mean every reachable input, not a sample.
//
// A separate, independently-written reference function (`expected_grant`)
// computes the correct answer by literally scanning forward from ptr with
// wraparound — the most direct, unoptimized statement of "closest requester
// at or after the pointer" — and the DUT's output is checked against it.
// Keeping the reference model structurally different from the DUT's own
// rotate/encode/un-rotate implementation is deliberate: if both were written
// the same way, a shared mistake in the approach wouldn't be caught.
// -----------------------------------------------------------------------------

module tb_rotate_mask_encoder;

    localparam int NUM_MASTERS = 4;
    localparam int PTR_WIDTH   = (NUM_MASTERS <= 1) ? 1 : $clog2(NUM_MASTERS);

    logic [NUM_MASTERS-1:0] mask_vec;
    logic [PTR_WIDTH-1:0]   ptr;
    logic [NUM_MASTERS-1:0] grant_vec;
    logic                   grant_valid;

    int errors;
    int checks;

    rotate_mask_encoder #(
        .NUM_MASTERS(NUM_MASTERS),
        .PTR_WIDTH  (PTR_WIDTH)
    ) dut (
        .mask_vec   (mask_vec),
        .ptr        (ptr),
        .grant_vec  (grant_vec),
        .grant_valid(grant_valid)
    );

    // Reference model: independent implementation, not derived from the DUT.
    // Scans real indices ptr, ptr+1, ptr+2, ... (mod N) and returns the first
    // requester found; returns 0 (no grant) if mask_vec is all-zero.
    function automatic logic [NUM_MASTERS-1:0] expected_grant(
        input logic [NUM_MASTERS-1:0] m,
        input int                     p
    );
        logic [NUM_MASTERS-1:0] result;
        logic                   found;
        int idx;
        result = '0;
        found  = 1'b0;
        if (m != '0) begin
            for (int i = 0; i < NUM_MASTERS; i++) begin
                idx = (p + i) % NUM_MASTERS;
                if (m[idx] && !found) begin
                    result[idx] = 1'b1;
                    found = 1'b1;
                end
            end
        end
        return result;
    endfunction

    task automatic check(input logic [NUM_MASTERS-1:0] m, input int p);
        logic [NUM_MASTERS-1:0] exp_grant;
        logic                   exp_valid;
        mask_vec = m;
        ptr      = p[PTR_WIDTH-1:0];
        #1; //  combinational logic settles here

        exp_grant = expected_grant(m, p);
        exp_valid = (m != '0);

        checks++;
        if (grant_vec !== exp_grant || grant_valid !== exp_valid) begin
            errors++;
            $display("FAIL: mask_vec=%b ptr=%0d -> got grant_vec=%b grant_valid=%b, expected grant_vec=%b grant_valid=%b",
                       m, p, grant_vec, grant_valid, exp_grant, exp_valid);
        end
    endtask

    initial begin
        errors = 0;
        checks = 0;

        // Exhaustive sweep: every mask_vec value x every pointer position.
        for (int m = 0; m < (1 << NUM_MASTERS); m++) begin
            for (int p = 0; p < NUM_MASTERS; p++) begin
                check(m[NUM_MASTERS-1:0], p);
            end
        end

        // Directed re-check of the worked example from the spec walkthrough:
        // N=4, ptr=2 (M2 is "next"), mask_vec = 4'b1001 (M0 and M3 requesting,
        // M2 not requesting) -> expected winner is M3 (bit 3).
        check(4'b1001, 2);

        $display("----------------------------------------------------");
        $display("rotate_mask_encoder exhaustive test: %0d checks, %0d errors", checks, errors);
        if (errors == 0)
            $display("RESULT: PASS");
        else
            $display("RESULT: FAIL");
        $display("----------------------------------------------------");

        $finish;
    end

endmodule
