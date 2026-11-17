`timescale 1ns / 1ns
`default_nettype none

// Testbench for Mincraft (vga_demo.v). Simulates the whole top level: PS/2 keyboard in,
// world drawing, and Steve walking, colliding, jumping and falling.
//
// Scenario (spawn is X = 320, Y = 224 standing on the grass at tile column 10):
//   1. tap A five times: 320 -> 312 -> 304 -> 296 -> 288, then the grass block at
//      column 8 (one block high) stops him, so X stays 288
//   2. press and release SPACE: he rises 40 px to Y = 184 and floats
//   3. while floating, tap A: he moves onto the block (X = 280) and lands at Y = 192
//   4. tap D: he walks off the block (X = 288) and falls back to Y = 224

module testbench ( );

    parameter CLOCK_PERIOD = 20;         // 50 MHz
    parameter PS2_HALF = 400;            // PS/2 clock half period in ns (a real keyboard is
                                         // about 40000; faster is fine for simulation)

    reg CLOCK_50;
    reg [3:0] KEY;
    reg [9:0] SW;
    reg ps2_clk_drv, ps2_dat_drv;        // what the "keyboard" drives onto the PS/2 lines
    wire PS2_CLK, PS2_DAT;
    wire [9:0] LEDR;
    wire [6:0] HEX5, HEX4, HEX3, HEX2, HEX1, HEX0;
    wire [7:0] VGA_R, VGA_G, VGA_B;
    wire VGA_HS, VGA_VS, VGA_BLANK_N, VGA_SYNC_N, VGA_CLK;

    assign PS2_CLK = ps2_clk_drv;
    assign PS2_DAT = ps2_dat_drv;

    initial CLOCK_50 = 1'b0;
    always #(CLOCK_PERIOD/2) CLOCK_50 <= ~CLOCK_50;

    vga_demo DUT (CLOCK_50, SW, KEY, LEDR, PS2_CLK, PS2_DAT, HEX5, HEX4, HEX3, HEX2, HEX1, HEX0,
                  VGA_R, VGA_G, VGA_B, VGA_HS, VGA_VS, VGA_BLANK_N, VGA_SYNC_N, VGA_CLK);
        defparam DUT.S.P = 13;           // physics tick every 2^13 clocks (not 2^21) so a jump
                                         // takes ~1.5 ms of simulated time instead of ~400 ms

    // send one byte like a PS/2 keyboard: start (0), d0..d7, odd parity, stop (1).
    // vga_demo shifts in PS2_DAT on each falling edge of PS2_CLK.
    task ps2_byte (input [7:0] data);
        reg [10:0] frame;
        integer i;
        begin
            frame = {1'b1, ~^data, data, 1'b0};      // {stop, parity, data, start}
            for (i = 0; i < 11; i = i + 1) begin
                ps2_dat_drv = frame[i];
                #(PS2_HALF) ps2_clk_drv = 1'b0;
                #(PS2_HALF) ps2_clk_drv = 1'b1;
            end
            #(PS2_HALF * 4);                         // idle gap between bytes
        end
    endtask

    // wait until Steve has finished every queued update and the command FSM is back in A
    task wait_idle;
        begin
            @(posedge CLOCK_50);
            wait (DUT.S_done == 1'b1 && DUT.y_Q == 2'd0);
            repeat (10) @(posedge CLOCK_50);
        end
    endtask

    // press and release one key: make code, then break code (F0, code)
    task tap (input [7:0] code);
        begin
            ps2_byte(code);
            wait_idle;
            ps2_byte(8'hF0);
            ps2_byte(code);
            wait_idle;
        end
    endtask

    task check (input [9:0] x_exp, input [8:0] y_exp, input [8*40-1:0] what);
        begin
            if (DUT.S.X == x_exp && DUT.S.Y == y_exp)
                $display("%t  PASS  %0s: X = %0d, Y = %0d", $time, what, DUT.S.X, DUT.S.Y);
            else
                $display("%t  FAIL  %0s: X = %0d, Y = %0d (expected X = %0d, Y = %0d)",
                         $time, what, DUT.S.X, DUT.S.Y, x_exp, y_exp);
        end
    endtask

    initial begin
        KEY = 4'b0000;                   // KEY[0] = 0: hold reset
        SW = 10'd0;
        ps2_clk_drv = 1'b1;              // PS/2 lines idle high
        ps2_dat_drv = 1'b1;
        #200 KEY[0] = 1'b1;              // release reset

        wait (DUT.world_done == 1'b1);
        $display("%t  world finished drawing", $time);
        wait_idle;                       // Steve's first draw
        check(10'd320, 9'd224, "spawn");

        // 1. walk left into the 1-block step at column 8
        repeat (5) tap(8'h1C);           // A
        check(10'd288, 9'd224, "blocked by the step");

        // 2. jump
        ps2_byte(8'h29);                 // SPACE down
        wait_idle;
        ps2_byte(8'hF0);                 // SPACE up
        ps2_byte(8'h29);
        wait (DUT.S.hang != 4'd0);       // reached the top, now floating
        check(10'd288, 9'd184, "top of the jump");

        // 3. move onto the block while floating, then land on it
        tap(8'h1C);                      // A
        wait (DUT.S.airborne == 1'b0);
        wait_idle;
        check(10'd280, 9'd192, "landed on the step");

        // 4. walk off the step and fall back down
        tap(8'h23);                      // D
        wait (DUT.S.airborne == 1'b0);
        wait_idle;
        check(10'd288, 9'd224, "fell back to the ground");

        $display("%t  done", $time);
        $stop;
    end

    initial begin                        // safety net if something hangs
        #40_000_000;
        $display("%t  TIMEOUT", $time);
        $stop;
    end

endmodule

// Stand-in for the course vga_adapter, used only in simulation. It has the same ports and
// parameters, so vga_demo.v compiles unchanged, but no PLL or video memory. The pixels
// Steve and the world draw are visible on MUX_x / MUX_y / MUX_color / MUX_write instead.
module vga_adapter (resetn, clock, color, x, y, write,
                    VGA_R, VGA_G, VGA_B, VGA_HS, VGA_VS, VGA_BLANK_N, VGA_SYNC_N, VGA_CLK);
    parameter RESOLUTION = "640x480";
    parameter BACKGROUND_IMAGE = "";
    parameter COLOR_DEPTH = 9;

    input wire resetn, clock;
    input wire [COLOR_DEPTH-1:0] color;
    input wire [9:0] x;
    input wire [8:0] y;
    input wire write;
    output wire [7:0] VGA_R, VGA_G, VGA_B;
    output wire VGA_HS, VGA_VS, VGA_BLANK_N, VGA_SYNC_N, VGA_CLK;

    assign VGA_R = 8'd0;
    assign VGA_G = 8'd0;
    assign VGA_B = 8'd0;
    assign VGA_HS = 1'b0;
    assign VGA_VS = 1'b0;
    assign VGA_BLANK_N = 1'b0;
    assign VGA_SYNC_N = 1'b0;
    assign VGA_CLK = 1'b0;
endmodule
