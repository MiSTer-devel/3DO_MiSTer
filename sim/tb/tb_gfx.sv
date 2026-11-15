// Testbench: MADAM's pixel processor (MADAM_PPMP) and CLIO's display path
// (CLIO_VIDEO): the real modules against the 3DO documentation.
//
// 1. Pixel processor: every PIXC field (1S, MS, MF, DF, 2S, AV, 2D) with the
//    USEAV and PXOR flags, random decoder (cel) and frame buffer components,
//    against a reference model written from the PIXC documentation
//    (3DO Portfolio "Pixel-processing control word") and the Opera emulator's
//    math (opera_madam.c PPROC), computed in full precision: first source
//    times (multiplier + 1) divided by the primary divider (DF 00 = 16,
//    01 = 2, 10 = 4, 11 = 8; with MS = 10 the divider code is the decoder
//    component's two LSBs, 00 included); secondary source divided by AV[4:3];
//    PXOR; AV[0] subtract, AV[1] sign extension of the secondary source,
//    AV[2] wraparound instead of clamping to 0..31; the sum divided by 2 with
//    2D. (AV[4:3] = 11, documented as "use the two lowest bits of the color
//    component coming from the decoder", is not checked: the documentation,
//    the core and Opera all differ, and nothing decides between them.)
//    Plus every AV, source and frame buffer value with the rest fixed.
// 2. VDL display control word: the 2-bit fields VSUB, HSUB, BLSB and their
//    window versions keep their prior setting when the word has 11 there
//    (US patent 5,502,462 Table 6, "maintain prior setting"; the SDK's
//    VDL_*_NOP), and the blue pen LSB follows the kept setting.
// 3. CLUT bypass (pen MSB set): the 5-bit components fill the 5 MSBs of the
//    8-bit outputs; the 3 LSBs are zero, the 3 MSBs again with MSBREP, or a
//    pseudo-random value with RNDM (US patent 6,191,772; SDK VDLDisplayCtlWord
//    bits 11 and 12).
// 9. CLIO's display line with its line timing (HSYNC every 1560 VCE ticks,
//    the serial strobes as MADAM_SPORT makes them): a VDL download (both
//    capture ports at once, in the horizontal blanking, US 5,502,462) is not
//    picture data: on a line without pixels it gives no DE, at its usual
//    position and late enough to run into the next line; after a line of
//    pixels it does not change that line's DE count or colours.
// 11. A palette (VDL) download that starts late in the horizontal blanking
//    (MADAM starts a pending one at any time from HCOUNT 1339 on) writes all
//    of its entries: a fade of all 32 entries and the background to black
//    (and back to white), started in, late in, and after CLIO's usual palette
//    window, shows every palette pen (2-31) in the new colour on the next
//    lines.
// 12. PIXC half per pixel (MADAM_PPMP with two different halves): the
//    pixel's P-mode bit picks the half with POVER 00 and 01, POVER 10 forces
//    the first half (PIXC[15:0]), 11 the second (Opera opera_madam.c PPROC:
//    only PMODE_ZERO 10 and PMODE_ONE 11 override; the SDK defines 00, 10
//    and 11).
// 10. VE (video encoder) held in reset during active display, at each of the
//    four dot-clock phases: no dot clock, horizontal and vertical blanking
//    (the capture to the framework keeps running through a 3DO reset).
//
// Copyright (c) 2026 Adam Polkosnik
// SPDX-License-Identifier: GPL-3.0-or-later

