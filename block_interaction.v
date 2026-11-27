`default_nettype none

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
	input wire can_collect,
	
	output wire write_enable,
	output wire [4:0] write_col,
	output wire [3:0] write_row,
	output wire [3:0] write_block,
	output wire edit_done,
    output wire [9:0] mining_progress,
    output wire [9:0] mining_required,
    output wire mining_active
);

	reg [1:0] break_sync, place_sync;
	reg place_previous;
	
	always @(posedge clk) begin // shift register to sync up block breaking and placing keys
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
			4'd1: hardness = 8'd9; // grass
			4'd2: hardness = 8'd9; // dirt
			4'd3: hardness = 8'd75; // stone
			4'd4: hardness = 8'd75; // cobble
			4'd5: hardness = 8'd30; // log
			4'd6: hardness = 8'd30; // planks
			4'd7: hardness = 8'd3; // leaves
			4'd8: hardness = 8'd75; // iron ore
			4'd9: hardness = 8'd75; // diamond ore
			default: hardness = 8'd20;
		endcase
	end
			
	localparam [18:0] TICK_LIMIT = 19'd499999;
	
	reg [18:0] tick_counter;
	reg [9:0] progress;
	
	reg [4:0] mining_col;
	reg [3:0] mining_row;
	
	wire same_target = (target_col == mining_col) && (target_row == mining_row);
	
	wire can_mine = enable && target_valid && breaking && (target_block != 4'd0) && (tool_strength != 4'd0);
	
	wire mining_tick = can_mine && same_target && (tick_counter == TICK_LIMIT);
	
	wire [9:0] required_progress = {2'b00, hardness} * 10'd10;
	
	wire [10:0] next_progress = {1'b0, progress} + {7'd0, tool_strength};
	
	wire break_complete = mining_tick && can_collect && (next_progress >= {1'b0, required_progress});
	
	wire place_complete = enable && target_valid && place_pressed && (target_block == 4'd0) && has_neighbor && (place_block != 4'd0);
	
	assign write_enable = break_complete || place_complete;
	
	assign write_col = target_col;
	assign write_row = target_row;
	
	assign write_block = break_complete ? 4'd0 : place_block;
	
	assign edit_done = write_enable;
    assign mining_progress = progress;
    assign mining_required = required_progress;
    assign mining_active = can_mine && same_target;
	
	always @(posedge clk) begin
		if (!resetn) begin
			tick_counter <= 19'd0;
			progress <= 10'd0;
			mining_col <= 5'd0;
			mining_row <= 4'd0;
		end
		
		// minig stopped, became invalid or changed targets
		else if (!can_mine || !same_target) begin
			tick_counter <= 19'd0;
			progress <= 10'd0;
			
			// remember the new target
			mining_col <= target_col;
			mining_row <= target_row;
		end
		
		// enough clock cycles have passed for one mining tick
		else if (mining_tick) begin
			tick_counter <= 19'd0;
			
			if (break_complete)
				progress <= 10'd0;
			else if (next_progress >= {1'b0, required_progress})
				progress <= required_progress;
			else 
				progress <= next_progress[9:0];
		end
		
		else begin 
			tick_counter <= tick_counter + 1'b1;
		end
		
	end
	
endmodule

`default_nettype wire
