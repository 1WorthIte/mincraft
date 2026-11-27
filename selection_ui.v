`default_nettype none

module selection_ui (
    input wire Clock,
    input wire Resetn,
    input wire start,

    input wire [9:0] player_x,
    input wire [8:0] player_y,
    input wire [3:0] selected_index,
    input wire show_outlines,

    output reg busy,

    output wire [9:0] VGA_x,
    output wire [8:0] VGA_y,
    output wire [8:0] VGA_color,
    output wire VGA_write
);

    // Which of the 10 surrounding blocks we're drawing
    reg [3:0] draw_index;

    // Which pixel inside the 32x32 block we're processing
    reg [9:0] pixel_index;

    wire [4:0] draw_col;
    wire [3:0] draw_row;
    wire draw_valid;

    // Reuse our existing selector to find each block
    block_selector UI_SELECTOR (
        .player_x(player_x),
        .player_y(player_y),
        .index(draw_index),

        .target_col(draw_col),
        .target_row(draw_row),
        .target_valid(draw_valid)
    );

    // A 32x32 block contains 1024 pixels.
    // The lower 5 bits represent X (0 to 31).
    // The upper 5 bits represent Y (0 to 31).
    wire [4:0] pixel_x = pixel_index[4:0];
    wire [4:0] pixel_y = pixel_index[9:5];

    // Convert block coordinates into VGA pixel coordinates
    assign VGA_x = {draw_col, 5'b0} + {5'b0, pixel_x};
    assign VGA_y = {draw_row, 5'b0} + {4'b0, pixel_y};

    // 1-pixel outline around a block
    wire thin_border =
        (pixel_x == 5'd0)  ||
        (pixel_x == 5'd31) ||
        (pixel_y == 5'd0)  ||
        (pixel_y == 5'd31);

    // 3-pixel outline for the currently selected block
    wire thick_border =
        (pixel_x <= 5'd2)  ||
        (pixel_x >= 5'd29) ||
        (pixel_y <= 5'd2)  ||
        (pixel_y >= 5'd29);

    wire is_selected = (draw_index == selected_index);

    // Yellow selected outline, black normal outline
    assign VGA_color = is_selected ? 9'b111_111_000 : 9'b000_000_000;

    // Only write pixels belonging to the outlines
    assign VGA_write = busy && draw_valid &&
                       (is_selected ? thick_border : (show_outlines && thin_border));

    // Drawing controller
    always @(posedge Clock) begin
        if (!Resetn) begin
            busy <= 1'b0;
            draw_index <= 4'd0;
            pixel_index <= 10'd0;
        end
        else if (!busy) begin
            if (start) begin
                busy <= 1'b1;
                draw_index <= 4'd0;
                pixel_index <= 10'd0;
            end
        end
        else begin
            // Finished processing one 32x32 block
            if (pixel_index == 10'd1023) begin
                pixel_index <= 10'd0;

                if (draw_index == ((player_x[4:0] != 5'd0) ? 4'd11 : 4'd9))
							busy <= 1'b0;
                else
                    draw_index <= draw_index + 1'b1;
            end
            else begin
                pixel_index <= pixel_index + 1'b1;
            end
        end
    end

endmodule

`default_nettype wire
