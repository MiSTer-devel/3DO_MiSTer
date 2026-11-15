// Light gun crosshair overlay.
// Draws a plus at the framebuffer pixel the light gun reports (HPS2PAD GUN_X,
// GUN_Y: 0..319 x 0..239), on the VE output. VE gives one DCLK per dot, 640
// dots (2 per framebuffer pixel) by 240 lines in the active window
// (HBLK_N & VBLK_N), in NTSC and PAL; the dots and lines are counted from the
// start of that window, so the plus lands on the pixel the counter encodes.
// The plus is white, with a black border one pixel wide so it shows on any
// picture. ARM is the length of each arm in pixels (not counting the centre).
// DRAW/COLOR are combinational from the counters for the dot being output on
// this DCLK, so they line up with RGB, HBLK_N and VBLK_N.
// GUN_X/GUN_Y come from the system clock domain; they are taken during
// vertical blanking, and only when two samples in a row agree.

module GUN_CROSS
(
	input            CLK,
	input            DCLK,
	input            HBLK_N,
	input            VBLK_N,

	input            EN,
	input            LARGE,
	input      [8:0] GUN_X,
	input      [8:0] GUN_Y,

	output           DRAW,
	output           COLOR    // 1 - white, 0 - black (border)
);

	reg  [17:0] pos_s1, pos_s2;
	reg  [ 8:0] cx, cy;
	reg  [ 9:0] dot;
	reg  [ 7:0] line;
	reg         line_act;
	always @(posedge CLK) begin
		pos_s1 <= {GUN_Y, GUN_X};
		pos_s2 <= pos_s1;
		if (!VBLK_N && pos_s1 == pos_s2) {cy, cx} <= pos_s2;

		if (DCLK) begin
			if (!VBLK_N) begin
				dot <= '0;
				line <= '0;
				line_act <= 0;
			end else if (HBLK_N) begin
				dot <= dot + 10'd1;
				line_act <= 1;
			end else if (line_act) begin
				dot <= '0;
				line <= line + 8'd1;
				line_act <= 0;
			end
		end
	end

	// distance from the centre in framebuffer pixels
	wire signed [10:0] dx = $signed({2'b00, dot[9:1]}) - $signed({2'b00, cx});
	wire signed [10:0] dy = $signed({3'b000, line}) - $signed({2'b00, cy});
	wire        [10:0] adx = dx[10] ? 11'(-dx) : dx;
	wire        [10:0] ady = dy[10] ? 11'(-dy) : dy;
	wire        [10:0] arm = LARGE ? 11'd8 : 11'd4;

	wire white  = (ady == 0 && adx <= arm) || (adx == 0 && ady <= arm);
	wire border = (ady <= 1 && adx <= arm + 11'd1) || (adx <= 1 && ady <= arm + 11'd1);

	assign DRAW  = EN && HBLK_N && VBLK_N && border;
	assign COLOR = white;

endmodule
