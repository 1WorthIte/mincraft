`default_nettype none

// draws nine 32x32 item icons at (318 + (32 + 4)*slot, 4).
module hotbar_ui (
    input wire clk,
    input wire resetn,
    input wire start,
    input wire grant,
    input wire [44:0] slot_items,
	 input wire [3:0] selected_slot,
	 
    output reg busy,
    output wire [9:0] VGA_x,
    output wire [8:0] VGA_y,
    output wire [8:0] VGA_color,
    output wire VGA_write
);
    localparam [9:0] FIRST_ICON_X = 10'd316;
    localparam [8:0] FIRST_ICON_Y = 9'd4;
    localparam [9:0] ICON_PITCH = 10'd36;

    reg [44:0] latched_items;
	 reg [3:0] latched_selected_slot;
    reg [3:0] slot_index;
    reg [9:0] pixel_index;

    wire [4:0] icon_x = pixel_index[4:0];
    wire [4:0] icon_y = pixel_index[9:5];
    wire [9:0] draw_x = FIRST_ICON_X + slot_index * ICON_PITCH + {5'd0, icon_x};
    wire [8:0] draw_y = FIRST_ICON_Y + {4'd0, icon_y};
    wire [4:0] current_item = latched_items[slot_index*5 +: 5];

    reg [2:0] background_palette [0:6399];
    initial $readmemh("./MIF/background_top_4x4.hex", background_palette);
    wire [5:0] background_row = draw_y[7:2];
    wire [7:0] background_col = draw_x[9:2];
    wire [12:0] background_address =
        ({7'd0, background_row} << 7) +
        ({7'd0, background_row} << 5) +
        {5'd0, background_col};
    reg [2:0] background_index;
    reg [8:0] background_color;

    always @(*) begin
        case (background_index)
            3'd0: background_color = 9'h0EF;
            3'd1: background_color = 9'h1FF;
            3'd2: background_color = 9'h092;
            3'd3: background_color = 9'h137;
            3'd4: background_color = 9'h1BF;
            3'd5: background_color = 9'h177;
            3'd6: background_color = 9'h17F;
            default: background_color = 9'h1BF;
        endcase
    end

    // TEXTURE MEMORIES

    wire [9:0] sprite_address = {icon_y, icon_x};

    wire [8:0] dirt_color, log_color, planks_color, stick_color;
    wire [8:0] cobble_color, iron_color, diamond_color;

    wire [8:0] wooden_pick_color, wooden_axe_color;
    wire [8:0] wooden_shovel_color, wooden_sword_color;

    wire [8:0] stone_pick_color, stone_axe_color;
    wire [8:0] stone_shovel_color, stone_sword_color;

    wire [8:0] iron_pick_color, iron_axe_color;
    wire [8:0] iron_shovel_color, iron_sword_color;

    wire [8:0] diamond_pick_color, diamond_axe_color;
    wire [8:0] diamond_shovel_color, diamond_sword_color;


    // materials

    object_mem LOG_ROM (sprite_address, clk, log_color);
        defparam LOG_ROM.n = 9;
        defparam LOG_ROM.Mn = 10;
        defparam LOG_ROM.INIT_FILE = "./MIF/log.mif";
		  
	 object_mem DIRT_ROM (sprite_address, clk, dirt_color);
		  defparam DIRT_ROM.n = 9;
		  defparam DIRT_ROM.Mn = 10;
		  defparam DIRT_ROM.INIT_FILE = "./MIF/dirt.mif";

    object_mem PLANKS_ROM (sprite_address, clk, planks_color);
        defparam PLANKS_ROM.n = 9;
        defparam PLANKS_ROM.Mn = 10;
        defparam PLANKS_ROM.INIT_FILE = "./MIF/planks.mif";

    object_mem STICK_ROM (sprite_address, clk, stick_color);
        defparam STICK_ROM.n = 9;
        defparam STICK_ROM.Mn = 10;
        defparam STICK_ROM.INIT_FILE = "./MIF/stick.mif";

    object_mem COBBLE_ROM (sprite_address, clk, cobble_color);
        defparam COBBLE_ROM.n = 9;
        defparam COBBLE_ROM.Mn = 10;
        defparam COBBLE_ROM.INIT_FILE = "./MIF/cobblestone.mif";

    object_mem IRON_ROM (sprite_address, clk, iron_color);
        defparam IRON_ROM.n = 9;
        defparam IRON_ROM.Mn = 10;
        defparam IRON_ROM.INIT_FILE = "./MIF/iron-ore.mif";

    object_mem DIAMOND_ROM (sprite_address, clk, diamond_color);
        defparam DIAMOND_ROM.n = 9;
        defparam DIAMOND_ROM.Mn = 10;
        defparam DIAMOND_ROM.INIT_FILE = "./MIF/diamond-ore.mif";


    // wooden tools

    object_mem WOOD_PICK_ROM (sprite_address, clk, wooden_pick_color);
        defparam WOOD_PICK_ROM.n = 9;
        defparam WOOD_PICK_ROM.Mn = 10;
        defparam WOOD_PICK_ROM.INIT_FILE = "./MIF/wooden-pick.mif";

    object_mem WOOD_AXE_ROM (sprite_address, clk, wooden_axe_color);
        defparam WOOD_AXE_ROM.n = 9;
        defparam WOOD_AXE_ROM.Mn = 10;
        defparam WOOD_AXE_ROM.INIT_FILE = "./MIF/wooden-axe.mif";

    object_mem WOOD_SHOVEL_ROM (sprite_address, clk, wooden_shovel_color);
        defparam WOOD_SHOVEL_ROM.n = 9;
        defparam WOOD_SHOVEL_ROM.Mn = 10;
        defparam WOOD_SHOVEL_ROM.INIT_FILE = "./MIF/wooden-shovel.mif";

    object_mem WOOD_SWORD_ROM (sprite_address, clk, wooden_sword_color);
        defparam WOOD_SWORD_ROM.n = 9;
        defparam WOOD_SWORD_ROM.Mn = 10;
        defparam WOOD_SWORD_ROM.INIT_FILE = "./MIF/wooden-sword.mif";


    // stone tools

    object_mem STONE_PICK_ROM (sprite_address, clk, stone_pick_color);
        defparam STONE_PICK_ROM.n = 9;
        defparam STONE_PICK_ROM.Mn = 10;
        defparam STONE_PICK_ROM.INIT_FILE = "./MIF/stone-pick.mif";

    object_mem STONE_AXE_ROM (sprite_address, clk, stone_axe_color);
        defparam STONE_AXE_ROM.n = 9;
        defparam STONE_AXE_ROM.Mn = 10;
        defparam STONE_AXE_ROM.INIT_FILE = "./MIF/stone-axe.mif";

    object_mem STONE_SHOVEL_ROM (sprite_address, clk, stone_shovel_color);
        defparam STONE_SHOVEL_ROM.n = 9;
        defparam STONE_SHOVEL_ROM.Mn = 10;
        defparam STONE_SHOVEL_ROM.INIT_FILE = "./MIF/stone-shovel.mif";

    object_mem STONE_SWORD_ROM (sprite_address, clk, stone_sword_color);
        defparam STONE_SWORD_ROM.n = 9;
        defparam STONE_SWORD_ROM.Mn = 10;
        defparam STONE_SWORD_ROM.INIT_FILE = "./MIF/stone-sword.mif";


    // iron tools

    object_mem IRON_PICK_ROM (sprite_address, clk, iron_pick_color);
        defparam IRON_PICK_ROM.n = 9;
        defparam IRON_PICK_ROM.Mn = 10;
        defparam IRON_PICK_ROM.INIT_FILE = "./MIF/iron-pick.mif";

    object_mem IRON_AXE_ROM (sprite_address, clk, iron_axe_color);
        defparam IRON_AXE_ROM.n = 9;
        defparam IRON_AXE_ROM.Mn = 10;
        defparam IRON_AXE_ROM.INIT_FILE = "./MIF/iron-axe.mif";

    object_mem IRON_SHOVEL_ROM (sprite_address, clk, iron_shovel_color);
        defparam IRON_SHOVEL_ROM.n = 9;
        defparam IRON_SHOVEL_ROM.Mn = 10;
        defparam IRON_SHOVEL_ROM.INIT_FILE = "./MIF/iron-shovel.mif";

    object_mem IRON_SWORD_ROM (sprite_address, clk, iron_sword_color);
        defparam IRON_SWORD_ROM.n = 9;
        defparam IRON_SWORD_ROM.Mn = 10;
        defparam IRON_SWORD_ROM.INIT_FILE = "./MIF/iron-sword.mif";


    // diamond tools

    object_mem DIAMOND_PICK_ROM (sprite_address, clk, diamond_pick_color);
        defparam DIAMOND_PICK_ROM.n = 9;
        defparam DIAMOND_PICK_ROM.Mn = 10;
        defparam DIAMOND_PICK_ROM.INIT_FILE = "./MIF/diamond-pick.mif";

    object_mem DIAMOND_AXE_ROM (sprite_address, clk, diamond_axe_color);
        defparam DIAMOND_AXE_ROM.n = 9;
        defparam DIAMOND_AXE_ROM.Mn = 10;
        defparam DIAMOND_AXE_ROM.INIT_FILE = "./MIF/diamond-axe.mif";

    object_mem DIAMOND_SHOVEL_ROM (sprite_address, clk, diamond_shovel_color);
        defparam DIAMOND_SHOVEL_ROM.n = 9;
        defparam DIAMOND_SHOVEL_ROM.Mn = 10;
        defparam DIAMOND_SHOVEL_ROM.INIT_FILE = "./MIF/diamond-shovel.mif";

    object_mem DIAMOND_SWORD_ROM (sprite_address, clk, diamond_sword_color);
        defparam DIAMOND_SWORD_ROM.n = 9;
        defparam DIAMOND_SWORD_ROM.Mn = 10;
        defparam DIAMOND_SWORD_ROM.INIT_FILE = "./MIF/diamond-sword.mif";

    // Align VGA coordinates, item ID, and write-enable with synchronous ROMs.
    reg [9:0] delayed_x;
    reg [8:0] delayed_y;
    reg [4:0] delayed_item;
    reg delayed_write;
	 reg delayed_selected_border;
	 
	 wire selected_border = (slot_index == latched_selected_slot) && (icon_x <= 5'd1 || icon_x >= 5'd30 || icon_y <= 5'd1 || icon_y >= 5'd30);

    always @(posedge clk) begin
        if (!resetn) begin
            latched_items <= 45'd0;
            slot_index <= 4'd0;
            pixel_index <= 10'd0;
            busy <= 1'b0;
            delayed_x <= 10'd0;
            delayed_y <= 9'd0;
            delayed_item <= 5'd0;
            delayed_write <= 1'b0;
				delayed_selected_border <= 1'b0;
            background_index <= 3'd0;
				latched_selected_slot <= 4'd0;
        end else begin
            background_index <= background_palette[background_address];
            delayed_x <= draw_x;
            delayed_y <= draw_y;
            delayed_item <= current_item;
            delayed_write <= busy && grant;
				delayed_selected_border <= selected_border;

            if (!busy) begin
                if (start && grant) begin
                    latched_items <= slot_items;
						  latched_selected_slot <= selected_slot;
                    slot_index <= 4'd0;
                    pixel_index <= 10'd0;
                    busy <= 1'b1;
                end
            end else if (grant) begin
                if (pixel_index == 10'd1023) begin
                    pixel_index <= 10'd0;
                    if (slot_index == 4'd8)
                        busy <= 1'b0;
                    else
                        slot_index <= slot_index + 1'b1;
                end else begin
                    pixel_index <= pixel_index + 1'b1;
                end
            end
        end
    end

    reg [8:0] sprite_color;

    always @(*) begin

        case (delayed_item)

            5'd1:  sprite_color = log_color;
            5'd2:  sprite_color = planks_color;
            5'd3:  sprite_color = stick_color;
            5'd4:  sprite_color = cobble_color;
            5'd5:  sprite_color = iron_color;
            5'd6:  sprite_color = diamond_color;

            5'd7:  sprite_color = wooden_pick_color;
            5'd8:  sprite_color = wooden_axe_color;
            5'd9:  sprite_color = wooden_shovel_color;
            5'd10: sprite_color = wooden_sword_color;

            5'd11: sprite_color = stone_pick_color;
            5'd12: sprite_color = stone_axe_color;
            5'd13: sprite_color = stone_shovel_color;
            5'd14: sprite_color = stone_sword_color;

            5'd15: sprite_color = iron_pick_color;
            5'd16: sprite_color = iron_axe_color;
            5'd17: sprite_color = iron_shovel_color;
            5'd18: sprite_color = iron_sword_color;

            5'd19: sprite_color = diamond_pick_color;
            5'd20: sprite_color = diamond_axe_color;
            5'd21: sprite_color = diamond_shovel_color;
            5'd22: sprite_color = diamond_sword_color;
				5'd23: sprite_color = dirt_color;

            default: sprite_color = background_color;

        endcase
    end

    assign VGA_x = delayed_x;
    assign VGA_y = delayed_y;
    assign VGA_color = delayed_selected_border ? 9'b111_111_000 : 
	 (delayed_item == 5'd0 || 
	 ((delayed_item == 5'd3 ||
	 (delayed_item >= 5'd7 && delayed_item <= 5'd22)) &&
	 sprite_color == 9'h1FF)) ? background_color : sprite_color;
    assign VGA_write = delayed_write;
endmodule

`default_nettype wire

