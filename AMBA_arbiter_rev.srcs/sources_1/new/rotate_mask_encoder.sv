`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 21.07.2026 16:49:47
// Design Name: 
// Module Name: rotate_mask_encoder
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
// rotate_mask_encoder
//
// Purely combinational. No state, no clock, no reset.
//
// Given a pointer position and an N-bit mask (the live request vector for the
// main RR pointer, or the tied-subset vector for the nested tie-break pointer),
// produces a one-hot grant for whichever masked bit is "closest, at or after
// the pointer, in cyclic order."
//
// Mechanism (§2 / §3a of the spec):
//   1. Rotate `mask_vec` so that index `ptr` maps to rotated index 0.
//   2. Priority-encode the rotated vector, lowest index wins (closest to ptr).
//   3. Rotate the single-bit result back to the original index space.
//
// NUM_MASTERS need not be a power of two — rotation is done with modulo
// arithmetic on indices, not bit shifts, so this is correct for any N.
//
// This module is instantiated twice in the design (rr_pointer_unit and
// tie_break_rr_unit) with different mask_vec/ptr sources. It is intentionally
// the only place this rotate-mask logic is written, so both pointers stay
// structurally identical by construction.
// -----------------------------------------------------------------------------

module rotate_mask_encoder #(
    parameter int NUM_MASTERS = 4,
    parameter int PTR_WIDTH   = (NUM_MASTERS <= 1) ? 1 : $clog2(NUM_MASTERS)
) (
    input  logic [NUM_MASTERS-1:0] mask_vec,   // request vector, or tied-subset vector
    input  logic [PTR_WIDTH-1:0]   ptr,        // current pointer position (0 .. NUM_MASTERS-1)

    output logic [NUM_MASTERS-1:0] grant_vec,  // one-hot grant, all-zero if mask_vec is all-zero
    output logic                   grant_valid // = |mask_vec ; tells the caller whether grant_vec is meaningful
);

    logic [NUM_MASTERS-1:0] rotated;
    logic [NUM_MASTERS-1:0] rotated_grant;

    // Step 1: rotate mask_vec so pointer position -> rotated index 0
    always_comb begin
        for (int i = 0; i < NUM_MASTERS; i++) begin
            rotated[i] = mask_vec[(ptr + i) % NUM_MASTERS];
        end
    end

    // Step 2: lowest-index-wins priority encode on the rotated vector
    // (lowest rotated index = closest requester at-or-after the pointer)
    always_comb begin
        rotated_grant = '0;
        for (int i = 0; i < NUM_MASTERS; i++) begin
            if (rotated[i]) begin
                rotated_grant[i] = 1'b1;
                break;
            end
        end
    end

    // Step 3: rotate the single granted bit back to original index space
    always_comb begin
        grant_vec = '0;
        for (int i = 0; i < NUM_MASTERS; i++) begin
            if (rotated_grant[i]) begin
                grant_vec[(ptr + i) % NUM_MASTERS] = 1'b1;
            end
        end
    end

    assign grant_valid = |mask_vec;

endmodule