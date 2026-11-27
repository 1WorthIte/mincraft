`default_nettype none

// Restores the original background above the playable world (y = 0..159).
// The original 640x160 image uses only seven colours and is constant within
// every 4x4 square. Its 6400 three-bit palette entries fit in about 19 Kbits.
// Below y=160, world.v can redraw the current map over the original sky colour.
module background_restore (
    input wire clk,
    input wire resetn,
    input wire start,
    output reg busy,
    output wire [9:0] VGA_x,
    output wire [8:0] VGA_y,
    output reg [8:0] VGA_color,
    output wire VGA_write
);
    reg [2:0] palette [0:6399];
    initial $readmemh("./MIF/background_top_4x4.hex", palette);

    reg [9:0] px;
    reg [7:0] py; // Only 0..159 is restored here.

    // A row of the compressed image has 160 four-pixel-wide entries.
    wire [5:0] tile_row = py[7:2];
    wire [7:0] tile_col = px[9:2];
    wire [12:0] palette_address =
        ({7'd0, tile_row} << 7) +
        ({7'd0, tile_row} << 5) +
        {5'd0, tile_col};

    reg [2:0] palette_pixel;
    reg [9:0] delayed_x;
    reg [8:0] delayed_y;
    reg delayed_write;

    always @(posedge clk) begin
        if (!resetn) begin
            busy <= 1'b0;
            px <= 10'd0;
            py <= 8'd0;
            delayed_x <= 10'd0;
            delayed_y <= 9'd0;
            delayed_write <= 1'b0;
            palette_pixel <= 3'd0;
        end else begin
            // These registers line up coordinates and write enable with the
            // synchronous FPGA block-ROM lookup (one clock of latency).
            palette_pixel <= palette[palette_address];
            delayed_x <= px;
            delayed_y <= {1'b0, py};
            delayed_write <= busy;

            if (!busy) begin
                if (start) begin
                    busy <= 1'b1;
                    px <= 10'd0;
                    py <= 8'd0;
                end
            end else if (px == 10'd639) begin
                px <= 10'd0;
                if (py == 8'd159) begin
                    py <= 8'd0;
                    busy <= 1'b0;
                end else begin
                    py <= py + 1'b1;
                end
            end else begin
                px <= px + 1'b1;
            end
        end
    end

    always @(*) begin
        case (palette_pixel)
            3'd0: VGA_color = 9'h0EF;
            3'd1: VGA_color = 9'h1FF;
            3'd2: VGA_color = 9'h092;
            3'd3: VGA_color = 9'h137;
            3'd4: VGA_color = 9'h1BF;
            3'd5: VGA_color = 9'h177;
            3'd6: VGA_color = 9'h17F;
            default: VGA_color = 9'h1BF;
        endcase
    end

    assign VGA_x = delayed_x;
    assign VGA_y = delayed_y;
    assign VGA_write = delayed_write;
endmodule

`default_nettype wire
