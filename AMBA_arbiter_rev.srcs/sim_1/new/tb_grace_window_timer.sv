`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 24.07.2026 12:25:06
// Design Name: 
// Module Name: tb_grace_window_timer
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
// tb_grace_window_timer — self-checking testbench for grace_window_timer (§5a)
// Requires: grace_window_timer.sv
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_grace_window_timer;

    localparam int NUM_MASTERS = 4;
    localparam int W           = 4;

    logic                   clk, rst_n;
    logic [NUM_MASTERS-1:0] grant_vec;
    logic [NUM_MASTERS-1:0] valid_xfer;
    logic                   slot_complete;
    logic                   forced_complete;

    int errors = 0;

    grace_window_timer #(.NUM_MASTERS(NUM_MASTERS), .W(W)) dut (
        .clk(clk), .rst_n(rst_n),
        .grant_vec(grant_vec), .valid_xfer(valid_xfer),
        .slot_complete(slot_complete), .forced_complete(forced_complete)
    );

    always #5 clk = ~clk;

    task automatic chk(input string name, input logic cond);
        if (!cond) begin errors++; $error("FAIL: %s", name); end
        else $display("  ok: %s", name);
    endtask

    int guard;

    initial begin
        clk = 0; rst_n = 0;
        grant_vec = '0; valid_xfer = '0; slot_complete = 0;
        @(negedge clk); rst_n = 1;

        // -- Case 1: abandoned grant, VALID_XFER never asserts -> forced complete.
        grant_vec = 4'b0001; valid_xfer = '0; slot_complete = 0;
        guard = 0;
        while (forced_complete == 0 && guard < 2*W + 4) begin
            @(negedge clk); guard++;
        end
        chk("abandoned grant -> forced_complete", forced_complete == 1);
        chk("forced fires within window",         guard <= W + 2);

        // Merge would turn forced_complete into slot_complete; feed it back to reset.
        slot_complete = 1; @(negedge clk); slot_complete = 0;
        chk("forced clears after slot_complete", forced_complete == 0);

        // Drop the grant to fully reset state.
        grant_vec = '0; @(negedge clk);

        // -- Case 2: VALID_XFER asserts inside the window -> never forced, even if
        //            the transfer is then slow (valid_xfer deasserts while underway).
        grant_vec = 4'b0100; valid_xfer = '0; @(negedge clk);  // grant, no xfer yet
        valid_xfer = 4'b0100; @(negedge clk);                  // transfer starts
        valid_xfer = '0;                                       // slow transfer, still underway
        guard = 0;
        while (guard < 2*W + 4) begin
            @(negedge clk); guard++;
            if (forced_complete) errors++;   // must never force a legitimately-started xfer
        end
        chk("slow-but-started xfer never forced", forced_complete == 0);

        // -- Case 3: no grant -> never forced.
        grant_vec = '0; valid_xfer = '0;
        repeat (W + 2) @(negedge clk);
        chk("no grant -> no forced", forced_complete == 0);

        if (errors == 0) $display("\n[tb_grace_window_timer] PASS");
        else             $display("\n[tb_grace_window_timer] FAIL (%0d errors)", errors);
        $finish;
    end

endmodule

