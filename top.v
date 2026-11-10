// top.v for DESim. Replaces the demo's top.v. Uses the world and steve modules from
// vga_demo.v (unchanged) and object_mem.v. The vga_adapter is NOT used here: DESim's
// window plays the role of video memory and draws a pixel whenever plot = 1.

`include "resolution.v"                  // DESim demo file; must contain `define VGA_640_480
`default_nettype none                    // every signal must be declared

module top (CLOCK_50, KEY, VGA_X, HEX0, HEX1, HEX2, HEX3, HEX4, HEX5, VGA_Y, VGA_COLOR, plot);

    parameter DRAW_BG = 1;               // 1 = copy background.mif first; 0 = skip it (faster)
    parameter T = 9;                    // Steve updates every 2^T clocks while a KEY is held

    input wire CLOCK_50;                 // 50 MHz clock from the testbench
    input wire [3:0] KEY;                // pushbuttons, 0 = pressed
    output wire [6:0] HEX0, HEX1, HEX2, HEX3, HEX4, HEX5; // 7-segment displays
    output wire [9:0] VGA_X;             // pixel column, 0..639
    output wire [8:0] VGA_Y;             // pixel row, 0..479
    output wire [23:0] VGA_COLOR;        // pixel colour, 8 bits each of R, G, B
    output wire plot;                    // 1 = DESim draws (VGA_X, VGA_Y) in VGA_COLOR

    wire Resetn = KEY[0];                // KEY[0] = reset, same as on the board

    // pixel-write signals from the three drawers: background (G), world (W), Steve (S)
    wire [9:0] G_x, W_x, S_x, MUX_x;
    wire [8:0] G_y, W_y, S_y, MUX_y;
    wire [8:0] G_color, W_color, S_color, MUX_color;  // 9-bit colours, as in the MIFs
    wire G_write, W_write, S_write, MUX_write;
    wire bg_done, world_done, S_done;    // finished flags; S_done = Steve idle

    // ---------------- 1. copy the background image to the screen ----------------
    reg [18:0] addr;                     // background memory address, 0..307199
    reg [9:0] bx;                        // x of the pixel being read
    reg [8:0] by;                        // y of the pixel being read
    reg running;                         // 1 while the copy is in progress

    always @(posedge CLOCK_50)
        if (!Resetn) begin               // on reset: start at the top-left pixel
            addr <= 19'd0;
            bx <= 10'd0;
            by <= 9'd0;
            running <= (DRAW_BG == 1);   // only run if DRAW_BG is 1
        end
        else if (running) begin
            addr <= addr + 19'd1;        // next memory word
            if (bx == 10'd639) begin     // end of a row:
                bx <= 10'd0;             //   back to column 0
                if (by == 9'd479)        //   last row?
                    running <= 1'b0;     //   then stop
                else
                    by <= by + 9'd1;     //   else next row
            end
            else
                bx <= bx + 10'd1;        // next column
        end

    // the MIF stores pixels row by row, so word number = y*640 + x = addr
    bg_mem BG (addr, CLOCK_50, G_color);

    // memory answers one clock later, so delay x, y and write by one clock to match
    regn UGX (bx, Resetn, 1'b1, CLOCK_50, G_x);
        defparam UGX.n = 10;
    regn UGY (by, Resetn, 1'b1, CLOCK_50, G_y);
        defparam UGY.n = 9;
    regn UGW (running, Resetn, 1'b1, CLOCK_50, G_write);
        defparam UGW.n = 1;

    assign bg_done = !running && !G_write;   // copy finished and last pixel written

    // ---------------- 2. draw the blocks (world module from vga_demo.v) ----------------
    // held in reset until the background is finished, so it starts right after it
    world W (Resetn & bg_done, CLOCK_50, W_x, W_y, W_color, W_write, world_done);

    // ---------------- 3. Steve, driven by pushbuttons ----------------
    wire left  = ~KEY[3];                // KEY[3] held = walk left
    wire right = ~KEY[2];                // KEY[2] held = walk right
    wire hitk  = ~KEY[1];                // KEY[1] held = hit
    wire any   = left | right | hitk;    // some button is held

    // pretend each button is a keyboard key, so steve needs no changes
    wire [7:0] code = left  ? 8'h1C :    // 'A'
                      right ? 8'h23 :    // 'D'
                      hitk  ? 8'h2B :    // 'F'
                              8'h00;     // nothing

    reg [T-1:0] tick_count;              // free-running counter
    always @(posedge CLOCK_50)
        if (!Resetn) tick_count <= 0;
        else tick_count <= tick_count + 1'b1;
    wire tick = (tick_count == 0);       // 1 for one clock every 2^T clocks

    reg held;                            // a button was held at the previous update
    // update Steve on a tick, only when he is idle, and only if a button is held now
    // (walk/hit) or was held last time (one more update to return to the standing pose)
    wire step = tick & S_done & (any | held);
    always @(posedge CLOCK_50)
        if (!Resetn) held <= 1'b0;
        else if (step) held <= any;      // remember for the next update

    wire [7:0] scancode;                 // latched key code for steve
    wire key_up;                         // latched "no button held" = release
    regn USC (code, Resetn, step, CLOCK_50, scancode);    // latch on step
    regn UKU (~any, Resetn, step, CLOCK_50, key_up);
        defparam UKU.n = 1;

    steve S (Resetn, CLOCK_50, world_done, step, scancode, key_up,
             S_x, S_y, S_color, S_write, S_done);

    // ---------------- choose who is drawing: background, then world, then Steve ----------
    assign MUX_x     = !bg_done ? G_x     : (!world_done ? W_x     : S_x);
    assign MUX_y     = !bg_done ? G_y     : (!world_done ? W_y     : S_y);
    assign MUX_color = !bg_done ? G_color : (!world_done ? W_color : S_color);
    assign MUX_write = !bg_done ? G_write : (!world_done ? W_write : S_write);

    // ---------------- outputs to DESim ----------------
    assign VGA_X = MUX_x;
    assign VGA_Y = MUX_y;
    assign plot  = MUX_write;
    // 9-bit colour is RRRGGGBBB. Widen each 3-bit channel to 8 bits by repeating it:
    // e.g. red 101 -> 10110110 (same idea as vga_controller.v)
    assign VGA_COLOR = {MUX_color[8:6], MUX_color[8:6], MUX_color[8:7],
                        MUX_color[5:3], MUX_color[5:3], MUX_color[5:4],
                        MUX_color[2:0], MUX_color[2:0], MUX_color[2:1]};

    assign HEX0 = 7'b1111111;            // all HEX displays off (active low)
    assign HEX1 = 7'b1111111;
    assign HEX2 = 7'b1111111;
    assign HEX3 = 7'b1111111;
    assign HEX4 = 7'b1111111;
    assign HEX5 = 7'b1111111;

endmodule

// object_mem from object_pro, but with an exact word count (307200 is not a power of 2)
module bg_mem (address, clock, q);
    parameter n = 9;                     // colour bits
    parameter Mn = 19;                   // address bits (2^19 > 307200)
    parameter WORDS = 307200;            // 640 * 480
    parameter INIT_FILE = "./MIF/background.mif";

    input wire [Mn-1:0] address;
    input wire clock;
    output wire [n-1:0] q;

    altsyncram altsyncram_component (
                .address_a (address),
                .clock0 (clock),
                .q_a (q),
                .aclr0 (1'b0),
                .aclr1 (1'b0),
                .address_b (1'b1),
                .addressstall_a (1'b0),
                .addressstall_b (1'b0),
                .byteena_a (1'b1),
                .byteena_b (1'b1),
                .clock1 (1'b1),
                .clocken0 (1'b1),
                .clocken1 (1'b1),
                .clocken2 (1'b1),
                .clocken3 (1'b1),
                .data_a ({n{1'b1}}),
                .data_b (1'b1),
                .eccstatus (),
                .q_b (),
                .rden_a (1'b1),
                .rden_b (1'b1),
                .wren_a (1'b0),
                .wren_b (1'b0));
    defparam
        altsyncram_component.address_aclr_a = "NONE",
        altsyncram_component.clock_enable_input_a = "BYPASS",
        altsyncram_component.clock_enable_output_a = "BYPASS",
        altsyncram_component.init_file = INIT_FILE,
        altsyncram_component.intended_device_family = "Cyclone V",
        altsyncram_component.lpm_hint = "ENABLE_RUNTIME_MOD=NO",
        altsyncram_component.lpm_type = "altsyncram",
        altsyncram_component.numwords_a = WORDS,
        altsyncram_component.operation_mode = "ROM",
        altsyncram_component.outdata_aclr_a = "NONE",
        altsyncram_component.outdata_reg_a = "UNREGISTERED",
        altsyncram_component.widthad_a = Mn,
        altsyncram_component.width_a = n,
        altsyncram_component.width_byteena_a = 1;
endmodule