`default_nettype none

// This is mincraft tyshi

module vga_demo(CLOCK_50, SW, KEY, LEDR, PS2_CLK, PS2_DAT, HEX5, HEX4, HEX3, HEX2, HEX1, HEX0,
				VGA_R, VGA_G, VGA_B,
				VGA_HS, VGA_VS, VGA_BLANK_N, VGA_SYNC_N, VGA_CLK);    parameter RESOLUTION = "640x480"; // "640x480" "320x240" "160x120"

    // specify the color depth. This design supports depths of 9, 6, and 3
    parameter COLOR_DEPTH = 9; // 9 6 3

    // specify the number of bits needed for an X (column) pixel coordinate on the VGA display
    parameter nX = (RESOLUTION == "640x480") ? 10 : ((RESOLUTION == "320x240") ? 9 : 8);
    // specify the number of bits needed for a Y (row) pixel coordinate on the VGA display
    parameter nY = (RESOLUTION == "640x480") ? 9 : ((RESOLUTION == "320x240") ? 8 : 7);

    `define COLOR_DEPTH_9
    
    // state names for the FSM that controls drawing of objects
	 parameter A = 2'b00, B = 2'b01, C = 2'b10, D = 2'b11;
	 
	 input wire CLOCK_50;	
	input wire [9:0] SW;
	input wire [3:0] KEY;
	output wire [9:0] LEDR;
    inout wire PS2_CLK, PS2_DAT;
    output wire [6:0] HEX5, HEX4, HEX3, HEX2, HEX1, HEX0;
	output wire [7:0] VGA_R;
	output wire [7:0] VGA_G;
	output wire [7:0] VGA_B;
	output wire VGA_HS;
	output wire VGA_VS;
	output wire VGA_BLANK_N;
	output wire VGA_SYNC_N;
	output wire VGA_CLK;	
	
    // The signals below are used to multiplex the pixels displayed for objects 1 and 2
	wire [nX-1:0] W_x, S_x, MUX_x;    // x coordinate multiplexer
	wire [nY-1:0] W_y, S_y, MUX_y;    // y coordinate multiplexer
	wire [COLOR_DEPTH-1:0] W_color, S_color, MUX_color; // color multiplexer
	wire W_write, S_write, MUX_write; // write control multiplexer
	
	wire world_done;
	
    reg prev_ps2_clk;               // ps2_clk value in the previous clock cycle
    wire negedge_ps2_clk;           // used for PS2 keyboard signals
    wire ps2_rec;                   // set when a PS2 packet has been received
	 
	 reg [32:0] Serial;              // each PS2 serial data packet has 11 bits:
                                    // STOP (1) PARITY d7 d6 d5 d4 d3 d2 d1 d0 START (0)
                                    // 33 total bits are received (scancode/release/scancode
    reg [3:0] Packet;               // used to know when 11 bits have been received
    wire [7:0] scancode;            // used to save the current ps2 scancode
    reg Esc;                        // enable scancode register
    reg step;                       // move an object
	 
	 wire S_done;							// 1 when steve is idle
	 
    reg [1:0] y_Q, Y_D;             // FSM, used to control drawing of objects

	 wire key_up;
	 
    wire Resetn;        // Reset, and synchronized versions of KEYs
    wire PS2_CLK_S, PS2_DAT_S;      // synchronized versions of PS2 signals
	 
    assign Resetn = KEY[0];
	 
	     sync S3 (PS2_CLK, Resetn, CLOCK_50, PS2_CLK_S);
    sync S4 (PS2_DAT, Resetn, CLOCK_50, PS2_DAT_S);

    always @(posedge CLOCK_50)  // record PS2 clock value in previous CLOCK_50 cycle
        prev_ps2_clk <= PS2_CLK_S;

    // check when PS2_CLK has changed from 1 to 0
    assign negedge_ps2_clk = (prev_ps2_clk & !PS2_CLK_S);

    // save PS2 data packet
    always @(posedge CLOCK_50) begin    // specify a 33-bit shift register
        if (Resetn == 0)
            Serial <= 33'b0;
        else if (negedge_ps2_clk) begin
            Serial[31:0] <= Serial[32:1];
            Serial[32] <= PS2_DAT_S;
        end
    end
        
    // 'count' ps2 data bits
    always @(posedge CLOCK_50) begin
        if (!Resetn || Packet == 'd11)
            Packet <= 'b0;
        else if (negedge_ps2_clk) begin
            Packet <= Packet + 'b1;
        end
    end
        
    // used to start an object move. Key press makes scancode/release/scancode, so we check
    // for Serial[30:23] == Serial[8:1]. Key repeat makes scancode/scancode/...
    assign ps2_rec = (Packet == 'd11) && (Serial[30:23] == Serial[8:1]);

    // ps2 scancode is in Serial[8:1]
    regn USC (Serial[8:1], Resetn, Esc, CLOCK_50, scancode);
	 
	 regn UKU (Serial[19:12] == 8'hF0, Resetn, Esc, CLOCK_50, key_up);
		defparam UKU.n = 1;
		
    assign LEDR = {2'b0,scancode};
	 
    // FSM state table
    always @ (*)
        case (y_Q)
            A:  if (!ps2_rec) Y_D = A;
                else Y_D = B;
            B:  Y_D = C;        // enable scancode register
            C:  Y_D = D;        // send step signal to object
            D:  if (S_done == 1'b0) Y_D = D;
                else Y_D = A;
            default: Y_D = A;
        endcase
    // FSM outputs
    always @ (*)
    begin
        // default assignments
        Esc = 1'b0; step = 1'b0;
        case (y_Q)
            A:  ;
            B:  Esc = 1'b1;
            C:  step = 1'b1;  
            D:  ;
        endcase
    end

    // FSM state FFs
    always @(posedge CLOCK_50)
        if (!Resetn)
            y_Q <= A;
        else
            y_Q <= Y_D;
				
	// draws the world, background first then blocks
	world W (Resetn, CLOCK_50, W_x, W_y, W_color, W_write, world_done);
	
	// Steve appears when world_done = 1, then updates on each step
	steve S (Resetn, CLOCK_50, world_done, step, scancode, key_up, S_x, S_y, S_color, S_write, S_done);
	
    // choose x, y, color, and write for one of the two objects
    assign MUX_x = world_done ? S_x : W_x;
    assign MUX_y = world_done ? S_y : W_y;
    assign MUX_color = world_done ? S_color : W_color;
    assign MUX_write = world_done ? S_write : W_write;
	 
	 // display PS2 data
    hex7seg H0 (Serial[4:1], HEX0);
    hex7seg H1 (Serial[8:5], HEX1);
    hex7seg H2 (Serial[15:12], HEX2);
    hex7seg H3 (Serial[19:16], HEX3);
    hex7seg H4 (Serial[26:23], HEX4);
    hex7seg H5 (Serial[30:27], HEX5);

    // connect to VGA controller
    vga_adapter VGA (
			.resetn(Resetn),
			.clock(CLOCK_50),
			.color(MUX_color),
			.x(MUX_x),
			.y(MUX_y),
			.write(MUX_write),
			.VGA_R(VGA_R),
			.VGA_G(VGA_G),
			.VGA_B(VGA_B),
			.VGA_HS(VGA_HS),
			.VGA_VS(VGA_VS),
			.VGA_BLANK_N(VGA_BLANK_N),
			.VGA_SYNC_N(VGA_SYNC_N),
			.VGA_CLK(VGA_CLK));
		defparam VGA.RESOLUTION = RESOLUTION;
		defparam VGA.BACKGROUND_IMAGE = "./MIF/background.mif";  // from display_mif
		
		defparam VGA.COLOR_DEPTH = COLOR_DEPTH;

endmodule

// syncronizer, implemented as two FFs in series
module sync(D, Resetn, Clock, Q);
    input wire D;
    input wire Resetn, Clock;
    output reg Q;

    reg Qi; // internal node

    always @(posedge Clock)
        if (Resetn == 0) begin
            Qi <= 1'b0;
            Q <= 1'b0;
        end
        else begin
            Qi <= D;
            Q <= Qi;
        end
endmodule

// n-bit register with enable
module regn(R, Resetn, E, Clock, Q);
    parameter n = 8;
    input wire [n-1:0] R;
    input wire Resetn, E, Clock;
    output reg [n-1:0] Q;

    always @(posedge Clock)
        if (!Resetn)
            Q <= 0;
        else if (E)
            Q <= R;
endmodule

// n-bit up/down-counter with reset, load, enable, and direction control
module upDn_count (R, Clock, Resetn, L, E, Dir, Q);
    parameter n = 8;
    input wire [n-1:0] R;
    input wire Clock, Resetn, E, L, Dir;
    output reg [n-1:0] Q;

    always @ (posedge Clock)
        if (Resetn == 0)
            Q <= {n{1'b0}};
        else if (L == 1)
            Q <= R;
        else if (E)
            if (Dir)
                Q <= Q + {{n-1{1'b0}},1'b1};
            else
                Q <= Q - {{n-1{1'b0}},1'b1};
endmodule

module hex7seg (hex, display);
    input wire [3:0] hex;
    output reg [6:0] display;

    /*
     *       0  
     *      ---  
     *     |   |
     *    5|   |1
     *     | 6 |
     *      ---  
     *     |   |
     *    4|   |2
     *     |   |
     *      ---  
     *       3  
     */
    always @ (hex)
        case (hex)
            4'h0: display = 7'b1000000;
            4'h1: display = 7'b1111001;
            4'h2: display = 7'b0100100;
            4'h3: display = 7'b0110000;
            4'h4: display = 7'b0011001;
            4'h5: display = 7'b0010010;
            4'h6: display = 7'b0000010;
            4'h7: display = 7'b1111000;
            4'h8: display = 7'b0000000;
            4'h9: display = 7'b0011000;
            4'hA: display = 7'b0001000;
            4'hB: display = 7'b0000011;
            4'hC: display = 7'b1000110;
            4'hD: display = 7'b0100001;
            4'hE: display = 7'b0000110;
            4'hF: display = 7'b0001110;
        endcase
endmodule


// first custom module
module world (Resetn, Clock, VGA_x, VGA_y, VGA_color, VGA_write, done);
    parameter nX = 10, nY = 9, COLOR_DEPTH = 9;
    parameter AIR = 4'd0, GRASS = 4'd1, DIRT = 4'd2, STONE = 4'd3, COBBLE = 4'd4, LOG = 4'd5,
	 PLANKS = 4'd6, LEAVES = 4'd7, IRON = 4'd8, DIAMOND = 4'd9; // block type codes
    parameter A = 3'd0, B = 3'd1, C = 3'd2, D = 3'd3, E = 3'd4, F = 3'd5; // FSM states

    input wire Resetn, Clock;
    output wire [nX-1:0] VGA_x;          // pixel x to write
    output wire [nY-1:0] VGA_y;          // pixel y to write
    output reg [COLOR_DEPTH-1:0] VGA_color; // pixel colour to write
    output wire VGA_write;               // write enable
    output reg done;                     // 1 when the whole world is drawn

    wire [4:0] TC;                       // tile column 0..19 (640 / 32 = 20)
    wire [3:0] TR;                       // tile row 0..14 (480 / 32 = 15)
    wire [4:0] XC, YC;                   // pixel inside the tile, 0..31 each
    reg Ltc, Etc, Ltr, Etr;              // load/enable for the tile counters
    reg Lxc, Exc, Lyc, Eyc;              // load/enable for the pixel counters
    reg write;                           // write this pixel (before the 1-cycle delay)
    reg [3:0] block;                     // block type at tile (TC, TR)
	 reg [3:0] surface;
    reg [2:0] y_Q, Y_D;                  // FSM present/next state
    wire [COLOR_DEPTH-1:0] grass_color, dirt_color, stone_color, cobble_color, log_color, planks_color, leaves_color, iron_color, diamond_color; // texture memory outputs

    // counters (upDn_count from object_pro). Ports: (load value, clock, reset, L, E, up, Q)
    upDn_count UTC (5'd0, Clock, Resetn, Ltc, Etc, 1'b1, TC);  // tile column
        defparam UTC.n = 5;
    upDn_count UTR (4'd0, Clock, Resetn, Ltr, Etr, 1'b1, TR);  // tile row
        defparam UTR.n = 4;
    upDn_count UXC (5'd0, Clock, Resetn, Lxc, Exc, 1'b1, XC);  // pixel column in tile
        defparam UXC.n = 5;
    upDn_count UYC (5'd0, Clock, Resetn, Lyc, Eyc, 1'b1, YC);  // pixel row in tile
        defparam UYC.n = 5;

    // world seed: #1 (and the only one bro pls)
    always @(*)
        if (TR == 4'd10 && (TC >= 5'd0 && TC <= 5'd4)) block = GRASS;
		  else if ((TR >= 4'd5 && TR <= 4'd6) && (TC >= 5'd2 && TC <= 5'd4)) block = LEAVES;
		  else if ((TR >= 4'd7 && TR <= 4'd9) && (TC == 5'd3)) block = LOG;
		  else if ((TR >= 4'd11 && TR <= 4'd12) && (TC >= 5'd0 && TC <= 5'd4)) block = DIRT;
		  else if ((TR >= 4'd13 && TR <= 4'd14) && (TC == 5'd0)) block = STONE;
		  else if ((TR >= 4'd13 && TR <= 4'd14) && (TC >= 5'd3 && TC <= 5'd6)) block = STONE;
		  
		  else if ((TR >= 4'd9 && TR <= 4'd9) && (TC >= 5'd5 && TC <= 5'd6)) block = GRASS;
		  else if ((TR >= 4'd8 && TR <= 4'd8) && (TC >= 5'd7 && TC <= 5'd8)) block = GRASS;
		  else if ((TR >= 4'd9 && TR <= 4'd9) && (TC >= 5'd9 && TC <= 5'd10)) block = GRASS;
		  else if ((TR >= 4'd10 && TR <= 4'd10) && (TC >= 5'd11 && TC <= 5'd11)) block = GRASS;
		  else if ((TR >= 4'd9 && TR <= 4'd9) && (TC >= 5'd12 && TC <= 5'd14)) block = GRASS;
		  else if ((TR >= 4'd10 && TR <= 4'd10) && (TC >= 5'd15 && TC <= 5'd15)) block = GRASS;
		  else if ((TR >= 4'd11 && TR <= 4'd11) && (TC >= 5'd16 && TC <= 5'd17)) block = GRASS;
		  else if ((TR >= 4'd10 && TR <= 4'd10) && (TC >= 5'd18 && TC <= 5'd19)) block = GRASS;
		  
		  else if ((TR >= 4'd7 && TR <= 4'd8) && (TC >= 5'd13 && TC <= 5'd13)) block = LOG;
		  else if ((TR >= 4'd5 && TR <= 4'd6) && (TC >= 5'd12 && TC <= 5'd14)) block = LEAVES;
		  
		  else if ((TR >= 4'd10 && TR <= 4'd11) && (TC >= 5'd5 && TC <= 5'd6)) block = DIRT;
		  else if ((TR >= 4'd9 && TR <= 4'd10) && (TC >= 5'd7 && TC <= 5'd8)) block = DIRT;
		  else if ((TR >= 4'd10 && TR <= 4'd11) && (TC >= 5'd9 && TC <= 5'd10)) block = DIRT;
		  else if ((TR >= 4'd11 && TR <= 4'd12) && (TC >= 5'd11 && TC <= 5'd11)) block = DIRT;
		  else if ((TR >= 4'd10 && TR <= 4'd11) && (TC >= 5'd12 && TC <= 5'd14)) block = DIRT;
		  else if ((TR >= 4'd11 && TR <= 4'd12) && (TC >= 5'd15 && TC <= 5'd15)) block = DIRT;
		  else if ((TR >= 4'd12 && TR <= 4'd13) && (TC >= 5'd16 && TC <= 5'd17)) block = DIRT;
		  else if ((TR >= 4'd11 && TR <= 4'd12) && (TC >= 5'd18 && TC <= 5'd19)) block = DIRT;
		  
		  else if ((TR >= 4'd14 && TR <= 4'd14) && (TC >= 5'd1 && TC <= 5'd1)) block = STONE;
		  else if ((TR >= 4'd12 && TR <= 4'd12) && (TC >= 5'd5 && TC <= 5'd5)) block = STONE;
		  else if ((TR >= 4'd11 && TR <= 4'd11) && (TC >= 5'd7 && TC <= 5'd8)) block = STONE;
		  else if ((TR >= 4'd12 && TR <= 4'd12) && (TC >= 5'd8 && TC <= 5'd10)) block = STONE;
		  else if ((TR >= 4'd13 && TR <= 4'd13) && (TC >= 5'd8 && TC <= 5'd9)) block = STONE;
		  else if ((TR >= 4'd14 && TR <= 4'd14) && (TC >= 5'd7 && TC <= 5'd8)) block = STONE;
		  else if ((TR >= 4'd12 && TR <= 4'd12) && (TC >= 5'd12 && TC <= 5'd13)) block = STONE;
		  else if ((TR >= 4'd13 && TR <= 4'd14) && (TC >= 5'd11 && TC <= 5'd13)) block = STONE;
		  else if ((TR >= 4'd14 && TR <= 4'd14) && (TC >= 5'd14 && TC <= 5'd16)) block = STONE;
		  else if ((TR >= 4'd13 && TR <= 4'd14) && (TC >= 5'd18 && TC <= 5'd19)) block = STONE;
		  
		  else if ((TR >= 4'd13 && TR <= 4'd13) && (TC >= 5'd1 && TC <= 5'd2)) block = IRON;
		  else if ((TR >= 4'd14 && TR <= 4'd14) && (TC >= 5'd2 && TC <= 5'd2)) block = IRON;
		  else if ((TR >= 4'd12 && TR <= 4'd12) && (TC >= 5'd6 && TC <= 5'd7)) block = IRON;
		  else if ((TR >= 4'd13 && TR <= 4'd13) && (TC >= 5'd7 && TC <= 5'd7)) block = IRON;
		  else if ((TR >= 4'd13 && TR <= 4'd13) && (TC >= 5'd14 && TC <= 5'd15)) block = IRON;
		  else if ((TR >= 4'd12 && TR <= 4'd12) && (TC >= 5'd14 && TC <= 5'd14)) block = IRON;
		  
		  else if ((TR >= 4'd13 && TR <= 4'd13) && (TC >= 5'd10 && TC <= 5'd10)) block = DIAMOND;
		  else if ((TR >= 4'd14 && TR <= 4'd14) && (TC >= 5'd9 && TC <= 5'd10)) block = DIAMOND;
		  else if ((TR >= 4'd14 && TR <= 4'd14) && (TC >= 5'd17 && TC <= 5'd17)) block = DIAMOND;
		  
		  
        else block = AIR;
		  
	 always @(*)
		case (TC)
			default: surface = 4'd10;
			5'd7, 5'd8: surface = 4'd8;
			5'd5, 5'd6, 5'd9, 5'd10, 5'd12, 5'd13, 5'd14: surface = 4'd9;
			5'd16, 5'd17: surface = 4'd11;
		endcase

    // FSM state table
    always @(*)
        case (y_Q)
            A:  Y_D = B;                                       // reset
            B:  if (block == AIR) Y_D = E;                     // nothing to draw: next tile
                else Y_D = C;                                  // otherwise draw it
            C:  if (XC != 5'd31) Y_D = C;                      // draw
                else Y_D = D;
            D:  if (YC != 5'd31) Y_D = C;                      // next row of the tile (row as in 32 rows per block)
                else Y_D = E;                                  // block finished
            E:  if (TC == 5'd19 && TR == 4'd14) Y_D = F;       // last tile? then done
                else Y_D = B;                                  // else check the next tile
            F:  Y_D = F;                                       // stay done forever
            default: Y_D = A;
        endcase

    // FSM outputs
    always @(*)
    begin
        Ltc = 1'b0; Etc = 1'b0; Ltr = 1'b0; Etr = 1'b0;        // defaults: counters hold
        Lxc = 1'b0; Exc = 1'b0; Lyc = 1'b0; Eyc = 1'b0;
        write = 1'b0; done = 1'b0;
        case (y_Q)
            A:  begin Ltc = 1'b1; Ltr = 1'b1; Lxc = 1'b1; Lyc = 1'b1; end // all counters = 0
            B:  ;                                              // just look at "block"
            C:  begin Exc = 1'b1; write = 1'b1; end            // write pixel, XC + 1
            D:  begin Lxc = 1'b1; Eyc = 1'b1; end              // XC = 0, YC + 1
            E:  if (TC != 5'd19) Etc = 1'b1;                   // next column...
                else begin Ltc = 1'b1; Etr = 1'b1; end         // ...or column 0, next row
            F:  done = 1'b1;                                   // world finished
        endcase
    end

    always @(posedge Clock)              // FSM state flip-flops
        if (!Resetn)
            y_Q <= A;
        else
            y_Q <= Y_D;

    // texture memories (object_mem from object_pro). Address {YC,XC} = YC*32 + XC works
    // because 32 is a power of 2. Each MIF must be DEPTH=1024, WIDTH=9.
    object_mem GR ({YC, XC}, Clock, grass_color);
        defparam GR.n = COLOR_DEPTH;
        defparam GR.Mn = 10;                                   // 1024 entries = 2^10 = 32 x 32
        defparam GR.INIT_FILE = "./MIF/grass.mif";
    object_mem DI ({YC, XC}, Clock, dirt_color);
        defparam DI.n = COLOR_DEPTH;
        defparam DI.Mn = 10;
        defparam DI.INIT_FILE = "./MIF/dirt.mif";
    object_mem ST ({YC, XC}, Clock, stone_color);
        defparam ST.n = COLOR_DEPTH;
        defparam ST.Mn = 10;
        defparam ST.INIT_FILE = "./MIF/stone.mif";
    object_mem CB ({YC, XC}, Clock, cobble_color);
        defparam CB.n = COLOR_DEPTH;
        defparam CB.Mn = 10;                                  
        defparam CB.INIT_FILE = "./MIF/cobblestone.mif";
    object_mem LG ({YC, XC}, Clock, log_color);
        defparam LG.n = COLOR_DEPTH;
        defparam LG.Mn = 10;
        defparam LG.INIT_FILE = "./MIF/log.mif";
    object_mem PL ({YC, XC}, Clock, planks_color);
        defparam PL.n = COLOR_DEPTH;
        defparam PL.Mn = 10;
        defparam PL.INIT_FILE = "./MIF/planks.mif";
	 object_mem LV ({YC, XC}, Clock, leaves_color);
        defparam LV.n = COLOR_DEPTH;
        defparam LV.Mn = 10;                                 
        defparam LV.INIT_FILE = "./MIF/leaves.mif";
    object_mem DM ({YC, XC}, Clock, diamond_color);
        defparam DM.n = COLOR_DEPTH;
        defparam DM.Mn = 10;
        defparam DM.INIT_FILE = "./MIF/diamond-ore.mif";
    object_mem FE ({YC, XC}, Clock, iron_color);
        defparam FE.n = COLOR_DEPTH;
        defparam FE.Mn = 10;
        defparam FE.INIT_FILE = "./MIF/iron-ore.mif";

    // From object_pro's U7/U8/U9 1 clock delay
    regn UX ({TC, XC}, Resetn, 1'b1, Clock, VGA_x);
        defparam UX.n = nX;
    regn UY ({TR, YC}, Resetn, 1'b1, Clock, VGA_y);
        defparam UY.n = nY;
    regn UW (write, Resetn, 1'b1, Clock, VGA_write);
        defparam UW.n = 1;

    always @(*)
        case (block)
            GRASS: VGA_color = grass_color;
            DIRT: VGA_color = dirt_color;
				STONE: VGA_color = stone_color;
				COBBLE: VGA_color = cobble_color;
				LOG: VGA_color = log_color;
				PLANKS: VGA_color = planks_color;
				LEAVES: VGA_color = leaves_color;
				IRON: VGA_color = iron_color;
				DIAMOND: VGA_color = diamond_color;
            default: VGA_color = stone_color;
        endcase

endmodule

module steve (Resetn, Clock, go, step, scancode, key_up,
              VGA_x, VGA_y, VGA_color, VGA_write, done);
    parameter nX = 10, nY = 9, COLOR_DEPTH = 9;
    parameter X_INIT = 10'd320;          // starting x (left edge of Steve)
    parameter Y_POS  = 9'd224;           // top edge: 9*32 - 64, so his feet touch the grass
    parameter STEP   = 10'd8;            // pixels moved per key repeat
    parameter SKY = 9'h1BF;
    parameter TRANSPARENT = 9'h000;
	 
    parameter KEY_A = 8'h1C, KEY_D = 8'h23, KEY_F = 8'h2B; // PS/2 scancodes
    parameter FRONT = 3'd0, SIDE = 3'd1, WALK1 = 3'd2, WALK2 = 3'd3, HIT = 3'd4; // poses
    parameter A = 3'd0, B = 3'd1, C = 3'd2, D = 3'd3, E = 3'd4, F = 3'd5, G = 3'd6; // states

    input wire Resetn, Clock;
    input wire go;                       // world finished: OK to draw Steve
    input wire step;                     // a key event arrived
    input wire [7:0] scancode;           // which key
    input wire key_up;                   // 1 = it was a release
    output wire [nX-1:0] VGA_x;
    output wire [nY-1:0] VGA_y;
    output wire [COLOR_DEPTH-1:0] VGA_color;
    output wire VGA_write;
    output reg done;                     // 1 = idle, ready for the next key

    reg [nX-1:0] X;                      // Steve's left edge
    reg [2:0] pose;                      // which of the 5 sprites to show
    reg face_left;                       // 1 = mirror the sprite horizontally
    wire [4:0] XC;                       // sprite column 0..31
    wire [5:0] YC;                       // sprite row 0..63
    wire [4:0] XM;                       // XC, mirrored when facing left
    reg Lxc, Exc, Lyc, Eyc;              // sprite counter controls
    reg write, erase;                    // write a pixel / it is an erase pixel
    reg init, update;                    // set start position / apply the key
    reg [2:0] y_Q, Y_D;                  // FSM present/next state
    wire [COLOR_DEPTH-1:0] front_c, side_c, walk1_c, walk2_c, hit_c; // sprite memory outputs
    reg [COLOR_DEPTH-1:0] obj_color;     // output of the currently selected sprite
    wire erase_d;                        // erase, delayed one clock

    upDn_count UXC (5'd0, Clock, Resetn, Lxc, Exc, 1'b1, XC); // sprite column counter
        defparam UXC.n = 5;
    upDn_count UYC (6'd0, Clock, Resetn, Lyc, Eyc, 1'b1, YC); // sprite row counter
        defparam UYC.n = 6;

    // position and pose register: changes only in state A (init) or E (update)
    always @(posedge Clock)
        if (!Resetn || init) begin
            X <= X_INIT;                 // start position
            pose <= FRONT;               // facing the player
            face_left <= 1'b0;
        end
        else if (update) begin
            if (key_up)                  // key let go: stand still, sideways
                pose <= SIDE;
            else if (scancode == KEY_A) begin
                face_left <= 1'b1;                              // look left
                pose <= (pose == WALK1) ? WALK2 : WALK1;        // alternate walk frames
                if (X >= STEP) X <= X - STEP;                   // move left, stop at edge
            end
            else if (scancode == KEY_D) begin
                face_left <= 1'b0;                              // look right
                pose <= (pose == WALK1) ? WALK2 : WALK1;
                if (X <= 10'd640 - 10'd32 - STEP) X <= X + STEP; // move right, stop at edge
            end
            else if (scancode == KEY_F)
                pose <= HIT;                                    // swing
        end

    // FSM state table (object_pro's object with a start state added)
    always @(*)
        case (y_Q)
            A:  if (go) Y_D = F;                // world done: draw Steve for the first time
                else Y_D = A;
            B:  if (step) Y_D = C;              // key event: start an update
                else Y_D = B;
            C:  if (XC != 5'd31) Y_D = C;       // erase one row
                else Y_D = D;
            D:  if (YC != 6'd63) Y_D = C;       // next row to erase
                else Y_D = E;
            E:  Y_D = F;                        // apply the key (move / change pose)
            F:  if (XC != 5'd31) Y_D = F;       // draw one row
                else Y_D = G;
            G:  if (YC != 6'd63) Y_D = F;       // next row to draw
                else Y_D = B;                   // finished: back to idle
            default: Y_D = A;
        endcase

    // FSM outputs
    always @(*)
    begin
        Lxc = 1'b0; Exc = 1'b0; Lyc = 1'b0; Eyc = 1'b0;
        write = 1'b0; erase = 1'b0; init = 1'b0; update = 1'b0; done = 1'b0;
        case (y_Q)
            A:  begin init = 1'b1; Lxc = 1'b1; Lyc = 1'b1; end            // reset everything
            B:  begin Lxc = 1'b1; Lyc = 1'b1; done = 1'b1; end            // idle, counters = 0
            C:  begin Exc = 1'b1; write = 1'b1; erase = 1'b1; end         // erase pixel
            D:  begin Lxc = 1'b1; Eyc = 1'b1; erase = 1'b1; end           // next row
            E:  update = 1'b1;                                            // move/pose
            F:  begin Exc = 1'b1; write = 1'b1; end                       // draw pixel
            G:  begin Lxc = 1'b1; Eyc = 1'b1; end                         // next row
        endcase
    end

    always @(posedge Clock)              // FSM state flip-flops
        if (!Resetn)
            y_Q <= A;
        else
            y_Q <= Y_D;

    assign XM = face_left ? ~XC : XC;    // ~XC = 31 - XC: read the row backwards = mirror

    // 5 sprite memories. Address {YC,XM} = YC*32 + XM. Each MIF: DEPTH=2048, WIDTH=9,
    // 32 pixels wide x 64 tall, stored row by row.
    object_mem M0 ({YC, XM}, Clock, front_c);
        defparam M0.n = COLOR_DEPTH;
        defparam M0.Mn = 11;                                   // 2048 entries = 2^11 = 64 x 32
        defparam M0.INIT_FILE = "./MIF/steve_front.mif";
    object_mem M1 ({YC, XM}, Clock, side_c);
        defparam M1.n = COLOR_DEPTH;
        defparam M1.Mn = 11;
        defparam M1.INIT_FILE = "./MIF/steve_side.mif";
    object_mem M2 ({YC, XM}, Clock, walk1_c);
        defparam M2.n = COLOR_DEPTH;
        defparam M2.Mn = 11;
        defparam M2.INIT_FILE = "./MIF/steve_walk_1.mif";
    object_mem M3 ({YC, XM}, Clock, walk2_c);
        defparam M3.n = COLOR_DEPTH;
        defparam M3.Mn = 11;
        defparam M3.INIT_FILE = "./MIF/steve_walk_2.mif";
    object_mem M4 ({YC, XM}, Clock, hit_c);
        defparam M4.n = COLOR_DEPTH;
        defparam M4.Mn = 11;
        defparam M4.INIT_FILE = "./MIF/steve_handout.mif";

    always @(*)                          // pick the sprite for the current pose
        case (pose)
            FRONT:   obj_color = front_c;
            SIDE:    obj_color = side_c;
            WALK1:   obj_color = walk1_c;
            WALK2:   obj_color = walk2_c;
            default: obj_color = hit_c;
        endcase

    // delay x, y, write and erase by one clock to line up with the memory output
    regn UX (X + XC, Resetn, 1'b1, Clock, VGA_x);
        defparam UX.n = nX;
    regn UY (Y_POS + YC, Resetn, 1'b1, Clock, VGA_y);
        defparam UY.n = nY;
    wire write_d;                        // write, delayed one clock
    regn UW (write, Resetn, 1'b1, Clock, write_d);
        defparam UW.n = 1;
    regn UE (erase, Resetn, 1'b1, Clock, erase_d);
        defparam UE.n = 1;

    assign VGA_color = erase_d ? SKY : obj_color;              // erase paints sky colour
    // only touch pixels that are part of Steve (erase uses the OLD pose, since update
    // happens after the erase, so this erases exactly the old outline)
    assign VGA_write = write_d & (obj_color != TRANSPARENT);

endmodule