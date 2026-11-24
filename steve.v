`default_nettype none

module steve (Resetn, Clock, go, step, scancode, key_up, VGA_x, VGA_y, VGA_color, VGA_write, done,
				  side_col, left_col, right_col,
				  top_row, mid_row, bottom_row, below_row, above_row,
				  s_top, s_mid, s_bot, d_left, d_right, u_left, u_right,
				  player_x, player_y, force_draw, hold_steve);
				  
    parameter nX = 10, nY = 9, COLOR_DEPTH = 9;
    parameter X_INIT = 10'd320;          // starting x (left edge of Steve)
    parameter Y_INIT  = 9'd224;           // top edge: 9*32 - 64, so his feet touch the grass
    parameter STEP   = 10'd8;            // pixels moved per key repeat
    parameter SKY = 9'h1BF;
    parameter TRANSPARENT = 9'h000;
	 
	 parameter JUMP = 40;
	 parameter VSTEP = 8;
	 parameter HANG = 4;
	 parameter P = 21;
	 
    parameter KEY_A = 8'h1C, KEY_D = 8'h23, KEY_F = 8'h2B, KEY_SPACE = 8'h29; // PS/2 scancodes
    parameter FRONT = 3'd0, SIDE = 3'd1, WALK1 = 3'd2, WALK2 = 3'd3, HIT = 3'd4; // poses
    parameter A = 3'd0, B = 3'd1, C = 3'd2, D = 3'd3, E = 3'd4, F = 3'd5, G = 3'd6; // states

	 output wire [4:0] side_col, left_col, right_col;
	 output wire [3:0] top_row, mid_row, bottom_row, below_row, above_row;
	 output wire [9:0] player_x;
	 output wire [8:0] player_y;
	 input wire [3:0] s_top, s_mid, s_bot, d_left, d_right, u_left, u_right;
	 
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
	 
	 input wire force_draw;
	 input wire hold_steve;

    reg [nX-1:0] X;                      // Steve's left edge
    reg [2:0] pose;                      // which of the 5 sprites to show
    reg face_left;                       // 1 = mirror the sprite horizontally
    wire [4:0] XC;                       // sprite column 0..31
    wire [5:0] YC;                       // sprite row 0..63
    wire [4:0] XM;                       // XC, mirrored when facing left
    reg Lxc, Exc, Lyc, Eyc;              // sprite counter controls
    reg tick;
	 reg write, erase;                    // write a pixel / it is an erase pixel
    reg init, update;                    // set start position / apply the key
    reg [2:0] y_Q, Y_D;                  // FSM present/next state
    wire [COLOR_DEPTH-1:0] front_c, side_c, walk1_c, walk2_c, hit_c; // sprite memory outputs
    reg [COLOR_DEPTH-1:0] obj_color;     // output of the currently selected sprite
    wire erase_d;                        // erase, delayed one clock
	 
	 // ADD OUTLINE AROUND STEVE:
	 
		wire outline;
		wire outline_d;
		
		assign outline = (XC == 5'd0) ||   // left edge
							  (XC == 5'd31) ||  // right edge
							  (YC == 6'd0) ||   // top edge
							  (YC == 6'd63);    // bottom edge
							  
	 // selection:
	 
		assign player_x = X;
		assign player_y = Y;
	 
	 reg [nY-1 : 0] Y;
	 reg [5:0] rise;
	 reg [3:0] hang;
	 reg [P-1 : 0] pcount;
	 reg pend;
	 reg phys;
	 
	 // pixel positions around steve
	 wire [9:0] XL = X - STEP;
	 wire [9:0] XR = X + 10'd31 + STEP;
	 wire [9:0] XE = X + 10'd31;
	 wire [8:0] YMID = Y + 9'd32;
	 wire [8:0] YFEET = Y + 9'd63;
	 wire [8:0] YBELOW = Y + 9'd64;
	 wire [8:0] YABOVE = Y - VSTEP;
	 
	 assign side_col = (scancode == KEY_A) ? XL[9:5] : XR[9:5];
	 assign left_col = X[9:5];
	 assign right_col = XE [9:5];
	 assign top_row = Y[8:5];
	 assign mid_row = YMID[8:5];
	 assign bottom_row = YFEET[8:5];
	 assign below_row = YBELOW[8:5];
	 assign above_row = YABOVE[8:5];
	 
	 wire side_blocked = (s_top != 4'd0) | (s_mid != 4'd0) | (s_bot != 4'd0);
	 wire on_ground = (d_left != 4'd0) | (d_right != 4'd0);
	 wire head_blocked = (u_left != 4'd0) | (u_right != 4'd0) | (Y < (9'd160 + VSTEP));
	 wire airborne = (rise != 0) | (hang != 0) | !on_ground;
	 
	 always @ (posedge Clock)
	 
		if (!Resetn) pcount <= 0;
		else pcount <= pcount + 1'b1;	
	 wire phys_tick = (pcount == 0);
	 
	 always @ (posedge Clock) 
		if (!Resetn) pend <= 1'b0;
		else if (phys_tick) pend <= 1'b1;
		else if (update && phys) pend <= 1'b0;
		
	 always @(posedge Clock) 
		if (!Resetn) phys <= 1'b0;
		else if (y_Q == B) phys <= ~step;
	 
	 parameter half_sec = 25000000;

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
				Y <= Y_INIT;
				rise <= 6'd0;
				hang <= 4'd0;
        end
		  else if (update && phys) begin
				if (rise != 0) begin
					if (head_blocked) rise <= 6'd0; // bonked his head
					else begin
						Y <= Y - VSTEP;
						rise <= rise - VSTEP;
						if (rise == VSTEP) hang <= HANG; // reached the top, float
					end
				end
				else if (hang != 0) hang <= hang - 1'b1;
				else if (!on_ground) Y <= Y + VSTEP; // gravity
		  end
		  
        else if (update) begin
            if (key_up)                  // key let go: stand still, sideways
                pose <= FRONT;
            else if (scancode == KEY_A) begin
                face_left <= 1'b1;                              // look left
                pose <= (pose == WALK1) ? WALK2 : WALK1;        // alternate walk frames
                if (X >= STEP && !side_blocked) begin
						X <= X - STEP;                   // move left, stop at edge
	   			 end
            end
            else if (scancode == KEY_D) begin
                face_left <= 1'b0;                              // look right
                pose <= (pose == WALK1) ? WALK2 : WALK1;
                if (X <= 10'd640 - 10'd32 - STEP  && !side_blocked) begin
						X <= X + STEP; 	
					 end 					              // move right, stop at edge
            end
				else if (scancode == KEY_SPACE) begin
					 if (on_ground && rise == 0 && hang == 0) rise <= JUMP;
				end
            else if (scancode == KEY_F)
                pose <= HIT;                                    // swing
        end
		  
		  

    // FSM state table (object_pro's object with a start state added)
    always @(*)
        case (y_Q)
            A:  if (go) Y_D = F;                // world done: draw Steve for the first time
                else Y_D = A;
            B:  if (force_draw) Y_D = F;              // key event: start an update
				    else if (hold_steve) Y_D = B;
					 else if (step) Y_D = C;
					 else if (pend && airborne) Y_D = C;
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
    regn UY (Y + YC, Resetn, 1'b1, Clock, VGA_y);
        defparam UY.n = nY;
    wire write_d;                        // write, delayed one clock
    regn UW (write, Resetn, 1'b1, Clock, write_d);
        defparam UW.n = 1;
    regn UE (erase, Resetn, 1'b1, Clock, erase_d);
        defparam UE.n = 1;
	 regn UO (outline, Resetn, 1'b1, Clock, outline_d);
		  defparam UO.n = 1;

	 // erase paints sky colour
    // only touch pixels that are part of Steve (erase uses the OLD pose, since update
    // happens after the erase, so this erases exactly the old outline)
	 
    assign VGA_color = erase_d ? SKY :      // erasing old pos steve
							  outline_d ? 9'h000:  // drawing outline pixel
							  obj_color;           // original sprite color otherwise
	 
	 
    assign VGA_write = write_d && (outline_d || (obj_color != TRANSPARENT));

endmodule

`default_nettype wire
