`default_nettype none

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

`default_nettype wire
