module HPS2PAD (
	input              CLK,
	input              RST,
	input              CE,
	
	output reg         PBDIN,
	input              PBDOUT,
	input              PBCLK,
	
	input              EXPBDIN,
	output reg         EXPBDOUT,
	
	input      [ 2: 0] PAD_SEL,
	input      [ 1: 0] ARCADE_SEL,
	input              STICK_EN,
	input              MOUSE_EN,
	input      [ 1: 0] GUN_SEL,        //0 - off, 1 - gun on joystick 0, 2 - gun on joystick 1
	input              GUN_PAL,        //PAL scan constants for the light gun
	input              ARCADE_SERVICE,
	
	input      [12: 0] joystick_0,
	input      [12: 0] joystick_1,
	input      [12: 0] joystick_2,
	input      [12: 0] joystick_3,
	input      [7 : 0] joy0_x0,
	input      [7 : 0] joy0_y0,
	input      [7 : 0] joy0_x1,
	input      [7 : 0] joy0_y1,
	input      [7 : 0] joy1_x0,
	input      [7 : 0] joy1_y0,
	input      [7 : 0] joy1_x1,
	input      [7 : 0] joy1_y1,
	input      [24: 0] ps2_mouse
);
	
	function automatic [7:0] stick_axis(input signed [7:0] axis);
		reg signed [8:0] v;
		begin
			v = {axis[7],axis} + 9'd128;
			stick_axis = v[7:0];
		end
	endfunction

	function automatic signed [10:0] mouse_delta(input ovf, input sign, input [7:0] data);
		begin
			if (ovf) mouse_delta = sign ? 11'sh400 : 11'sd1022;
			else     mouse_delta = $signed({sign,sign,sign,data}) <<< 1;
		end
	endfunction

	function automatic signed [10:0] mouse_limit(input signed [11:0] axis);
		begin
			if (axis > 12'sd1023) mouse_limit = 11'sd1023;
			else if (axis < -12'sd1024) mouse_limit = 11'sh400;
			else mouse_limit = axis[10:0];
		end
	endfunction

	// A read takes up to the 10-bit field's range, -511..511. With the former
	// limit of 96 counts per read a fast mouse could not move the cursor faster
	// than 96 counts a field, and the rest of a fast movement queued up and
	// drained over the next fields (the cursor went on after the mouse stopped).
	function automatic signed [9:0] mouse_step(input signed [10:0] axis);
		begin
			if (axis > 11'sd511) mouse_step = 10'sd511;
			else if (axis < -11'sd511) mouse_step = -10'sd511;
			else mouse_step = axis[9:0];
		end
	endfunction
	
	bit          LATCH;
	
	//pad
	wire [15:0] joy0_data = {1'b1, 2'b00, joystick_0[2], joystick_0[3], joystick_0[0], joystick_0[1], joystick_0[4], joystick_0[5], joystick_0[6], joystick_0[7], joystick_0[8], joystick_0[9], joystick_0[10], 2'b00};
	wire [15:0] joy1_data = {1'b1, 2'b00, joystick_1[2], joystick_1[3], joystick_1[0], joystick_1[1], joystick_1[4], joystick_1[5], joystick_1[6], joystick_1[7], joystick_1[8], joystick_1[9], joystick_1[10], 2'b00};
	wire [15:0] joy2_data = {1'b1, 2'b00, joystick_2[2], joystick_2[3], joystick_2[0], joystick_2[1], joystick_2[4], joystick_2[5], joystick_2[6], joystick_2[7], joystick_2[8], joystick_2[9], joystick_2[10], 2'b00};
	wire [15:0] joy3_data = {1'b1, 2'b00, joystick_3[2], joystick_3[3], joystick_3[0], joystick_3[1], joystick_3[4], joystick_3[5], joystick_3[6], joystick_3[7], joystick_3[8], joystick_3[9], joystick_3[10], 2'b00};
	
	//stick
	wire [7:0] stick0_x = stick_axis($signed(joy0_x0));
	wire [7:0] stick0_y = stick_axis($signed(joy0_y0));
	wire [7:0] stick0_z = stick_axis($signed(joy0_y1));
	wire [7:0] stick1_x = stick_axis($signed(joy1_x0));
	wire [7:0] stick1_y = stick_axis($signed(joy1_y0));
	wire [7:0] stick1_z = stick_axis($signed(joy1_y1));
	
	wire [71:0] stick0_data = {
		8'h01,
		8'h7B,
		8'h08,
		stick0_x,
		2'b00,
		stick0_y,
		2'b00,
		stick0_z,
		4'h2,
		{joystick_0[11], joystick_0[4], joystick_0[5], joystick_0[6], joystick_0[3], joystick_0[2], joystick_0[0], joystick_0[1]},
		{joystick_0[7], joystick_0[8], joystick_0[10], joystick_0[9], 4'b0000}
	};
	wire [71:0] stick1_data = {
		8'h01,
		8'h7B,
		8'h08,
		stick1_x,
		2'b00,
		stick1_y,
		2'b00,
		stick1_z,
		4'h2,
		{joystick_1[11], joystick_1[4], joystick_1[5], joystick_1[6], joystick_1[3], joystick_1[2], joystick_1[0], joystick_1[1]},
		{joystick_1[7], joystick_1[8], joystick_1[10], joystick_1[9], 4'b0000}
	};
	
	//mouse
	wire [7:0] mouse_flags = ps2_mouse[7:0];
	wire signed [10:0] mouse_dx = mouse_delta(mouse_flags[6], mouse_flags[4], ps2_mouse[15:8]);
	wire signed [10:0] mouse_dy = mouse_delta(mouse_flags[7], mouse_flags[5], ps2_mouse[23:16]);
	
	reg mouse_toggle = 0;
	reg mouse_left = 0;
	reg mouse_middle = 0;
	reg mouse_right = 0;
	reg signed [10:0] mouse_x_acc = '0;
	reg signed [10:0] mouse_y_acc = '0;
	wire signed [9:0] mouse_x = mouse_step(mouse_x_acc);
	wire signed [9:0] mouse_y = mouse_step(mouse_y_acc);
	always @(posedge CLK) begin
		reg signed [11:0] x;
		reg signed [11:0] y;

		if (RST || !MOUSE_EN) begin
			mouse_toggle <= ps2_mouse[24];
			mouse_left <= 1'b0;
			mouse_middle <= 1'b0;
			mouse_right <= 1'b0;
			mouse_x_acc <= '0;
			mouse_y_acc <= '0;
		end else begin
			x = {mouse_x_acc[10],mouse_x_acc};
			y = {mouse_y_acc[10],mouse_y_acc};

			if (LATCH) begin
				x = x - $signed({{2{mouse_x[9]}},mouse_x});
				y = y - $signed({{2{mouse_y[9]}},mouse_y});
			end

			// the buttons are the flags byte's as it stands (hps_io keeps it
			// between packets), not the last packet's since the mouse was enabled:
			// a button held from before the mouse was switched on was never seen
			mouse_left <= ps2_mouse[0];
			mouse_middle <= ps2_mouse[2];
			mouse_right <= ps2_mouse[1];
			if (ps2_mouse[24] != mouse_toggle) begin
				mouse_toggle <= ps2_mouse[24];
				x = x + $signed({mouse_dx[10],mouse_dx});
				y = y - $signed({mouse_dy[10],mouse_dy});
			end

			mouse_x_acc <= mouse_limit(x);
			mouse_y_acc <= mouse_limit(y);
		end
	end
	
	wire [31:0] mouse_data = {
		8'h49,
		mouse_left,
		mouse_middle,
		mouse_right,
		1'b0,
		mouse_y[9:0],
		mouse_x[9:0]
	};
	
	//arcade control
	wire [31:0] arcade_silli = {8'hC0, 8'h00, {1'b0, 1'b0, joystick_0[12], joystick_1[12], 1'b0, joystick_1[11], joystick_0[11], ARCADE_SERVICE}, 8'h00};
	wire [31:0] arcade_tb = {
		8'h49,
		1'b0,
		1'b0,
		1'b0,
		1'b0,
		mouse_y[9:0],
		mouse_x[9:0]
	};
	
	//light gun (Portfolio LightGunRom.c / lightgun.h; Opera opera_pbus.c)
	// The gun reports no position: a 20-bit count from the start of the
	// field to the moment its sensor saw the beam, and the number of line
	// pulses it saw (0: no hit). The driver turns it back into a position:
	//   c' = count + TIMEOFFSET, y = 10 c' / YSCANTIME,
	//   x = ((10 c') % YSCANTIME) * WIDTH / (XSCANTIME * 10).
	// Here, for a pixel (x, y):
	//   count = ceil((y * YSCANTIME + ceil(x * XSCANTIME * 10 / WIDTH)) / 10) - TIMEOFFSET
	// Opera rounds the division by 10 down; then 10 c' can fall before the
	// line's start, and the driver decodes x = 0 as the end of the line
	// above. With both divisions rounded up every pixel decodes to itself:
	// a pixel is XSCANTIME * 10 / WIDTH (27 PAL, 32 NTSC) units of 10 c'
	// wide, the two roundings add at most 10. NTSC 1030 / 12707 / -12835 /
	// 320 wide, PAL 1051 / 12796 / -58995 / 388 wide (lightgun.h: the PAL
	// values are the SDK's defaults, not verified on a PAL gun).
	// The aim is the light gun position hps_io gives on the left analog axes:
	// Main_MiSTer scales the calibrated screen to -127..+127 (clamped there;
	// -128 is taken as -127). The screen it was calibrated on is the VE
	// window, framebuffer pixels 0..319 x 0..239 in NTSC and in PAL (VE keeps
	// the 640 dot, 240 line window in PAL), so the aim maps to that, rounded:
	//   x = ((a + 127) * 319 + 127) / 254, y = ((a + 127) * 239 + 127) / 254
	// -127 is the first pixel, 0 the middle (160, 120), +127 the last. The
	// division by 254 is a multiplication by 132105 / 2^25 (exact for these
	// numbers). The other divisions run in a small serial divider that
	// repeats all the time (about 60 clocks); the result changes only
	// between whole computations.
	wire        gun_arcade = (ARCADE_SEL == 2'd2);
	wire        gun_joy1 = (GUN_SEL == 2'd2) && !gun_arcade;
	wire [12:0] gun_btn = gun_joy1 ? joystick_1 : joystick_0;
	wire [ 7:0] gun_ax = gun_joy1 ? joy1_x0 : joy0_x0;
	wire [ 7:0] gun_ay = gun_joy1 ? joy1_y0 : joy0_y0;
	wire [ 7:0] gun_ux = (gun_ax == 8'h80) ? 8'd0 : 8'(gun_ax + 8'd127);   // 0..254
	wire [ 7:0] gun_uy = (gun_ay == 8'h80) ? 8'd0 : 8'(gun_ay + 8'd127);
	
	wire        gun_trigger = gun_btn[4];             //A
	wire        gun_option = gun_btn[5];              //B
	wire        gun_offscreen = gun_btn[6];           //C: shot off screen (reload) / holster
	
	wire [ 8:0] LG_W   = GUN_PAL ? 9'd388 : 9'd320;
	wire [10:0] LG_XS  = GUN_PAL ? 11'd1051 : 11'd1030;
	wire [13:0] LG_YS  = GUN_PAL ? 14'd12796 : 14'd12707;
	wire [15:0] LG_OFF = GUN_PAL ? 16'd58995 : 16'd12835;
	reg  [19:0] lg_count;   // cleared by RST
	reg  [ 2:0] lg_st;
	reg  [16:0] lg_nx, lg_ny;
	reg  [ 8:0] lg_px, lg_py;
	reg  [23:0] lg_num, lg_q, lg_rem;
	reg  [ 8:0] lg_den;
	reg  [ 4:0] lg_bit;
	always @(posedge CLK) begin
		if (RST) begin
			lg_st <= '0;
			lg_count <= '0;
		end else begin
			case (lg_st)
				3'd0: begin   // aim -127..+127 to 0..254, times the last pixel, + half of 254
					lg_nx <= 17'(gun_ux) * 17'd319 + 17'd127;
					lg_ny <= 17'(gun_uy) * 17'd239 + 17'd127;
					lg_st <= 3'd1;
				end
				3'd1: begin   // / 254: pixel position
					lg_px <= 9'((35'(lg_nx) * 35'd132105) >> 25);
					lg_py <= 9'((35'(lg_ny) * 35'd132105) >> 25);
					lg_st <= 3'd2;
				end
				3'd2: begin   // x * XSCANTIME * 10 / WIDTH, rounded up
					lg_num <= 24'(lg_px * LG_XS * 10) + 24'(LG_W) - 24'd1;
					lg_den <= LG_W;
					lg_q <= '0; lg_rem <= '0; lg_bit <= 5'd23;
					lg_st <= 3'd3;
				end
				3'd3, 3'd5: begin   // one bit of a restoring division a step
					reg [24:0] r;
					r = {lg_rem, lg_num[lg_bit]};
					if (r >= 25'(lg_den)) begin lg_rem <= 24'(r - 25'(lg_den)); lg_q[lg_bit] <= 1'b1; end
					else                  begin lg_rem <= r[23:0];                 lg_q[lg_bit] <= 1'b0; end
					if (lg_bit == 0) lg_st <= lg_st + 3'd1;
					else lg_bit <= lg_bit - 5'd1;
				end
				3'd4: begin   // + y * YSCANTIME, then / 10 rounded up
					lg_num <= 24'(lg_py * LG_YS) + lg_q + 24'd9;
					lg_den <= 9'd10;
					lg_q <= '0; lg_rem <= '0; lg_bit <= 5'd23;
					lg_st <= 3'd5;
				end
				3'd6: begin   // - TIMEOFFSET, 20 bits
					lg_count <= 20'(lg_q + 24'(LG_OFF));
					lg_st <= 3'd0;
				end
				default: lg_st <= 3'd0;
			endcase
		end
	end
	
	//home gun: a shot off screen is seen as trigger with no light detected
	wire [39:0] gun_data = {
		8'h4D,
		gun_trigger | gun_offscreen,
		3'b000,
		gun_option,
		2'b00,
		gun_offscreen ? 20'd0 : lg_count,
		gun_offscreen ? 5'd0 : 5'h1F
	};
	//arcade gun: holstered gun points at the top left corner with no light detected
	wire [39:0] arcade_gun = {
		8'h4D,
		gun_trigger,
		ARCADE_SERVICE,
		joystick_0[12],
		joystick_0[11],
		gun_offscreen,
		2'b00,
		gun_offscreen ? 20'(LG_OFF) : lg_count,
		gun_offscreen ? 5'd0 : 5'h1F
	};
	
	bit [255: 0] IN_DATA;
	always_comb begin
		if (gun_arcade)
			IN_DATA = {arcade_gun,{256-40{1'b1}}};
		else if (ARCADE_SEL)
			IN_DATA = {arcade_tb,arcade_silli,{256-32-32{1'b1}}};
		else if (GUN_SEL)
			case (PAD_SEL)
				//the gun is first in the chain, then the pads (American Laser Games manuals:
				//"Player one's game pad/lightgun/mouse should be first in the daisy chain")
				3'b000:  IN_DATA = {gun_data,                    {256-40-00{1'b1}}};
				3'b001:  IN_DATA = {gun_data,joy0_data,          {256-40-16{1'b1}}};
				3'b010:  IN_DATA = {gun_data,joy0_data,joy1_data,{256-40-32{1'b1}}};
				default: IN_DATA = {                             {256      {1'b1}}};
			endcase
		else
			case ({MOUSE_EN,STICK_EN,PAD_SEL})
				5'b0_0_001: IN_DATA = {joy0_data,                                                     {256-16      {1'b1}}};
				5'b0_0_010: IN_DATA = {joy0_data,joy1_data,                                           {256-32      {1'b1}}};
				5'b0_0_011: IN_DATA = {joy0_data,joy1_data,joy2_data,                                 {256-48      {1'b1}}};
				5'b0_0_100: IN_DATA = {joy0_data,joy1_data,joy2_data,joy3_data,                       {256-64      {1'b1}}};
				5'b0_1_000: IN_DATA = {                                        stick0_data,           {256-00-72   {1'b1}}};
				5'b0_1_001: IN_DATA = {joy0_data,                              stick1_data,           {256-16-72   {1'b1}}};
				5'b1_0_000: IN_DATA = {                                                    mouse_data,{256-00-   32{1'b1}}};
				5'b1_0_001: IN_DATA = {joy0_data,                                          mouse_data,{256-16-   32{1'b1}}};
				5'b1_0_010: IN_DATA = {joy0_data,joy1_data,                                mouse_data,{256-32-   32{1'b1}}};
				5'b1_1_000: IN_DATA = {                                        stick0_data,mouse_data,{256-00-72-32{1'b1}}};
				5'b1_1_001: IN_DATA = {joy0_data,                              stick1_data,mouse_data,{256-16-72-32{1'b1}}};
				default:    IN_DATA = {                                                               {256         {1'b1}}};
			endcase
	end

	always @(posedge CLK) begin
		bit [  2: 0] STATE;
		bit [255: 0] DIN,DOUT;
		bit [ 12: 0] WAIT_CNT;
//		bit [  3: 0] BIT_CNT;
		bit          PBCLK_OLD;
		
		if (RST) begin
			STATE <= '0;
			PBDIN <= 1'b1;
			EXPBDOUT <= 1'b1;
			LATCH <= 1'b0;
		end else begin
			LATCH <= 1'b0;
			if (CE) begin
				PBCLK_OLD <= PBCLK;
				if (WAIT_CNT) WAIT_CNT <= WAIT_CNT - 1'd1;
				case (STATE)
					5'd0: begin
						if (PBCLK && !PBCLK_OLD) begin
							WAIT_CNT <= '1;
							STATE <= 3'd1;
						end
					end
					
					5'd1: begin
						if (WAIT_CNT == 0) begin
							WAIT_CNT <= '1;
							if (PBCLK) begin
								STATE <= 3'd2;
							end
							else begin
								STATE <= 3'd0;
							end
						end
					end
					
					5'd2: begin
						if (!PBCLK && PBCLK_OLD) begin
							WAIT_CNT <= '1;
							STATE <= 3'd3;
						end
					end
					
					5'd3: begin
						if (WAIT_CNT == 0) begin
							WAIT_CNT <= '1;
							if (!PBCLK) begin
								DOUT <= IN_DATA;
								LATCH <= 1'b1;
//								BIT_CNT <= '0;
								STATE <= 3'd4;
							end
							else begin
								STATE <= 3'd0;
							end
						end
					end
					
					5'd4: begin
						if (PBCLK && !PBCLK_OLD) begin 
							{EXPBDOUT,DIN} <= {DIN,PBDOUT}; 
							WAIT_CNT <= '1;
							STATE <= 3'd5; 
						end
						if (WAIT_CNT == 0) STATE <= !PBCLK ? 3'd0 : 3'd2;
					end
					
					5'd5: begin
						if (!PBCLK && PBCLK_OLD) begin 
							{PBDIN,DOUT} <= {DOUT,EXPBDIN}; 
//							BIT_CNT <= BIT_CNT + 4'd1; 
							WAIT_CNT <= '1;
							/*if (BIT_CNT == 4'd15) STATE <= 5'd0; 
							else*/ STATE <= 3'd4; 
						end
						if (WAIT_CNT == 0) STATE <= !PBCLK ? 3'd0 : 3'd2;
					end
					
					default: ;
				endcase
			end
		end
	end
	
endmodule
