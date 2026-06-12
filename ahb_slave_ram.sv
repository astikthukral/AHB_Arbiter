module ahb_slave_ram #(
    parameter DEPTH = 256   // number of 32-bit words
    )(
    input  logic HCLK,
    input  logic HRESETn,

    input  logic        HSEL,
    input  logic [31:0] HADDR,
    input  logic [1:0]  HTRANS,
    input  logic        HWRITE,
    input  logic [31:0] HWDATA,

    output logic [31:0] HRDATA,
    output logic        HREADY,
    output logic [1:0]  HRESP
    );

  logic [31:0] mem [0:DEPTH-1]; // ram emory table


    logic        sel_q;
    logic        write_q;
    logic [31:0] addr_q;

    always_ff @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            sel_q   <= 1'b0;
            write_q <= 1'b0;
            addr_q  <= 32'd0;
        end else begin
            // capture address phase only on a valid transfer
            sel_q   <= HSEL && (HTRANS != 2'b00);
            write_q <= HWRITE;
            addr_q  <= HADDR;
        end
    end

    always_ff @(posedge HCLK) begin
        if (sel_q && write_q)
            mem[addr_q[31:2]] <= HWDATA;   // write
    end

    assign HRDATA = mem[addr_q[31:2]];     // read (combinational from latched addr)
    assign HREADY = 1'b1;                  // zero wait-state slave
    assign HRESP  = 2'b00;                 // always OKAY

endmodule
