// Fractional clock enable generator for the testbenches (from the 3DO_GameBub
// port's gb_util.sv; the core uses CEGen.vhd for this).
// Copyright (c) 2026 Adam Polkosnik
// SPDX-License-Identifier: GPL-3.0-or-later

module ce_gen #(
	parameter longint IN_CLK  = 50_000_000,
	parameter longint OUT_CLK = 24_545_400
)(
	input      CLK,
	input      RST_N,
	output reg CE
);
	localparam int W = $clog2(IN_CLK + OUT_CLK + 1);
	reg [W-1:0] sum;
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) begin
			sum <= '0;
			CE  <= 0;
		end else begin
			CE <= 0;
			if (sum + W'(OUT_CLK) >= W'(IN_CLK)) begin
				sum <= sum + W'(OUT_CLK) - W'(IN_CLK);
				CE  <= 1;
			end else begin
				sum <= sum + W'(OUT_CLK);
			end
		end
	end
endmodule
