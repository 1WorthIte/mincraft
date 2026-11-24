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
	
	
	wire [9:0] UI_x;
	wire [8:0] UI_y;
	wire [8:0] UI_color;
	wire UI_write;
	wire UI_busy;
	
	wire UI_start;
	wire refresh_busy;
	wire steve_force_redraw;
	
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
	 
	 reg [9:0] rendered_x;
	 reg [8:0] rendered_y;
	 reg [3:0] rendered_index;
	 
	 wire position_changed = (steve_x != rendered_x) || (steve_y != rendered_y);
	 
	 wire selection_changed = (SW[3:0] != rendered_index);
	 
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
    assign ps2_rec = (Packet == 'd11);
	 
	 wire [7:0] received_byte;
	 assign received_byte = Serial[30:23];
	 
	 reg release_pending;
	 reg extended_pending;
	 
	 reg left_down;
	 reg right_down;
	 reg hit_down;
	 reg jump_down;
	 
	 always@(posedge CLOCK_50) begin
		if (!Resetn) begin
			release_pending <= 1'b0;
			extended_pending <= 1'b0;
			
			left_down <= 1'b0;
			right_down <= 1'b0;
			hit_down <= 1'b0;
			jump_down <= 1'b0;
		end
		else if (ps2_rec) begin
			if (received_byte == 8'hE0) begin
				extended_pending <= 1'b1;
			end
			
			else if (received_byte == 8'hF0) begin
				release_pending <= 1'b1;
			end
			else begin
				if (!extended_pending) begin
					case (received_byte)
						8'h1C: left_down <= !release_pending;
						8'h23: right_down <= !release_pending;
						8'h2B: hit_down <= !release_pending;
						8'h29: jump_down <= !release_pending;
						default: ;
					endcase
				end
				release_pending <= 1'b0;
				extended_pending <= 1'b0;
			end
		end
	 end
	 
	 // choose which action to request
	 
	 reg [7:0] wanted_code;
	 
	 // F takes priority, holding A and D together stops horiz motion
	 always @(*) begin
	   if (jump_down) wanted_code = 8'h29;
		else if (hit_down) wanted_code = 8'h2B;
		else if (left_down && !right_down) wanted_code = 8'h1C;
		else if (right_down && !left_down) wanted_code = 8'h23;
		else wanted_code = 8'h00;
	 end
	 
	 // command registers:
	 reg [21:0] repeat_count;
	 reg [7:0] last_code;
	 reg [7:0] command_code;
	 reg command_release;
	 
	 wire walking;
	 wire jumping;
	 wire request_update;
	 
	 assign walking = (wanted_code == 8'h1C) || (wanted_code == 8'h23);
	 assign jumping = (wanted_code == 8'h29);
	 
	 assign request_update = (wanted_code != last_code) || ((walking || jumping) && (repeat_count == 22'd0));
	 
	 always @(posedge CLOCK_50) begin
		if (!Resetn) begin
			repeat_count <= 22'd0;
			last_code <= 8'h00;
			command_code <= 8'h00;
			command_release <= 1'b0;
		end
		else begin
			if (repeat_count != 22'd0) repeat_count <= repeat_count - 1'b1;
			if ((y_Q == A) && S_done && !refresh_busy && request_update) begin
				command_code <= wanted_code;
				command_release <= (wanted_code == 8'h00);
				
				last_code <= wanted_code;
				repeat_count <= 22'd2_499_999;
			end
		end
	 end

    // ps2 scancode is in Serial[8:1]
    regn USC (command_code, Resetn, Esc, CLOCK_50, scancode);
	 
	 regn UKU (command_release, Resetn, Esc, CLOCK_50, key_up);
		defparam UKU.n = 1;
		
    // assign LEDR = SW[9] ? {target_valid, selected_col, selected_row} : {2'b0, scancode}; // temporary SW testing
	 assign LEDR = {refresh_state, UI_busy, S_done, world_done, tile_redraw_done, refresh_busy, refresh_pending};
	 
    // FSM state table
    always @ (*)
        case (y_Q)
			A:  if (S_done && !refresh_busy && request_update) Y_D = B;
                else Y_D = A;
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
				
	// shared mutable block map
	
		wire map_ready;
		wire [4:0] world_col, side_col, left_col, right_col;
		wire [3:0] world_row, top_row, mid_row, bottom_row, below_row, above_row;
		wire [3:0] world_block, s_top, s_mid, s_bot, d_left, d_right, u_left, u_right;
		wire [3:0] selected_block;
		wire selected_valid;
		wire [3:0] selected_above_block, selected_below_block;
		wire [3:0] selected_left_block, selected_right_block;
		
		wire selected_has_neighbor;
		wire map_write_enable;
		
		wire [4:0] map_write_col;
		wire [3:0] map_write_row, map_write_block;
		wire [4:0] selected_col;
		wire [3:0] selected_row;
		
		wire [9:0] steve_x;
		wire [8:0] steve_y;
		wire target_valid;
		
		wire edit_done;
		reg world_dirty;
		
		wire [3:0] held_tool_strength = 4'd1; // hand
		wire [3:0] held_place_block = 4'd3; // stone
		
		block_interaction INTERACTION (
		
			.clk(CLOCK_50),
			.resetn(Resetn),
			.key_break(KEY[3]),
			.key_place(KEY[2]),
			
			.enable(map_ready),
			.target_valid(target_valid && selected_valid),
			.target_col(selected_col),
			.target_row(selected_row),
			.target_block(selected_block),
			.has_neighbor(selected_has_neighbor),
			
			.tool_strength(held_tool_strength),
			.place_block(held_place_block),
			
			.write_enable(map_write_enable),
			.write_col(map_write_col),
			.write_row(map_write_row),
			.write_block(map_write_block),
			.edit_done(edit_done)
		
		);
		
	
		block_selector SELECTOR (
										
											.player_x(steve_x),
											.player_y(steve_y),
											.index(SW[3:0]), // temporary, keyboard not integrated
											
											.target_col(selected_col),
											.target_row(selected_row),
											.target_valid(target_valid)
											
										);
	
	assign selected_has_neighbor = (selected_above_block != 4'd0) || (selected_below_block != 4'd0) || (selected_left_block != 4'd0) || (selected_right_block != 4'd0);
	
	block_map MAP (
		
		.Clock(CLOCK_50), .Resetn(Resetn), .ready(map_ready),
		.write_enable(map_write_enable), .write_col(map_write_col),
		.write_row(map_write_row), .write_block(map_write_block),
		.read0_col(world_col), .read0_row(world_row), .read0_block(world_block), 
		.read1_col(side_col), .read1_row(top_row), .read1_block(s_top), 
		.read2_col(side_col), .read2_row(mid_row), .read2_block(s_mid), 
		.read3_col(side_col), .read3_row(bottom_row), .read3_block(s_bot), 
		.read4_col(left_col), .read4_row(below_row), .read4_block(d_left), 
		.read5_col(right_col), .read5_row(below_row), .read5_block(d_right), 
		.read6_col(left_col), .read6_row(above_row), .read6_block(u_left), 
		.read7_col(right_col), .read7_row(above_row), .read7_block(u_right), 
		.read8_col(selected_col), .read8_row(selected_row), .read8_block(selected_block),
		.read8_valid(selected_valid),
		.read8_above_block(selected_above_block), .read8_below_block(selected_below_block),
		.read8_left_block(selected_left_block), .read8_right_block(selected_right_block)
		
	);
	
	wire tile_redraw_req;
	wire [4:0] tile_redraw_col;
	wire [3:0] tile_redraw_row;
	wire tile_redraw_done;
	
	world W (
	
		.Resetn(Resetn & map_ready), .Clock(CLOCK_50), .redraw_req(tile_redraw_req), .redraw_col(tile_redraw_col), .redraw_row(tile_redraw_row), .redraw_done(tile_redraw_done), 
		.VGA_x(W_x), .VGA_y(W_y), .VGA_color(W_color), .VGA_write(W_write),
		.done(world_done), .TC(world_col), .TR(world_row), .block(world_block)
	
	);
	
	steve S (
		
		.Resetn(Resetn), .Clock(CLOCK_50), .go(world_done),
		.step(step), .scancode(scancode), .key_up(key_up),
		.VGA_x(S_x), .VGA_y(S_y), .VGA_color(S_color), .VGA_write(S_write), .done(S_done),
		.side_col(side_col), .left_col(left_col), .right_col(right_col),
		.top_row(top_row), .mid_row(mid_row), .bottom_row(bottom_row),
		.below_row(below_row), .above_row(above_row), 
		.s_top(s_top), .s_mid(s_mid), .s_bot(s_bot),
		.d_left(d_left), .d_right(d_right), .u_left(u_left), .u_right(u_right),
		.player_x(steve_x), .player_y(steve_y),
		.force_draw(steve_force_redraw), .hold_steve(refresh_busy)
		
	);
	
	selection_ui UI (
	
		.Clock(CLOCK_50),
		.Resetn(Resetn),
		.start(UI_start),
		
		.player_x(frame_x),
		.player_y(frame_y),
		.selected_index(frame_selection),
		
		.busy(UI_busy),
		
		.VGA_x(UI_x),
		.VGA_y(UI_y),
		.VGA_color(UI_color),
		.VGA_write(UI_write)
	
	);
	
	// Refresh the old outline tiles, then paint the new UI and Steve over them.
	localparam R_IDLE = 4'd0, R_TILE = 4'd1, R_WAIT_TILE = 4'd2,
	           R_NEXT_TILE = 4'd3, R_UI = 4'd4, R_WAIT_UI = 4'd5,
	           R_STEVE = 4'd6, R_WAIT_STEVE_BUSY = 4'd7,
	           R_WAIT_STEVE_DONE = 4'd8;
	reg [3:0] refresh_state;
	reg [1:0] restore_c, restore_r;
	reg [9:0] drawn_x, frame_x;
	reg [8:0] drawn_y, frame_y;
	reg [3:0] drawn_selection, frame_selection;
	reg drawn_valid, sprite_dirty;

	wire refresh_pending = world_done && S_done && (y_Q == A) &&
	                       (!drawn_valid || sprite_dirty || world_dirty ||
	                        steve_x != drawn_x || steve_y != drawn_y ||
	                        SW[3:0] != drawn_selection);
	assign refresh_busy = (refresh_state != R_IDLE) || refresh_pending;

	wire signed [6:0] restore_col = $signed({2'b00, drawn_x[9:5]}) +
	                                $signed({5'b0, restore_c}) - 7'sd1;
	wire signed [6:0] restore_row = $signed({3'b000, drawn_y[8:5]}) +
	                                $signed({5'b0, restore_r}) - 7'sd1;
	wire restore_valid = (restore_col >= 0) && (restore_col < 20) &&
	                     (restore_row >= 5) && (restore_row < 15);
	assign tile_redraw_col = restore_col[4:0];
	assign tile_redraw_row = restore_row[3:0];
	assign tile_redraw_req = (refresh_state == R_TILE) && restore_valid;
	assign UI_start = (refresh_state == R_UI);
	assign steve_force_redraw = (refresh_state == R_STEVE);

	always @(posedge CLOCK_50) begin
		if (!Resetn) begin
			refresh_state <= R_IDLE;
			restore_c <= 2'd0;
			restore_r <= 2'd0;
			drawn_x <= 10'd0;
			drawn_y <= 9'd0;
			drawn_selection <= 4'd0;
			frame_x <= 10'd0;
			frame_y <= 9'd0;
			frame_selection <= 4'd0;
			drawn_valid <= 1'b0;
			sprite_dirty <= 1'b0;
			world_dirty <= 1'b0;
		end
		else begin
			if (refresh_state == R_IDLE && !S_done)
				sprite_dirty <= 1'b1;
			if (edit_done)
				world_dirty <= 1'b1;
			case (refresh_state)
				R_IDLE: if (refresh_pending) begin
					frame_x <= steve_x;
					frame_y <= steve_y;
					frame_selection <= SW[3:0];
					restore_c <= 2'd0;
					restore_r <= 2'd0;
					refresh_state <= drawn_valid ? R_TILE : R_UI;
				end
				R_TILE: refresh_state <= restore_valid ? R_WAIT_TILE : R_NEXT_TILE;
				R_WAIT_TILE: if (tile_redraw_done) refresh_state <= R_NEXT_TILE;
				R_NEXT_TILE: if (restore_c == ((drawn_x[4:0] != 5'd0) ? 2'd3 : 2'd2)) begin
					restore_c <= 2'd0;
					if (restore_r == 2'd3) refresh_state <= R_UI;
					else begin
						restore_r <= restore_r + 1'b1;
						refresh_state <= R_TILE;
					end
				end
				else begin
					restore_c <= restore_c + 1'b1;
					refresh_state <= R_TILE;
				end
				R_UI: refresh_state <= R_WAIT_UI;
				R_WAIT_UI: if (!UI_busy) refresh_state <= R_STEVE;
				R_STEVE: refresh_state <= R_WAIT_STEVE_BUSY;
				R_WAIT_STEVE_BUSY: if (!S_done) refresh_state <= R_WAIT_STEVE_DONE;
				R_WAIT_STEVE_DONE: if (S_done) begin
					drawn_x <= frame_x;
					drawn_y <= frame_y;
					drawn_selection <= frame_selection;
					drawn_valid <= 1'b1;
					sprite_dirty <= 1'b0;
					world_dirty <= 1'b0;
					refresh_state <= R_IDLE;
				end
				default: refresh_state <= R_IDLE;
			endcase
		end
	end
	
    // choose x, y, color, and write for one of the two objects
    assign MUX_x = UI_busy ? UI_x : world_done ? S_x : W_x;
    assign MUX_y = UI_busy ? UI_y : world_done ? S_y : W_y;
    assign MUX_color = UI_busy ? UI_color : world_done ? S_color : W_color;
    assign MUX_write = UI_busy ? (UI_write && UI_y >= 9'd160) : world_done ? (S_write && S_y >= 9'd160) : (W_write && W_y >= 9'd160); // prevents both world renderer and steve from overwriting the top 160 pixrls
	 
	 // display PS2 data
    hex7seg H0 (Serial[4:1], HEX0);
    hex7seg H1 (Serial[8:5], HEX1);
    hex7seg H2 (Serial[15:12], HEX2);
    hex7seg H3 (Serial[19:16], HEX3);
    hex7seg H4 (Serial[26:23], HEX4);
    hex7seg H5 (SW[9] ? selected_block : Serial[30:27], HEX5); // temporary, displays if selected block is right

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

module block_map(

	input wire Clock, Resetn,
	output reg ready,
	input wire write_enable,
	
	input wire [4:0] write_col,
	input wire [3:0] write_row,
	input wire [3:0] write_block,
	
	// read steve adjacent blocks:
		input wire [4:0] read0_col,
		input wire [3:0] read0_row,
		output wire [3:0] read0_block,

		input wire [4:0] read1_col,
		input wire [3:0] read1_row,
		output wire [3:0] read1_block,
		
		input wire [4:0] read2_col,
		input wire [3:0] read2_row,
		output wire [3:0] read2_block,
		
		input wire [4:0] read3_col,
		input wire [3:0] read3_row,
		output wire [3:0] read3_block,
		
		input wire [4:0] read4_col,
		input wire [3:0] read4_row,
		output wire [3:0] read4_block,
		
		input wire [4:0] read5_col,
		input wire [3:0] read5_row,
		output wire [3:0] read5_block,
		
		input wire [4:0] read6_col,
		input wire [3:0] read6_row,
		output wire [3:0] read6_block,
		
		input wire [4:0] read7_col,
		input wire [3:0] read7_row,
		output wire [3:0] read7_block,
		
		input wire [4:0] read8_col,
		input wire [3:0] read8_row,
		output wire [3:0] read8_block,
		output wire read8_valid,
		output wire [3:0] read8_above_block,
		output wire [3:0] read8_below_block,
		output wire [3:0] read8_left_block,
		output wire [3:0] read8_right_block
		);
		
		localparam STONE = 4'd3;
		reg [3:0] seed [0:299]; // fixed starting layout 20x15
		reg [3:0] tiles [0:14][0:19]; // live world tiles[row][col]
		reg [8:0] init_address; // entry in the 1D seed
		reg [3:0] init_row;
		reg [4:0] init_col;
		
		initial begin 
			$readmemh("./MIF/world_seed.hex", seed);
		end
			
		// no game write accepted until the entire map is ready
		
		always @(posedge Clock) begin
		
			if (!Resetn) begin
			
				init_address <= 9'd0;
				init_row <= 4'd0;
				init_col <= 5'd0;
				ready <= 1'b0;
			end
			else if (!ready) begin
				
				tiles[init_row][init_col] <= seed[init_address];
				// tiles[init_row][init_col] <= (init_row < 4'd9) ? 4'd0 : (init_row == 4'd9) ? 4'd1 : 4'd2;
				
				if (init_address == 9'd299) begin
					ready <= 1'b1;
				end
				else begin
				
					init_address <= init_address + 1'b1;
					
					if (init_col == 5'd19) begin 
						init_col <= 5'd0;
						init_row <= init_row + 1'b1;
					end
					else begin 
						init_col <= init_col + 1'b1;
					end
				end
			end
			
			else if (write_enable && write_col < 5'd20 && write_row < 4'd15) begin
				tiles[write_row][write_col] <= write_block;
			end
		end
		
		// outside the screen is solid
		
		assign read0_block = (ready && read0_col < 5'd20 && read0_row < 4'd15) ? tiles[read0_row][read0_col] : STONE;
		assign read1_block = (ready && read1_col < 5'd20 && read1_row < 4'd15) ? tiles[read1_row][read1_col] : STONE;
		assign read2_block = (ready && read2_col < 5'd20 && read2_row < 4'd15) ? tiles[read2_row][read2_col] : STONE;
		assign read3_block = (ready && read3_col < 5'd20 && read3_row < 4'd15) ? tiles[read3_row][read3_col] : STONE;
		assign read4_block = (ready && read4_col < 5'd20 && read4_row < 4'd15) ? tiles[read4_row][read4_col] : STONE;
		assign read5_block = (ready && read5_col < 5'd20 && read5_row < 4'd15) ? tiles[read5_row][read5_col] : STONE;
		assign read6_block = (ready && read6_col < 5'd20 && read6_row < 4'd15) ? tiles[read6_row][read6_col] : STONE;
		assign read7_block = (ready && read7_col < 5'd20 && read7_row < 4'd15) ? tiles[read7_row][read7_col] : STONE;
		
		// interaction controller supplies on sepected corrdinate on read8
		assign read8_valid = ready && read8_col < 5'd20 && read8_row < 4'd15;
		assign read8_block = read8_valid ? tiles[read8_row][read8_col] : STONE;
		
		// actual neighbours of the seelcted cell
		
		assign read8_above_block = (read8_valid && read8_row > 4'd0) ? tiles[read8_row - 4'd1][read8_col] : 4'd0;
		assign read8_below_block = (read8_valid && read8_row < 4'd14) ? tiles[read8_row + 4'd1][read8_col] : 4'd0;
		assign read8_left_block = (read8_valid && read8_col > 5'd0) ? tiles[read8_row][read8_col - 5'd1] : 4'd0;
		assign read8_right_block = (read8_valid && read8_col < 5'd19) ? tiles[read8_row][read8_col + 5'd1] : 4'd0;
		
endmodule


// first custom module
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

module block_selector (

								input wire [9:0] player_x,
								input wire [8:0] player_y,
								input wire [3:0] index,
								
								output wire [4:0] target_col,
								output wire [3:0] target_row,
								output wire target_valid

							  );
							  
	// convert steve's pixel positions into tile coords
	
	wire signed [6:0] player_col = {2'b00, player_x[9:5]};
	wire spans_two_cols = (player_x[4:0] != 5'd0);
	wire signed [6:0] player_row = {3'b000, player_y[8:5]};
	
	// offset of the selected block relative to steve
	reg signed [6:0] dx, dy;
	
	always @ (*) begin
	
		dx = 0;
		dy = 0;
		
	if (spans_two_cols) begin
	
		case (index)
		
			// top row
			4'd0: begin dx = -1; dy = -1; end
			4'd1: begin dx =  0; dy = -1; end
			4'd2: begin dx =  1; dy = -1; end
			4'd3: begin dx =  2; dy = -1; end
			
			// upper sides
			4'd4: begin dx = -1; dy =  0; end
			4'd5: begin dx =  2; dy =  0; end
			
			// lower sides
			4'd6: begin dx = -1; dy =  1; end
			4'd7: begin dx =  2; dy =  1; end
			
			// bottom row
			4'd8: begin dx = -1; dy =  2; end
			4'd9: begin dx =  0; dy =  2; end
			4'd10: begin dx =  1; dy =  2; end
			4'd11: begin dx =  2; dy =  2; end

			default: begin dx = 0; dy = 0; end
			
		endcase
	end
	else begin
		
		case (index)
		
			/*
			
			-----------------
			| 0 |   1   | 2 |
			-----------------
			| 3 | STEVE | 4 |
			-----------------
			| 5 | STEVE | 6 |
			-----------------
			| 7 |   8   | 9 | 
			-----------------
			
			*/
			
			4'd0: begin dx = -1; dy = -1; end
			4'd1: begin dx =  0; dy = -1; end
			4'd2: begin dx =  1; dy = -1; end
			
			4'd3: begin dx = -1; dy =  0; end
			4'd4: begin dx =  1; dy =  0; end
			
			4'd5: begin dx = -1; dy =  1; end
			4'd6: begin dx =  1; dy =  1; end
			
			4'd7: begin dx = -1; dy =  2; end
			4'd8: begin dx =  0; dy =  2; end
			4'd9: begin dx =  1; dy =  2; end
			
			default: begin dx = 0; dy = 0; end
		endcase
	end
	end
	
	wire signed [6:0] col = player_col + dx;
	wire signed [6:0] row = player_row + dy;
	
	// valid only inside playable area
	
	assign target_valid = (index < (spans_two_cols ? 4'd12 : 4'd10)) && (col >= 0) && (col < 20) && (row >= 5) && (row < 15);
	
	assign target_col = target_valid ? col[4:0] : 5'd0;
	assign target_row = target_valid ? row[3:0] : 4'd0;
	
endmodule


module selection_ui (
    input wire Clock,
    input wire Resetn,
    input wire start,

    input wire [9:0] player_x,
    input wire [8:0] player_y,
    input wire [3:0] selected_index,

    output reg busy,

    output wire [9:0] VGA_x,
    output wire [8:0] VGA_y,
    output wire [8:0] VGA_color,
    output wire VGA_write
);

    // Which of the 10 surrounding blocks we're drawing
    reg [3:0] draw_index;

    // Which pixel inside the 32x32 block we're processing
    reg [9:0] pixel_index;

    wire [4:0] draw_col;
    wire [3:0] draw_row;
    wire draw_valid;

    // Reuse our existing selector to find each block
    block_selector UI_SELECTOR (
        .player_x(player_x),
        .player_y(player_y),
        .index(draw_index),

        .target_col(draw_col),
        .target_row(draw_row),
        .target_valid(draw_valid)
    );

    // A 32x32 block contains 1024 pixels.
    // The lower 5 bits represent X (0 to 31).
    // The upper 5 bits represent Y (0 to 31).
    wire [4:0] pixel_x = pixel_index[4:0];
    wire [4:0] pixel_y = pixel_index[9:5];

    // Convert block coordinates into VGA pixel coordinates
    assign VGA_x = {draw_col, 5'b0} + {5'b0, pixel_x};
    assign VGA_y = {draw_row, 5'b0} + {4'b0, pixel_y};

    // 1-pixel outline around a block
    wire thin_border =
        (pixel_x == 5'd0)  ||
        (pixel_x == 5'd31) ||
        (pixel_y == 5'd0)  ||
        (pixel_y == 5'd31);

    // 3-pixel outline for the currently selected block
    wire thick_border =
        (pixel_x <= 5'd2)  ||
        (pixel_x >= 5'd29) ||
        (pixel_y <= 5'd2)  ||
        (pixel_y >= 5'd29);

    wire is_selected = (draw_index == selected_index);

    // Yellow selected outline, black normal outline
    assign VGA_color = is_selected ? 9'b111_111_000 : 9'b000_000_000;

    // Only write pixels belonging to the outlines
    assign VGA_write = busy && draw_valid &&
                       (is_selected ? thick_border : thin_border);

    // Drawing controller
    always @(posedge Clock) begin
        if (!Resetn) begin
            busy <= 1'b0;
            draw_index <= 4'd0;
            pixel_index <= 10'd0;
        end
        else if (!busy) begin
            if (start) begin
                busy <= 1'b1;
                draw_index <= 4'd0;
                pixel_index <= 10'd0;
            end
        end
        else begin
            // Finished processing one 32x32 block
            if (pixel_index == 10'd1023) begin
                pixel_index <= 10'd0;

                if (draw_index == ((player_x[4:0] != 5'd0) ? 4'd11 : 4'd9))
							busy <= 1'b0;
                else
                    draw_index <= draw_index + 1'b1;
            end
            else begin
                pixel_index <= pixel_index + 1'b1;
            end
        end
    end

endmodule

module block_interaction (
	input wire clk, resetn,
	input wire key_break, key_place,
	input wire enable, target_valid,
	input wire [4:0] target_col,
	input wire [3:0] target_row,
	input wire [3:0] target_block,
	input wire has_neighbor,
	input wire [3:0] tool_strength,
	input wire [3:0] place_block,
	
	output wire write_enable,
	output wire [4:0] write_col,
	output wire [3:0] write_row,
	output wire [3:0] write_block,
	output wire edit_done
);

	reg [1:0] break_sync, place_sync;
	reg place_previous;
	
	always @(posedge clk) begin
		if (!resetn) begin
			break_sync <= 2'b11;
			place_sync <= 2'b11;
			place_previous <= 1'b1;
		end
		else begin
			break_sync <= {break_sync[0], key_break};
			place_sync <= {place_sync[0], key_place};
			place_previous <= place_sync[1];
		end
	end
	
	wire breaking = !break_sync[1];
	wire place_pressed = place_previous && !place_sync[1];
	
	// hardness units: tenths of a second using the hand
	reg [7:0] hardness;
	
	always @ (*) begin
		case (target_block)
			4'd0: hardness = 8'd0; // air
			4'd1: hardness = 8'd5; // grass
			4'd2: hardness = 8'd5; // dirt
			4'd3: hardness = 8'd20; // stone
			4'd4: hardness = 8'd25; // cobble
			4'd5: hardness = 8'd15; // log
			4'd6: hardness = 8'd10; // planks
			4'd7: hardness = 8'd2; // leaves
			4'd8: hardness = 8'd30; // iron ore
			4'd9: hardness = 8'd40; // diamond ore
			default: hardness = 8'd20;
		endcase
	end
			
	localparam [18:0] TICK_LIMIT = 19'd499999;
	
	reg [18:0] tick_counter;
	reg [8:0] progress;
	
	reg [4:0] mining_col;
	reg [4:0] mining_row;
	
	wire same_target = (target_col == mining_col) && (target_row == mining_row);
	
	wire can_mine = enable && target_valid && breaking && (target_block != 4'd0) && (tool_strength != 4'd0);
	
	wire mining_tick = can_mine && same_target && (tick_counter == TICK_LIMIT);
	
	wire [8:0] required_progress = {1'b0, hardness} * 9'd10;
	
	wire [9:0] next_progress = {1'b0, progress} + {6'd0, tool_strength};
	
	wire break_complete = mining_tick && (next_progress >= {1'b0, required_progress});
	
	wire place_complete = enable && target_valid && place_pressed && (target_block == 4'd0) && has_neighbor && (place_block != 4'd0);
	
	assign write_enable = break_complete || place_complete;
	
	assign write_col = target_col;
	assign write_row = target_row;
	
	assign write_block = break_complete ? 4'd0 : place_block;
	
	assign edit_done = write_enable;
	
	always @(posedge clk) begin
		if (!resetn) begin
			tick_counter <= 19'd0;
			progress <= 9'd0;
			mining_col <= 5'd0;
			mining_row <= 4'd0;
		end
		else if (!can_mine || !same_target) begin
			tick_counter <= 19'd0;
			
			if (break_complete) progress <= 9'd0;
			else progress <= next_progress[8:0];
			
		end
		else begin
			tick_counter <= tick_counter + 1'b1;
		end
	end
	
endmodule
