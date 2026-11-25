
`default_nettype none

module crafting_ui (
    input wire clk,
    input wire resetn,

    // Rendering
    input wire start,
    input wire grant,
    output reg busy,

    // Crafting
    input wire [4:0] recipe_select,
    input wire [17:0] available_recipes,

    // Inventory
    input wire [44:0] slot_items,
    input wire [62:0] slot_counts,

    // VGA
    output wire [9:0] VGA_x,
    output wire [8:0] VGA_y,
    output wire [8:0] VGA_color,
    output wire VGA_write
);

    // UI POSITION AND DIMENSIONS

    localparam integer UI_WIDTH  = 477;
    localparam integer UI_HEIGHT = 450;

    localparam integer UI_X = 81;
    localparam integer UI_Y = 15;

    // 3x3 crafting grid
    localparam integer GRID_X = UI_X + 77;
    localparam integer GRID_Y = UI_Y + 43;
    localparam integer GRID_SLOT = 49;

    // crafting result
    localparam integer RESULT_X = UI_X + 323;
    localparam integer RESULT_Y = UI_Y + 82;
    localparam integer RESULT_SIZE = 70;

    // recipe list: 9 columns, 2 rows
    localparam integer RECIPE_X = UI_X + 18;
    localparam integer RECIPE_Y = UI_Y + 235;
    localparam integer RECIPE_SLOT = 49;

    // inventory: 9 slots
    localparam integer INV_X = UI_X + 18;
    localparam integer INV_Y = UI_Y + 381;
    localparam integer INV_SLOT = 49;


    // COLOURS

    localparam [8:0] OUTSIDE_COLOR = 9'b010_010_010;
    localparam [8:0] BG_COLOR      = 9'b110_110_110;
    localparam [8:0] SLOT_COLOR    = 9'b100_100_100;
    localparam [8:0] BORDER_LIGHT  = 9'b111_111_111;
    localparam [8:0] BORDER_DARK   = 9'b010_010_010;
    localparam [8:0] SELECT_COLOR  = 9'b111_111_000;
    localparam [8:0] ARROW_COLOR   = 9'b011_011_011;


    // PIXEL COUNTERS

    reg [9:0] px;
    reg [8:0] py;

    always @(posedge clk) begin

        if (!resetn) begin
            px <= 10'd0;
            py <= 9'd0;
            busy <= 1'b0;
        end

        else begin

            if (!busy) begin

                if (start && grant) begin
                    busy <= 1'b1;
                    px <= 10'd0;
                    py <= 9'd0;
                end

            end

            else if (grant) begin

                if (px == 10'd639) begin

                    px <= 10'd0;

                    if (py == 9'd479) begin
                        py <= 9'd0;
                        busy <= 1'b0;
                    end
                    else
                        py <= py + 1'b1;

                end
                else
                    px <= px + 1'b1;

            end
        end
    end


    // CRAFTING RECIPE LOOKUP

    wire [4:0] grid_item [0:8];
    wire [4:0] output_item;
    wire [6:0] output_count;

    genvar g;

    generate
        for (g = 0; g < 9; g = g + 1) begin: GRID_RECIPES

            crafting_recipes RECIPE (
                .recipe_id(recipe_select),
                .cell_index(g),
                .ingredient(grid_item[g]),
                .result_item(),
                .result_count()
            );

        end
    endgenerate

    crafting_recipes RESULT_RECIPE (
        .recipe_id(recipe_select),
        .cell_index(4'd0),
        .ingredient(),
        .result_item(output_item),
        .result_count(output_count)
    );

    // only display a recipe preview if it is available
    wire recipe_active =
        (recipe_select < 5'd18) &&
        available_recipes[recipe_select];


    // PIXEL CLASSIFICATION

    reg [8:0] base_color;
    reg [4:0] current_item;
    reg icon_pixel;

    reg [4:0] icon_x;
    reg [4:0] icon_y;

    integer row;
    integer col;
    integer slot_index;
    integer local_x;
    integer local_y;

    always @(*) begin

        // Default values
        base_color = OUTSIDE_COLOR;
        current_item = 5'd0;
        icon_pixel = 1'b0;

        icon_x = 5'd0;
        icon_y = 5'd0;

        row = 0;
        col = 0;
        slot_index = 0;
        local_x = 0;
        local_y = 0;


        // CRAFTING WINDOW BACKGROUND

        if (px >= UI_X && px < UI_X + UI_WIDTH &&
            py >= UI_Y && py < UI_Y + UI_HEIGHT) begin

            base_color = BG_COLOR;

            // Outer dark border
            if (px == UI_X || px == UI_X + UI_WIDTH - 1 ||
                py == UI_Y || py == UI_Y + UI_HEIGHT - 1)
                base_color = BORDER_DARK;

            // Inner white border
            if (px == UI_X + 1 ||
                px == UI_X + UI_WIDTH - 2 ||
                py == UI_Y + 1 ||
                py == UI_Y + UI_HEIGHT - 2)
                base_color = BORDER_LIGHT;

        end

        // 3x3 CRAFTING GRID

        for (row = 0; row < 3; row = row + 1) begin
            for (col = 0; col < 3; col = col + 1) begin

                if (px >= GRID_X + col*GRID_SLOT &&
                    px < GRID_X + (col+1)*GRID_SLOT &&
                    py >= GRID_Y + row*GRID_SLOT &&
                    py < GRID_Y + (row+1)*GRID_SLOT) begin

                    local_x = px - (GRID_X + col*GRID_SLOT);
                    local_y = py - (GRID_Y + row*GRID_SLOT);

                    slot_index = row*3 + col;

                    base_color = SLOT_COLOR;

                    if (local_x < 2 || local_y < 2)
                        base_color = BORDER_DARK;

                    if (local_x >= GRID_SLOT-2 ||
                        local_y >= GRID_SLOT-2)
                        base_color = BORDER_LIGHT;

                    // 32x32 ingredient texture
                    if (recipe_active &&
                        local_x >= 8 && local_x < 40 &&
                        local_y >= 8 && local_y < 40 &&
                        grid_item[slot_index] != 5'd0) begin

                        current_item = grid_item[slot_index];
                        icon_pixel = 1'b1;

                        icon_x = local_x - 8;
                        icon_y = local_y - 8;

                    end
                end
            end
        end

        // CRAFTING ARROW

        // Horizontal shaft
        if (px >= UI_X + 244 && px < UI_X + 282 &&
            py >= UI_Y + 107 && py < UI_Y + 115)
            base_color = ARROW_COLOR;

        // Arrowhead
        if (px >= UI_X + 276 && px < UI_X + 298 &&
            py >= UI_Y + 95 && py < UI_Y + 127) begin

            if ((px - (UI_X + 276)) >=
                ((py > UI_Y + 111) ?
                (py - (UI_Y + 111)) :
                ((UI_Y + 111) - py)))
                base_color = ARROW_COLOR;

        end


        // CRAFTING RESULT SLOT

        if (px >= RESULT_X &&
            px < RESULT_X + RESULT_SIZE &&
            py >= RESULT_Y &&
            py < RESULT_Y + RESULT_SIZE) begin

            local_x = px - RESULT_X;
            local_y = py - RESULT_Y;

            base_color = SLOT_COLOR;

            if (local_x < 2 || local_y < 2)
                base_color = BORDER_DARK;

            if (local_x >= RESULT_SIZE-2 ||
                local_y >= RESULT_SIZE-2)
                base_color = BORDER_LIGHT;

            if (recipe_active &&
                local_x >= 19 && local_x < 51 &&
                local_y >= 19 && local_y < 51 &&
                output_item != 5'd0) begin

                current_item = output_item;
                icon_pixel = 1'b1;

                icon_x = local_x - 19;
                icon_y = local_y - 19;

            end
        end

        // AVAILABLE RECIPES — 2 ROWS OF 9

        for (row = 0; row < 2; row = row + 1) begin
            for (col = 0; col < 9; col = col + 1) begin

                slot_index = row*9 + col;

                if (px >= RECIPE_X + col*RECIPE_SLOT &&
                    px < RECIPE_X + (col+1)*RECIPE_SLOT &&
                    py >= RECIPE_Y + row*RECIPE_SLOT &&
                    py < RECIPE_Y + (row+1)*RECIPE_SLOT) begin

                    local_x = px - (RECIPE_X + col*RECIPE_SLOT);
                    local_y = py - (RECIPE_Y + row*RECIPE_SLOT);

                    base_color = SLOT_COLOR;

                    if (local_x < 2 || local_y < 2)
                        base_color = BORDER_DARK;

                    if (local_x >= RECIPE_SLOT-2 ||
                        local_y >= RECIPE_SLOT-2)
                        base_color = BORDER_LIGHT;

                    // Highlight selected recipe
                    if (slot_index == recipe_select &&
                        available_recipes[slot_index] &&
                        (local_x < 3 || local_y < 3 ||
                         local_x >= RECIPE_SLOT-3 ||
                         local_y >= RECIPE_SLOT-3))
                        base_color = SELECT_COLOR;

                    // Only draw items for available recipes
                    if (available_recipes[slot_index] &&
                        local_x >= 8 && local_x < 40 &&
                        local_y >= 8 && local_y < 40) begin

                        if (slot_index == 0)
                            current_item = 5'd2;
                        else if (slot_index == 1)
                            current_item = 5'd3;
                        else
                            current_item = slot_index + 5;

                        icon_pixel = 1'b1;

                        icon_x = local_x - 8;
                        icon_y = local_y - 8;

                    end
                end
            end
        end

        // INVENTORY — 9 SLOTS

        for (col = 0; col < 9; col = col + 1) begin

            if (px >= INV_X + col*INV_SLOT &&
                px < INV_X + (col+1)*INV_SLOT &&
                py >= INV_Y &&
                py < INV_Y + INV_SLOT) begin

                local_x = px - (INV_X + col*INV_SLOT);
                local_y = py - INV_Y;

                base_color = SLOT_COLOR;

                if (local_x < 2 || local_y < 2)
                    base_color = BORDER_DARK;

                if (local_x >= INV_SLOT-2 ||
                    local_y >= INV_SLOT-2)
                    base_color = BORDER_LIGHT;

                // Item in this inventory slot
                if (local_x >= 8 && local_x < 40 &&
                    local_y >= 8 && local_y < 40) begin

                    current_item = slot_items[col*5 +: 5];

                    if (current_item != 5'd0) begin

                        icon_pixel = 1'b1;

                        icon_x = local_x - 8;
                        icon_y = local_y - 8;

                    end
                end
            end
        end

    end

    // TEXTURE MEMORIES

    wire [9:0] sprite_address = {icon_y, icon_x};

    wire [8:0] log_color, planks_color, stick_color;
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


    // SYNCHRONOUS ROM OUTPUT PIPELINE

    reg [9:0] delayed_x;
    reg [8:0] delayed_y;
    reg [8:0] delayed_base_color;
    reg [4:0] delayed_item;
    reg delayed_icon;
    reg delayed_write;

    always @(posedge clk) begin

        if (!resetn) begin
            delayed_x <= 10'd0;
            delayed_y <= 9'd0;
            delayed_base_color <= OUTSIDE_COLOR;
            delayed_item <= 5'd0;
            delayed_icon <= 1'b0;
            delayed_write <= 1'b0;
        end

        else begin
            delayed_x <= px;
            delayed_y <= py;

            delayed_base_color <= base_color;
            delayed_item <= current_item;
            delayed_icon <= icon_pixel;

            delayed_write <= busy && grant;
        end
    end


    // SELECT TEXTURE BASED ON ITEM ID

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

            default: sprite_color = SLOT_COLOR;

        endcase
    end

    // VGA OUTPUTS

    assign VGA_x = delayed_x;
    assign VGA_y = delayed_y;

    assign VGA_color = delayed_icon ?
                       sprite_color :
                       delayed_base_color;

    assign VGA_write = delayed_write;

endmodule

`default_nettype wire