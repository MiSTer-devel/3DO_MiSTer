// Video and VDL DMA sequencing in MADAM (real RTL), four checks:
//
// 1. Line-start and mid-line requests (MADAM_SPORT + MADAM_ARB, with CLIO_VIDEO
//    and VE for the line timing). A mid-line request (a VRAM half's QSF
//    toggle) still pending when the line-start request is posted (HCOUNT
//    1469) and a stall over the line end: the arbiter grants the mid-line
//    request first (priority 2). With one acknowledge for both, that grant
//    also cleared the line-start request and the line got no transfers
//    (chipset audit 2026-11-10, finding 2). Control: the same stall without
//    the mid-line request.
// 2. Two mid-line requests (left, right) one tick apart: each sequence must
//    advance the DMA register (0x66 prev / 0x67 curr) of the branch the
//    arbiter latched for it (VIDMID_PREV_CURR -> VID_MIDPREV0 /
//    VID_MIDCURR0). The register read in VID_MIDINIT1 is {1, VIDMID_CURR},
//    which the second request's posting changed while the first sequence
//    was still on the bus (finding 3).
// 3. The field line (MADAM_AG PFL) across VDL entries: an entry that loads
//    the current-line address (LDCURR) sets the line from bit 1 of it; an
//    entry without LDCURR (palette only) leaves the line sequence alone
//    (Opera opera_vdlp.c vdlp_process_vdl_entry). The original took bit 1
//    of every entry's address word (Opera audit 2026-11-10, finding 2).
// 4. A VDL entry with no optional words (ListLen 0) shifts none out to CLIO
//    (MADAM_SPORT + CLIO_VIDEO): before, the count wrapped to 64 words and
//    the following words (the next entry's header, bit 31 clear) were taken
//    as colour words. ListLen 34 still shifts 34.
//
// Copyright (c) 2026 Adam Polkosnik
// SPDX-License-Identifier: GPL-3.0-or-later

