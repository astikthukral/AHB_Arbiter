`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 03.05.2026 07:32:57
// Design Name: 
// Module Name: ahb_arbiter
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


module ahb_arbiter #(
parameter NUM_MASTERS=3,
parameter [1:0] PRIORITY [0:NUM_MASTERS-1]='{2'd2,2'd1,2'd0}
    )(
   input logic HCLK,
   input logic HRESETn,
   
   input logic [NUM_MASTERS-1:0] HBUSREQ,
   input logic [NUM_MASTERS-1:0] HLOCK,
   
   input logic [1:0] HTRANS,
   input logic HREADY,
   
   output logic [NUM_MASTERS-1:0] HGRANT,
   output logic [$clog2(NUM_MASTERS)-1:0] HMASTER     
    );
    logic [$clog2(NUM_MASTERS)-1:0] rr_ptr;
    logic locked;
    
    integer i;
    logic [$clog2(NUM_MASTERS)-1:0] next_master;
    logic found;
    
    always_ff@(posedge HCLK or negedge HRESETn)
    begin
    if(!HRESETn)
    begin
    HGRANT<={{NUM_MASTERS-1{1'b0}}, 1'b1};
    HMASTER<=0;
    rr_ptr<=0;
    locked<=0;
    end
  else if(HREADY)
    begin
    if(HLOCK[HMASTER] && HTRANS!=2'b00)
    begin
    locked<=1;
    end
    else 
    begin
    locked <=0;
    found<=0;
    next_master = rr_ptr;
    
    for(i=NUM_MASTERS-1;i>=0;i=i-1)
    begin
    if(HBUSREQ[i] && PRIORITY[i]>PRIORITY[next_master])
    begin
    next_master =i[$clog2(NUM_MASTERS)-1:0];
    found =1;
    end
    end
    
    if (!found)
    begin
        for(i=0;i<NUM_MASTERS;i=i+1)
            begin
            if(!found)
                begin
                if(HBUSREQ[(rr_ptr+1+i)% NUM_MASTERS])
                    begin
                    next_master = (rr_ptr+1+i)%NUM_MASTERS;
                    found =1;
                    end
                end
            end 
        
    end   
    
    
    if(found)
        begin
            HGRANT<=0;
            HGRANT[next_master]<=1'b1;
            HMASTER<=next_master;
            rr_ptr<=next_master;
        end 
    else
        begin
        HGRANT<={{(NUM_MASTERS-1){1'b0}},1'b1};
        HMASTER<=0;
        end
    end
    end
    end
endmodule
