`timescale 1ns / 1ns

module randomizer_core (

	Clock,
	Resetn,
	Enable,
	start_seed,
	read_row,
	read_col,
	generated_block,
	generator_done

);

    input Clock;
    input Resetn;
    input Enable;

    input [15:0] start_seed;
	 
	 input [3:0] read_row;
	 input [4:0] read_col;
	 
	 output [3:0] generated_block;
	 output generator_done;

    // each cell stores 4 bit block ID
    reg [3:0] map [0:14][0:19];
	 
	 assign generator_done = trees_done;
	 assign generated_block = (generator_done && read_row < 4'd15 && read_col < 5'd20) ? map[read_row][read_col] : 4'd0;	 

    reg [3:0] fill_row; // remembers which row to write next
    reg [4:0] fill_col; // remembers which col to write next
    reg done; // prevents further write after all 300 cells are filled

    reg caves_done;

    reg trees_done;

    localparam T_PICK = 3'd0,
               T_BOUNDS = 3'd1,
               T_CHECK = 3'd2,
               T_DRAW = 3'd3,
               T_NEXT = 3'd4,
               T_DONE = 3'd5;

    reg [2:0] tree_state;

    reg [4:0] tree_col;
    reg [3:0] tree_base_row;

    reg [2:0] trunk_height;
    reg tree_type; // 0 - rect, 1 - triangle

    reg [1:0] tree_x;
    reg [2:0] tree_y;

    localparam C_PICK   = 3'd0,
               C_BOUNDS = 3'd1,
               C_CHECK  = 3'd2,
               C_DRAW   = 3'd3,
               C_DONE   = 3'd4;

    wire [3:0] tree_map_row;
    wire [4:0] tree_map_col;

    wire tree_is_log;
    wire tree_is_leaf;
    wire tree_cell_used;
    wire tree_last_cell;

    assign tree_map_row = tree_base_row - tree_y;
    assign tree_map_col = tree_col - 5'd1 + tree_x;

    // Logs only occupy the middle column
    assign tree_is_log =
        (tree_x == 2'd1) &&
        (tree_y <= trunk_height);

    // Leaves occupy two complete rows above the trunk
    assign tree_is_leaf =
        (tree_y == trunk_height + 3'd1) ||  // bottom of tree is always three blocks wide
        (
            (tree_y == trunk_height + 3'd2) && (!tree_type || tree_x == 2'd1)
        );

    // Does this position belong to the tree?
    assign tree_cell_used =
        tree_is_log || tree_is_leaf;

    // Have we reached the final cell of the tree region?
    assign tree_last_cell =
        (tree_x == 2'd2) &&
        (tree_y == trunk_height + 3'd2);

    reg [2:0] cave_state;

    // Total dimensions, INCLUDING the stone border
    reg [3:0] cave_width;       // 5..8
    reg [2:0] cave_height;      // 3..5

    // Top-left corner of the rectangle
    reg [4:0] cave_col;
    reg [3:0] cave_row;

    // Current position inside the rectangle
    reg [3:0] cave_x;
    reg [2:0] cave_y;

    // Try up to 64 candidate caves
    reg [6:0] cave_attempts;

    wire cave_border;
    wire cave_corner;

    assign cave_border =
        (cave_x == 4'd0) ||
        (cave_x == cave_width - 4'd1) ||
        (cave_y == 3'd0) ||
        (cave_y == cave_height - 3'd1);

    // Round the interior corners only for a 3-block-tall pocket
    // Shorter caves keep their full interior
    assign cave_corner =
        (cave_height == 3'd5) &&
        (cave_width >= 4'd7) &&
        ((cave_x == 4'd1) ||
         (cave_x == cave_width - 4'd2)) &&
        ((cave_y == 3'd1) ||
         (cave_y == cave_height - 3'd2));

    wire [15:0] random_value;
	 
	 reg seed_loaded;
	 
	 wire load_seed;
	 wire generation_enable;
	 
	 assign load_seed = Enable && !seed_loaded;
	 assign generation_enable = Enable && seed_loaded;
	 
	 always @(posedge Clock) begin
			
			if (!Resetn) seed_loaded <= 1'b0;
			else if (load_seed) seed_loaded <= 1'b1;
			
	 end 

    lfsr RNG (
        .Clock(Clock),
        .Resetn(Resetn),
        .Enable(generation_enable && !trees_done), // advance each enabled clock until world is finished
		  .LoadSeed(load_seed),
        .random_value(random_value),
        .start_seed(start_seed)
    );

    wire terrain_ready;
    wire [3:0] surface_row;

    terrain_profile TERRAIN (
        .Clock(Clock),
        .Resetn(Resetn),
        .Enable(generation_enable),
        .random_value(random_value),
        .read_col(done ? tree_col : fill_col),
        .surface_row(surface_row),
        .ready(terrain_ready)
    );

    always @ (posedge Clock) begin

        if (!Resetn) begin

            fill_row <= 4'd0; // start at (0,0)
            fill_col <= 5'd0;
            done <= 1'b0; // false

            caves_done <= 1'b0;
            cave_state <= C_PICK;

            cave_width <= 4'd5;
            cave_height <= 3'd3;

            cave_col <= 5'd0;
            cave_row <= 4'd7;

            cave_x <= 4'd0;
            cave_y <= 3'd0;

            cave_attempts <= 7'd0;

            trees_done <= 1'b0;
            tree_state <= T_PICK;

            tree_col <= 5'd1;
            tree_base_row <= 4'd0;

            trunk_height <= 3'd3;
            tree_type <= 1'b1;

            tree_x <= 2'd0;
            tree_y <= 3'd1;
        end

        else if (generation_enable && !done && terrain_ready) begin

            // write the block at the current coordinates

            if (fill_row < surface_row) begin
                map[fill_row][fill_col] <= 4'd0; // air
            end
            else if (fill_row == surface_row) begin
                map[fill_row][fill_col] <= 4'd1; // grass
            end
            else if (fill_row <= surface_row + 4'd2) begin
                map[fill_row][fill_col] <= 4'd2; // two dirt layers
            end
            else begin
                // below the dirt: stone iron or diamong
                if (random_value[2:0] == 3'b000 || random_value[2:0] == 3'b001 || random_value[2:0] == 3'b010) begin
                    map[fill_row][fill_col] <= 4'd8; // iron, 3 cases
                end
                else if (fill_row >= 4'd13 && random_value[2:0] == 3'b011) begin
                    map[fill_row][fill_col] <= 4'd9; // diamond
                end
                else begin
                    map[fill_row][fill_col] <= 4'd3; // stone
                end
            end

            // advance to next location or finish
            if (fill_row == 4'd14 && fill_col == 5'd19) begin
                done <= 1'b1;
            end
            else if (fill_col == 5'd19) begin
                fill_col <= 5'd0;
                fill_row <= fill_row + 4'd1;
            end
            else begin
                fill_col <= fill_col + 5'd1;
            end
        end

        else if (generation_enable && done && !caves_done) begin
            case (cave_state)

                C_PICK: begin
                    if (cave_attempts == 7'd64) begin
                        // No suitable cave found within 64 attempts.
                        caves_done <= 1'b1;
                        cave_state <= C_DONE;
                    end
                    else begin
                        cave_attempts <= cave_attempts + 7'd1;

                        // Outer width 5..8: air width 3..6.
                        cave_width <=
                            4'd5 + {2'b00, random_value[1:0]};

                        // Outer height 3..5: air height 1..3.
                        case (random_value[3:2])
                            2'b00: cave_height <= 3'd3;
                            2'b01: cave_height <= 3'd4;
                            2'b10: cave_height <= 3'd5;
                            default: cave_height <= 3'd4;
                        endcase

                        // Candidate position.
                        // Out-of-bounds candidates are rejected next.
                        cave_col <= random_value[8:4];
                        cave_row <=
                            4'd7 + {1'b0, random_value[11:9]};

                        cave_x <= 4'd0;
                        cave_y <= 3'd0;

                        cave_state <= C_BOUNDS;
                    end
                end

                C_BOUNDS: begin
                    // Extra bits prevent these sums from overflowing.
                    // Check BEFORE accessing map at this position.
                    if (
                        ({1'b0, cave_col} +
                         {2'b00, cave_width} <= 6'd20) &&

                        ({1'b0, cave_row} +
                         {2'b00, cave_height} <= 5'd15)
                    ) begin
                        cave_state <= C_CHECK;
                    end
                    else begin
                        cave_state <= C_PICK;
                    end
                end

                C_CHECK: begin
                    // Inspect one cell per clock.
                    // The ENTIRE rectangle must be underground.
                    if (
                        map[cave_row + cave_y]
                           [cave_col + cave_x] == 4'd0 ||

                        map[cave_row + cave_y]
                           [cave_col + cave_x] == 4'd1
                    ) begin
                        // Air or grass: reject without changing map.
                        cave_state <= C_PICK;
                    end
                    else if (cave_x == cave_width - 4'd1) begin
                        cave_x <= 4'd0;

                        if (cave_y == cave_height - 3'd1) begin
                            // Every cell passed. Start drawing.
                            cave_y <= 3'd0;
                            cave_state <= C_DRAW;
                        end
                        else begin
                            cave_y <= cave_y + 3'd1;
                        end
                    end
                    else begin
                        cave_x <= cave_x + 4'd1;
                    end
                end

                C_DRAW: begin
                    if (cave_border || cave_corner) begin
                        map[cave_row + cave_y]
                           [cave_col + cave_x] <= 4'd3; // stone
                    end
                    else begin
                        map[cave_row + cave_y]
                           [cave_col + cave_x] <= 4'd0; // cave air
                    end

                    if (cave_x == cave_width - 4'd1) begin
                        cave_x <= 4'd0;

                        if (cave_y == cave_height - 3'd1) begin
                            caves_done <= 1'b1;
                            cave_state <= C_DONE;
                        end
                        else begin
                            cave_y <= cave_y + 3'd1;
                        end
                    end
                    else begin
                        cave_x <= cave_x + 4'd1;
                    end
                end

                C_DONE: begin
                    caves_done <= 1'b1;
                end

                default: cave_state <= C_PICK;

            endcase
        end

        // Tree generation
        else if (generation_enable && done && caves_done && !trees_done) begin
            case (tree_state)

                T_PICK: begin

                    // 25% chance of attempting a tree
                    if (random_value[1:0] == 2'b00) begin

                        tree_base_row <= surface_row;

                        // Random trunk height: 2, 3 or 4
                        case (random_value[3:2])
                            2'b00: trunk_height <= 3'd2;
                            2'b01: trunk_height <= 3'd3;
                            2'b10: trunk_height <= 3'd4;
                            default: trunk_height <= 3'd3;
                        endcase

                        // Random canopy shape
                        tree_type <= random_value[4];

                        tree_x <= 2'd0;
                        tree_y <= 3'd1;

                        tree_state <= T_BOUNDS;

                    end

                    else begin
                        tree_state <= T_NEXT;
                    end

                end

                T_BOUNDS: begin

                    // Horizontal bounds
                    if (
                        (tree_col < 5'd1) ||
                        (tree_col > 5'd18)
                    ) begin
                        tree_state <= T_NEXT;
                    end

                    // Not enough space for even the smallest tree
                    else if (tree_base_row < 4'd9) begin
                        tree_state <= T_NEXT;
                    end

                    // Reduce the trunk height until the tree fits
                    else if (tree_base_row < trunk_height + 4'd7) begin
                        trunk_height <= trunk_height - 3'd1;
                    end

                    // Ensure the tree is on grass
                    else if (map[tree_base_row][tree_col] != 4'd1) begin
                        tree_state <= T_NEXT;
                    end

                    else begin
                        tree_state <= T_CHECK;
                    end

                end

                T_CHECK: begin

                    // Every intended log/leaf position must be air
                    if (
                        tree_cell_used &&
                        map[tree_map_row][tree_map_col] != 4'd0
                    ) begin
                        tree_state <= T_NEXT;
                    end

                    else if (tree_last_cell) begin

                        // Every position passed, start drawing
                        tree_x <= 2'd0;
                        tree_y <= 3'd1;

                        tree_state <= T_DRAW;

                    end

                    else if (tree_x == 2'd2) begin

                        // Move one row upwards
                        tree_x <= 2'd0;
                        tree_y <= tree_y + 3'd1;

                    end

                    else begin
                        tree_x <= tree_x + 2'd1;
                    end

                end

                T_DRAW: begin

                    // Write the appropriate block
                    if (tree_is_log) begin
                        map[tree_map_row][tree_map_col] <= 4'd5;
                    end

                    else if (tree_is_leaf) begin
                        map[tree_map_row][tree_map_col] <= 4'd7;
                    end

                    // Advance through the tree region
                    if (tree_last_cell) begin
                        tree_state <= T_NEXT;
                    end

                    else if (tree_x == 2'd2) begin
                        tree_x <= 2'd0;
                        tree_y <= tree_y + 3'd1;
                    end

                    else begin
                        tree_x <= tree_x + 2'd1;
                    end

                end

                T_NEXT: begin

                    if (tree_col == 5'd18) begin

                        // Finished scanning all valid columns
                        tree_state <= T_DONE;

                    end

                    else begin

                        // Consider the next column
                        tree_col <= tree_col + 5'd1;
                        tree_state <= T_PICK;

                    end

                end

                T_DONE: begin
                    trees_done <= 1'b1;
                end

                default: tree_state <= T_PICK;

            endcase
        end
    end

endmodule

module lfsr (Clock, Resetn, Enable, LoadSeed, random_value, start_seed);

    input Clock, Resetn, Enable, LoadSeed;
    input [15:0] start_seed;
	 
    output reg [15:0] random_value;

    wire feedback;

    assign feedback = random_value[15] ^ 
                      random_value[13] ^ 
                      random_value[12] ^ 
                      random_value[10];

    always @ (posedge Clock or negedge Resetn) begin

        if (!Resetn) begin

            random_value <= 16'h0001;

        end
		  
		  else if (LoadSeed) begin
		  
				// prevent the lfsr from getting stuck at 0
				if (start_seed == 16'd0) random_value <= 16'h0001;
				else random_value <= start_seed;
				
			end

        else if (Enable) begin
            
            // shifts the existing bits left, inserts feedback bit at bit 0
            random_value <= {random_value[14:0], feedback}; 
        
        end

    end

endmodule 

module terrain_profile(Clock, Resetn, Enable, random_value, read_col, surface_row, ready);

    input Clock, Resetn, Enable;
    input [15:0] random_value;
    input [4:0] read_col;

    output wire [3:0] surface_row;
    output reg ready;

    reg [3:0] heights [0:19];

    reg [4:0] build_col;
    reg [3:0] previous_height;
    reg [3:0] next_height;

    wire [2:0] terrain_choice;

    assign terrain_choice = random_value[2:0] ^ random_value[7:5] ^ random_value[12:10];

    // read the stored surface height for the requested column
    assign surface_row = heights[read_col];

    // Decide the surface row for the next column
    always @(*) begin

        next_height = previous_height;

        if (build_col == 5'd0) begin
            // Start at row 6, 7, 8, 9, 10, 11, or 12
            case (terrain_choice)
                3'b000: next_height = 4'd6;
                3'b001: next_height = 4'd7;
                3'b010: next_height = 4'd8;
                3'b011: next_height = 4'd9;
                3'b100: next_height = 4'd10;
                3'b101: next_height = 4'd11;
                3'b110: next_height = 4'd12;
                default: next_height = 4'd9;
            endcase
        end

        else begin
            case (terrain_choice)

                // Three choices: move uphill
                3'd0, 3'd1, 3'd2: begin
                    if (previous_height > 4'd6)
                        next_height = previous_height - 4'd1;
                    else
                        next_height = previous_height + 4'd1;
                end

                // Three choices: move downhill
                3'd3, 3'd4, 3'd5: begin
                    if (previous_height < 4'd12)
                        next_height = previous_height + 4'd1;
                    else
                        next_height = previous_height - 4'd1;
                end

                // Two choices: stay level
                default: begin
                    next_height = previous_height;
                end

            endcase
        end
    end

    // store one column's height per enabled clock

    always @ (posedge Clock) begin
        if (!Resetn) begin
            build_col <= 5'd0;
            previous_height <= 4'd9;
            ready <= 1'b0;
        end
        else if (Enable && !ready) begin
            heights[build_col] <= next_height;
            previous_height <= next_height;

            if (build_col == 5'd19) begin // done all columns
                ready <= 1'b1;
            end
            else begin
                build_col <= build_col + 5'd1; // increment next column
            end
        end
    end
endmodule
