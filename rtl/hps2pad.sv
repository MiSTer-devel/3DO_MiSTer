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
	input              ARCADE_SERVICE,
	
	input      [11: 0] joystick_0,
	input      [11: 0] joystick_1,
	input      [11: 0] joystick_2,
	input      [11: 0] joystick_3,
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
			if (ovf) mouse_delta = sign ? -11'sd1024 : 11'sd1022;
			else     mouse_delta = $signed({sign,sign,sign,data}) <<< 1;
		end
	endfunction

	function automatic signed [10:0] mouse_limit(input signed [11:0] axis);
		begin
			if (axis > 12'sd1023) mouse_limit = 11'sd1023;
			else if (axis < -12'sd1024) mouse_limit = -11'sd1024;
			else mouse_limit = axis[10:0];
		end
	endfunction

	function automatic signed [9:0] mouse_step(input signed [10:0] axis);
		begin
			if (axis > 11'sd96) mouse_step = 10'sd96;
			else if (axis < -11'sd96) mouse_step = -10'sd96;
			else mouse_step = axis[9:0];
		end
	endfunction

	function automatic signed [9:0] trackball_step(input signed [7:0] axis);
		reg [8:0] magnitude;
		reg signed [9:0] step;
		begin
			magnitude = axis[7] ? -{axis[7],axis} : {1'b0,axis};
			step = 0;
			if (magnitude > 9'd16)
				step = $signed({1'b0, (magnitude - 9'd16 + 9'd3) >> 2});
			trackball_step = axis[7] ? -step : step;
		end
	endfunction
	
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
	wire mouse_event = ps2_mouse[24] != mouse_toggle;
	reg signed [9:0] mouse_x_sent, mouse_y_sent;
	bit LATCH;
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
				x = x - $signed({{2{mouse_x_sent[9]}},mouse_x_sent});
				y = y - $signed({{2{mouse_y_sent[9]}},mouse_y_sent});
			end

			if (mouse_event) begin
				mouse_toggle <= ps2_mouse[24];
				mouse_left <= ps2_mouse[0];
				mouse_middle <= ps2_mouse[2];
				mouse_right <= ps2_mouse[1];
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
	wire [31:0] arcade_silli = {8'hC0, 8'h00, {1'b0, 1'b0, joystick_0[8], joystick_1[8], 1'b0, joystick_1[7], joystick_0[7], ARCADE_SERVICE}, 8'h00};
	wire mouse_pending = (mouse_x_acc != 0) || (mouse_y_acc != 0) ||
	                     (mouse_event && ((mouse_dx != 0) || (mouse_dy != 0)));
	wire signed [9:0] trackball_x = mouse_pending ? mouse_x : trackball_step($signed(joy0_x0));
	wire signed [9:0] trackball_y = mouse_pending ? mouse_y : trackball_step($signed(joy0_y0));
	wire [31:0] arcade_tb = {
		8'h49,
		1'b0,
		1'b0,
		1'b0,
		1'b0,
		trackball_y,
		trackball_x
	};
	
	bit [255: 0] IN_DATA;
	always_comb begin
		if (ARCADE_SEL)
			IN_DATA = {arcade_tb,arcade_silli,{256-32-32{1'b1}}};
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
								// Drain only the mouse motion captured in this packet.
								mouse_x_sent <= mouse_x;
								mouse_y_sent <= mouse_y;
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
