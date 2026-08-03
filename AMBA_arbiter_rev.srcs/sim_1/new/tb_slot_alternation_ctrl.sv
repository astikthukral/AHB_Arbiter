`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 24.07.2026 12:22:14
// Design Name: 
// Module Name: tb_slot_alternation_ctrl
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
// tb_slot_alternation_ctrl — self-checking testbench for slot_alternation_ctrl (§4)
// Requires: slot_alternation_ctrl.sv
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_slot_alternation_ctrl;

    logic clk, rst_n;
    logic slot_complete, freeze;
    logic slot_type;

    int errors = 0;

    slot_alternation_ctrl dut (
        .clk(clk), .rst_n(rst_n),
        .slot_complete(slot_complete), .freeze(freeze), .slot_type(slot_type)
    );

    always #5 clk = ~clk;

    task automatic chk(input string name, input logic cond);
        if (!cond) begin errors++; $error("FAIL: %s", name); end
        else $display("  ok: %s", name);
    endtask

    initial begin
        clk = 0; rst_n = 0; slot_complete = 0; freeze = 0;
        @(negedge clk); rst_n = 1;

        chk("reset -> RR(0)", slot_type == 1'b0);

        // No completion -> no toggle.
        slot_complete = 0; @(negedge clk);
        chk("idle: stays RR", slot_type == 1'b0);

        // Completion toggles RR -> PRIORITY.
        slot_complete = 1; @(negedge clk); slot_complete = 0;
        chk("complete -> PRIORITY", slot_type == 1'b1);

        // Another completion toggles PRIORITY -> RR.
        slot_complete = 1; @(negedge clk); slot_complete = 0;
        chk("complete -> RR", slot_type == 1'b0);

        // Freeze holds slot_type even on completion (locked-sequence mid-flight).
        slot_complete = 1; freeze = 1; @(negedge clk);
        chk("frozen: no toggle", slot_type == 1'b0);
        @(negedge clk);
        chk("frozen still holds", slot_type == 1'b0);

        // Freeze released on the completing cycle -> the sequence consumes one slot.
        freeze = 0; slot_complete = 1; @(negedge clk); slot_complete = 0;
        chk("unfreeze+complete -> PRIORITY", slot_type == 1'b1);

        if (errors == 0) $display("\n[tb_slot_alternation_ctrl] PASS");
        else             $display("\n[tb_slot_alternation_ctrl] FAIL (%0d errors)", errors);
        $finish;
    end

endmodule