`timescale 1ns/1ps

module tb_gfx;
	import P3DO_PKG::*;

	reg clk = 0;
	always #5 clk = ~clk;
	reg rst = 1;

	int errors = 0, checks = 0;
	task automatic fail(input string m);
		errors++;
		if (errors <= 30) $display("[%0t] TB ERROR: %s", $realtime, m);
	endtask

	// ---------------- pixel processor ----------------
	SCoBCtl_t  ctl  = '0;
	SCoBFlag_t flag = '0;
	SCoBPre1_t pre1 = '0;
	PPMPCx_t   pixc = '0;
	IPN_t      ipn  = '0;
	reg [15:0] cfbd = '0;
	wire [15:0] pen;
	MADAM_PPMP ppmp (
		.CLK(clk), .RST(rst), .EN(1'b1), .CE(1'b1),
		.SCOBCTL(ctl), .SCOB_FLAG(flag), .SCOB_PRE1(pre1), .PPMPCA(pixc), .PPMPCB(pixc),
		.IPN(ipn), .CFBD(cfbd), .PEN(pen)
	);

	// section 12: a pixel processor with two different PIXC halves
	PPMPCx_t   pixc_a = '0, pixc_b = '0;
	wire [15:0] pen2;
	MADAM_PPMP ppmp2 (
		.CLK(clk), .RST(rst), .EN(1'b1), .CE(1'b1),
		.SCOBCTL(ctl), .SCOB_FLAG(flag), .SCOB_PRE1(pre1), .PPMPCA(pixc_a), .PPMPCB(pixc_b),
		.IPN(ipn), .CFBD(cfbd), .PEN(pen2)
	);

	// one 5-bit component: cel = the decoder's component, fb = the frame
	// buffer's, amv = the AMV multiplier (MS = 01)
	function automatic int ppmp_ref(input bit [4:0] cel, input bit [4:0] fb, input bit [2:0] amv,
	                                input PPMPCx_t p, input bit useav, input bit pxor);
		int mv, dv, a, b, aop, bop, sum;
		bit [4:0] av;
		bit neg, xtend, wrap;
		av    = useav ? p.AV : 5'd0;
		neg   = av[0];
		xtend = av[1];
		wrap  = av[2];
		a = p.S1 ? fb : cel;
		case (p.MS)
			2'd0:    mv = p.MXF;
			2'd1:    mv = amv;
			default: mv = cel[4:2];
		endcase
		dv = (p.MS == 2'd2) ? cel[1:0] : p.DV1;
		a = (a * (mv + 1)) >> (dv == 0 ? 4 : dv);
		case (p.S2)
			2'd0: b = 0;
			2'd1: b = p.AV;
			2'd2: b = fb;
			2'd3: b = cel;
		endcase
		b = b >> (av[4:3] == 2'd0 ? 0 : av[4:3] == 2'd1 ? 1 : 2);
		if (neg)       b = ~b & 31;            // subtract: the inverted secondary source...
		else if (pxor) b = b ^ (a & 31);
		aop = pxor ? 0 : a;
		if (xtend) bop = (b >= 16) ? b - 32 : b;
		else       bop = neg ? b - 32 : b;     // ...as a negative number (+ 1 below)
		sum = aop + bop + int'(neg);
		if (p.DV2) sum = sum >>> 1;
		return wrap ? (sum & 31) : (sum < 0 ? 0 : sum > 31 ? 31 : sum);
	endfunction

	// apply, wait for the two-stage pipeline, compare all three components
	// The blue component's LSB as it enters the pixel processor (engine
	// control word CFBDLSB for the frame buffer pixel, IPNLSB for the
	// decoder's; WO 94/10642 Table VI, SDK CFBDLSB_* / PDCLSB_*): 0, bit 0,
	// bit 4, bit 5 of the 16-bit pixel.
	function automatic [4:0] blue_in(input [4:0] b, input bit bit5, input [1:0] sel);
		case (sel)
			2'd0: return {b[4:1], 1'b0};
			2'd1: return b;
			2'd2: return {b[4:1], b[4]};
			2'd3: return {b[4:1], bit5};
		endcase
	endfunction

	// The whole output pen (WO 94/10642 Tables VI and IX):
	//  * the decoder's blue LSB by IPNLSB, or for an unpacked ("totally
	//    literal") cel by its second preamble word's TLLSB;
	//  * NOBLK clear: a black result is written as 100 (red 1), so that it is
	//    not taken for background (SDK "The NOBLK Flag"); the blue LSB counts
	//    for the black detector only when B0POS = 2 puts it in the pen;
	//  * the subposition bits H (pen bit 0) and V (bit 15) for B0POS / B15POS
	//    = 3: the decoder's, swapped by SWAPHV unless an unpacked cel's PRE1
	//    has NOSWAP; with CFBDSUB and the frame buffer pixel a pixel processor
	//    source (1S = 1 or 2S = 2), the frame buffer pixel's bits 0 and 15.
	task automatic ppmp_check(input string what);
		bit [15:0] e;
		bit [ 4:0] cb, fb;
		bit [ 1:0] isel;
		bit        swap, h, v, b0, b15;
		@(negedge clk);
		repeat (3) @(negedge clk);
		isel = !flag.PACKED ? pre1.TLLSBIPN : ctl.IPNLSB;
		cb = blue_in(ipn.B, ipn.G[0], isel);
		fb = blue_in(cfbd[4:0], cfbd[5], ctl.CFBDLSB);
		e = {1'b0, 5'(ppmp_ref(ipn.R, cfbd[14:10], ipn.MR, pixc, flag.USEAV, flag.PXOR)),
		           5'(ppmp_ref(ipn.G, cfbd[ 9: 5], ipn.MG, pixc, flag.USEAV, flag.PXOR)),
		           5'(ppmp_ref(cb,    fb,          ipn.MB, pixc, flag.USEAV, flag.PXOR))};
		if (!flag.NOBLK && e[14:1] == 14'd0 && (ctl.B0POS != 2'd2 || !e[0])) e[14:10] = 5'd1;
		swap = ctl.SWAPHV && !(!flag.PACKED && pre1.NOSWAP);
		{h, v} = swap ? {ipn.SPV, ipn.SPH} : {ipn.SPH, ipn.SPV};
		if (ctl.CFBDSUB && (pixc.S1 || pixc.S2 == 2'd2)) {h, v} = {cfbd[0], cfbd[15]};
		case (ctl.B0POS)
			2'd0: b0 = 0;
			2'd1: b0 = 1;
			2'd2: b0 = e[0];
			2'd3: b0 = h;
		endcase
		case (ctl.B15POS)
			2'd0: b15 = 0;
			2'd1: b15 = 1;
			2'd2: b15 = 0;     // not defined ("xx"): the core writes 0
			2'd3: b15 = v;
		endcase
		e = {b15, e[14:1], b0};
		checks++;
		if (pen !== e)
			fail($sformatf("%s: PIXC 1S %0d MS %0d MF %0d DF %0d 2S %0d AV %02h 2D %0d USEAV %0d PXOR %0d NOBLK %0d PACKED %0d, CTL IPNLSB %0d CFBDLSB %0d B0POS %0d B15POS %0d SWAPHV %0d CFBDSUB %0d, PRE1 TLLSB %0d NOSWAP %0d, cel %0d/%0d/%0d H %0d V %0d AMV %0d/%0d/%0d, fb %04h: got %04h expected %04h",
			               what, pixc.S1, pixc.MS, pixc.MXF, pixc.DV1, pixc.S2, pixc.AV, pixc.DV2, flag.USEAV, flag.PXOR,
			               flag.NOBLK, flag.PACKED, ctl.IPNLSB, ctl.CFBDLSB, ctl.B0POS, ctl.B15POS, ctl.SWAPHV, ctl.CFBDSUB,
			               pre1.TLLSBIPN, pre1.NOSWAP, ipn.R, ipn.G, ipn.B, ipn.SPH, ipn.SPV, ipn.MR, ipn.MG, ipn.MB, cfbd, pen, e));
	endtask

	// ---------------- display path ----------------
	reg  [31:0] sbus = '0;
	reg         lsc_n = 1, rsc_n = 1;
	wire [23:0] rgb;
	wire        de, pcsc, field;
	wire [10:0] hcount;
	wire [ 8:0] vcount;
	CLIO_VIDEO video (
		.CLK(clk), .RST_N(~rst), .EN(1'b1), .PAL(1'b0), .VCE(1'b1), .HSYNC_N(1'b1), .VSYNC_N(1'b1),
		.HCNT(hcount), .VCNT(vcount), .FLD(field), .S(sbus), .LSC_N(lsc_n), .RSC_N(rsc_n), .PCSC(pcsc),
		.AD(rgb), .DE(de), .HINTREPOL_DISABLE(1'b0), .VINTREPOL_DISABLE(1'b0), .DBG_EXT(8'd0)
	);

	// MADAM's cel engine as a whole (engine control and clipping): its CPU
	// register port (offsets in the 0x03300100 block), the interrupt request
	// that pauses it; no bus grant, so it only requests its transfers
	reg  [31:0] se_di = '0;
	reg  [23:2] se_a = '0;
	reg         se_wr = 0, se_sel = 0, se_int = 0;
	wire [31:0] se_do;
	wire [ 3:0] se_stat;
	wire [ 2:0] se_scobld;
	MADAM_SE se (
		.CLK(clk), .RST_N(~rst), .EN(1'b1), .CE_R(1'b1), .CE_F(1'b1),
		.CPU_DI(se_di), .MADR(se_a), .MDTI(32'd0), .MDTO(se_do), .MWR(se_wr), .SEL(se_sel), .BUS_STATE(BUS_IDLE),
		.BUS_PB(1'b0), .GRANT(1'b0), .DMA_REG_ZERO(1'b0), .AG_CTL(), .CFB_ADDR_A(), .CFB_ADDR_B(),
		.CFB_RAS_A(), .CFB_RAS_B(), .CFB_WRITE_A(), .CFB_WRITE_B(), .CFB_READ(), .INT_REQ(se_int),
		.SCOBLD_REQ(se_scobld), .SCOB_SEL(), .SPRDATA_REQ(), .SPR_SEL(), .SPRDRAW_REQ(), .CFB_SEL(), .CFB_SUSPEND(1'b0),
		.SPRPAUS_REQ(), .SPREND_REQ(), .ACK(1'b0), .STAT(se_stat), .DBG_SPR_EN(1'b1), .DBG_EXT(8'd0)
	);
	// a CPU register write, held as long as the CPU interface holds it
	task automatic se_write(input [7:0] off, input [31:0] d, input int hold = 3);
		@(negedge clk); se_a = 22'(off >> 2); se_di = d; se_sel = 1; se_wr = 1;
		repeat (hold) @(negedge clk);
		se_sel = 0; se_wr = 0;
		repeat (3) @(negedge clk);
	endtask

	// CLIO's colour lookup table on its own: VDL colour words (bit 31 = 0;
	// bits 30-29 select all components, blue, green or red; 28-24 the entry)
	// and the background word (111 in bits 31-29)
	reg  [15:0] c_pix = '0;
	reg  [31:0] c_word = '0;
	reg         c_write = 0, c_bg = 0;
	wire [23:0] c_out;
	CLIO_CLUT clut (
		.CLK(clk), .RST_N(~rst), .EN(1'b1), .CE(1'b1), .INPUT(c_pix), .SCAP(c_word), .WRITE(c_write),
		.READCLKEN(1'b1), .COPY_EN(1'b0), .WRITE_EN(1'b1), .CURR_PREV(1'b1), .BG_DET(c_bg), .OUTPUT(c_out)
	);
	task automatic clut_write(input [31:0] w);
		@(negedge clk); c_word = w; c_write = 1;
		@(negedge clk); c_write = 0;
	endtask
	task automatic clut_read(input [4:0] e, input bit bg, output [23:0] q);
		@(negedge clk); c_pix = {1'b0, e, e, e}; c_bg = bg;
		repeat (3) @(negedge clk);
		q = c_out;
	endtask

	// a VDL word on the serial bus to both capture registers (control word),
	// or a pixel halfword pair to the left one
	task automatic send_ctl(input [31:0] w);
		@(negedge clk); sbus = w; lsc_n = 0; rsc_n = 0;
		repeat (6) @(negedge clk);
		lsc_n = 1; rsc_n = 1;
		repeat (6) @(negedge clk);
	endtask
	task automatic send_pix(input [15:0] p);
		@(negedge clk); sbus = {p, p}; lsc_n = 0; rsc_n = 1;
		repeat (8) @(negedge clk);
		lsc_n = 1;
		repeat (8) @(negedge clk);
	endtask

	// 9: a second CLIO_VIDEO with line timing
	reg         hs2_n = 1, l2_n = 1, r2_n = 1, line_run = 0;
	reg  [31:0] s2 = '0;
	wire [23:0] rgb2;
	wire        de2;
	wire [10:0] hc2;
	CLIO_VIDEO video2 (
		.CLK(clk), .RST_N(~rst), .EN(1'b1), .PAL(1'b0), .VCE(1'b1), .HSYNC_N(hs2_n), .VSYNC_N(1'b1),
		.HCNT(hc2), .VCNT(), .FLD(), .S(s2), .LSC_N(l2_n), .RSC_N(r2_n), .PCSC(),
		.AD(rgb2), .DE(de2), .HINTREPOL_DISABLE(1'b1), .VINTREPOL_DISABLE(1'b1), .DBG_EXT(8'd0)
	);
	always begin
		if (!line_run) @(posedge line_run);
		repeat (1556) @(negedge clk);
		hs2_n = 0;
		repeat (4) @(negedge clk);
		hs2_n = 1;
	end
	int        de2_cnt = 0;
	bit [23:0] de2_rgb [$];
	always @(posedge clk) if (de2) begin de2_cnt++; de2_rgb.push_back(rgb2); end
	task automatic at_h(input int h);
		@(negedge clk iff hc2 == 11'(h));
	endtask
	// n pixels, one port per strobe, alternating, every other tick (MADAM_SPORT LSC / RSC)
	task automatic line_pixels(input int n, input [15:0] base);
		at_h(30);
		for (int i = 0; i < n; i++) begin
			@(negedge clk); s2 = {base + 16'(i), base + 16'(i)}; l2_n = i[0]; r2_n = ~i[0];
			@(negedge clk); l2_n = 1; r2_n = 1;
		end
	endtask
	// a VDL download of len words: both ports for len ticks (CLUT_TRANS_EXEC)
	task automatic vdl_download(input int h, input int len);
		at_h(h);
		for (int i = 0; i < len; i++) begin
			@(negedge clk); s2 = {3'b000, 5'(i), 24'h406080}; l2_n = 0; r2_n = 0;
		end
		@(negedge clk); l2_n = 1; r2_n = 1;
	endtask

	// 11: a VDL download of the given words (both ports, one word per tick)
	task automatic vdl_words(input int h, input bit [31:0] w [$]);
		at_h(h);
		foreach (w[i]) begin
			@(negedge clk); s2 = w[i]; l2_n = 0; r2_n = 0;
		end
		@(negedge clk); l2_n = 1; r2_n = 1;
	endtask
	// n pixels with pen {e,e,e}, e = 0..31 in turn
	task automatic line_pens(input int n);
		at_h(30);
		for (int i = 0; i < n; i++) begin
			bit [4:0] e;
			e = 5'(i);
			@(negedge clk); s2 = {2{1'b0, e, e, e}}; l2_n = i[0]; r2_n = ~i[0];
			@(negedge clk); l2_n = 1; r2_n = 1;
		end
	endtask
	// all 32 colour entries (all components) and the background in one colour
	function automatic void palette_words(input [23:0] c, output bit [31:0] w [$]);
		w.delete();
		for (int e = 0; e < 32; e++) w.push_back({3'b000, 5'(e), c});
		w.push_back({8'hE0, c});
	endfunction

	// 10: VE with its own video clock
	reg         vclk = 0, ve_rst_n = 0;
	always #10 vclk = ~vclk;
	wire        ve_hb_n, ve_vb_n, ve_dclk;
	VE ve2 (
		.MCLK(clk), .VCLK(vclk), .RST_N(ve_rst_n), .EN(1'b1), .PAL(1'b0), .VCE(1'b1), .AD(24'h0), .DE(1'b0),
		.HSYNC_N(), .VSYNC_N(), .RGB(), .HS_N(), .VS_N(), .HBLK_N(ve_hb_n), .VBLK_N(ve_vb_n), .DCLK(ve_dclk),
		.DBG_EXT(8'd0), .DBG_BORD_DIS(1'b0), .DBG_HS_START(), .DBG_HS_END()
	);

	// display control word: 110 in bits 31..29, the fields in 28..0
	function automatic [31:0] dcw(input DispCtrl_t d);
		return {3'b110, 29'(d)};
	endfunction

	initial begin
		repeat (2) @(negedge clk);
		rst = 0;

		// ---------------- 1a. random sweep over every field ----------------
		ctl.B0POS = 2'd2;          // bit 0 of the pen from the pixel processor
		ctl.B15POS = 2'd0;
		flag.DOVER = 2'b01;        // PIXC A
		for (int n = 0; n < 200000; n++) begin
			pixc = PPMPCx_t'($urandom());
			flag.USEAV = $urandom_range(0, 1);
			flag.PXOR  = $urandom_range(0, 1);
			flag.NOBLK  = $urandom_range(0, 1);
			flag.PACKED = $urandom_range(0, 1);
			ctl.IPNLSB  = 2'($urandom());
			ctl.CFBDLSB = 2'($urandom());
			ctl.B0POS   = 2'($urandom());
			ctl.B15POS  = 2'($urandom());
			ctl.SWAPHV  = $urandom_range(0, 1);
			ctl.CFBDSUB = $urandom_range(0, 1);
			pre1.TLLSBIPN = 2'($urandom());
			pre1.NOSWAP   = $urandom_range(0, 1);
			if (flag.USEAV && pixc.AV[4:3] == 2'd3) pixc.AV[4:3] = 2'($urandom_range(0, 2));
			ipn = IPN_t'($urandom());
			cfbd = 16'($urandom());
			ppmp_check("sweep");
		end
		$display("[%0t] pixel processor: random sweep, %0d checks, %0d errors", $realtime, checks, errors);
		// the rest with the SDK's CECONTROL_DEFAULT blue LSB selection (bit 0
		// of each) and B0POS from the pixel processor
		ctl.IPNLSB = 2'd1; ctl.CFBDLSB = 2'd1; ctl.B0POS = 2'd2; ctl.B15POS = 2'd0;
		ctl.SWAPHV = 0; ctl.CFBDSUB = 0; pre1 = '0; pre1.TLLSBIPN = 2'd1;

		// ---------------- 1b. every AV, source and frame buffer value ----------------
		pixc = '0; flag.PXOR = 0; flag.USEAV = 1; ipn = '0;
		pixc.MXF = 3'd7; pixc.DV1 = 2'd3;      // first source x 8 / 8
		pixc.S2 = 2'd2;                        // secondary source: frame buffer
		for (int av = 0; av < 32; av++) begin
			if (av[4:3] == 2'd3) continue;
			for (int a = 0; a < 32; a++)
				for (int b = 0; b < 32; b++) begin
					pixc.AV = 5'(av);
					ipn.R = 5'(a); ipn.G = 5'(a); ipn.B = 5'(a);
					cfbd = {1'b0, 5'(b), 5'(b), 5'(b)};
					pixc.DV2 = (b & 1) ? 1'b1 : 1'b0;
					ppmp_check("AV sweep");
				end
		end
		$display("[%0t] pixel processor: AV x source x frame buffer, %0d checks in all, %0d errors", $realtime, checks, errors);

		// ---------------- 1c. MS = 10, divider code 00 (/16) ----------------
		pixc = '0; flag = '0; flag.DOVER = 2'b01; ipn = '0; cfbd = '0;
		pixc.MS = 2'd2; pixc.DV1 = 2'd1; pixc.S2 = 2'd0;
		for (int c = 0; c < 32; c++) begin
			ipn.R = 5'(c); ipn.G = 5'(c); ipn.B = 5'(c);
			ppmp_check("MS=10");
		end
		$display("[%0t] pixel processor: %0d checks, %0d errors", $realtime, checks, errors);

		// ---------------- 2. VDL display control word, "maintain prior setting" ----------------
		begin
			DispCtrl_t d, k;
			int e0;
			e0 = errors;
			for (int f = 0; f < 6; f++)
				for (int v = 0; v < 3; v++) begin
					// explicit setting of every field, then 11 in field f only
					d = '0;
					d.VSUB = 2'((v + 1) % 3); d.HSUB = 2'((v + 2) % 3); d.BLSB = 2'(v);
					d.WVSUB = 2'(v); d.WHSUB = 2'((v + 1) % 3); d.WBLSB = 2'((v + 2) % 3);
					send_ctl(dcw(d));
					checks++;
					if (video.DISPCTL !== d) fail($sformatf("control word %08h loaded as %08h", dcw(d), {3'b110, 29'(video.DISPCTL)}));
					k = d;
					k.MSBREP = 1; k.SWAPHV = 1;            // other fields of the word still load
					case (f)
						0: k.VSUB  = 2'b11;
						1: k.HSUB  = 2'b11;
						2: k.BLSB  = 2'b11;
						3: k.WVSUB = 2'b11;
						4: k.WHSUB = 2'b11;
						5: k.WBLSB = 2'b11;
					endcase
					send_ctl(dcw(k));
					k = d; k.MSBREP = 1; k.SWAPHV = 1;     // expected: field f as before
					checks++;
					if (video.DISPCTL !== k)
						fail($sformatf("field %0d = 11 (prior setting %0d): DISPCTL %08h, expected %08h", f, v,
						               29'(video.DISPCTL), 29'(k)));
				end
			// the blue pen LSB follows the kept BLSB setting: 0, green LSB (bit 5), frame buffer bit 0
			for (int v = 0; v < 3; v++) begin
				d = '0; d.BLSB = 2'(v);
				send_ctl(dcw(d));
				d.BLSB = 2'b11;
				send_ctl(dcw(d));
				send_pix(16'h0421);                       // bit 5 and bit 0 set
				checks++;
				if (video.INPUT !== (v == 0 ? 16'h0420 : 16'h0421))
					fail($sformatf("BLSB %0d kept: pen %04h, expected %04h", v, video.INPUT, v == 0 ? 16'h0420 : 16'h0421));
				send_pix(16'h0401);                       // bit 0 set, bit 5 clear
				checks++;
				if (video.INPUT !== (v == 2 ? 16'h0401 : 16'h0400))
					fail($sformatf("BLSB %0d kept: pen %04h, expected %04h", v, video.INPUT, v == 2 ? 16'h0401 : 16'h0400));
			end
			$display("[%0t] display control word: %0d errors", $realtime, errors - e0);
		end

		// ---------------- 3. CLUT bypass expansion ----------------
		begin
			DispCtrl_t d;
			int e0;
			bit [2:0] seen [$];
			bit [4:0] comps [5];
			comps = '{5'd0, 5'd1, 5'd20, 5'd31, 5'd9};
			e0 = errors;
			d = '0; d.BYPASS = 1; d.BLSB = 2'd2;
			for (int m = 0; m < 2; m++) begin
				d.MSBREP = m[0];
				send_ctl(dcw(d));
				foreach (comps[i]) begin
					bit [4:0] c;
					bit [7:0] x;
					c = comps[i];
					send_pix({1'b1, c, c, c});
					x = {c, m ? c[4:2] : 3'b000};
					checks++;
					if (video.BYPASS_OUTPUT !== {x, x, x})
						fail($sformatf("bypass, MSBREP %0d: component %0d gives %06h, expected %06h", m, c, video.BYPASS_OUTPUT, {x, x, x}));
				end
			end
			// RNDM: the 3 LSBs come from the pseudo-random generator
			d.MSBREP = 0; d.RNDM = 1;
			send_ctl(dcw(d));
			for (int i = 0; i < 32; i++) begin
				bit [23:0] o;
				send_pix(16'hD294);                       // 20, 20, 20
				o = video.BYPASS_OUTPUT;
				checks++;
				if (o[23:19] != 5'd20 || o[15:11] != 5'd20 || o[7:3] != 5'd20)
					fail($sformatf("bypass, RNDM: %06h does not keep the 5 MSBs of each component", o));
				seen.push_back(o[2:0]);
			end
			begin
				int distinct;
				bit [7:0] m8;
				m8 = '0;
				foreach (seen[i]) m8[seen[i]] = 1;
				distinct = $countones(m8);
				checks++;
				if (distinct < 4) fail($sformatf("bypass, RNDM: only %0d different LSB values in 32 pixels", distinct));
			end
			$display("[%0t] CLUT bypass expansion: %0d errors", $realtime, errors - e0);
		end

		// ---------------- 4. single-component palette writes ----------------
		begin
			int e0;
			bit [4:0] ents [3];
			e0 = errors;
			ents = '{5'd7, 5'd0, 5'd31};
			foreach (ents[i])
				for (int c = 0; c < 3; c++) begin
					bit [4:0] e, o;
					bit [23:0] q, x;
					e = ents[i]; o = e ^ 5'd1;
					clut_write({1'b0, 2'b00, e, 24'h112233});        // all components of entry e
					clut_write({1'b0, 2'b00, o, 24'h778899});        // and of its neighbour
					clut_write(32'hE0445566);                        // background
					case (c)                                          // one component: red 11, green 10, blue 01
						0: begin clut_write({1'b0, 2'b11, e, 24'hAA0000}); x = 24'hAA2233; end
						1: begin clut_write({1'b0, 2'b10, e, 24'h00AA00}); x = 24'h11AA33; end
						2: begin clut_write({1'b0, 2'b01, e, 24'h0000AA}); x = 24'h1122AA; end
					endcase
					clut_read(e, 0, q);
					checks++;
					if (q !== x) fail($sformatf("palette entry %0d after a write of component %0d: %06h, expected %06h", e, c, q, x));
					clut_read(o, 0, q);
					checks++;
					if (q !== 24'h778899) fail($sformatf("palette entry %0d changed by a write to entry %0d: %06h", o, e, q));
					clut_read(e, 1, q);
					checks++;
					if (q !== 24'h445566) fail($sformatf("background %06h after a write of component %0d of entry %0d, expected 445566", q, c, e));
				end
			$display("[%0t] palette writes: %0d errors", $realtime, errors - e0);
		end

		// ---------------- 5. "Colors only" ----------------
		// A display control word with COLONLY: the rest of the VDL entry's
		// download (one CLUT download window) takes colour words only (US
		// patent 5,502,462 Table 6 bit 1; Opera vdlp_process_optional_cmds).
		begin
			DispCtrl_t d;
			int e0;
			e0 = errors;
			// a window without COLONLY: a second control word loads
			@(posedge video.WRITE_EN);
			d = '0; d.BLSB = 2'd2;
			send_ctl(dcw(d));
			d.BYPASS = 1;
			send_ctl(dcw(d));
			checks++;
			if (!video.DISPCTL.BYPASS) fail("second control word of a download without COLONLY not loaded");
			// COLONLY: later control words of the same download are ignored
			@(posedge video.WRITE_EN);
			d = '0; d.BLSB = 2'd2; d.COLONLY = 1;
			send_ctl(dcw(d));
			checks++;
			if (!video.DISPCTL.COLONLY || video.DISPCTL.BYPASS) fail("control word with COLONLY not loaded");
			d = '0; d.BLSB = 2'd1; d.BYPASS = 1;
			send_ctl(dcw(d));
			checks++;
			if (video.DISPCTL.BYPASS || video.DISPCTL.BLSB != 2'd2)
				fail($sformatf("control word after COLONLY in the same download loaded (BYPASS %b BLSB %0d)",
				               video.DISPCTL.BYPASS, video.DISPCTL.BLSB));
			// the next download takes control words again
			@(posedge video.WRITE_EN);
			send_ctl(dcw(d));
			checks++;
			if (!video.DISPCTL.BYPASS || video.DISPCTL.BLSB != 2'd1)
				fail("control word in the download after a COLONLY one not loaded");
			$display("[%0t] colors only: %0d errors", $realtime, errors - e0);
		end

		// ---------------- 6. CLIO: PEN MSB / LSB swap ----------------
		// Display control word bit 10 (SwapPENms, SDK swapPenVH) swaps the
		// MSB and LSB of the pen halfword before CLIO interprets it: the
		// swapped MSB decides the CLUT bypass, the swapped LSB is the blue LSB
		// that BLSB = 10 takes from the frame buffer.
		begin
			DispCtrl_t d;
			int e0;
			bit [15:0] px [4];
			e0 = errors;
			px = '{16'h8400, 16'h0401, 16'h8401, 16'h1234};
			@(posedge video.WRITE_EN);   // a new download: no COLONLY lock
			for (int sw = 0; sw < 2; sw++) begin
				d = '0; d.BYPASS = 1; d.BLSB = 2'd2; d.SWAPHV = sw[0];
				send_ctl(dcw(d));
				foreach (px[i]) begin
					bit [15:0] x;
					x = sw ? {px[i][0], px[i][14:1], px[i][15]} : px[i];
					send_pix(px[i]);
					checks++;
					if (video.INPUT !== x || video.BYPASS_EN !== x[15])
						fail($sformatf("SwapPENms %0d: pen %04h read as %04h (bypass %b), expected %04h (bypass %b)",
						               sw, px[i], video.INPUT, video.BYPASS_EN, x, x[15]));
				end
			end
			$display("[%0t] PEN swap: %0d errors", $realtime, errors - e0);
		end

		// ---------------- 7. cel engine: SPRSTOP ----------------
		// SPRSTRT (+0x00) starts the engine (SPRON, the first CCB requested);
		// an interrupt pauses it; SPRSTOP (+0x04) aborts it: SPRON and the
		// pause clear, nothing is requested, the CPU's registers stay, and a
		// new SPRSTRT starts it again (the SDK's DrawSprytes; Opera: idle).
		begin
			int e0;
			SCoBCtl_t c;
			e0 = errors;
			c = '0; c.B0POS = 2'd2; c.CFBDLSB = 2'd1; c.ASCALL = 1;
			se_write(8'h10, 32'(c));
			se_write(8'h34, {5'd0, 11'd239, 5'd0, 11'd319});
			for (int k = 0; k < 2; k++) begin
				se_write(8'h00, 32'd0);                  // SPRSTRT
				checks++;
				if (!se_stat[0] || se_scobld == '0) fail($sformatf("SPRSTRT (%0d): SPRON %b, CCB load request %0d", k, se_stat[0], se_scobld));
				if (k == 0) begin
					@(negedge clk); se_int = 1;           // an interrupt pauses it
					repeat (3) @(negedge clk); se_int = 0;
					repeat (3) @(negedge clk);
					checks++;
					if (!se.PAUSE || !se.SPRPAUS_REQ) fail("interrupt did not pause the engine");
				end
				se_write(8'h04, 32'd0);                  // SPRSTOP
				checks++;
				if (se_stat[0] || se.PAUSE || se.SPRPAUS_REQ || se_scobld != '0 || se.MAIN_ST.name() != "MS_IDLE")
					fail($sformatf("SPRSTOP (%s): SPRON %b PAUSE %b pause request %b CCB request %0d",
					               k == 0 ? "paused" : "waiting for its CCB", se_stat[0], se.PAUSE, se.SPRPAUS_REQ, se_scobld));
				checks++;
				if (se.SCOBCTL !== c || se.REGCTL1.CLIPY != 11'd239)
					fail("SPRSTOP changed the CPU's registers");
			end
			$display("[%0t] cel engine SPRSTOP: %0d errors", $realtime, errors - e0);
		end

		// ---------------- 8. regional fill end by the clip Y limit ----------------
		// With ASCALL, a corner engine's regional fill ends below the clip
		// rectangle: row Y (signed) > clip Y (REGCTL1 bits 26-16, unsigned,
		// the last row).
		begin
			int e0;
			int cys [6], ys [7];
			SCoBCtl_t c;
			e0 = errors;
			cys = '{0, 239, 1023, 1024, 1500, 2047};
			for (int asc = 0; asc < 2; asc++) begin
				c = '0; c.ASCALL = asc[0];
				se_write(8'h10, 32'(c));
				foreach (cys[i]) begin
					se_write(8'h34, {5'd0, 11'(cys[i]), 5'd0, 11'd319});
					ys = '{-5, 0, 100, cys[i] - 1, cys[i], cys[i] + 1, -2048};
					foreach (ys[j]) begin
						bit x;
						if (ys[j] > 2047) continue;
						force se.MATH_A_Y = 12'(ys[j]);
						force se.MATH_B_Y = 12'(ys[j]);
						@(negedge clk); #1;
						x = asc && ys[j] > cys[i];
						checks++;
						if (se.REGIS_A_TERMINATE !== x || se.REGIS_B_TERMINATE !== x)
							fail($sformatf("ASCALL %0d clip Y %0d row %0d: end of regional fill A/B %b/%b, expected %b",
							               asc, cys[i], ys[j], se.REGIS_A_TERMINATE, se.REGIS_B_TERMINATE, x));
					end
				end
			end
			release se.MATH_A_Y;
			release se.MATH_B_Y;
			$display("[%0t] clip Y limit: %0d errors", $realtime, errors - e0);
		end

		// ---------------- 9. VDL downloads are not pixels ----------------
		begin
			int e0, d0;
			bit [23:0] r0 [$];
			e0 = errors;
			line_run = 1;
			repeat (2) at_h(5);                                  // the line timing runs
			for (int k = 0; k < 3; k++) begin
				int h;
				h = k == 0 ? 1340 : k == 1 ? 1480 : 1540;      // usual, late, into the next line
				at_h(5);
				de2_cnt = 0;
				vdl_download(h, 34);
				at_h(5); at_h(1500);                               // through the next line
				checks++;
				if (de2_cnt != 0) fail($sformatf("VDL download of 34 words at HCOUNT %0d on a line without pixels: %0d DE", h, de2_cnt));
			end
			// a line of pixels alone, then the same line with a late download after it
			at_h(5);
			de2_cnt = 0; de2_rgb.delete();
			line_pixels(600, 16'h1000);
			at_h(5); at_h(1500);
			d0 = de2_cnt; r0 = de2_rgb;
			checks++;
			if (d0 == 0) fail("a line of 600 pixel captures gives no DE");
			at_h(5);
			de2_cnt = 0; de2_rgb.delete();
			line_pixels(600, 16'h1000);
			vdl_download(1540, 34);
			at_h(5); at_h(1500);
			checks++;
			if (de2_cnt != d0) fail($sformatf("a pixel line with a late VDL download: %0d DE, %0d without it", de2_cnt, d0));
			checks++;
			if (de2_rgb != r0) fail("a pixel line with a late VDL download: the colours differ from the same line without it");
			line_run = 0;
			$display("[%0t] VDL downloads vs. pixels: %0d DE per pixel line, %0d errors", $realtime, d0, errors - e0);
		end

		// ---------------- 11. late palette downloads ----------------
		begin
			int e0, starts [5];
			bit [31:0] w [$];
			e0 = errors;
			starts = '{1340, 1362, 1373, 1390, 1450};
			line_run = 1;
			repeat (2) at_h(5);
			for (int dir = 0; dir < 2; dir++) begin
				bit [23:0] from_c, to_c;
				from_c = dir ? 24'h000000 : 24'hFFFFFF;
				to_c   = dir ? 24'hFFFFFF : 24'h000000;
				foreach (starts[k]) begin
					int wrong;
					palette_words(from_c, w);
					at_h(5); vdl_words(1340, w);                    // in the window: the old colours
					palette_words(to_c, w);
					at_h(5); vdl_words(starts[k], w);               // the fade
					at_h(5); at_h(1500);                            // a line for the palette copy
					at_h(5);
					de2_cnt = 0; de2_rgb.delete();
					line_pens(320);
					at_h(1500);
					wrong = 0;
					// pens 0 and 1 are taken for background (pen 000, blue LSB not
					// counted) and show the background colour, not a palette entry
					foreach (de2_rgb[i]) if (i % 32 >= 2 && de2_rgb[i] !== to_c) wrong++;
					checks++;
					if (de2_cnt == 0 || wrong != 0)
						fail($sformatf("palette %s, download of 33 words started at HCOUNT %0d: %0d of %0d pixels not in the new colour",
						               dir ? "fade in" : "fade out", starts[k], wrong, de2_cnt));
				end
			end
			line_run = 0;
			$display("[%0t] late palette downloads: %0d errors", $realtime, errors - e0);
		end

		// ---------------- 10. VE outputs in reset ----------------
		begin
			int e0;
			e0 = errors;
			ve_rst_n = 1;
			for (int ph = 0; ph < 4; ph++) begin
				int bad_dclk, bad_blk;
				@(posedge vclk iff ve_hb_n && ve_vb_n);           // active display
				@(posedge vclk iff ve2.DCLK_DIV == 2'(ph));
				#1 ve_rst_n = 0;
				repeat (4) @(posedge vclk);                      // its reset synchroniser
				bad_dclk = 0; bad_blk = 0;
				repeat (400) begin
					@(posedge vclk); #1;
					if (ve_dclk !== 1'b0) bad_dclk++;
					if (ve_hb_n !== 1'b0 || ve_vb_n !== 1'b0) bad_blk++;
				end
				checks++;
				if (bad_dclk) fail($sformatf("VE reset at dot-clock phase %0d: DCLK set in %0d of 400 clocks", ph, bad_dclk));
				checks++;
				if (bad_blk) fail($sformatf("VE reset at dot-clock phase %0d: not blanking in %0d of 400 clocks", ph, bad_blk));
				ve_rst_n = 1;
			end
			$display("[%0t] VE in reset: %0d errors", $realtime, errors - e0);
		end

		// ---------------- 12. PIXC half per pixel ----------------
		begin
			int e0;
			e0 = errors;
			// half A: the cel unchanged (x8 / 8); half B: cel / 16 minus the
			// cel, wrapped (1S x1 / 16; 2S = the cel, AV = 00101: NEG, wrap):
			// the two give different pens for every cel
			pixc_a = '0; pixc_a.MXF = 3'd7; pixc_a.DV1 = 2'd3;
			pixc_b = '0; pixc_b.S2 = 2'd3; pixc_b.AV = 5'b00101;
			ctl = '0; ctl.B0POS = 2'd2; ctl.B15POS = 2'd0; ctl.IPNLSB = 2'd1; ctl.CFBDLSB = 2'd1;
			flag = '0; flag.USEAV = 1; flag.NOBLK = 1; flag.PACKED = 1;
			pre1 = '0; cfbd = '0;
			for (int pov = 0; pov < 4; pov++) for (int d = 0; d < 2; d++) for (int c = 1; c < 32; c += 5) begin
				bit half_b;
				bit [4:0] e;
				flag.DOVER = 2'(pov);
				ipn = '0; ipn.D = d[0]; ipn.R = 5'(c); ipn.G = 5'(c); ipn.B = 5'(c);
				repeat (4) @(negedge clk);
				half_b = pov == 3 ? 1'b1 : pov == 2 ? 1'b0 : d[0];
				e = half_b ? 5'((c >> 4) - c) : 5'(c);
				checks++;
				if (pen2[14:10] !== e || pen2[9:5] !== e || pen2[4:0] !== e)
					fail($sformatf("POVER %0d%0d, pixel P-mode %0d, cel %0d: pen %04h, expected %0d per component (PIXC %s half)",
					               pov[1], pov[0], d, c, pen2, e, half_b ? "second" : "first"));
			end
			$display("[%0t] PIXC half per pixel: %0d errors", $realtime, errors - e0);
		end

		$display("tb_gfx: %0d checks, %0d errors", checks, errors);
		// a failure ends with a non-zero exit status ($fatal), so scripts see it
		if (errors == 0) begin $display("tb_gfx: PASS"); $finish; end
		else $fatal(1, "tb_gfx: FAIL");
	end
endmodule
