`default_nettype none

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
		
		// ********************************************************************************************************************************************
		
		localparam STONE = 4'd3;
		
		reg [3:0] tiles [0:14][0:19];
		
		reg [8:0] init_address;
		reg [3:0] init_row;
		reg [4:0] init_col;
		
		// randomizer signals
		wire generator_done;
		wire [3:0] generated_block;
		
		// free-running seed counter:
		reg [15:0] seed_counter = 16'd0;
		
		always @(posedge Clock) begin
			seed_counter <= seed_counter + 16'd1;
		end
		
		randomizer_core GEN (
		
			.Clock(Clock),
			.Resetn(Resetn),
			.Enable(1'b1),
			
			.start_seed(seed_counter),
			
			.read_row(init_row),
			.read_col(init_col),
			
			.generated_block(generated_block),
			.generator_done(generator_done)
		
		);
		
		
		// ********************************************************************************************************************************************
			
		// no game write accepted until the entire map is ready
		
		always @(posedge Clock) begin
		
			if (!Resetn) begin
			
				init_address <= 9'd0;
				init_row <= 4'd0;
				init_col <= 5'd0;
				
				ready <= 1'b0;
				
			end
			
			else if (!ready) begin
			
				// wait until randomizer has finished 
				if (generator_done) begin
					
					// copy one generated block per clock cycle
					tiles[init_row][init_col] <= generated_block;
					
					if (init_address == 9'd299) begin
					
						// all blocks are generated
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
			end
			
			// normal gameplay, mining and placement
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

`default_nettype wire
