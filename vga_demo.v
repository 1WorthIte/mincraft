`default_nettype none

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

    // KEY1 toggles non-selected block outlines (active-low button).
    reg show_outlines;
    reg [1:0] key1_sync;
    reg key1_prev;
    reg [17:0] key1_debounce;
    always @(posedge CLOCK_50) begin
        if (!Resetn) begin
            show_outlines <= 1'b1;
            key1_sync <= 2'b11;
            key1_prev <= 1'b1;
            key1_debounce <= 18'd0;
        end else begin
            key1_sync <= {key1_sync[0], KEY[1]};
            key1_prev <= key1_sync[1];
            if (key1_debounce != 18'd0)
                key1_debounce <= key1_debounce - 1'b1;
            if (key1_prev && !key1_sync[1] && key1_debounce == 18'd0) begin
                show_outlines <= ~show_outlines;
                key1_debounce <= 18'd249999; // 5 ms bounce guard
            end
        end
    end
	
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
	 
	 wire [3:0] selection_index;
	 
	 reg [9:0] rendered_x;
	 reg [8:0] rendered_y;
	 reg [3:0] rendered_index;
	 
	 wire position_changed = (steve_x != rendered_x) || (steve_y != rendered_y);
	 
	 wire selection_changed = (selection_index != rendered_index);
	 
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
	 reg break_down;
	 reg place_down;
	 
	 reg up_arrow_down;
	 reg down_arrow_down;
	 reg left_arrow_down;
	 reg right_arrow_down;
	 
	 always@(posedge CLOCK_50) begin
		if (!Resetn) begin
			release_pending <= 1'b0;
			extended_pending <= 1'b0;
			
			left_down <= 1'b0;
			right_down <= 1'b0;
			hit_down <= 1'b0;
			jump_down <= 1'b0;
			
			break_down <= 1'b0;
			place_down <= 1'b0;
			
			up_arrow_down <= 1'b0;
			down_arrow_down <= 1'b0;
			left_arrow_down <= 1'b0;
			right_arrow_down <= 1'b0;
			
		end
		else if (ps2_rec) begin
			if (received_byte == 8'hE0) begin
				extended_pending <= 1'b1;
			end
			
			else if (received_byte == 8'hF0) begin
				release_pending <= 1'b1;
			end
			
			else begin
			
				if (extended_pending) begin
				
					// extended keys: arrow keys
				
					case (received_byte)
					
						8'h75: up_arrow_down <= !release_pending;
						8'h72: down_arrow_down <= !release_pending;
						8'h6B: left_arrow_down <= !release_pending;
						8'h74: right_arrow_down <= !release_pending;
					
						default: ;
					
					endcase
				end
			
				else begin
					// orginary keys: movement, mining and placing
				
					case (received_byte)
				
						8'h1C: left_down <= !release_pending; // A
						8'h23: right_down <= !release_pending; // D
						8'h2B: hit_down <= !release_pending; // F
						8'h29: jump_down <= !release_pending; // Space
					
						8'h32: break_down <= !release_pending; // B
						8'h4D: place_down <= !release_pending; // P
					
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
        wire [9:0] mining_progress, mining_required;
        wire mining_active;
		reg world_dirty;

        // =============================================================
        // TEMPORARY CRAFTING TEST CONTROLS
        // SW9 = crafting menu; SW[4:0] = fixed recipe ID (0..17).
        // Rising edges: SW8 craft; SW7 planks; SW6 sticks; SW5 cobble.
        // These controls can be replaced by keyboard events later.
        // =============================================================
        wire crafting_mode = SW[9];
        wire [4:0] recipe_select = SW[4:0];
        reg craft_switch_previous;

        always @(posedge CLOCK_50) begin
            if (!Resetn)
                craft_switch_previous <= 1'b0;
            else
                craft_switch_previous <= SW[8];
        end

        wire craft_pulse = crafting_mode && SW[8] && !craft_switch_previous;

        wire [17:0] available_recipes;
        wire [44:0] slot_items;
        wire [62:0] slot_counts;
        wire pickup_accepted, craft_accepted;
        wire [4:0] preview_item, preview_ingredient;
        wire [6:0] preview_count;

        crafting_inventory INVENTORY (
            .clk(CLOCK_50), .resetn(Resetn),
            .recipe_select(recipe_select), .craft_pulse(craft_pulse),
            .pickup_pulse(pickup_from_mining),
            .pickup_item(mined_item), .pickup_count(7'd1),
				.pickup_can_fit(pickup_can_fit),
            .pickup_accepted(pickup_accepted), .craft_accepted(craft_accepted),
            .available_recipes(available_recipes),
            .slot_items(slot_items), .slot_counts(slot_counts),
            .preview_item(preview_item), .preview_count(preview_count),
            .preview_cell(4'd0), .preview_ingredient(preview_ingredient)
        );
		  
		reg [4:0] mined_item;
		
		always @(*) begin
			case (selected_block)
				4'd1, 4'd2: mined_item = 5'd23;
				4'd3, 4'd4: mined_item = 5'd4;
				4'd5: mined_item = 5'd1;
				4'd6: mined_item = 5'd2;
				4'd8: mined_item = 5'd5;
				4'd9: mined_item = 5'd6;
				default: mined_item = 5'd0;
			endcase
		end
		
		wire pickup_can_fit;
		
		wire can_collect_block = (mined_item == 5'd0) || pickup_can_fit;
		
		wire mined_block_pulse = map_write_enable && (map_write_block == 4'd0);
		
		wire pickup_from_mining = mined_block_pulse && (mined_item != 5'd0);
		
		wire [3:0] held_tool_strength = 4'd1; // hand
		wire [3:0] held_place_block = 4'd3; // stone
		
		block_interaction INTERACTION (
		
			.clk(CLOCK_50),
			.resetn(Resetn),
			.key_break(~break_down), // expects active low
			.key_place(~place_down), // expects active low
			
			.enable(map_ready && !crafting_mode),
			.target_valid(target_valid && selected_valid),
			.target_col(selected_col),
			.target_row(selected_row),
			.target_block(selected_block),
			.has_neighbor(selected_has_neighbor),
			
			.tool_strength(held_tool_strength),
			.place_block(held_place_block),
			.can_collect(can_collect_block),
			
			.write_enable(map_write_enable),
			.write_col(map_write_col),
			.write_row(map_write_row),
			.write_block(map_write_block),
			.edit_done(edit_done),
            .mining_progress(mining_progress),
            .mining_required(mining_required),
            .mining_active(mining_active)
		
		);
		
		selection_control NAV (
		
			.clk(CLOCK_50),
			.resetn(Resetn),
			
			.player_x(steve_x),
			.player_y(steve_y),
			
			.up_down(up_arrow_down),
			.down_down(down_arrow_down),
			.left_down(left_arrow_down),
			.right_down(right_arrow_down),
			
			.selection_index(selection_index)
		
		);
		
	
		block_selector SELECTOR (
										
											.player_x(steve_x),
											.player_y(steve_y),
											.index(selection_index), // temporary, keyboard not integrated
											
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
	wire restoration_active;
	localparam [2:0] REST_IDLE = 3'd0, REST_TOP_START = 3'd1,
	                 REST_TOP_WAIT = 3'd2, REST_WORLD_RESET = 3'd3,
	                 REST_WORLD_WAIT = 3'd4;
	reg [2:0] restore_state;
	
	world W (
	
		// Re-run only the world renderer's boot drawing pass.
		// MAP, INVENTORY, and Steve are NOT reset.
		.Resetn(Resetn & map_ready & !(restore_state == REST_WORLD_RESET)),
		.Clock(CLOCK_50), .redraw_req(tile_redraw_req),
		.redraw_col(tile_redraw_col), .redraw_row(tile_redraw_row),
		.redraw_done(tile_redraw_done),
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
        .show_outlines(frame_outlines),
		
		.busy(UI_busy),
		
		.VGA_x(UI_x),
		.VGA_y(UI_y),
		.VGA_color(UI_color),
		.VGA_write(UI_write)
	
	);

    // =============================================================
    // CRAFTING SCREEN RENDERER
    // Snapshots ensure a new full-screen pass follows any switch,
    // inventory, or availability change during an earlier pass.
    // =============================================================
    wire [9:0] CRAFT_x;
    wire [8:0] CRAFT_y, CRAFT_color;
    wire CRAFT_write, CRAFT_busy;
    reg crafting_drawn;
    reg [4:0] drawn_recipe;
    reg [17:0] drawn_available;
    reg [44:0] drawn_items;
    reg [62:0] drawn_counts;

    wire craft_redraw_needed = !crafting_drawn ||
        drawn_recipe != recipe_select ||
        drawn_available != available_recipes ||
        drawn_items != slot_items ||
        drawn_counts != slot_counts;
    wire CRAFT_start = crafting_mode && !CRAFT_busy && craft_redraw_needed;

    always @(posedge CLOCK_50) begin
        if (!Resetn) begin
            crafting_drawn <= 1'b0;
            drawn_recipe <= 5'd0;
            drawn_available <= 18'd0;
            drawn_items <= 45'd0;
            drawn_counts <= 63'd0;
        end else if (!crafting_mode) begin
            crafting_drawn <= 1'b0;
        end else if (CRAFT_start) begin
            crafting_drawn <= 1'b1;
            drawn_recipe <= recipe_select;
            drawn_available <= available_recipes;
            drawn_items <= slot_items;
            drawn_counts <= slot_counts;
        end
    end

    crafting_ui CRAFT_UI (
        .clk(CLOCK_50), .resetn(Resetn && crafting_mode),
        .start(CRAFT_start), .grant(crafting_mode), .busy(CRAFT_busy),
        .recipe_select(recipe_select), .available_recipes(available_recipes),
        .slot_items(slot_items), .slot_counts(slot_counts),
        .VGA_x(CRAFT_x), .VGA_y(CRAFT_y),
        .VGA_color(CRAFT_color), .VGA_write(CRAFT_write)
    );

    // SW9 changes which renderer can WRITE the VGA framebuffer; the pixels
    // already in framebuffer memory do not disappear when SW9 is switched off.
    // Restore the original upper background, rebuild the live block map, then
    // let the ordinary refresh FSM redraw selection outlines and Steve.
    reg crafting_mode_previous;
    wire crafting_closed = crafting_mode_previous && !crafting_mode;
    assign restoration_active = (restore_state != REST_IDLE);

    wire [9:0] REST_x;
    wire [8:0] REST_y, REST_color;
    wire REST_write, REST_busy;
    wire restoring_top = (restore_state == REST_TOP_START) ||
                         (restore_state == REST_TOP_WAIT);

    background_restore RESTORE_BACKGROUND (
        .clk(CLOCK_50), .resetn(Resetn && !crafting_mode),
        .start(restore_state == REST_TOP_START), .busy(REST_busy),
        .VGA_x(REST_x), .VGA_y(REST_y),
        .VGA_color(REST_color), .VGA_write(REST_write)
    );

    always @(posedge CLOCK_50) begin
        if (!Resetn) begin
            crafting_mode_previous <= 1'b0;
            restore_state <= REST_IDLE;
        end else begin
            crafting_mode_previous <= crafting_mode;

            // If the menu reopens during restoration, restart from the
            // beginning the next time it closes.
            if (crafting_mode)
                restore_state <= REST_IDLE;
            else begin
                case (restore_state)
                    REST_IDLE: if (crafting_closed)
                        restore_state <= REST_TOP_START;
                    REST_TOP_START: restore_state <= REST_TOP_WAIT;
                    REST_TOP_WAIT: if (!REST_busy && !REST_write)
                        restore_state <= REST_WORLD_RESET;
                    REST_WORLD_RESET: restore_state <= REST_WORLD_WAIT;
                    REST_WORLD_WAIT: if (world_done)
                        restore_state <= REST_IDLE;
                    default: restore_state <= REST_IDLE;
                endcase
            end
        end
    end
	
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
    reg drawn_outlines, frame_outlines;

	wire refresh_pending = !crafting_mode && !restoration_active &&
                           world_done && S_done && (y_Q == A) &&
	                       (!drawn_valid || sprite_dirty || world_dirty ||
	                        steve_x != drawn_x || steve_y != drawn_y ||
	                        selection_index != drawn_selection ||
                            show_outlines != drawn_outlines);
	assign refresh_busy = (refresh_state != R_IDLE) || refresh_pending ||
                          crafting_mode || restoration_active;

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
            drawn_outlines <= 1'b1;
            frame_outlines <= 1'b1;
			drawn_valid <= 1'b0;
			sprite_dirty <= 1'b0;
			world_dirty <= 1'b0;
		end
		else if (crafting_mode || restoration_active) begin
			// Menu rendering can interrupt a normal tile/selection refresh.
			// The restoration sequence will repaint everything from scratch.
			refresh_state <= R_IDLE;
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
					frame_selection <= selection_index;
                    frame_outlines <= show_outlines;
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
                    drawn_outlines <= frame_outlines;
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
    // The HUD bar is in the protected top 160 pixels, below the first row.
    // It paints only while all other VGA writers are idle.
    wire [9:0] BAR_x;
    wire [8:0] BAR_y, BAR_color;
    wire BAR_write;
    wire bar_grant = world_done && S_done && !refresh_busy && !UI_busy;
    mining_bar BAR (
        .clk(CLOCK_50), .resetn(Resetn), .grant(bar_grant),
        .active(mining_active), .progress(mining_progress),
        .required(mining_required),
        .x(BAR_x), .y(BAR_y), .color(BAR_color), .write(BAR_write)
    );
	assign MUX_x = crafting_mode ? CRAFT_x :
                   restoring_top ? REST_x :
                   restoration_active ? W_x :
                   BAR_write ? BAR_x : UI_busy ? UI_x : world_done ? S_x : W_x;
	assign MUX_y = crafting_mode ? CRAFT_y :
                   restoring_top ? REST_y :
                   restoration_active ? W_y :
                   BAR_write ? BAR_y : UI_busy ? UI_y : world_done ? S_y : W_y;
	assign MUX_color = crafting_mode ? CRAFT_color :
                       restoring_top ? REST_color :
                       restoration_active ? W_color :
                       BAR_write ? BAR_color : UI_busy ? UI_color : world_done ? S_color : W_color;
	assign MUX_write = crafting_mode ? CRAFT_write :
                       restoring_top ? REST_write :
                       restoration_active ? (W_write && W_y >= 9'd160) :
                       BAR_write ? 1'b1 :
                       UI_busy ? (UI_write && UI_y >= 9'd160) :
                       world_done ? (S_write && S_y >= 9'd160) :
                                    (W_write && W_y >= 9'd160); // Preserve the upper HUD during normal gameplay.
	 
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

`default_nettype wire
