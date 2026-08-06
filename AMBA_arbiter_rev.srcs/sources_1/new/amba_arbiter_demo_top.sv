`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 05.08.2026 10:56:32
// Design Name: 
// Module Name: amba_arbiter_demo_top
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


module amba_arbiter_demo_top#
(
    parameter int TICK_DIV = 50_000_000,
    parameter int DEBOUNCE_CYCLES = 1_000_000
    )(
    input logic clk,
    input logic btnC,
    input logic btnU,
    output logic [15:0] led,
    input logic [15:0] sw
    );

    logic [3:0] req;   //request signal for each master
    logic [11:0] pri;    //priority for each master is 3 bits wide, for 4 masters we need 12 bits
    logic [3:0] lock;  //lock signal for each master
    logic [3:0] complete;   
    logic [3:0] grant;
    logic [3:0] valid_xfer;
    logic rst_n_sync;
    logic slot_complete;
    logic slot_type;
    localparam int STRETCH_CYCLES = 5_000_000; //50ms @100MHz
    localparam int TICK_W = $clog2(TICK_DIV);
    localparam int DB_W = $clog2(DEBOUNCE_CYCLES);

    (*ASYNC_REG = "TRUE"*) logic [15:0]sw_meta, sw_sync;
    (*ASYNC_REG = "TRUE"*) logic btn_meta, btn_sync;

    logic [22:0] stretch_cnt;
    logic slot_complete_led;
    logic [TICK_W-1:0] tick_cnt;
    logic auto_tick;
    logic tick;
    
    logic [DB_W-1:0] db_cnt;
    logic btn_stable;
    logic btn_stable_q;
    logic step_pulse;

    always_ff@(posedge clk or negedge rst_n_sync) begin
        if(!rst_n_sync) begin
            btn_meta<=1'b0;
            btn_sync<=1'b0;
            db_cnt<='0;
            btn_stable<=1'b0;
            btn_stable_q<=1'b0;
        end

        else begin
           btn_meta<= btnU;
           btn_sync <= btn_meta;

           if( btn_sync != btn_stable) begin
            if(db_cnt == DEBOUNCE_CYCLES-1) begin
                btn_stable <= btn_sync;
                db_cnt <= '0;
            end
            else begin
                db_cnt <= db_cnt + 1'b1;
            end
           end 
        else begin
            db_cnt<='0;

        end

        btn_stable_q <= btn_stable;
            end
    end

    assign step_pulse = btn_stable && !btn_stable_q;

    logic [3:0] sw_req;
    logic [1:0] sw_pri_sel;
    logic [3:0] sw_lock;
    logic [3:0] sw_abandon;
    logic sw_step_mode;
    
    logic [1:0] pri_sel_q;
    always_ff@(posedge clk or negedge rst_n_sync) begin
        if(!rst_n_sync) begin
            pri_sel_q<=2'b00;
        end
        else if (slot_complete || (grant == '0))
        begin
            pri_sel_q <= sw_pri_sel;
        end
    end
    
    //priroity table logic

    always_comb begin
        unique case(pri_sel_q)
            2'b00: begin                //all equal
                pri[0*3 +: 3] = 3'd4;
                pri[1*3 +: 3] = 3'd4;
                pri[2*3+:3] = 3'd4;
                pri[3*3+:3] = 3'd4;
            end

            2'b01: begin                //graded 
                pri[0*3 +: 3] = 3'd0;
                pri[1*3 +: 3] = 3'd1;
                pri[2*3+:3] = 3'd2;
                pri[3*3+:3] = 3'd3;
            end

            2'b10: begin                // partial tie
               pri[0*3+: 3] = 3'd1;
               pri[1*3+:3] = 3'd1;
               pri[2*3+:3] = 3'd5;
               pri[3*3+:3] = 3'd5;
            end

            2'b11: begin                // one dominant master
                pri[0*3+: 3] = 3'd1;
                pri[1*3+:3] = 3'd1;
                pri[2*3+:3] = 3'd1;
                pri[3*3+:3] = 3'd7;
            end

        endcase
    end
  

    always_ff@(posedge clk or negedge rst_n_sync) begin
        if(!rst_n_sync) begin
            sw_meta <= '0;
            sw_sync <= '0;
        end
        else begin
            sw_meta<=sw;
            sw_sync <= sw_meta;
        end
    end


    always_ff @(posedge clk or negedge rst_n_sync) begin
        if(!rst_n_sync) begin
            stretch_cnt <='0;
        end
        else if (slot_complete) 
        begin
            stretch_cnt <= STRETCH_CYCLES[22:0];
        end
        else if (stretch_cnt != '0)
        begin
            stretch_cnt <= stretch_cnt - 1'b1;
        end
    end

    assign slot_complete_led = (stretch_cnt != '0);

    // always_ff @(posedge clk or negedge rst_n_sync) begin
    //     if(!rst_n_sync) 
    //        begin
    //         slot_complete_led <= 1'b0;
    //        end
    //     else if(slot_complete)
    //         begin
    //             slot_complete_led <= ~slot_complete_led;
    //         end
    // end

    assign sw_req = sw_sync[3:0];
    assign sw_lock = sw_sync[7:4];
    assign sw_abandon = sw_sync[11:8]; 
    assign sw_pri_sel = sw_sync[13:12];
    assign sw_step_mode = sw_sync[15];
    


    always_ff@(posedge clk or negedge rst_n_sync) begin
        if(!rst_n_sync) begin
            tick_cnt <= '0;
        end
        else if(tick_cnt == TICK_DIV-1) begin
            tick_cnt <= '0;
        end
        else begin
            tick_cnt <= tick_cnt + 1'b1;
        end
    end

    assign auto_tick = (tick_cnt == TICK_DIV-1);

    assign tick = sw_step_mode ? step_pulse : auto_tick;

    assign led[3:0] = grant;
    assign led[4] = slot_type;
    assign led[5] = slot_complete_led;
    assign led[15:12] = req;
    assign led[11:6] = '0;


    assign lock = sw_lock;

    reset_sync #(
        .STAGES(2)
    )
    u_reset_sync (
        .arst_n(~btnC),
        .clk(clk),
        .rst_n(rst_n_sync)
    );


    amba_arbiter_top #(
        .NUM_MASTERS(4),
        .PRI_WIDTH(3),
        .GRACE_W(4)
    ) u_amba_arbiter_top (
        .clk(clk),
        .rst_n(rst_n_sync),
        .REQ(req),
        .PRI(pri),
        .LOCK(lock),
        .COMPLETE(complete),
        .GRANT(grant),
        .VALID_XFER(valid_xfer),
        .slot_complete(slot_complete),
        .slot_type(slot_type)
    );


    master_model #(
        .NUM_MASTERS(4)
    ) u_master_model (
        .clk(clk),
        .rst_n_sync(rst_n_sync),
        .grant(grant),
        .tick(tick),
        .sw_req(sw_req),
        .sw_abandon(sw_abandon),
        .valid_xfer(valid_xfer),
        .req(req),
        .complete(complete)        
    );
    

    
endmodule
