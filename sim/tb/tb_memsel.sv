// Testbench: MADAM's memory map decode (P3DO_PKG::MemRegionSel) and the
// on-chip VRAM window maps against the range compares they replace, for every
// memory size setting and every word address, and every window offset.
//
// SPDX-License-Identifier: GPL-3.0-or-later

`timescale 1ns/1ps

module tb_memsel;
	import P3DO_PKG::*;

	int errors = 0, checks = 0;

	// the compares as they were (MADAM_AG.sv, MADAM.sv)
	task automatic ref_sel(input [6:0] MEM_SIZE, input [23:2] AOUT, output bit d0, output bit d1, output bit v, output bit v_extra);
		bit [23:0] DRAM0_END,DRAM1_START,DRAM1_END,VRAM_START,VRAM_END;
		case (MEM_SIZE[4:3])
			2'b00: begin DRAM0_END = 24'h000000; DRAM1_START = 24'h000000; end
			2'b01: begin DRAM0_END = 24'h0FFFFF; DRAM1_START = 24'h100000; end
			2'b10: begin DRAM0_END = 24'h3FFFFF; DRAM1_START = 24'h400000; end
			2'b11: begin DRAM0_END = 24'hDFFFFF; DRAM1_START = 24'hE00000; end
		endcase
		case (MEM_SIZE[6:5])
			2'b00: begin DRAM1_END = DRAM1_START + 24'h000000; VRAM_START = DRAM1_START + 24'h000000; end
			2'b01: begin DRAM1_END = DRAM1_START + 24'h0FFFFF; VRAM_START = DRAM1_START + 24'h100000; end
			2'b10,
			2'b11: begin DRAM1_END = DRAM1_START + 24'h3FFFFF; VRAM_START = DRAM1_START + 24'h400000; end
		endcase
		VRAM_END = VRAM_START + 24'h100000;
		d0 = (AOUT >= (24'h000000>>2) && AOUT <= (DRAM0_END>>2)) && |MEM_SIZE[4:3];
		d1 = (AOUT >= (DRAM1_START>>2) && AOUT <= (DRAM1_END>>2)) && |MEM_SIZE[6:5];
		v  = (AOUT >= (VRAM_START>>2) && AOUT <= (VRAM_END>>2));
		v_extra = (AOUT == (VRAM_END>>2));   // the first word after VRAM, which the compares also took
	endtask

	// the on-chip window registers of vram.sv / 3DO.sv
	reg         clk = 0;
	always #5 clk = ~clk;
	reg  [ 3:0] O4 = 0, O2 = 0, O1 = 0;
	reg  [17:0] A = 0;
	wire [17:0] ESADDR, unused_a;
	P3DO_VRAM #(1) vram (
		.CLK(clk), .CLK_MEM(clk), .RST_N(1'b0),
		.A(A), .D(16'h0), .Q(), .RAS_N(1'b1), .CAS_N(1'b1), .WE_N(2'b11), .OE_N(1'b1), .DSF1(1'b0),
		.SC(1'b0), .SE_N(1'b0), .SQ(), .QSF(), .RDY(),
		.EQ(16'h0), .ESADDR(ESADDR), .ESDATA(), .ESWR(), .ESRD(), .ESFW(), .ESQ(32'h0), .ESTE(1'b0),
		.BRAM4_OFFS(O4), .BRAM2_OFFS(O2), .BRAM1_OFFS(O1), .SP_CPU(1'b0),
		.DP(16'h0), .PEER_BUSY(1'b0), .XBUSY(), .DBG_WAIT_CNT()
	);

	initial begin
		// 1. memory regions: every size setting, every word address
		for (int ms = 0; ms < 16; ms++) begin
			bit [6:0] MEM_SIZE;
			MEM_SIZE = {ms[3:0], 3'b000};
			for (int a = 0; a < (1 << 22); a++) begin
				bit d0, d1, v, vx;
				bit [2:0] s;
				ref_sel(MEM_SIZE, a[21:0], d0, d1, v, vx);
				s = MemRegionSel(MEM_SIZE, a[21:18]);
				checks++;
				if ((s[0] && |MEM_SIZE[4:3]) !== d0 || (s[1] && |MEM_SIZE[6:5]) !== d1 || (s[2] !== v && !vx)) begin
					errors++;
					if (errors < 20) $display("FAIL size %02h address %06h: DRAM0 %b/%b DRAM1 %b/%b VRAM %b/%b", MEM_SIZE, {a[21:0], 2'b00}, s[0], d0, s[1], d1, s[2], v);
				end
				if (vx && s[2]) begin
					errors++;
					if (errors < 20) $display("FAIL size %02h: the word after VRAM is selected", MEM_SIZE);
				end
			end
		end
		$display("memory regions: %0d checks, errors=%0d", checks, errors);

		// 2. on-chip windows: every offset, every 16 KiB unit and the words at its ends
		for (int o = 0; o < 4096; o++) begin
			{O4, O2, O1} = o[11:0];
			repeat (2) @(posedge clk);
			for (int u = 0; u < 64; u++) begin
				for (int e = 0; e < 2; e++) begin
					bit r4, r2, r1;
					A = {u[5:0], {12{e[0]}}};
					#1;
					r4 = (A >= ({O4+0,16'h0000}>>2) && A <= ({O4+3,16'hFFFF}>>2));
					r2 = (A >= ({O2+0,16'h0000}>>2) && A <= ({O2+1,16'hFFFF}>>2));
					r1 = (A >= ({O1+0,16'h0000}>>2) && A <= ({O1+0,16'hBFFF}>>2)) || (A >= (20'hFC000>>2));
					checks++;
					if (vram.USE_INT_RAM4 !== r4 || vram.USE_INT_RAM2 !== r2 || vram.USE_INT_RAM1 !== r1) begin
						errors++;
						if (errors < 20) $display("FAIL offsets %h %h %h address %05h: %b%b%b expected %b%b%b", O4, O2, O1, {A, 2'b00},
						                          vram.USE_INT_RAM4, vram.USE_INT_RAM2, vram.USE_INT_RAM1, r4, r2, r1);
					end
				end
			end
		end
		$display("tb_memsel: %0d checks, %0d errors", checks, errors);
		if (errors == 0) begin $display("tb_memsel: PASS"); $finish; end
		else $fatal(1, "tb_memsel: FAIL");
	end
endmodule
