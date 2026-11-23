module P3DO_CROSSHAIR
(
	input              clk_sys,
	input              clk_vid,
	input              ce_pix,
	input              hblank,
	input              vblank,
	input              enable,
	input      [ 1: 0] size0, size1,
	input              holster0, holster1,
	input      [15: 0] aim0, aim1,
	input      [23: 0] rgb_in,
	output     [23: 0] rgb_out
);
	reg request = 0, ready = 0, accepted = 0;
	(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
	reg [1:0] request_sync = 0, ready_sync = 0;
	reg [35:0] sample = 0;

	always @(posedge clk_sys) begin
		request_sync <= {request_sync[0],request};
		if (request_sync[1] != ready) begin
			sample <= {enable && !holster1 ? size1 : 2'd0,aim1,
			           enable && !holster0 ? size0 : 2'd0,aim0};
			ready <= request_sync[1];
		end
	end

	reg        hblank_d = 1, vblank_d = 0;
	reg [9:0]  x = 0;
	reg [7:0]  y = 0;
	// The reply stays stable until the next vertical blank. Capture it during
	// a blank scanline, after the synchronized reply, never during active video.
	wire capture = ce_pix && vblank && hblank_d && !hblank && (ready_sync[1] != accepted);
	always @(posedge clk_vid) begin
		ready_sync <= {ready_sync[0],ready};
		if (capture) accepted <= ready_sync[1];
		if (ce_pix) begin
			hblank_d <= hblank;
			vblank_d <= vblank;
			if (vblank) begin
				x <= 0;
				y <= 0;
				if (!vblank_d && ready_sync[1] == request) request <= ~request;
			end else if (hblank) begin
				x <= 0;
				if (!hblank_d) y <= y + 1'd1;
			end else x <= x + 1'd1;
		end
	end

	function automatic [9:0] lower_bound(input [9:0] center, radius);
		lower_bound = center < radius ? 10'd0 : center - radius;
	endfunction

	wire [1:0] draw;
	genvar p;
	generate for (p = 0; p < 2; p = p + 1) begin : cursor
		wire [17:0] aim = sample[18*p +: 18];
		wire [1:0] size = aim[17:16];
		wire [7:0] u = {~aim[15],aim[14:8]};
		wire [7:0] v = {~aim[7],aim[6:0]};
		wire [9:0] aim_x = {1'b0,u,1'b0} + {3'b0,u[7:1]};
		wire [11:0] scan = {v,4'b0} - {4'b0,v};
		wire [7:0] aim_y = scan[11:4];
		wire [3:0] radius = size == 2'd1 ? 4'd3 : size == 2'd2 ? 4'd5 : 4'd8;
		wire [9:0] radius_x = {5'd0,radius,1'b0};
		wire [9:0] radius_y = {6'd0,radius};

		reg        show = 0;
		reg [9:0]  tx, x_lo, x_hi;
		reg [7:0]  ty, y_lo, y_hi;
		always @(posedge clk_vid) if (capture) begin
			// The ALG beam counter treats its first and last scanlines as misses.
			show <= (size != 0 && aim_y != 0 && aim_y != 8'd239);
			tx <= aim_x;
			ty <= aim_y;
			x_lo <= lower_bound(aim_x,radius_x);
			x_hi <= aim_x + radius_x;
			y_lo <= 8'(lower_bound({2'b00,aim_y},radius_y));
			y_hi <= aim_y + {4'd0,radius};
		end
		assign draw[p] = show && ((y == ty && x >= x_lo && x <= x_hi) ||
		                          (x == tx && y >= y_lo && y <= y_hi));
	end endgenerate

	assign rgb_out = (hblank || vblank) ? rgb_in :
	                 draw == 2'b11 ? 24'hffffff :
	                 draw[0] ? 24'hff4040 :
	                 draw[1] ? 24'h40ff40 : rgb_in;
endmodule
