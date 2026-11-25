module selection_control (

	input wire clk, resetn,
	input wire [9:0] player_x,
	input wire [8:0] player_y,
	input wire up_down, down_down, left_down, right_down,
	output reg [3:0] selection_index

);

	// columns
	
	// 0-left edge, 3-right edge, 
	// only 1 for narrow box
	
	reg [1:0] cursor_col, cursor_row;
	reg [1:0] base_col, base_row;
	reg [1:0] next_col, next_row;
	
	wire wide = (player_x[4:0] != 5'd0);
	
	// which edges of the selection box are inside the playable world
	wire left_ok = (player_x[9:5] > 5'd0);
	wire right_ok = (player_x[9:5] < (wide ? 5'd18 : 5'd19));
	wire top_ok = (player_y[8:5] > 4'd5);
	wire bottom_ok = (player_y[8:5] < 4'd13);
	
	reg [3:0] arrows_previous;
	wire [3:0] arrows_down = {right_down, left_down, down_down, up_down};
	wire [3:0] arrow_press = arrows_down & ~arrows_previous;
	
	always @(*) begin
		base_col = cursor_col;
		base_row = cursor_row;
		
		// keep the same side/row when the box changes width
		if (!wide && base_col == 2'd2) base_col = 2'd1;
		
		// repair the selection if steve moves against a world bpudary
		if (!left_ok && base_col == 2'd0) base_col = 2'd1;
		if (!right_ok && base_col == 2'd3) base_col = wide ? 2'd2 : 2'd1; // different cases for wide and narrowbox
		if (!top_ok && base_row == 2'd0) base_row = 2'd1;
		if (!bottom_ok && base_row == 2'd3) base_row = 2'd2;
		
		// the two body rows only have selectable cells at the sides
		if ((base_row == 2'd1 || base_row == 2'd2) && (base_col == 2'd1 || base_col == 2'd2)) begin
			if (base_col == 2'd1 && left_ok) base_col = 2'd0;
			else if (right_ok) base_col = 2'd3;
			else base_col = 2'd0;
		end
		
		next_col = base_col;
		next_row = base_row;
		
		if (arrow_press[0]) begin // up
			if (base_row != 2'd0) begin
				if (base_col == 2'd0 || base_col == 2'd3) next_row = base_row - 2'd1;
				else next_row = 2'd0; // skip steve
			end
		end
		else if (arrow_press[1]) begin // down
			if (base_row != 2'd3) begin 
				if (base_col == 2'd0 || base_col == 2'd3) next_row = base_row + 2'd1;
				else next_row = 2'd3;
			end
		end
		else if (arrow_press[2]) begin
			if (base_col != 2'd0) begin
				if (base_row == 2'd1 || base_row == 2'd2) next_col = 2'd0;
				else if (!wide && base_col == 2'd3) next_col = 2'd1;
				else next_col = base_col - 2'd1;
			end
		end
		else if (arrow_press[3]) begin
			if (base_col != 2'd3) begin
				if (base_row == 2'd1 || base_row == 2'd2) next_col = 2'd3;
				else if (!wide && base_col == 2'd1) next_col = 2'd3;
				else next_col = base_col + 2'd1;
			end
		end
		
		// reject an arrow move beyong the playable world
		if ((!left_ok && next_col == 2'd0) || (!right_ok && next_col == 2'd3) || (!top_ok && next_row == 2'd0) || (!bottom_ok && next_row == 2'd3)) begin
			next_col = base_col;
			next_row = base_row;
		end
		
		// translate cursor position into the existing selector's index
		selection_index = 4'd0;
		
		if (wide) begin
			case (base_row) 
				2'd0: selection_index = {2'b000, base_col};
				2'd1: selection_index = (base_col == 2'd0) ? 4'd4 : 4'd5;
				2'd2: selection_index = (base_col == 2'd0) ? 4'd6 : 4'd7;
				2'd3: selection_index = 4'd8 + {2'b000, base_col};
			endcase
		end
		else begin 
			case (base_row)
				2'd0: selection_index = (base_col == 2'd3) ? 4'd2 : {2'b000, base_col};
				2'd1: selection_index = (base_col == 2'd0) ? 4'd3 : 4'd4;
				2'd2: selection_index = (base_col == 2'd0) ? 4'd5 : 4'd6;
				2'd3: selection_index = (base_col == 2'd3) ? 4'd9 : 4'd7 + {2'b000, base_col};
			endcase
		end
	end
	
	always @(posedge clk) begin
		if (!resetn) begin
			cursor_col <= 2'd0;
			cursor_row <= 2'd0;
			arrows_previous <= 4'b0000;
		end
		else begin 
			cursor_col <= next_col;
			cursor_row <= next_row;
			arrows_previous <= arrows_down;
		end
	end
endmodule
				
		