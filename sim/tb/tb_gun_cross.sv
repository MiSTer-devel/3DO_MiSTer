// Testbench for the light gun crosshair overlay (rtl/gun_cross.sv).
// The real HPS2PAD turns the aim into the gun pixel (system clock), the real
// VE makes the video timing (video clock), and GUN_CROSS draws on it. The
// testbench counts the active dots and lines itself from VE's HBLK_N/VBLK_N
// and DCLK, captures a whole frame of DRAW/COLOR and compares it, dot by dot,
// with the plus expected at the pixel Main_MiSTer's aim maps to, in NTSC and
// PAL, small and large, at the corners (clipped), the middle and elsewhere.
// It also checks nothing is drawn outside the active window or when the
// overlay is off, and that a new aim is taken only between frames.
// Run: sim/run_tb.sh tb_gun_cross

`timescale 1ns/1ps

module tb_gun_cross;

	reg         CLK = 0;     // system clock, HPS2PAD
	reg         VCLK = 0;    // video clock, VE and GUN_CROSS
	reg         RST = 1;
	reg         CE = 0;

	reg         PAL = 0;
	reg  [ 1:0] GUN_SEL = 1;
	reg  [ 7:0] joy0_x0 = 0, joy0_y0 = 0;
	reg         EN = 1;
	reg         LARGE = 0;

	wire [ 8:0] GUN_X, GUN_Y;
	wire        GUN_ON;

	wire [23:0] RGB;
	wire        HS_N, VS_N, HBLK_N, VBLK_N, DCLK;
	wire        DRAW, COLOR;

	integer errors = 0;
	integer checks = 0;

	always #5 CLK = ~CLK;
	always #6.17 VCLK = ~VCLK;
	always @(posedge CLK) CE <= ~CE;

	HPS2PAD pad
	(
		.CLK(CLK),
		.RST(RST),
		.CE(CE),

		.PBDIN(),
		.PBDOUT(1'b1),
		.PBCLK(1'b0),

		.EXPBDIN(1'b1),
		.EXPBDOUT(),

		.PAD_SEL(3'd0),
		.ARCADE_SEL(2'd0),
		.STICK_EN(1'b0),
		.MOUSE_EN(1'b0),
		.GUN_SEL(GUN_SEL),
		.GUN_PAL(PAL),
		.ARCADE_SERVICE(1'b0),

		.joystick_0(13'd0),
		.joystick_1(13'd0),
		.joystick_2(13'd0),
		.joystick_3(13'd0),
		.joy0_x0(joy0_x0),
		.joy0_y0(joy0_y0),
		.joy0_x1(8'd0),
		.joy0_y1(8'd0),
		.joy1_x0(8'd0),
		.joy1_y0(8'd0),
		.joy1_x1(8'd0),
		.joy1_y1(8'd0),
		.ps2_mouse(25'd0),

		.GUN_X(GUN_X),
		.GUN_Y(GUN_Y),
		.GUN_ON(GUN_ON)
	);

	VE ve
	(
		.MCLK(CLK),
		.VCLK(VCLK),
		.RST_N(~RST),
		.EN(1'b1),

		.PAL(PAL),

		.VCE(1'b0),
		.AD(24'd0),
		.DE(1'b0),
		.HSYNC_N(),
		.VSYNC_N(),

		.RGB(RGB),
		.HS_N(HS_N),
		.VS_N(VS_N),
		.HBLK_N(HBLK_N),
		.VBLK_N(VBLK_N),
		.DCLK(DCLK),

		.DBG_EXT(8'hFF),
		.DBG_BORD_DIS(1'b1),
		.DBG_HS_START(),
		.DBG_HS_END()
	);

	GUN_CROSS dut
	(
		.CLK(VCLK),
		.DCLK(DCLK),
		.HBLK_N(HBLK_N),
		.VBLK_N(VBLK_N),

		.EN(EN && GUN_ON),
		.LARGE(LARGE),
		.GUN_X(GUN_X),
		.GUN_Y(GUN_Y),

		.DRAW(DRAW),
		.COLOR(COLOR)
	);

	// capture of the last frame: 0 nothing, 1 black, 2 white
	reg  [1:0] cap [0:239][0:639];
	integer    cap_lines, cap_bad_dots, cap_outside;
	integer    tb_dot, tb_line;
	reg        tb_line_act;
	reg        capturing = 0;
	event      frame_done;

	// the testbench's own count of the active window from VE's outputs
	always @(posedge VCLK) begin
		if (DCLK) begin
			if (!VBLK_N) begin
				if (capturing && tb_line > 0) begin
					capturing = 0;
					cap_lines = tb_line;
					-> frame_done;
				end
				tb_dot = 0;
				tb_line = 0;
				tb_line_act = 0;
				if (DRAW) cap_outside = cap_outside + 1;
			end else if (HBLK_N) begin
				if (capturing && tb_line < 240 && tb_dot < 640)
					cap[tb_line][tb_dot] = DRAW ? (COLOR ? 2'd2 : 2'd1) : 2'd0;
				tb_dot = tb_dot + 1;
				tb_line_act = 1;
			end else begin
				if (DRAW) cap_outside = cap_outside + 1;
				if (tb_line_act) begin
					if (capturing && tb_dot != 640) cap_bad_dots = cap_bad_dots + 1;
					tb_dot = 0;
					tb_line = tb_line + 1;
					tb_line_act = 0;
				end
			end
		end
	end

	// the next whole frame (from the start of its active window)
	task automatic grab;
		integer l, d;
		begin
			@(posedge VBLK_N);
			for (l = 0; l < 240; l = l + 1)
				for (d = 0; d < 640; d = d + 1)
					cap[l][d] = 2'd3;
			cap_lines = 0;
			cap_bad_dots = 0;
			cap_outside = 0;
			capturing = 1;
			@(frame_done);
		end
	endtask

	// Main_MiSTer aim -127..+127 to the framebuffer pixel, nearest
	function automatic integer ref_px(input integer a, input integer last);
		real t;
		begin
			if (a < -127) a = -127;
			t = (a + 127) * last / 254.0;
			ref_px = $rtoi(t + 0.5);
		end
	endfunction

	// expected overlay at a dot: a plus of 1 pixel lines, ARM pixels each way
	// from the centre pixel, white, inside a black border 1 pixel wide
	function automatic [1:0] ref_dot(input integer line, input integer dot, input integer cx, input integer cy, input integer arm);
		integer px, ax, ay;
		begin
			px = dot / 2;
			ax = px > cx ? px - cx : cx - px;
			ay = line > cy ? line - cy : cy - line;
			if ((ay == 0 && ax <= arm) || (ax == 0 && ay <= arm))
				ref_dot = 2'd2;
			else if ((ay <= 1 && ax <= arm + 1) || (ax <= 1 && ay <= arm + 1))
				ref_dot = 2'd1;
			else
				ref_dot = 2'd0;
		end
	endfunction

	task automatic check_frame(input integer cx, input integer cy, input integer arm, input [255:0] name);
		integer l, d, bad, n;
		reg [1:0] e;
		begin
			bad = 0;
			n = 0;
			checks = checks + 1;
			if (cap_lines !== 240 || cap_bad_dots !== 0) begin
				errors = errors + 1;
				$display("FAIL %0s pal=%0d: window %0d lines, %0d lines not 640 dots", name, PAL, cap_lines, cap_bad_dots);
			end
			checks = checks + 1;
			if (cap_outside !== 0) begin
				errors = errors + 1;
				$display("FAIL %0s pal=%0d: %0d dots drawn outside the window", name, PAL, cap_outside);
			end
			for (l = 0; l < 240; l = l + 1)
				for (d = 0; d < 640; d = d + 1) begin
					e = arm < 0 ? 2'd0 : ref_dot(l, d, cx, cy, arm);
					if (e == 2'd2) n = n + 1;
					checks = checks + 1;
					if (cap[l][d] !== e) begin
						bad = bad + 1;
						if (bad <= 5) $display("FAIL %0s pal=%0d: line %0d dot %0d is %0d expected %0d", name, PAL, l, d, cap[l][d], e);
					end
				end
			if (bad) errors = errors + 1;
			// the centre pixel is lit (both of its dots) when the overlay is on
			if (arm >= 0) begin
				checks = checks + 1;
				if (cap[cy][2*cx] !== 2'd2 || cap[cy][2*cx+1] !== 2'd2) begin
					errors = errors + 1;
					$display("FAIL %0s pal=%0d: centre %0d,%0d not white", name, PAL, cx, cy);
				end
			end
		end
	endtask

	// aim, let the position reach the video side (taken in vertical blank), then
	// check a whole frame
	task automatic aim_check(input integer ax, input integer ay, input [255:0] name);
		integer arm;
		begin
			joy0_x0 = ax;
			joy0_y0 = ay;
			arm = !EN || !GUN_ON ? -1 : LARGE ? 8 : 4;
			@(negedge VBLK_N);
			grab();
			check_frame(ref_px(ax, 319), ref_px(ay, 239), arm, name);
		end
	endtask

	integer pal, sz, i, x0, y0, l, d, frames;
	reg changed_mid;
	initial begin
		repeat (20) @(posedge CLK);
		RST = 0;
		repeat (20) @(posedge CLK);

		for (pal = 0; pal < 2; pal = pal + 1) begin
			PAL = pal[0];
			// VE's PAL input is synchronised; give it a frame to settle
			@(negedge VBLK_N);
			for (sz = 0; sz < 2; sz = sz + 1) begin
				LARGE = sz[0];
				aim_check(-127, -127, "top left");
				aim_check( 127, -127, "top right");
				aim_check(-127,  127, "bottom left");
				aim_check( 127,  127, "bottom right");
				aim_check(   0,    0, "middle");
				aim_check(-128, -128, "clamped top left");
				aim_check(  72,  -51, "aim 72,-51");
				aim_check(-118,  100, "aim -118,100");
				aim_check(-124,  125, "near bottom left");
				$display("pal=%0d large=%0d done, errors=%0d", pal, sz, errors);
			end
		end
		PAL = 0;
		LARGE = 0;
		@(negedge VBLK_N);

		// off: nothing drawn
		EN = 0;
		aim_check(0, 0, "overlay off");
		EN = 1;
		// gun not selected: nothing drawn
		GUN_SEL = 0;
		aim_check(0, 0, "gun off");
		GUN_SEL = 1;
		aim_check(0, 0, "gun back on");

		// an aim change in the middle of a frame shows from the next frame, whole
		joy0_x0 = -60;
		joy0_y0 = -60;
		@(negedge VBLK_N);
		@(negedge VBLK_N);
		for (i = 0; i < 4; i = i + 1) begin
			fork
				grab();
				begin
					wait (tb_line == 60 + 40 * i);
					joy0_x0 = (i[0] ? -60 : 90);
					joy0_y0 = (i[0] ? -60 : 50);
				end
			join
			// the frame being changed keeps the position it started with
			check_frame(ref_px(i[0] ? 90 : -60, 319), ref_px(i[0] ? 50 : -60, 239), 4, "frame during change");
			grab();
			check_frame(ref_px(i[0] ? -60 : 90, 319), ref_px(i[0] ? -60 : 50, 239), 4, "frame after change");
		end

		$display("checks=%0d errors=%0d", checks, errors);
		if (errors == 0) $display("TEST PASSED");
		else $display("TEST FAILED");
		$finish;
	end

	initial begin
		repeat (8) #1000000000;
		$display("TIMEOUT");
		$finish;
	end

endmodule
