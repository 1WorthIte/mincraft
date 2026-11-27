`default_nettype none

module world (Resetn, Clock, redraw_req, redraw_col, redraw_row, redraw_done, VGA_x, VGA_y, VGA_color, VGA_write, done, TC, TR, block);
    parameter nX = 10, nY = 9, COLOR_DEPTH = 9;
    parameter AIR = 4'd0, GRASS = 4'd1, DIRT = 4'd2, STONE = 4'd3, COBBLE = 4'd4, LOG = 4'd5,
	 PLANKS = 4'd6, LEAVES = 4'd7, IRON = 4'd8, DIAMOND = 4'd9; // block type codes
    parameter A = 3'd0, B = 3'd1, C = 3'd2, D = 3'd3, E = 3'd4, F = 3'd5, G = 3'd6; // FSM states

    input wire Resetn, Clock;
    output wire [nX-1:0] VGA_x;          // pixel x to write
    output wire [nY-1:0] VGA_y;          // pixel y to write
    output reg [COLOR_DEPTH-1:0] VGA_color; // pixel colour to write
    output wire VGA_write;               // write enable
    output reg done;                     // 1 when the whole world is drawn
	 
	 input wire redraw_req;
	 input wire [4:0] redraw_col;
	 input wire [3:0] redraw_row;
	 output wire redraw_done;

    output wire [4:0] TC;                       // tile column 0..19 (640 / 32 = 20)
    output wire [3:0] TR;                       // tile row 0..14 (480 / 32 = 15)
    wire [4:0] XC, YC;                   // pixel inside the tile, 0..31 each
    reg Ltc, Etc, Ltr, Etr;              // load/enable for the tile counters
    reg Lxc, Exc, Lyc, Eyc;              // load/enable for the pixel counters
    reg write;                           // write this pixel (before the 1-cycle delay)
    // output wire [3:0] block;                     // block type at tile (TC, TR)
	 // reg [3:0] surface;
	 input wire [3:0] block; // response from map
	 
    reg [2:0] y_Q, Y_D;                  // FSM present/next state
    wire [COLOR_DEPTH-1:0] grass_color, dirt_color, stone_color, cobble_color, log_color, planks_color, leaves_color, iron_color, diamond_color; // texture memory outputs

    wire [4:0] tc_load = tile_mode ? saved_col : 5'd0;
	 wire [3:0] tr_load = tile_mode ? saved_row : 4'd0;
	 
	 // counters (upDn_count from object_pro). Ports: (load value, clock, reset, L, E, up, Q)
    upDn_count UTC (tc_load, Clock, Resetn, Ltc, Etc, 1'b1, TC);  // tile column
        defparam UTC.n = 5;
    upDn_count UTR (tr_load, Clock, Resetn, Ltr, Etr, 1'b1, TR);  // tile row
        defparam UTR.n = 4;
    upDn_count UXC (5'd0, Clock, Resetn, Lxc, Exc, 1'b1, XC);  // pixel column in tile
        defparam UXC.n = 5;
    upDn_count UYC (5'd0, Clock, Resetn, Lyc, Eyc, 1'b1, YC);  // pixel row in tile
        defparam UYC.n = 5;
		  
	 reg tile_mode;
	 reg [4:0] saved_col;
	 reg [3:0] saved_row;
	 
	 always @(posedge Clock) begin
		if (!Resetn) begin
			tile_mode <= 1'b0;
			saved_col <= 5'd0;
			saved_row <= 4'd0;
		end
		else if (y_Q == F && redraw_req) begin
			tile_mode <= 1'b1;
			saved_col <= redraw_col;
			saved_row <= redraw_row;
		end
		else if (y_Q == E && tile_mode) begin
			tile_mode <= 1'b0;
		end
	 end
	 
	 assign redraw_done = (y_Q == E) && tile_mode;

    // FSM state table
    always @(*)
        case (y_Q)
            A:  Y_D = B;                                       // reset
            B:  Y_D = C;                                       // draw every tile including AIR after reset  
            C:  if (XC != 5'd31) Y_D = C;                      // draw
                else Y_D = D;
            D:  if (YC != 5'd31) Y_D = C;                      // next row of the tile (row as in 32 rows per block)
                else Y_D = E;                                  // block finished
            E:  if (tile_mode) Y_D = F;       // last tile? then done
                else if (TC == 5'd19 && TR == 4'd14) Y_D = F;
					 else Y_D = B;                                  // else check the next tile
            F:  if (redraw_req) Y_D = G;
					 else Y_D = F;                                       // stay done forever
				G:  Y_D = B;
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
				G: begin Ltc = 1'b1; Ltr = 1'b1; Lxc = 1'b1; Lyc = 1'b1; end
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
				AIR: VGA_color = 9'h1BF;
            default: VGA_color = stone_color;
        endcase

endmodule

`default_nettype wire
