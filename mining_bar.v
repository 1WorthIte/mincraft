`default_nettype none

module mining_bar (
    input wire clk, resetn, grant, active,
    input wire [9:0] progress, required,
    output wire [9:0] x,
    output wire [8:0] y, color,
    output wire write
);
    localparam [9:0] BAR_X = 10'd496;
    localparam [8:0] BAR_Y = 9'd44;
    localparam [8:0] HUD_BACKGROUND = 9'h1BF; // sky color; adjust for HUD
    reg [6:0] px;
    reg [3:0] py;
    reg drawing;
    reg [9:0] displayed_progress, displayed_required;
    reg displayed_active;
    reg [9:0] pending_progress, pending_required;
    reg pending_active;
    reg [21:0] update_timer;

    wire active_now = active && (required != 10'd0);
    wire [9:0] progress_now = active_now ? progress : 10'd0;
    wire changed = (progress_now != displayed_progress) ||
                   (active_now != displayed_active) ||
                   (required != displayed_required);

    always @(posedge clk) begin
        if (!resetn) begin
            px <= 7'd0;
            py <= 4'd0;
            drawing <= 1'b0;
            displayed_progress <= 10'd0;
            displayed_required <= 10'd0;
            displayed_active <= 1'b0;
            pending_progress <= 10'd0;
            pending_required <= 10'd0;
            pending_active <= 1'b0;
            update_timer <= 22'd0;
        end else begin
            if (update_timer == 22'd2499999)
                update_timer <= 22'd0;
            else
                update_timer <= update_timer + 1'b1;

            if (!drawing) begin
                if (grant && changed && update_timer == 22'd0) begin
                    drawing <= 1'b1;
                    px <= 7'd0;
                    py <= 4'd0;
                    pending_progress <= progress_now;
                    pending_required <= required;
                    pending_active <= active_now;
                end
            end else if (grant) begin
                if (px == 7'd127) begin
                    px <= 7'd0;
                    if (py == 4'd9) begin
                        py <= 4'd0;
                        drawing <= 1'b0;
                        displayed_progress <= pending_progress;
                        displayed_required <= pending_required;
                        displayed_active <= pending_active;
                    end else
                        py <= py + 1'b1;
                end else
                    px <= px + 1'b1;
            end
        end
    end

    assign x = BAR_X + {3'd0, px};
    assign y = BAR_Y + {5'd0, py};

    // Avoid hardware division: compare cross-products at 20-bit precision.
    // Fill only interior pixels, keeping the white border intact.
    wire filled = pending_active && pending_required != 10'd0 &&
                  ({13'd0, px} * {10'd0, pending_required} <
                   {10'd0, pending_progress} * 20'd128);
    wire border = px == 7'd0 || px == 7'd127 || py == 4'd0 || py == 4'd9;
    assign color = !pending_active ? HUD_BACKGROUND :
                   border ? 9'b111_111_111 :
                   filled ? 9'b001_111_001 : 9'b010_010_010;
    assign write = drawing && grant;
endmodule

`default_nettype wire
