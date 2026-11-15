// Testbench: MADAM's matrix engine (Game Bub 3DO core).
//
// The real MADAM module, with CPU accesses to its registers (0x0330_06xx,
// 0x0330_07Fx) as the ARM60 bus makes them. Matrix (0x600-0x63C, 16.16) times
// vector (0x640-0x64C), started by writing the command to 0x7FC:
//   1  4x4: out[i] = sum_j M[i][j] * V[j], 64-bit, bits 47..16
//   2  3x3: the same over three rows and columns
//   3  3x3, then the perspective divide: q = N (0x680/0x684, 64-bit) / out[2]
//      (signed, remainder positive, as the original LPM_DIVIDE), and rows 0
//      and 1 become q[47:16] * out[i] (bits 47..16); row 2 stays
// All products are signed. Writing 0 to 0x7FC hands the result bank to the
// CPU (0x660-0x66C). The first cases are -0.5 * 0.5 with the negative factor
// in the matrix and in the vector (FFFFC000), the rest random over
// [-1, 1] in steps of 1/16. Before each command the CPU reads the sixteen
// matrix entries and the vector back, each at its own address.
// First, MSYS (0x04): it reports the memory configuration MADAM decodes the
// DRAM from. (In the 3DO_GameBub port writes leave it, as in Opera; this
// core keeps it writable for its experimental DRAM sizes.)
//
// Copyright (c) 2026 Adam Polkosnik
// SPDX-License-Identifier: GPL-3.0-or-later

