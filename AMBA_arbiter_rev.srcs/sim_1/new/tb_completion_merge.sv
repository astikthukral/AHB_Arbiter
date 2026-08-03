`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 24.07.2026 12:25:42
// Design Name: 
// Module Name: tb_completion_merge
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
// tb_completion_merge — self-checking testbench for completion_merge
// Requires: completion_merge.sv
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_completion_merge;

    logic genuine_complete, forced_complete, slot_complete;
    int errors = 0;

    completion_merge dut (
        .genuine_complete(genuine_complete),
        .forced_complete(forced_complete),
        .slot_complete(slot_complete)
    );

    task automatic chk(input string name, input logic cond);
        if (!cond) begin errors++; $error("FAIL: %s", name); end
        else $display("  ok: %s", name);
    endtask

    initial begin
        // Exhaustive truth table for the 2-input OR.
        genuine_complete = 0; forced_complete = 0; #1;
        chk("0|0 = 0", slot_complete == 0);
        genuine_complete = 0; forced_complete = 1; #1;
        chk("0|1 = 1", slot_complete == 1);
        genuine_complete = 1; forced_complete = 0; #1;
        chk("1|0 = 1", slot_complete == 1);
        genuine_complete = 1; forced_complete = 1; #1;
        chk("1|1 = 1", slot_complete == 1);

        if (errors == 0) $display("\n[tb_completion_merge] PASS");
        else             $display("\n[tb_completion_merge] FAIL (%0d errors)", errors);
        $finish;
    end

endmodule

