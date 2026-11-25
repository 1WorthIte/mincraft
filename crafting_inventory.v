`default_nettype none
module crafting_inventory (
    input wire clk, resetn,
    input wire [4:0] recipe_select,
    input wire craft_pulse,
    input wire pickup_pulse,
    input wire [4:0] pickup_item,
    input wire [6:0] pickup_count,
    output reg pickup_accepted,
    output reg craft_accepted,
    output wire [17:0] available_recipes,
    output wire [44:0] slot_items,
    output wire [62:0] slot_counts,
    output wire [4:0] preview_item,
    output wire [6:0] preview_count,
    input wire [3:0] preview_cell,
    output wire [4:0] preview_ingredient
);

    reg [4:0] item_id [0:8];
    reg [6:0] item_count [0:8];

    // proposed inventory state
    reg [4:0] next_item [0:8];
    reg [6:0] next_count [0:8];

    // transaction variables
    reg commit;
    integer remaining;
    integer space;
    integer amount;

    genvar j;
    generate
        for (j = 0; j < 9; j = j + 1) begin: INVENTORY_OUTPUT
            assign slot_items[j*5 +: 5] = item_id[j];
            assign slot_counts[j*7 +: 7] = item_count[j];
        end
    endgenerate

    crafting_recipes PREVIEW (
        .recipe_id(recipe_select),
        .cell_index(preview_cell),
        .ingredient(preview_ingredient),
        .result_item(preview_item),
        .result_count(preview_count)
    );

    wire [4:0] recipe_ingredient [0:17][0:8];
    wire [4:0] recipe_output [0:17];
    wire [6:0] recipe_quantity [0:17];

    genvar r, c;
    generate
        for (r = 0; r < 18; r = r + 1) begin: RECIPE_LOOP
            for (c = 0; c < 9; c = c + 1) begin: CELL_LOOP
                crafting_recipes RECIPE (
                    .recipe_id(r),
                    .cell_index(c),
                    .ingredient(recipe_ingredient[r][c]),
                    .result_item(),
                    .result_count()
                );
            end
            crafting_recipes RECIPE_RESULT (
                .recipe_id(r),
                .cell_index(4'd0),
                .ingredient(),
                .result_item(recipe_output[r]),
                .result_count(recipe_quantity[r])
            );
        end
    endgenerate

    reg [17:0] available;
    assign available_recipes = available;

    integer a, b, d;
    integer required;
    integer owned;

    always @(*) begin

        available = 18'd0;
        required = 0;
        owned = 0;

        // check all 18 recipes
        for (a = 0; a < 18; a = a + 1) begin

            available[a] = 1'b1;

            // check each possible ingredient type
            for (b = 1; b <= 6; b = b + 1) begin

                required = 0;
                owned = 0;

                // count how many of this ingredient the recipe needs
                for (d = 0; d < 9; d = d + 1) begin
                    if (recipe_ingredient[a][d] == b)
                        required = required + 1;
                end

                // count how many the player owns
                for (d = 0; d < 9; d = d + 1) begin
                    if (item_id[d] == b)
                        owned = owned + item_count[d];
                end

                // insufficient ingredients
                if (owned < required)
                    available[a] = 1'b0;

            end
        end
    end

    integer k;

    integer m;
    integer needed;
    integer crafted_quantity;
    reg [4:0] crafted_item;

    always @(*) begin // copy the existing inventory
        for (k = 0; k < 9; k = k + 1) begin
            next_item[k] = item_id[k];
            next_count[k] = item_count[k];
        end

        commit = 1'b0;
        remaining = 0;
        space = 0;
        amount = 0;
        needed = 0;
        crafted_item = 5'd0;
        crafted_quantity = 0;

        // CRAFTING
        if (craft_pulse && recipe_select < 5'd18 && available_recipes[recipe_select]) begin

            // get the output from crafting_recipes
            crafted_item = recipe_output[recipe_select];
            crafted_quantity = recipe_quantity[recipe_select];

            // REMOVE INGREDIENTS

            // Check every possible ingredient ID (1-6)
            for (m = 1; m <= 6; m = m + 1) begin

                needed = 0;

                // count how many of this ingredient are required
                for (k = 0; k < 9; k = k + 1) begin
                    if (recipe_ingredient[recipe_select][k] == m)
                        needed = needed + 1;
                end

                // remove required items from inventory
                for (k = 0; k < 9; k = k + 1) begin

                    if (next_item[k] == m && needed > 0) begin

                        if (next_count[k] <= needed) begin
                            needed = needed - next_count[k];

                            next_item[k] = 5'd0;
                            next_count[k] = 7'd0;
                        end
                        else begin
                            next_count[k] = next_count[k] - needed;
                            needed = 0;
                        end

                    end
                end
            end

            // ADD CRAFTED ITEM

            remaining = crafted_quantity;

            // find existing stacks
            for (k = 0; k < 9; k = k + 1) begin

                if (next_item[k] == crafted_item && remaining > 0) begin

                    if (crafted_item >= 5'd7)
                        space = 1 - next_count[k];
                    else
                        space = 64 - next_count[k];

                    if (remaining < space)
                        amount = remaining;
                    else
                        amount = space;

                    next_count[k] = next_count[k] + amount;
                    remaining = remaining - amount;
                end
            end

            // find empty slots
            for (k = 0; k < 9; k = k + 1) begin

                if (next_item[k] == 5'd0 && remaining > 0) begin

                    if (crafted_item >= 5'd7)
                        space = 1;
                    else
                        space = 64;

                    if (remaining < space)
                        amount = remaining;
                    else
                        amount = space;

                    next_item[k] = crafted_item;
                    next_count[k] = amount;

                    remaining = remaining - amount;
                end
            end

            // only commit if the crafted item fits
            if (remaining == 0)
                commit = 1'b1;

        end

        else if (pickup_pulse && pickup_item != 5'd0 && pickup_count != 7'd0) begin
            remaining = pickup_count;

            // find existing stacks
            for (k = 0; k < 9; k = k + 1) begin

                if (next_item[k] == pickup_item && remaining > 0) begin
                    // tools stack to 1, materials to 64
                    if (pickup_item >= 5'd7)
                        space = 1 - next_count[k];
                    else
                        space = 64 - next_count[k];

                    // add as much as this slot can hold
                    if (remaining < space)
                        amount = remaining;
                    else
                        amount = space;

                    next_count[k] = next_count[k] + amount;
                    remaining = remaining - amount;
                end
            end
            // find empty slots
            for (k = 0; k < 9; k = k + 1) begin

                if (next_item[k] == 5'd0 && remaining > 0) begin

                    if (pickup_item >= 5'd7)
                        space = 1;
                    else
                        space = 64;

                    if (remaining < space)
                        amount = remaining;
                    else
                        amount = space;

                    next_item[k] = pickup_item;
                    next_count[k] = amount;

                    remaining = remaining - amount;

                end
            end
            // only accept if every item fits
            if (remaining == 0)
                commit = 1'b1;
        end
    end

    integer i;

    always @(posedge clk) begin
        if (!resetn) begin // empty all 9 slots

            for (i = 0; i < 9; i = i + 1) begin
                item_id[i] <= 5'd0;
                item_count[i] <= 7'd0;
            end

            pickup_accepted <= 1'b0;
            craft_accepted <= 1'b0;

        end
        else begin

            pickup_accepted <= 1'b0;
            craft_accepted <= 1'b0;

            if (commit) begin
                for (i = 0; i < 9; i = i + 1) begin
                    item_id[i] <= next_item[i];
                    item_count[i] <= next_count[i];
                end
                if (craft_pulse)
                    craft_accepted <= 1'b1;
                else if (pickup_pulse)
                    pickup_accepted <= 1'b1;
            end
        end
    end

endmodule
`default_nettype wire