`timescale 1ns/1ps
import P3DO_PKG::*;

// ---------------- 1 and 2: requests and acknowledges ----------------
module viddma_req (output bit done, output int errors);
	bit clk = 0, rst = 1, vid = 0;
	always #10 clk = ~clk;
	always #10.191 vid = ~vid;
	wire vce;
	ce_gen vce_gen(.CLK(clk), .RST_N(~rst), .CE(vce));
	bit div = 0;
	always @(posedge clk) div <= ~div;
	wire CE_R = div, CE_F = ~div;
	// a stall pauses MADAM (EN-style: CE_R / CE_F held) while the dot clock runs
	bit pause = 0, stall = 0;
	always @(posedge clk) if (CE_F) pause <= stall;
	wire ce_r = CE_R && !pause, ce_f = CE_F && !pause;

	wire hs, vs, pcsc; wire [10:0] hc; wire [8:0] vc; wire [23:0] ad; wire de;
	CLIO_VIDEO cv(.CLK(clk), .RST_N(~rst), .EN(1'b1), .PAL(1'b0),
		.VCE(vce), .HSYNC_N(hs), .VSYNC_N(vs), .HCNT(hc), .VCNT(vc), .FLD(),
		.S(32'b0), .LSC_N(1'b1), .RSC_N(1'b1), .PCSC(pcsc), .AD(ad), .DE(de),
		.HINTREPOL_DISABLE(1'b1), .VINTREPOL_DISABLE(1'b1), .DBG_EXT(8'b0));
	VE ve(.MCLK(clk), .VCLK(vid), .RST_N(~rst), .EN(1'b1), .PAL(1'b0),
		.VCE(vce), .AD(ad), .DE(de), .HSYNC_N(hs), .VSYNC_N(vs), .RGB(),
		.HS_N(), .VS_N(), .HBLK_N(), .VBLK_N(), .DCLK(), .DBG_EXT(8'b0),
		.DBG_BORD_DIS(1'b0), .DBG_HS_START(), .DBG_HS_END());

	wire ph1, ph2, vreq, vack, midack, sg, clreq, clack, midreq, midcurr, midfirst;
	AddrGenCtl_t sportctl;
	BusState_t   bus_state;
	bit          setup_vdl = 0;
	CLUTCtrl_t   control;
	always_comb begin control = '0; control.LINE = 9'd511; control.ENVIDDMA = 1; end
	bit lmid = 0, rmid = 0;
	MADAM_SPORT sport(.CLK(clk), .RST_N(~rst), .EN(1'b1), .CE_R(ce_r), .CE_F(ce_f),
		.MDTI(control), .BUS_STATE(setup_vdl ? CLUT_CTRL1 : bus_state), .GRANT(sg),
		.AG_CTL(sportctl), .LINE0(), .LMIDLINE_REQ(lmid), .RMIDLINE_REQ(rmid),
		.CLUTXEN(1'b0), .VSCTXEN(1'b1), .CLUTWR_REQ(clreq), .CLUTWR_ACK(clack),
		.CLUTWR_FORCE(1'b0), .VIDOUT_REQ(vreq), .VIDOUT_PFL(1'b0), .VIDMID_REQ(midreq),
		.VIDMID_CURR(midcurr), .VIDMID_FIRST(midfirst), .VIDOUT_ACK(vack), .VIDMID_ACK(midack),
		.VCE(vce), .PCSC(pcsc), .LSC(), .RSC(), .FIELD(), .V480());
	MADAM_ARB arb(.CLK(clk), .RST_N(~rst), .EN(1'b1), .CE_R(ce_r), .CE_F(ce_f),
		.PHASE1(ph1), .PHASE2(ph2), .CPU_GRANT(), .CPU_READY(1'b1), .CPU_AG_CTL('0),
		.PBI(1'b0), .CLIO_REQ(1'b0), .EXTP_REQ(1'b0), .EXTP_ACK(), .EXTP_GRANT(),
		.EXTP_AG_CTL('0), .EXTP_NEXT('0), .SCOBLD_REQ('0), .SCOB_SEL('0),
		.SPRDATA_REQ('0), .SPR_SEL('0), .SPRDRAW_REQ(1'b0), .CFB_SEL('0),
		.CFB_SUSPEND(), .SPRPAUS_REQ(1'b0), .SPREND_REQ(1'b0), .SE_ACK(),
		.SE_GRANT(), .SE_AG_CTL('0), .CLUTWR_REQ(clreq), .CLUTWR_ACK(clack),
		.VIDOUT_REQ(vreq), .VIDMID_REQ(midreq), .VIDMID_CURR(midcurr),
		.VIDMID_FIRST(midfirst), .VIDOUT_ACK(vack), .VIDMID_ACK(midack), .SPORT_GRANT(sg),
		.SPORT_AG_CTL(sportctl), .PLAYER_REQ(1'b0), .REFRESH_REQ(1'b0),
		.PLAYER_GRANT(), .PLAYER_AG_CTL('0), .BUS_STATE(bus_state), .BUS_PB(),
		.DMA_CTL(), .DBG_EXT('0));

	// line-start sequences (VID_CURR1) and mid-line sequences
	int n_curr = 0, n_mid = 0;
	always @(posedge clk) if (ce_f) begin
		if (bus_state == VID_CURR1) n_curr++;
		if (bus_state == VID_MIDPREINIT1) n_mid++;
	end
	// 2: the register a mid-line sequence reads in VID_MIDINIT1 ({1,
	// VIDMID_CURR}: 0x66 or 0x67) against the branch the arbiter latched
	int b_bad = 0, b_seq = 0;
	bit b_rd = 0, b_have = 0;
	always @(posedge clk) begin
		if (ce_r && bus_state == VID_MIDINIT1) begin b_rd = sportctl.DMA_REG_READ_CTL[0]; b_have = 1; end
		if (b_have && (bus_state == VID_MIDCURR0 || bus_state == VID_MIDPREV0)) begin
			b_have = 0; b_seq++;
			if (b_rd != (bus_state == VID_MIDCURR0)) begin
				b_bad++;
				$display("[%0t] TB ERROR: mid-line sequence read DMA register 6%0d in VID_MIDINIT1 and goes on to %s",
				         $realtime, 6 + b_rd, bus_state == VID_MIDCURR0 ? "VID_MIDCURR0 (writes 67)" : "VID_MIDPREV0 (writes 66)");
			end
		end
	end

	task automatic wait_h(input int h);
		do @(posedge clk); while (!(vce && sport.HCOUNT == 11'(h)));
	endtask
	task automatic pulse(input bit l, input bit r);
		@(posedge clk); while (!ce_r) @(posedge clk);
		lmid <= l; rmid <= r;
		@(posedge clk); while (!ce_r) @(posedge clk);
		@(posedge clk);
		lmid <= 0; rmid <= 0;
	endtask

	initial begin
		int c0, m0;
		#1000; rst = 0;
		wait (vc == 60 && hc > 100);
		@(negedge clk); setup_vdl = 1;          // video DMA on (ENVIDDMA), no VDL downloads
		repeat (20) @(negedge clk);
		setup_vdl = 0;
		wait (sport.ENVIDDMA);
		wait_h(100); wait_h(100);

		// 1, control: a 10 us stall from HCOUNT 1285 (over the line request
		// at 1469), no mid-line request
		wait_h(1285);
		c0 = n_curr;
		stall = 1; #10us; stall = 0;
		wait_h(400);
		$display("1. control (stall over the line request): %0d line-start sequence(s)", n_curr - c0);
		if (n_curr - c0 != 1) begin errors++; $display("TB ERROR: control line lost its transfers"); end

		// 1: a mid-line request at HCOUNT 1283, then the same stall: the
		// mid-line grant comes first, the line's transfers must follow
		wait_h(1283);
		c0 = n_curr; m0 = n_mid;
		pulse(1, 0);
		stall = 1; #10us; stall = 0;
		wait_h(400);
		$display("1. mid-line request pending at the line request: %0d mid-line, %0d line-start sequence(s)", n_mid - m0, n_curr - c0);
		if (n_mid - m0 < 1) begin errors++; $display("TB ERROR: the mid-line request was not served"); end
		if (n_curr - c0 != 1) begin errors++; $display("TB ERROR: the mid-line grant cleared the line-start request: the line got no transfers"); end

		// 2: left and right mid-line requests one tick apart, both orders
		wait_h(600);
		pulse(1, 0); pulse(0, 1);
		wait_h(900);
		pulse(0, 1); pulse(1, 0);
		wait_h(1100);
		$display("2. %0d mid-line sequences, %0d read the other branch's DMA register", b_seq, b_bad);
		if (b_seq < 4) begin errors++; $display("TB ERROR: %0d mid-line sequences, expected at least 4", b_seq); end
		errors += b_bad;
		done = 1;
	end
endmodule

// ---------------- 3: field line across VDL entries ----------------
module viddma_pfl (output bit done, output int errors);
	reg clk = 0; always #5 clk = ~clk;
	reg rst_n = 0;
	BusState_t bs = BUS_IDLE;
	reg [31:0] mdti = 0;
	AddrGenCtl_t ctl = '0, ctl_ff = '0;
	// MADAM_ARB registers the granted unit's control (DMA_CTL2) on the same
	// tick as MADAM_AG registers the bus state, and the state's memory word
	// (MDTI) is there with them: all line up a tick after the bus state
	reg [31:0] mdti_ff = 0;
	always @(posedge clk) begin ctl_ff <= ctl; mdti_ff <= mdti; end
	wire pfl;
	MADAM_AG ag (.CLK(clk), .RST_N(rst_n), .EN(1'b1), .CE_R(1'b1), .CE_F(1'b1), .PHASE1(1'b0), .PHASE2(1'b1),
		.CPU_ADDR('0), .CPU_ACCESS(1'b0), .CPU_START(1'b0), .CPU_DRAM0_SEL(1'b0), .CPU_DRAM1_SEL(1'b0), .CPU_VRAM_SEL(1'b0),
		.CPU_SPORT_SEL(1'b0), .CPU_WE(4'b0), .CPU_GRANT(1'b0), .MEM_SIZE(7'd0), .DRAM_EN(1'b1), .EXTP_GRANT(1'b0),
		.SE_ADDR_A('0), .SE_ADDR_B('0), .SE_RAS_A(1'b0), .SE_RAS_B(1'b0), .SE_WRITE_A(1'b0), .SE_WRITE_B(1'b0), .SE_READ(1'b0), .SE_GRANT(1'b0),
		.PLAYER_GRANT(1'b0), .LINE0(1'b0), .CLUTWR_FORCE(), .VIDOUT_PFL(pfl), .LMIDLINE_REQ(), .RMIDLINE_REQ(),
		.MADR(), .MDTI(mdti_ff), .MDTO(), .MWR(), .BUS_STATE(bs), .DMA_CTL(ctl_ff), .PBI(), .REG_OVF(), .REG_ZERO(),
		.LA(), .LRAS0_N(), .LRAS2_N(), .LRAS3_N(), .LCAS_N(), .LWE_N(), .LOE_N(), .LDSF(), .LQSF(1'b0), .LCODE(),
		.RA(), .RRAS0_N(), .RRAS2_N(), .RRAS3_N(), .RCAS_N(), .RWE_N(), .ROE_N(), .RDSF(), .RQSF(1'b0), .RCODE());
	task automatic step(input BusState_t s, input [31:0] d, input bit we = 0);
		bs = s; mdti = d; ctl = '0; ctl.DMA_REG_WRITE_EN = we; @(posedge clk); #1;
	endtask
	// one line's video transfer sequence, then its field line
	task automatic video_line(input int n, input bit e);
		step(VID_PREINIT1, 0); step(VID_INIT0, 0); step(VID_INIT1, 0); step(BUS_IDLE, 0); step(BUS_IDLE, 0);
		if (pfl !== e) begin
			errors++;
			$display("TB ERROR: line %0d: field line %0d, expected %0d", n, pfl, e);
		end
	endtask
	// a VDL entry: header (240-line mode), then the current-line address
	// word, written to the DMA register only with LDCURR (MADAM_SPORT
	// CLUT_CURR1: DMA_REG_WRITE_EN = LDCURR)
	task automatic vdl(input bit ldcurr, input [31:0] w1);
		step(CLUT_CTRL1, 32'h0020_0000 | (ldcurr << 16) | 10); step(CLUT_CURR1, w1, ldcurr); step(BUS_IDLE, 0); step(BUS_IDLE, 0);
	endtask
	initial begin
		repeat (2) @(posedge clk); rst_n = 1; @(posedge clk); #1;
		vdl(1, 32'h0020_0000);                    // frame buffer address on an even line
		video_line(0, 0); video_line(1, 1); video_line(2, 0);
		vdl(0, 32'h0000_0000);                    // palette-only entry before line 3 (odd)
		video_line(3, 1); video_line(4, 0); video_line(5, 1);
		vdl(0, 32'h0000_0002);                    // palette-only, its (ignored) address word odd, before line 6
		video_line(6, 0); video_line(7, 1);
		vdl(1, 32'h0020_0002);                    // address on an odd line, before line 8
		video_line(8, 1); video_line(9, 0);
		$display("3. field line across VDL entries: %0d errors", errors);
		done = 1;
	end
endmodule

// ---------------- 4: ListLen 0 ----------------
module viddma_len (output bit done, output int errors);
	reg clk = 0; always #10 clk = ~clk;
	reg rst = 1;
	reg ce_r = 0; always @(posedge clk) ce_r <= ~ce_r;
	reg [31:0] mdti = '0;
	BusState_t bus_state = BUS_IDLE;
	wire lsc, rsc, pcsc;
	reg hs_n = 1;
	reg [31:0] sbus = 32'h0000_0000;   // the words on the serial bus (colour words for entry 0)
	wire [23:0] rgb; wire de;
	MADAM_SPORT sport (
		.CLK(clk), .RST_N(~rst), .EN(1'b1), .CE_R(ce_r), .CE_F(~ce_r),
		.MDTI(mdti), .BUS_STATE(bus_state), .GRANT(1'b1), .AG_CTL(), .LINE0(),
		.LMIDLINE_REQ(1'b0), .RMIDLINE_REQ(1'b0), .CLUTXEN(1'b1), .VSCTXEN(1'b0),
		.CLUTWR_REQ(), .CLUTWR_ACK(1'b1), .CLUTWR_FORCE(1'b0), .VIDOUT_REQ(), .VIDOUT_PFL(1'b0),
		.VIDMID_REQ(), .VIDMID_CURR(), .VIDMID_FIRST(), .VIDOUT_ACK(1'b1), .VIDMID_ACK(1'b1),
		.VCE(1'b1), .PCSC(pcsc), .LSC(lsc), .RSC(rsc), .FIELD(), .V480());
	CLIO_VIDEO video (
		.CLK(clk), .RST_N(~rst), .EN(1'b1), .PAL(1'b0), .VCE(1'b1), .HSYNC_N(hs_n), .VSYNC_N(1'b1),
		.HCNT(), .VCNT(), .FLD(), .S(sbus), .LSC_N(~lsc), .RSC_N(~rsc), .PCSC(pcsc),
		.AD(rgb), .DE(de), .HINTREPOL_DISABLE(1'b1), .VINTREPOL_DISABLE(1'b1), .DBG_EXT(8'd0));
	always begin
		repeat (1556) @(negedge clk); hs_n = 0; repeat (4) @(negedge clk); hs_n = 1;
	end
	int nl = 0;
	always @(posedge clk) if (lsc) nl++;
	task automatic entry(input int len);
		CLUTCtrl_t c;
		c = '0; c.LEN = 6'(len); c.LINE = 9'd3;
		@(posedge clk iff ce_r);
		@(negedge clk); mdti = c; bus_state = CLUT_CTRL1;
		@(posedge clk iff ce_r); @(negedge clk); bus_state = CLUT_TRANSFER1;
		@(posedge clk iff ce_r); @(negedge clk); bus_state = BUS_IDLE;
	endtask
	initial begin
		repeat (20) @(negedge clk); rst = 0;
		repeat (3200) @(negedge clk);
		// ListLen 34 (entry 0 <- 00 00 00), then 0 with a header-like word
		// on the bus (as a colour word: entry 0 <- 20 34 56), which must not
		// reach the palette, then 1 (entry 0 <- 20 34 56: the word does)
		for (int k = 0; k < 3; k++) begin
			int len;
			bit [23:0] e, c;
			len = k == 0 ? 34 : k == 1 ? 0 : 1;
			sbus = k == 0 ? 32'h0000_0000 : 32'h0020_3456;
			e = k == 2 ? 24'h203456 : 24'h000000;
			nl = 0;
			entry(len);
			repeat (3200) @(negedge clk);
			c = {video.CLUT.COL_R.altdpram_component.mem[32], video.CLUT.COL_G.altdpram_component.mem[32],
			     video.CLUT.COL_B.altdpram_component.mem[32]};
			$display("4. ListLen %0d: %0d words shifted to CLIO, palette entry 0 %06h", len, nl, c);
			if (nl != len) begin errors++; $display("TB ERROR: ListLen %0d shifted %0d words", len, nl); end
			if (c !== e) begin errors++; $display("TB ERROR: after ListLen %0d palette entry 0 is %06h, expected %06h", len, c, e); end
		end
		done = 1;
	end
endmodule

module tb_viddma;
	bit d1, d3, d4;
	int e1, e3, e4;
	viddma_req req (.done(d1), .errors(e1));
	viddma_pfl pfl (.done(d3), .errors(e3));
	viddma_len len (.done(d4), .errors(e4));
	initial begin
		fork
			wait (d1 && d3 && d4);
			#60ms;
		join_any
		if (!(d1 && d3 && d4)) $fatal(1, "tb_viddma: timeout (done %b%b%b)", d1, d3, d4);
		$display("tb_viddma: errors: requests %0d, field line %0d, ListLen %0d", e1, e3, e4);
		if (e1 + e3 + e4 == 0) begin $display("tb_viddma: PASS"); $finish; end
		else $fatal(1, "tb_viddma: FAIL");
	end
endmodule
