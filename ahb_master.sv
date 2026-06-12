`timescale 1ns / 1ps


module ahb_master #(
    parameter MASTER_ID = 0,
    parameter BURST_LEN = 4          // fixed number of back-to-back transfers
    )
    (
    input  logic HRESETn,
    input  logic HCLK,

    output logic HBUSREQ,
    input  logic HGRANT,
    output logic HLOCK,

    output logic [31:0] HADDR,
    output logic [1:0]  HTRANS,
    output logic        HWRITE,
    output logic [2:0]  HSIZE,
    output logic [2:0]  HBURST,
    output logic [31:0] HWDATA,
    input  logic [31:0] HRDATA,
    input  logic        HREADY,
    input  logic [1:0]  HRESP,

    input  logic        start_transfer,
    input  logic [31:0] target_addr,     // base address of the burst
    input  logic [31:0] write_data,      // base write data (incremented per beat in this example)
    input  logic        do_write
    );

    localparam IDLE  = 2'd0;
    localparam FIRST = 2'd1;  // issue address phase of transfer 1 (no data phase yet)
    localparam PIPE  = 2'd2;  // data phase of N  +  address phase of N+1, repeated
    localparam LAST  = 2'd3;  // final data phase only, no further address phase

    logic [1:0] state;

    // counts of address phases issued so far in this burst
    logic [$clog2(BURST_LEN+1)-1:0] addr_cnt;
    // count of data phases completed so far in this burst
    logic [$clog2(BURST_LEN+1)-1:0] data_cnt;

     // ------------------------------------------------------------------
    function automatic [31:0] beat_addr(input [31:0] base, input integer idx);
        beat_addr = base + (idx << 2); // word increment
    endfunction

    function automatic [31:0] beat_data(input [31:0] base, input integer idx);
        beat_data = base + idx;
    endfunction

    always_ff @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            state    <= IDLE;
            HBUSREQ  <= 1'b0;
            HLOCK    <= 1'b0;
            HTRANS   <= 2'b00;
            HADDR    <= 32'd0;
            HWRITE   <= 1'b0;
            HWDATA   <= 32'd0;
            HSIZE    <= 3'b010;
            HBURST   <= 3'b000;
            addr_cnt <= '0;
            data_cnt <= '0;
        end
        else begin
            case (state)

                IDLE: begin
                    HTRANS <= 2'b00;
                    if (start_transfer) begin
                        HBUSREQ  <= 1'b1;
                        addr_cnt <= '0;
                        data_cnt <= '0;
                        state    <= FIRST;
                    end
                end

           
                FIRST: begin
                    if (HGRANT && HREADY) begin
                        HADDR    <= beat_addr(target_addr, 0);
                        HTRANS   <= 2'b10;          // NONSEQ
                        HWRITE   <= do_write;
                        addr_cnt <= addr_cnt + 1'b1; // 1 address phase issued
                        state    <= PIPE;
                    end
                    else begin
                        state <= FIRST;
                    end
                end

                
                PIPE: begin
                    if (HREADY) begin
                        HWDATA   <= beat_data(write_data, data_cnt);
                        data_cnt <= data_cnt + 1'b1;

                        if (addr_cnt < BURST_LEN) begin
                            HADDR    <= beat_addr(target_addr, addr_cnt);
                            HTRANS   <= 2'b10;       // NONSEQ (could be SEQ for true burst)
                            HWRITE   <= do_write;
                            addr_cnt <= addr_cnt + 1'b1;
                            state    <= PIPE;        // continue pipelining
                        end
                        else begin
                            HTRANS <= 2'b00;          // drop bus to IDLE
                            state  <= LAST;
                        end
                    end
                    else begin
                            HREADY <=1'b0;
                    end
                 
                end
                // ------------------------------------------------------
                LAST: begin
                    if (HREADY) begin
                        HBUSREQ <= 1'b0;
                        state   <= IDLE;
                    end
                    
                end

            endcase
        end
    end

endmodule
