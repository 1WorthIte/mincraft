`default_nettype none

/*
RECIPE ID | ITEM ID | ITEM
-------------------------------
    0     |    2    | Planks
    1     |    3    | Sticks
    2     |    7    | Wooden Pickaxe
    3     |    8    | Wooden Axe
    4     |    9    | Wooden Shovel
    5     |   10    | Wooden Sword
    6     |   11    | Stone Pickaxe
    7     |   12    | Stone Axe
    8     |   13    | Stone Shovel
    9     |   14    | Stone Sword
   10     |   15    | Iron Pickaxe
   11     |   16    | Iron Axe
   12     |   17    | Iron Shovel
   13     |   18    | Iron Sword
   14     |   19    | Diamond Pickaxe
   15     |   20    | Diamond Axe
   16     |   21    | Diamond Shovel
   17     |   22    | Diamond Sword

OTHER ITEM IDs
-------------------------------
    0     | Empty
    1     | Log
    4     | Cobblestone
    5     | Iron Ore
    6     | Diamond
*/

module crafting_recipes (
    input wire [4:0] recipe_id,
    input wire [3:0] cell_index,

    output reg [4:0] ingredient,
    output reg [4:0] result_item,
    output reg [6:0] result_count
);

    always @(*) begin
        ingredient = 5'd0;
        result_item = 5'd0;
        result_count = 7'd0;

        case (recipe_id)

            5'd0: begin
                result_item = 5'd2;
                result_count = 7'd4;

                if (cell_index == 4'd0)
                    ingredient = 5'd1;
            end
            
            5'd1: begin
                result_item = 5'd3;
                result_count = 7'd4;

                if (cell_index == 4'd0 || cell_index == 4'd3)
                    ingredient = 5'd2;
            end

            5'd2: begin
                result_item = 5'd7;
                result_count = 7'd1;

                if (cell_index == 4'd0 || cell_index == 4'd1 || cell_index == 4'd2)
                    ingredient = 5'd2;
                if (cell_index == 4'd4 || cell_index == 4'd7)
                    ingredient = 5'd3;
            end

            5'd3: begin
                result_item = 5'd8;
                result_count = 7'd1;

                if (cell_index == 4'd0 || cell_index == 4'd1 || cell_index == 4'd3)
                    ingredient = 5'd2;
                if (cell_index == 4'd4 || cell_index == 4'd7)
                    ingredient = 5'd3;
            end

            5'd4: begin
                result_item = 5'd9;
                result_count = 7'd1;

                if (cell_index == 4'd1)
                    ingredient = 5'd2;
                if (cell_index == 4'd4 || cell_index == 4'd7)
                    ingredient = 5'd3;
            end

            5'd5: begin
                result_item = 5'd10;
                result_count = 7'd1;

                if (cell_index == 4'd1 || cell_index == 4'd4)
                    ingredient = 5'd2;
                if (cell_index == 4'd7)
                    ingredient = 5'd3;
            end

            5'd6: begin
                result_item = 5'd11;
                result_count = 7'd1;

                if (cell_index == 4'd0 || cell_index == 4'd1 || cell_index == 4'd2)
                    ingredient = 5'd4;
                if (cell_index == 4'd4 || cell_index == 4'd7)
                    ingredient = 5'd3;
            end

            5'd7: begin
                result_item = 5'd12;
                result_count = 7'd1;

                if (cell_index == 4'd0 || cell_index == 4'd1 || cell_index == 4'd3)
                    ingredient = 5'd4;
                if (cell_index == 4'd4 || cell_index == 4'd7)
                    ingredient = 5'd3;
            end

            5'd8: begin
                result_item = 5'd13;
                result_count = 7'd1;

                if (cell_index == 4'd1)
                    ingredient = 5'd4;
                if (cell_index == 4'd4 || cell_index == 4'd7)
                    ingredient = 5'd3;
            end

            5'd9: begin
                result_item = 5'd14;
                result_count = 7'd1;

                if (cell_index == 4'd1 || cell_index == 4'd4)
                    ingredient = 5'd4;
                if (cell_index == 4'd7)
                    ingredient = 5'd3;
            end

            5'd10: begin
                result_item = 5'd15;
                result_count = 7'd1;

                if (cell_index == 4'd0 || cell_index == 4'd1 || cell_index == 4'd2)
                    ingredient = 5'd5;
                if (cell_index == 4'd4 || cell_index == 4'd7)
                    ingredient = 5'd3;
            end

            5'd11: begin
                result_item = 5'd16;
                result_count = 7'd1;

                if (cell_index == 4'd0 || cell_index == 4'd1 || cell_index == 4'd3)
                    ingredient = 5'd5;
                if (cell_index == 4'd4 || cell_index == 4'd7)
                    ingredient = 5'd3;
            end

            5'd12: begin
                result_item = 5'd17;
                result_count = 7'd1;

                if (cell_index == 4'd1)
                    ingredient = 5'd5;
                if (cell_index == 4'd4 || cell_index == 4'd7)
                    ingredient = 5'd3;
            end

            5'd13: begin
                result_item = 5'd18;
                result_count = 7'd1;

                if (cell_index == 4'd1 || cell_index == 4'd4)
                    ingredient = 5'd5;
                if (cell_index == 4'd7)
                    ingredient = 5'd3;
            end

            5'd14: begin
                result_item = 5'd19;
                result_count = 7'd1;

                if (cell_index == 4'd0 || cell_index == 4'd1 || cell_index == 4'd2)
                    ingredient = 5'd6;
                if (cell_index == 4'd4 || cell_index == 4'd7)
                    ingredient = 5'd3;
            end

            5'd15: begin
                result_item = 5'd20;
                result_count = 7'd1;

                if (cell_index == 4'd0 || cell_index == 4'd1 || cell_index == 4'd3)
                    ingredient = 5'd6;
                if (cell_index == 4'd4 || cell_index == 4'd7)
                    ingredient = 5'd3;
            end

            5'd16: begin
                result_item = 5'd21;
                result_count = 7'd1;

                if (cell_index == 4'd1)
                    ingredient = 5'd6;
                if (cell_index == 4'd4 || cell_index == 4'd7)
                    ingredient = 5'd3;
            end

            5'd17: begin
                result_item = 5'd22;
                result_count = 7'd1;

                if (cell_index == 4'd1 || cell_index == 4'd4)
                    ingredient = 5'd6;
                if (cell_index == 4'd7)
                    ingredient = 5'd3;
            end

            default: begin
                // Invalid recipe
            end

        endcase
    end

endmodule
`default_nettype wire