`timescale 1ns/1ps
module tb_math;
	reg clk = 0;
	always #10 clk = ~clk;
	reg ce_r = 0;
	always @(posedge clk) ce_r <= ~ce_r;
	reg rst_n = 0;
	reg  [31:0] a = 0, di = 0;
	reg         nrw = 0, nmreq = 1;
	wire [31:0] q;
	wire        ph1, ph2;

	MADAM dut (
		.CLK(clk), .RST_N(rst_n), .EN(1'b1), .CE_R(ce_r), .CE_F(~ce_r),
		.A(a), .DI(32'h0), .CPU_DI(di), .CPU_DO(q), .nRW(nrw), .nWB(1'b1), .nMREQ(nmreq), .SEQ(1'b0), .nOPC(1'b0),
		.nTRANS(1'b1), .LOCK(1'b0), .MCLK_PH1(ph1), .MCLK_PH2(ph2), .VCE(1'b0), .LQSF(1'b0), .RQSF(1'b0),
		.DMAREQ(1'b0), .DMACH(5'd0), .CREADY_N(1'b0), .PCSC(1'b0), .MIRQ_N(1'b1), .PBDIN(1'b1), .PDI(32'd0),
		.DBG_SPR_EN(1'b1), .DBG_EXT(8'd0)
	);

	int errors = 0, checks = 0;
	task automatic clocks(input int n = 1); repeat (n) @(posedge clk); #1; endtask
	// a CPU write / read of MADAM register 0x0330_0000 + off: the address
	// and data with nMREQ, held to MCLK phase 2
	task automatic wr(input [15:0] off, input [31:0] v);
		@(negedge clk); a = 32'h03300000 + off; di = v; nrw = 1; nmreq = 0;
		@(posedge clk iff ph2); #1; nrw = 0; nmreq = 1; clocks(4);
	endtask
	task automatic rd(input [15:0] off, output [31:0] v);
		@(negedge clk); a = 32'h03300000 + off; nrw = 0; nmreq = 0;
		@(posedge clk iff ph2); #1; v = q; nmreq = 1; clocks(4);
	endtask
	task automatic check(input string what, input [31:0] got, input [31:0] exp);
		checks++;
		if (got !== exp) begin
			errors++;
			if (errors <= 30) $display("[%0t] TB ERROR: %s: got %08h, expected %08h", $realtime, what, got, exp);
		end
	endtask

	// bits 47..16 of a signed 32 x 32 product (sum)
	function automatic [31:0] fx(input longint signed v);
		return 32'(v >>> 16);
	endfunction

	initial begin
		int signed m [16], v [4];
		int        n_cases [4] = '{0, 0, 0, 0};
		clocks(6); rst_n = 1; clocks(20);
		// MSYS (0x04) reports the memory configuration MADAM decodes the DRAM from
		begin
			bit [31:0] ms;
			rd(16'h0004, ms); check("MSYS after reset", ms, 32'h00000029);
		end
		for (int t = 0; t < 120; t++) begin
			int mode, size;
			longint signed r [4];
			bit [31:0] got;
			mode = t < 2 ? 2 : 1 + t % 3;
			size = mode == 1 ? 4 : 3;
			do begin
				for (int i = 0; i < 16; i++) m[i] = (int'($urandom_range(0, 32)) - 16) * 4096;
				for (int i = 0; i < 4; i++) v[i] = (int'($urandom_range(0, 32)) - 16) * 4096;
				if (t < 2) begin                       // -0.5 * 0.5
					m = '{default: 0}; v = '{default: 0};
					m[0] = t == 0 ? -32768 : 32768;
					v[0] = t == 0 ? 32768 : -32768;
				end
				for (int i = 0; i < 4; i++) begin
					r[i] = 0;
					for (int j = 0; j < size; j++) r[i] += longint'(m[4 * i + j]) * longint'(v[j]);
				end
			end while (mode == 3 && fx(r[2]) == 0);      // no divide by zero
			for (int i = 0; i < 16; i++) wr(16'h0600 + 16'(4 * i), m[i]);
			for (int i = 0; i < 4; i++) wr(16'h0640 + 16'(4 * i), v[i]);
			for (int i = 0; i < 16; i++) begin
				rd(16'h0600 + 16'(4 * i), got);
				check($sformatf("case %0d: matrix entry %0d read back", t, i), got, m[i]);
			end
			for (int i = 0; i < 4; i++) begin
				rd(16'h0640 + 16'(4 * i), got);
				check($sformatf("case %0d: vector entry %0d read back", t, i), got, v[i]);
			end
			if (mode == 3) begin
				longint signed nn;
				nn = longint'($urandom()) <<< ($urandom() % 9);
				if ($urandom() % 2) nn = -nn;
				wr(16'h0680, 32'(nn >>> 32));
				wr(16'h0684, 32'(nn));
				wr(16'h07FC, 32'(mode));
				clocks(400);
				begin
					longint signed z, rem, qq;
					bit [31:0] qm;
					z = longint'($signed(fx(r[2])));
					check($sformatf("case %0d: divider input (row 2)", t), dut.MATH_DIV_Z, fx(r[2]));
					rem = nn % z;
					if (rem < 0) rem += (z < 0 ? -z : z);
					qq = (nn - rem) / z;
					check($sformatf("case %0d: quotient bits 47..16", t), dut.MATH_DIV_RES[47:16], 32'(qq >>> 16));
					qm = dut.MATH_DIV_RES[47:16];
					r[0] = longint'($signed(qm)) * longint'($signed(fx(r[0])));
					r[1] = longint'($signed(qm)) * longint'($signed(fx(r[1])));
				end
			end else begin
				wr(16'h07FC, 32'(mode));
				clocks(200);
			end
			rd(16'h07F8, got);
			check($sformatf("case %0d: command %0d done", t, mode), got, 32'h0);
			wr(16'h07FC, 32'h0);                         // result bank to the CPU
			for (int i = 0; i < size; i++) begin
				rd(16'h0660 + 16'(4 * i), got);
				check($sformatf("case %0d (command %0d) row %0d", t, mode, i), got, fx(r[i]));
			end
			if (t < 2) $display("[%0t] case %0d: -0.5 * 0.5 (negative factor in the %s) row 0 = %08h", $realtime, t,
			                    t == 0 ? "matrix" : "vector", fx(r[0]));
			n_cases[mode]++;
		end
		$display("tb_math: %0d 4x4, %0d 3x3, %0d 3x3 with divide; %0d checks, %0d errors", n_cases[1], n_cases[2], n_cases[3], checks, errors);
		if (errors == 0) begin $display("tb_math: PASS"); $finish; end
		else $fatal(1, "tb_math: FAIL");
	end
	initial begin #20ms; $display("tb_math: TIMEOUT"); $fatal(1, "tb_math: FAIL"); end
endmodule
