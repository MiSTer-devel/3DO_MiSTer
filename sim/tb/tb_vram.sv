// Testbench: VRAM (vram.sv) and its DDR3 path (ddram.sv), wired as in 3DO.sv.
//
// Real modules: two P3DO_VRAM (left/right halves) and ddram.sv, on a model
// of the MiSTer DDRAM interface (64-bit Avalon-MM bursts, with busy periods).
// A bus-functional model drives the VRAM pins the way MADAM does for:
//   * read transfers (full and split) followed by serial read-out (SC/SQ)
//   * random CPU writes and reads (ddram.sv's random access ports)
//   * write transfers (shift register -> row: SPORT row copy); the CPU's
//     copies (SP_CPU, MADAM's SPORT space) use their own shift register, so
//     video transfers and serial read-out between a copy's read and write
//     transfer must not change what the copy stores, the copy must not
//     change what the video read-out shows, and a copy into the row the
//     video shift register holds must reach its next split transfer
//   * flash writes (colour register -> whole row)
//   * write transfers with the halves out of step (ddram.sv's two passes)
//   * write masks on copies and flash writes in on-chip and DDR rows, and
//     split transfers after writes into the half-row the video shift
//     register holds
//   * random reads after a flash write, a masked flash write or a page copy
//     into the block ddram.sv last read
// and checks every word shifted out or read against a reference model of
// VRAM. The bus-functional model and the test phases are from tb_rtcache of
// the 3DO_GameBub port, without its read-transfer cache, SRAM and SDRAM.
//
// Copyright (c) 2026 Adam Polkosnik
// SPDX-License-Identifier: GPL-3.0-or-later

`timescale 1ns/1ps

module tb_vram;
	reg clk_mem = 0, clk_sys = 0;
	always #5  clk_mem = ~clk_mem;
	always #10 clk_sys = ~clk_sys;
	reg rst = 1;

	localparam [3:0] BRAM1_OFFS = 4'hC;   // on-chip block at 0xC0000: test rows below it

	// ---------------- VRAM pins (both halves driven alike) ----------------
	reg  [17:0] A = 0;
	reg  [15:0] DL = 0, DR = 0;
	reg         RAS_N = 1, CAS_N = 1, OE_N = 1, DSF1 = 0, SC = 0;
	reg         SP_CPU = 0;    // the access is the CPU's SPORT access (MADAM CPU_SPORT_SEL)
	reg  [ 1:0] WE_N = 2'b11;
	wire [15:0] SQL, SQR;
	wire        RDYL, RDYR;

	wire [17:0] v_laddr, v_raddr;
	wire        v_lwr, v_rwr, v_lrd, v_rrd, v_lfw;
	wire [31:0] bldata, brdata;

	// The video DMA's transfers go to one VRAM half at a time (MADAM's
	// LEFT_TRANS / RIGHT_TRANS): l_off / r_off keep that half's RAS high.
	reg l_off = 0, r_off = 0;
	wire v_lbusy, v_rbusy;

	wire [63:0] ddr_bout;
	wire        ddr_blte, ddr_brte, ddr_bbusy;
	wire [15:0] w_ldout, w_rdout;

	// as in 3DO.sv: the VRAM halves' transfers go straight to ddram.sv's burst ports
	P3DO_VRAM #(0) vram_l (
		.CLK(clk_sys), .CLK_MEM(clk_mem), .RST_N(~rst),
		.A(A), .D(DL), .Q(), .RAS_N(RAS_N | l_off), .CAS_N(CAS_N), .WE_N(WE_N), .OE_N(OE_N), .DSF1(DSF1),
		.SC(SC), .SE_N(1'b0), .SQ(SQL), .QSF(), .RDY(RDYL),
		.EQ(w_ldout), .ESADDR(v_laddr), .ESDATA(bldata), .ESWR(v_lwr), .ESRD(v_lrd), .ESFW(v_lfw),
		.ESQ({ddr_bout[63:48], ddr_bout[31:16]}), .ESTE(ddr_blte),
		.BRAM4_OFFS(4'h0), .BRAM2_OFFS(4'h4), .BRAM1_OFFS(BRAM1_OFFS), .SP_CPU(SP_CPU),
		.DP(DR), .PEER_BUSY(v_rbusy), .XBUSY(v_lbusy), .DBG_WAIT_CNT()
	);
	P3DO_VRAM #(0) vram_r (
		.CLK(clk_sys), .CLK_MEM(clk_mem), .RST_N(~rst),
		.A(A), .D(DR), .Q(), .RAS_N(RAS_N | r_off), .CAS_N(CAS_N), .WE_N(WE_N), .OE_N(OE_N), .DSF1(DSF1),
		.SC(SC), .SE_N(1'b0), .SQ(SQR), .QSF(), .RDY(RDYR),
		.EQ(w_rdout), .ESADDR(v_raddr), .ESDATA(brdata), .ESWR(v_rwr), .ESRD(v_rrd), .ESFW(),
		.ESQ({ddr_bout[47:32], ddr_bout[15:0]}), .ESTE(ddr_brte),
		.BRAM4_OFFS(4'h0), .BRAM2_OFFS(4'h4), .BRAM1_OFFS(BRAM1_OFFS), .SP_CPU(SP_CPU),
		.DP(DL), .PEER_BUSY(v_lbusy), .XBUSY(v_rbusy), .DBG_WAIT_CNT()
	);

	// ---------------- ddram.sv ----------------
	wire [63:0] ddr_bin = {bldata[31:16], brdata[31:16], bldata[15:0], brdata[15:0]};
	wire        DDRAM_BUSY, DDRAM_DOUT_READY, DDRAM_RD, DDRAM_WE;
	wire [ 7:0] DDRAM_BURSTCNT, DDRAM_BE;
	wire [28:0] DDRAM_ADDR;
	wire [63:0] DDRAM_DOUT, DDRAM_DIN;

	// CPU random writes and reads go to ddram.sv's random access ports
	reg  [17:0] w_addr = 0;
	reg  [15:0] w_ldata = 0, w_rdata = 0;
	reg  [ 1:0] w_lwe = 0, w_rwe = 0;
	reg         w_ras = 0;
	reg         w_lrd = 0, w_rrd = 0;
	reg         w_ras_d = 0;           // RAS at the clock before
	always @(posedge clk_mem) w_ras_d <= w_ras;

	ddram ddram (
		.DDRAM_CLK(), .DDRAM_BUSY(DDRAM_BUSY), .DDRAM_BURSTCNT(DDRAM_BURSTCNT), .DDRAM_ADDR(DDRAM_ADDR),
		.DDRAM_DOUT(DDRAM_DOUT), .DDRAM_DOUT_READY(DDRAM_DOUT_READY), .DDRAM_RD(DDRAM_RD),
		.DDRAM_DIN(DDRAM_DIN), .DDRAM_BE(DDRAM_BE), .DDRAM_WE(DDRAM_WE),
		.clk(clk_mem), .rst(rst),
		.io_addr('0), .io_din('0), .io_we('0), .io_rd(1'b0), .io_dout(), .io_busy(),
		.nvram_addr('0), .nvram_din('0), .nvram_wr(1'b0), .nvram_rd(1'b0), .nvram_dout(), .nvram_busy(),
		.sclk(1'b0),
		.laddr(w_addr), .ldin(w_ldata), .lras(w_ras), .lras_d(w_ras_d), .lwe(w_lwe), .lrd(w_lrd), .ldout(w_ldout),
		.raddr(w_addr), .rdin(w_rdata), .rras(w_ras), .rras_d(w_ras_d), .rwe(w_rwe), .rrd(w_rrd), .rdout(w_rdout),
		.busy(),
		.bladdr(v_laddr), .blwr(v_lwr), .blrd(v_lrd), .braddr(v_raddr), .brwr(v_rwr),
		.brrd(v_rrd), .bfw(v_lfw), .ba(), .bin(ddr_bin), .bout(ddr_bout),
		.blte(ddr_blte), .brte(ddr_brte), .bbusy(ddr_bbusy)
	);

	// ---------------- DDRAM interface model ----------------
	// A command (RD or WE) is accepted on a clock edge where BUSY is low. A
	// write burst's first beat gives the address and the beat count; every
	// further beat is accepted the same way. A read returns its beats with
	// DOUT_READY after a latency, BUSY low meanwhile. Between commands BUSY
	// goes high for a few clocks now and then, as the DDR3 bridge's does.
	bit [63:0] ddr_mem [bit [28:0]];
	reg        ddr_busy = 0;
	reg [63:0] ddr_q = '0;
	reg        ddr_qv = 0;
	int        ddr_wleft = 0, ddr_rleft = 0, ddr_rlat = 0, ddr_busy_left = 0;
	bit [28:0] ddr_wa, ddr_ra;
	int        ddr_writes = 0, ddr_reads = 0, ddr_busy_cmds = 0;
	bit        ddr_cmd_wait = 0;
	assign DDRAM_BUSY = ddr_busy;
	assign DDRAM_DOUT = ddr_q;
	assign DDRAM_DOUT_READY = ddr_qv;
	always @(posedge clk_mem) begin
		bit rd_act;
		rd_act = ddr_rleft != 0;   // a read's data is still to come (ddram.sv takes it only with BUSY low)
		ddr_qv <= 0;
		if ((DDRAM_WE || DDRAM_RD) && ddr_busy && !ddr_cmd_wait) ddr_busy_cmds++;
		ddr_cmd_wait <= (DDRAM_WE || DDRAM_RD) && ddr_busy;
		if (!ddr_busy && DDRAM_WE) begin
			bit [28:0] a;
			bit [63:0] d;
			if (ddr_wleft == 0) begin a = DDRAM_ADDR; ddr_wleft = DDRAM_BURSTCNT; end
			else a = ddr_wa;
			d = ddr_mem.exists(a) ? ddr_mem[a] : 64'h0;
			for (int b = 0; b < 8; b++) if (DDRAM_BE[b]) d[b*8 +: 8] = DDRAM_DIN[b*8 +: 8];
			ddr_mem[a] = d;
			ddr_wa = a + 29'd1;
			ddr_wleft--;
			ddr_writes++;
		end
		else if (!ddr_busy && DDRAM_RD && ddr_rleft == 0) begin
			ddr_ra = DDRAM_ADDR;
			ddr_rleft = DDRAM_BURSTCNT;
			ddr_rlat = 6;
			ddr_reads++;
		end
		if (ddr_rleft != 0) begin
			if (ddr_rlat != 0) ddr_rlat--;
			else begin
				ddr_q <= ddr_mem.exists(ddr_ra) ? ddr_mem[ddr_ra] : 64'h0;
				ddr_qv <= 1;
				ddr_ra = ddr_ra + 29'd1;
				ddr_rleft--;
			end
		end
		// busy periods, not during a read's data
		if (ddr_busy_left != 0) begin
			ddr_busy_left--;
			if (ddr_busy_left == 0) ddr_busy <= 0;
		end else if (!rd_act && ddr_rleft == 0 && !rst && ($urandom() % 24) == 0) begin
			ddr_busy <= 1;
			ddr_busy_left = 1 + ($urandom() % 6);
		end
	end

	// ---------------- reference model ----------------
	bit [15:0] ref_l [bit [17:0]];
	bit [15:0] ref_r [bit [17:0]];
	bit [15:0] sr_l [512], sr_r [512];     // expected shift register contents (video)
	bit [15:0] sc_l [512], sc_r [512];     // expected CPU (SPORT copy) shift register contents
	int        sq_pos;                     // serial read-out position after rt_read/sq_read
	function automatic [15:0] rl(input [17:0] a); return ref_l.exists(a) ? ref_l[a] : 16'h0; endfunction
	function automatic [15:0] rr(input [17:0] a); return ref_r.exists(a) ? ref_r[a] : 16'h0; endfunction

	int errors = 0, checks = 0;
	task automatic fail(input string m);
		errors++;
		if (errors < 30) $display("[%0t] TB ERROR: %s", $realtime, m);
	endtask

	task automatic mem_cycles(input int n); repeat (n) @(posedge clk_mem); endtask

	// wait until the VRAM modules and ddram.sv are idle
	task automatic wait_idle();
		int to;
		to = 0;
		do begin
			mem_cycles(8);
			to++;
		end while ((vram_l.XBUSY || vram_r.XBUSY || ddr_bbusy ||
		            ddram.state != 0 || ddram.write_lpend || ddram.write_rpend || ddr_rleft != 0) && to < 20000);
		if (to >= 20000)
			fail($sformatf("timeout waiting for idle: VRAM L busy %b (RT %b MWT %b FW %b MRD %b) R busy %b (RT %b MWT %b FW %b MRD %b), ddram state %0d burst busy %b (rd %b%b wr %b%b) write pending %b%b, DDR busy %b read beats left %0d write beats left %0d",
			               vram_l.XBUSY, vram_l.RT_EXEC, vram_l.MWT_EXEC, vram_l.FW_EXEC, vram_l.MRD_EXEC,
			               vram_r.XBUSY, vram_r.RT_EXEC, vram_r.MWT_EXEC, vram_r.FW_EXEC, vram_r.MRD_EXEC,
			               ddram.state, ddr_bbusy, ddram.burst_read_lbusy, ddram.burst_read_rbusy, ddram.burst_write_lbusy, ddram.burst_write_rbusy,
			               ddram.write_lpend, ddram.write_rpend, ddr_busy, ddr_rleft, ddr_wleft));
		mem_cycles(16);
	endtask

	// RAS cycle with the given control lines (as MADAM's SPORT/transfer cycles)
	task automatic ras_cycle(input [17:0] a, input bit oe_n, input [1:0] we_n, input bit dsf);
		@(posedge clk_mem);
		A <= a; OE_N <= oe_n; WE_N <= we_n; DSF1 <= dsf;
		mem_cycles(2);
		RAS_N <= 0;
		mem_cycles(4);
	endtask
	task automatic ras_end();
		@(posedge clk_mem);
		RAS_N <= 1; CAS_N <= 1; OE_N <= 1; WE_N <= 2'b11; DSF1 <= 0;
		mem_cycles(4);
	endtask

	// Read transfer of row/column a (full or split) and serial read-out of
	// 'n' words starting at the shift register position the transfer sets.
	task automatic rt_read(input [17:0] a, input bit split, input int n);
		ras_cycle(a, 0, 2'b11, split);
		ras_end();
		wait_idle();
		// expected shift register contents after the transfer
		if (!split) begin
			for (int i = a[8:1] * 2; i < 512; i++) begin sr_l[i] = rl({a[17:9], 9'(i)}); sr_r[i] = rr({a[17:9], 9'(i)}); end
			sq_pos = a[8:0];
		end else begin
			for (int i = 0; i < 256; i++) begin
				sr_l[{a[8], 8'(i)}] = rl({a[17:8], 8'(i)});
				sr_r[{a[8], 8'(i)}] = rr({a[17:8], 8'(i)});
			end
			sq_pos = vram_l.SR_RA;
		end
		sq_read(n, $sformatf("RT %05h%s", a, split ? " split" : ""));
	endtask

	// serial read-out of 'n' more words of the video shift register
	task automatic sq_read(input int n, input string what = "read-out");
		for (int k = 0; k < n; k++) begin
			@(posedge clk_mem); SC <= 1;
			mem_cycles(3);
			@(posedge clk_mem); SC <= 0;
			mem_cycles(3);
			checks++;
			if (SQL !== sr_l[sq_pos] || SQR !== sr_r[sq_pos])
				fail($sformatf("%s word %03h: got %04h/%04h expected %04h/%04h", what, sq_pos,
				               SQL, SQR, sr_l[sq_pos], sr_r[sq_pos]));
			sq_pos = (sq_pos + 1) % 512;
		end
	endtask

	// CPU random write (both halves) through ddram.sv
	task automatic cpu_write(input [17:0] a, input [15:0] dl, input [15:0] dr);
		// ddram.sv's busy pauses MADAM in the core: no new write until it drops
		while (ddram.busy) @(posedge clk_mem);
		@(posedge clk_mem);
		w_addr <= a; w_ldata <= dl; w_rdata <= dr; w_ras <= 1;
		mem_cycles(2);
		w_lwe <= 2'b11; w_rwe <= 2'b11;
		mem_cycles(3);
		w_lwe <= 0; w_rwe <= 0; w_ras <= 0;
		mem_cycles(3);
		ref_l[a] = dl; ref_r[a] = dr;
	endtask
	// random read of both halves through ddram.sv (the CPU's or the CEL
	// engine's frame buffer read), checked against the reference model
	task automatic cpu_read(input [17:0] a, input string what);
		bit [15:0] ql, qr;
		while (ddram.busy) @(posedge clk_mem);
		@(posedge clk_mem); w_addr <= a; w_ras <= 1;
		mem_cycles(2);
		w_lrd <= 1; w_rrd <= 1;
		mem_cycles(2);
		while (ddram.busy) @(posedge clk_mem);
		mem_cycles(2);
		ql = w_ldout; qr = w_rdout;
		w_lrd <= 0; w_rrd <= 0; w_ras <= 0;
		mem_cycles(3);
		checks++;
		if (ql !== rl(a) || qr !== rr(a))
			fail($sformatf("%s: random read of %05h gave %04h %04h, VRAM holds %04h %04h", what, a, ql, qr, rl(a), rr(a)));
	endtask
	// Write masks: the CPU's write data to MADAM's SPORT space is the write
	// mask of a write transfer or flash write (1: the bit is written, 0: the
	// row keeps it), one per VRAM half. In the core it is on the data bus
	// from CAS (PHASE2 of the access; P3DO.sv registers the CPU's write data
	// at PHASE1), not yet when RAS falls: the bus model puts the mask's
	// complement there until CAS, as a stand-in for the stale data.
	function automatic [15:0] merge(input [15:0] new_, input [15:0] old, input [15:0] m);
		return (new_ & m) | (old & ~m);
	endfunction
	task automatic sport_ras(input [17:0] a, input bit oe_n, input [1:0] we_n, input bit dsf,
	                         input [15:0] dl, input [15:0] dr);
		@(posedge clk_mem); DL <= ~dl; DR <= ~dr;
		ras_cycle(a, oe_n, we_n, dsf);
	endtask
	task automatic sport_cas(input [15:0] dl, input [15:0] dr);
		@(posedge clk_mem); DL <= dl; DR <= dr; CAS_N <= 0;
		mem_cycles(4);
	endtask

	// MWT: write the current shift register into row 'row'
	task automatic mwt(input [8:0] row, input [15:0] ml = 16'hFFFF, input [15:0] mr = 16'hFFFF);
		sport_ras({row, 9'h0}, 0, 2'b00, 0, ml, mr);
		sport_cas(ml, mr);
		ras_end();
		wait_idle();
		for (int i = 0; i < 512; i++) begin
			ref_l[{row, 9'(i)}] = merge(sr_l[i], rl({row, 9'(i)}), ml);
			ref_r[{row, 9'(i)}] = merge(sr_r[i], rr({row, 9'(i)}), mr);
		end
	endtask

	// The CPU's SPORT read transfer (MADAM: SPORT space read, column 0, full
	// row) into the CPU shift register, and its write transfer from it
	task automatic cpu_rt(input [8:0] row);
		@(posedge clk_mem); SP_CPU <= 1;
		ras_cycle({row, 9'h0}, 0, 2'b11, 0);
		ras_end();
		SP_CPU <= 0;
		wait_idle();
		for (int i = 0; i < 512; i++) begin sc_l[i] = rl({row, 9'(i)}); sc_r[i] = rr({row, 9'(i)}); end
	endtask
	task automatic cpu_mwt(input [8:0] row, input [15:0] ml = 16'hFFFF, input [15:0] mr = 16'hFFFF);
		@(posedge clk_mem); SP_CPU <= 1;
		sport_ras({row, 9'h0}, 0, 2'b00, 0, ml, mr);
		sport_cas(ml, mr);
		ras_end();
		SP_CPU <= 0;
		wait_idle();
		for (int i = 0; i < 512; i++) begin
			ref_l[{row, 9'(i)}] = merge(sc_l[i], rl({row, 9'(i)}), ml);
			ref_r[{row, 9'(i)}] = merge(sc_r[i], rr({row, 9'(i)}), mr);
		end
	endtask

	// Phase 12: commands issued as soon as MADAM may, as in the core: when a
	// RAS falls while a VRAM half is still busy with a transfer, that half's
	// RDY drops, PAUSE stops MADAM with the command on the pins, and the half
	// takes the command when it becomes ready. 'paused_hung' is set if a half
	// never becomes ready.
	bit paused_hung = 0;
	task automatic hold_until_ready(input string what);
		int to;
		mem_cycles(4);
		to = 0;
		while ((!RDYL || !RDYR) && to < 20000) begin @(posedge clk_mem); to++; end
		if (to >= 20000) begin
			fail($sformatf("%s: a VRAM half never became ready (L RDY %b MWT %b, R RDY %b MWT %b): its write transfer did not end",
			               what, RDYL, vram_l.MWT_EXEC, RDYR, vram_r.MWT_EXEC));
			paused_hung = 1;
		end
		mem_cycles(4);
	endtask
	// the CPU's write transfer into 'row', not waiting for it to end
	// (CAS falls before the busy half is ready: the half takes the command
	// late, with CAS already low)
	task automatic cpu_mwt_paused(input [8:0] row);
		@(posedge clk_mem); SP_CPU <= 1;
		sport_ras({row, 9'h0}, 0, 2'b00, 0, 16'hFFFF, 16'hFFFF);
		sport_cas(16'hFFFF, 16'hFFFF);
		hold_until_ready($sformatf("write transfer into row %03h", row));
		ras_end();
		SP_CPU <= 0;
		for (int i = 0; i < 512; i++) begin ref_l[{row, 9'(i)}] = sc_l[i]; ref_r[{row, 9'(i)}] = sc_r[i]; end
	endtask
	// a video split read transfer to one half only, not waiting for it to end
	task automatic half_rt_paused(input bit right, input [17:0] a);
		if (right) l_off = 1; else r_off = 1;
		ras_cycle(a, 0, 2'b11, 1);
		hold_until_ready($sformatf("%s read transfer %05h", right ? "right" : "left", a));
		ras_end();
		l_off = 0; r_off = 0;
	endtask
	// Phase 12 coverage. ddram.sv serves a half's write burst in two passes
	// of 128 beats (one half-row each) and serves the left half first.
	// l_between: a left write burst started while the right half's burst was
	// between its two passes (its first done, its second still to come);
	// r_during_l: a right write burst latched while only the left half's
	// burst was in progress.
	int ph12_l_between = 0, ph12_r_during_l = 0;
	bit ph12_brwr_d = 0, ph12_lstart_d = 0;
	always @(posedge clk_mem) begin
		ph12_brwr_d <= v_rwr;
		if (v_rwr && !ph12_brwr_d && ddram.burst_write_lbusy && !ddram.burst_write_rbusy) ph12_r_during_l++;
		if (ddram.state == 0 && !DDRAM_BUSY && ddram.burst_write_lbusy && !ph12_lstart_d &&
		    ddram.burst_write_rbusy && ddram.burst_raddr[10] && ddram.burst_raddr != ddram.burst_laddr) ph12_l_between++;
		ph12_lstart_d <= ddram.state == 0 && !DDRAM_BUSY && ddram.burst_write_lbusy;
	end

	// FW: load the colour registers, flash-write row 'row' (MADAM: the
	// CPU's writes to SPORT space with address bit 13, the colour, and bit
	// 14, the mask)
	task automatic flash_write(input [8:0] row, input [15:0] cl, input [15:0] cr,
	                           input [15:0] ml = 16'hFFFF, input [15:0] mr = 16'hFFFF);
		// colour load: RAS with DSF and no OE/WE, then CAS with the colour
		sport_ras({row, 9'h0}, 1, 2'b11, 1, cl, cr);
		sport_cas(cl, cr);
		ras_end();
		// flash write: RAS with WE and DSF, then CAS with the mask
		sport_ras({row, 9'h0}, 1, 2'b00, 1, ml, mr);
		sport_cas(ml, mr);
		ras_end();
		wait_idle();
		for (int i = 0; i < 512; i++) begin
			ref_l[{row, 9'(i)}] = merge(cl, rl({row, 9'(i)}), ml);
			ref_r[{row, 9'(i)}] = merge(cr, rr({row, 9'(i)}), mr);
		end
	endtask

	// on-chip VRAM in this testbench (vram.sv USE_INT_RAM1 with USE_BRAM 0):
	// the BRAM1 window and the VDL area
	function automatic bit on_chip(input [17:0] a);
		return (a >= ({BRAM1_OFFS, 16'h0000} >> 2) && a <= ({BRAM1_OFFS, 16'hBFFF} >> 2)) || a >= (20'hFC000 >> 2);
	endfunction
	// A random write as the core makes it: the VRAM pins (RAS, then WE with
	// the data: on-chip VRAM is written there, and vram.sv sees the write)
	// and, for VRAM outside, ddram.sv's write port at the same time
	task automatic pin_write(input [17:0] a, input [15:0] dl, input [15:0] dr);
		bit ext;
		ext = !on_chip(a);
		while (ddram.busy) @(posedge clk_mem);
		@(posedge clk_mem);
		A <= a; DL <= dl; DR <= dr; OE_N <= 1; WE_N <= 2'b11; DSF1 <= 0;
		if (ext) begin w_addr <= a; w_ldata <= dl; w_rdata <= dr; w_ras <= 1; end
		mem_cycles(2);
		RAS_N <= 0;
		mem_cycles(4);
		WE_N <= 2'b00;
		if (ext) begin w_lwe <= 2'b11; w_rwe <= 2'b11; end
		mem_cycles(4);
		WE_N <= 2'b11;
		if (ext) begin w_lwe <= 0; w_rwe <= 0; w_ras <= 0; end
		mem_cycles(2);
		RAS_N <= 1;
		mem_cycles(4);
		ref_l[a] = dl; ref_r[a] = dr;
	endtask
	// phase 13 coverage: the ways vram.sv carries out a masked write.
	// n_mrd: destination-row reads outside (partial mask); n_rmw: on-chip
	// merged block writes; n_lazy: ddram.sv lazy flash fills (both halves
	// FFFF, in step); n_fwm: a half's flash colour written as a burst
	int  n_mrd = 0, n_rmw = 0, n_lazy = 0, n_fwm = 0;
	bit  mrd_l_d = 0, mrd_r_d = 0, bfw_d = 0, fwm_l_d = 0, fwm_r_d = 0;
	always @(posedge clk_mem) begin
		mrd_l_d <= vram_l.MRD_EXEC; mrd_r_d <= vram_r.MRD_EXEC; bfw_d <= v_lfw;
		fwm_l_d <= vram_l.MWT_EXEC && vram_l.FWM; fwm_r_d <= vram_r.MWT_EXEC && vram_r.FWM;
		if (vram_l.MRD_EXEC && !mrd_l_d) n_mrd++;
		if (vram_r.MRD_EXEC && !mrd_r_d) n_mrd++;
		if (v_lfw && !bfw_d) n_lazy++;
		if (vram_l.MWT_EXEC && vram_l.FWM && !fwm_l_d) n_fwm++;
		if (vram_r.MWT_EXEC && vram_r.FWM && !fwm_r_d) n_fwm++;
		if (vram_l.MEM_SWR && vram_l.MASKED) n_rmw++;
		if (vram_r.MEM_SWR && vram_r.MASKED) n_rmw++;
	end

	// read transfers the left VRAM module executes (a skipped split transfer
	// does not start one)
	int  n_rt_l = 0;
	bit  rt_l_d = 0;
	always @(posedge clk_mem) begin rt_l_d <= vram_l.RT_EXEC; if (vram_l.RT_EXEC && !rt_l_d) n_rt_l++; end

	initial begin
		bit [8:0] rows [8];
		$display("tb_vram: start");
		// ddram.sv clears its flash-write flags while in reset
		mem_cycles(9000);
		rst = 0;
		mem_cycles(50);

		for (int i = 0; i < 8; i++) rows[i] = 9'(16 + i * 3);     // VRAM 0x08000.. (in the DDR3)

		// 1) fill 8 rows with CPU writes (a sample of words per row; rest 0)
		foreach (rows[i]) for (int w = 0; w < 512; w += 7) cpu_write({rows[i], 9'(w)}, $urandom(), $urandom());
		wait_idle();

		// 2) read all rows back through read transfers
		foreach (rows[i]) rt_read({rows[i], 9'h0}, 0, 512);
		$display("[%0t] phase 2: full-row reads done, errors=%0d", $realtime, errors);

		// 4) CPU writes into rows, then read again
		for (int k = 0; k < 12; k++) begin
			bit [8:0] r;
			r = rows[$urandom() % 8];
			rt_read({r, 9'h0}, 0, 512);
			for (int j = 0; j < 4; j++) cpu_write({r, 1'b0, 8'($urandom())}, $urandom(), $urandom());
			wait_idle();
			rt_read({r, 9'h0}, 0, 512);
		end
		$display("[%0t] phase 4: after CPU writes, errors=%0d", $realtime, errors);

		// 5) SPORT copy: the CPU's read transfer of row a, then its write
		//    transfer into row b. Between them, as when a copy runs into the
		//    picture, video transfers of other rows with serial read-out: b
		//    must get row a, and the video read-out must go on with its own
		//    row across both of the copy's transfers. Then b is read back.
		//    Also the legacy path (a write transfer that is not the CPU's
		//    stores the video shift register).
		for (int k = 0; k < 4; k++) begin
			rt_read({rows[k + 4], 9'h0}, 0, 512);
			rt_read({rows[(k + 1) % 4], 9'h0}, 0, 16);  // video: row c, 16 words out
			cpu_rt(rows[k]);                            // copy source -> CPU shift register
			sq_read(16, "video read-out after the CPU's read transfer");
			rt_read({rows[(k + 2) % 4], 9'h0}, 0, 16);  // another video transfer inside the copy
			cpu_mwt(rows[k + 4]);
			sq_read(16, "video read-out after the CPU's write transfer");
			rt_read({rows[k + 4], 9'h0}, 0, 512);
		end
		for (int k = 0; k < 2; k++) begin
			rt_read({rows[k + 2], 9'h0}, 0, 0);         // legacy: video shift register
			mwt(rows[k + 6]);
			rt_read({rows[k + 6], 9'h0}, 0, 512);
		end
		// A split transfer of the half-row the video shift register holds is
		// skipped. A copy into that row must not leave the old data there:
		// the next split transfer of the half shows the copy.
		for (int k = 0; k < 2; k++) begin
			int n0;
			rt_read({rows[k + 4], 9'h000}, 0, 16);      // video register <- row d
			n0 = n_rt_l;
			rt_read({rows[k + 4], 9'h000}, 1, 16);      // split, same half
			if (n_rt_l != n0) fail("split transfer of the half the video shift register holds was not skipped");
			cpu_rt(rows[k + 2]);                        // copy another row into d
			cpu_mwt(rows[k + 4]);
			rt_read({rows[k + 4], 9'h000}, 1, 64);      // split, same half: the copied data
		end
		$display("[%0t] phase 5: MWT copies, errors=%0d", $realtime, errors);

		// 6) flash writes
		for (int k = 0; k < 3; k++) begin
			rt_read({rows[k], 9'h0}, 0, 512);
			flash_write(rows[k], 16'h1111 * (k + 1), 16'h0F0F + k);
			rt_read({rows[k], 9'h0}, 0, 512);
		end
		// a CPU write into a flash-filled row
		cpu_write({rows[1], 9'h055}, 16'hABCD, 16'h1234);
		wait_idle();
		rt_read({rows[1], 9'h0}, 0, 512);
		$display("[%0t] phase 6: flash writes, errors=%0d", $realtime, errors);

		// 7) split transfers and transfers starting mid-row
		foreach (rows[i]) begin
			rt_read({rows[i], 9'h000}, 0, 64);
			rt_read({rows[i], 9'h100}, 1, 256);       // other half (split)
			rt_read({rows[i], 9'h0A2}, 0, 100);
		end
		$display("[%0t] phase 7: split/mid-row transfers, errors=%0d", $realtime, errors);

		// 8) random mix
		for (int k = 0; k < 120; k++) begin
			bit [8:0] r;
			r = rows[$urandom() % 8];
			case ($urandom() % 6)
				0, 1: rt_read({r, 9'($urandom() % 2 ? 0 : 9'(($urandom() % 256) * 2))}, 0, 40);
				2:    begin cpu_write({r, 9'($urandom())}, $urandom(), $urandom()); wait_idle(); end
				3:    begin
				          cpu_rt(rows[$urandom() % 8]);
				          if ($urandom() % 2) rt_read({rows[$urandom() % 8], 9'h0}, 0, 8);
				          cpu_mwt(r);
				      end
				4:    flash_write(r, $urandom(), $urandom());
				5:    begin rt_read({rows[$urandom() % 8], 9'h0}, 0, 0); mwt(r); end
			endcase
		end
		$display("[%0t] phase 8: random mix, errors=%0d", $realtime, errors);

		// ---------------- phase 12: write transfers with the halves out of step ----------------
		// A frame buffer clear as games do it: the CPU's SPORT read transfer
		// of a source row, then write transfers into one row after another,
		// each issued as soon as MADAM may (held while a VRAM half is busy,
		// as PAUSE does in the core). The video DMA's transfers go to one
		// half at a time, so a half can still be busy with one when a write
		// transfer comes: the other half starts its write burst first.
		// ddram.sv serves a half's write burst in two passes of 128 beats
		// and serves the left half first, so a left burst can start between
		// the right half's two passes. It used to count that pass as the
		// second one and end the burst after it: the left module then waited
		// for the rest of its write transfer for ever (the core hung, paused),
		// and the right half's second pass was counted as a first one and a
		// third ran on into the next row.
		// (a) a video transfer to the left half before every write transfer
		// (the left half starts late), (b) to the right half, (c) none. The
		// destination rows and the row after each (a guard row nothing
		// writes) are flash-filled before and read back after, and every
		// transfer must end.
		begin
			bit [8:0] src, vid [2], dst [6];
			int errors0;
			errors0 = errors;
			src = 9'h140; vid = '{9'h150, 9'h152};
			foreach (dst[i]) dst[i] = 9'(9'h160 + 2 * i);
			for (int w = 0; w < 512; w += 3) cpu_write({src, 9'(w)}, $urandom(), $urandom());
			foreach (vid[i]) for (int w = 0; w < 512; w += 9) cpu_write({vid[i], 9'(w)}, $urandom(), $urandom());
			wait_idle();
			for (int c = 0; c < 3 && !paused_hung; c++) begin
				int lb0, rl0, n;
				lb0 = ph12_l_between; rl0 = ph12_r_during_l;
				foreach (dst[i]) begin
					flash_write(dst[i], 16'hD100 + 16'(c), 16'h2E00 + 16'(c));
					flash_write(9'(dst[i] + 1), 16'h5A00 + 16'(c), 16'hA500 + 16'(c));
				end
				cpu_rt(src);
				
				n = 0;
				foreach (dst[i]) begin
					if (paused_hung) break;
					// a different half-row each time: a split transfer of the
					// half-row the video shift register holds is skipped
					if (c != 2) half_rt_paused(c == 1, {vid[i % 2], (i / 2) % 2 == 1, 8'h00});
					if (paused_hung) break;
					cpu_mwt_paused(dst[i]);
					n++;
				end
				if (!paused_hung) wait_idle();
				if (vram_l.MWT_EXEC || vram_r.MWT_EXEC || vram_l.RT_EXEC || vram_r.RT_EXEC) begin
					fail($sformatf("phase 12 (%s): a transfer never ended (left MWT %b RT %b, right MWT %b RT %b)",
					               c == 0 ? "left half late" : c == 1 ? "right half late" : "in step",
					               vram_l.MWT_EXEC, vram_l.RT_EXEC, vram_r.MWT_EXEC, vram_r.RT_EXEC));
					paused_hung = 1;
				end
				if (paused_hung) break;
				foreach (dst[i]) begin
					rt_read({dst[i], 9'h0}, 0, 512);
					rt_read({9'(dst[i] + 1), 9'h0}, 0, 512);
				end
				$display("[%0t] phase 12 (%s): %0d write transfers; left bursts started between the right half's passes %0d, right bursts latched during a left one %0d",
				         $realtime, c == 0 ? "left half late" : c == 1 ? "right half late" : "in step", n,
				         ph12_l_between - lb0, ph12_r_during_l - rl0);
				if (c == 0 && ph12_l_between == lb0)
					fail("phase 12: no left write burst started between the right half's two passes (case not exercised)");
				if (c == 1 && ph12_r_during_l == rl0)
					fail("phase 12: no right write burst latched during a left one (case not exercised)");
			end
			$display("[%0t] phase 12: write transfers with the halves out of step, errors=%0d", $realtime, errors - errors0);
		end

		// ---------------- phase 13: write masks; split transfers after writes ----------------
		// The CPU's write transfers (SPORT copies) and flash writes take a
		// write mask, one per VRAM half: 1 bits are written, 0 bits keep the
		// row's (US 5,502,462). The core ignored it: a zero or partial mask
		// overwrote the whole row. For a row in each memory (on-chip, DDR3): copies and flash writes with partial masks, no bits, all
		// bits, and different masks in the two halves, each followed by a
		// read-back of every word of the row and of the next (guard) row.
		// Then split transfers: the half-row the video shift register holds
		// is not transferred again (MiSTer core); a flash write, a masked
		// copy or a random write into that half must make its next split
		// transfer reload it, and a write into the other half must not.
		begin
			bit [8:0] srcs [2], dsts [2];
			int errors0;
			errors0 = errors;
			srcs = '{9'h188, 9'h1A0};   // on-chip (BRAM1 window), DDR3
			dsts = '{9'h18A, 9'h1A2};
			for (int k = 0; k < 2; k++) begin
				bit [8:0] s, d;
				string mem;
				int e0, mrd0, rmw0, lazy0, fwm0, n0;
				s = srcs[k]; d = dsts[k];
				mem = on_chip({d, 9'h0}) ? "on-chip" : "DDR3";
				if ((k == 0) != on_chip({d, 9'h0}))
					fail($sformatf("phase 13: row %03h is not in the memory the test needs (%s)", d, mem));
				e0 = errors; mrd0 = n_mrd; rmw0 = n_rmw; lazy0 = n_lazy; fwm0 = n_fwm;
				// every word of the source and destination rows its own
				flash_write(9'(d + 1), 16'hC3C3, 16'h3C3C);
				for (int w = 0; w < 512; w++) begin
					pin_write({s, 9'(w)}, $urandom(), $urandom());
					pin_write({d, 9'(w)}, $urandom(), $urandom());
				end
				wait_idle();
				// copies and flash writes, each read back (row and guard row)
				for (int op = 0; op < 12; op++) begin
					int e1;
					string what;
					e1 = errors;
					case (op)
						0:  begin cpu_rt(s); cpu_mwt(d, 16'h00FF, 16'h0F0F); what = "copy, masks 00FF/0F0F"; end
						1:  begin cpu_rt(s); cpu_mwt(d, 16'h0000, 16'h0000); what = "copy, masks 0000/0000"; end
						2:  begin flash_write(d, 16'h1234, 16'h5678, 16'hF0F0, 16'hFF00); what = "flash, masks F0F0/FF00"; end
						3:  begin flash_write(d, 16'h9ABC, 16'hDEF0, 16'h0000, 16'h0000); what = "flash, masks 0000/0000"; end
						4:  begin cpu_rt(s); cpu_mwt(d, 16'hFFFF, 16'h3C3C); what = "copy, masks FFFF/3C3C"; end
						5:  begin flash_write(d, 16'h2468, 16'h1357, 16'hFFFF, 16'h0000); what = "flash, masks FFFF/0000"; end
						6:  begin flash_write(d, 16'h7531, 16'h8642, 16'h0000, 16'hFFFF); what = "flash, masks 0000/FFFF"; end
						7:  begin cpu_rt(s); cpu_mwt(d, 16'h0000, 16'hA5A5); what = "copy, masks 0000/A5A5"; end
						8:  begin flash_write(d, 16'h0F1E, 16'h2D3C, 16'h5555, 16'hFFFF); what = "flash, masks 5555/FFFF"; end
						9:  begin rt_read({s, 9'h0}, 0, 0); mwt(d, 16'h33CC, 16'hFFFF); what = "video write transfer, masks 33CC/FFFF"; end
						10: begin flash_write(d, 16'h4B4B, 16'hB4B4); what = "flash, masks FFFF/FFFF"; end
						default: begin cpu_rt(s); cpu_mwt(d); what = "copy, masks FFFF/FFFF"; end
					endcase
					rt_read({d, 9'h0}, 0, 512);
					rt_read({9'(d + 1), 9'h0}, 0, 512);
					if (errors != e1) $display("[%0t] phase 13 (%s): %s: %0d mismatches", $realtime, mem, what, errors - e1);
				end
				// the way each memory carries them out
				if (k == 0 && (n_rmw == rmw0 || n_mrd != mrd0 || n_lazy != lazy0 || n_fwm != fwm0))
					fail($sformatf("phase 13 (on-chip): merged writes %0d, row reads %0d, lazy fills %0d, colour bursts %0d (expected merged writes only)",
					               n_rmw - rmw0, n_mrd - mrd0, n_lazy - lazy0, n_fwm - fwm0));
				if (k != 0 && (n_mrd == mrd0 || n_fwm == fwm0 || n_lazy == lazy0 || n_rmw != rmw0))
					fail($sformatf("phase 13 (%s): row reads %0d, colour bursts %0d, lazy fills %0d, merged on-chip writes %0d (expected all but the last)",
					               mem, n_mrd - mrd0, n_fwm - fwm0, n_lazy - lazy0, n_rmw - rmw0));
				$display("[%0t] phase 13 (%s): masked copies and flash writes, errors=%0d (row reads %0d, merged on-chip writes %0d, lazy fills %0d, colour bursts %0d)",
				         $realtime, mem, errors - e0, n_mrd - mrd0, n_rmw - rmw0, n_lazy - lazy0, n_fwm - fwm0);

				// split transfers after writes into the half-row the video
				// shift register holds (the lower one: the transfer started
				// at column 0); 256 words read out, so the upper half is the
				// one being shifted out and the lower one the inactive half
				e0 = errors;
				for (int c = 0; c < 5; c++) begin
					string what;
					bit reload;
					rt_read({d, 9'h000}, 0, 256);
					n0 = n_rt_l;
					rt_read({d, 9'h000}, 1, 0);
					if (n_rt_l != n0) fail($sformatf("phase 13 (%s): split transfer of the half-row the video shift register holds was not skipped", mem));
					rt_read({d, 9'h000}, 0, 256);
					reload = 1;
					case (c)
						0: begin flash_write(d, 16'h1357, 16'h2468); what = "flash write"; end
						1: begin flash_write(d, 16'hE1E1, 16'h1E1E, 16'h0FF0, 16'hF00F); what = "masked flash write"; end
						2: begin cpu_rt(s); cpu_mwt(d, 16'hFF00, 16'h00FF); what = "masked copy"; end
						3: begin pin_write({d, 9'h013}, 16'hBEEF, 16'hF00D); what = "random write"; end
						default: begin pin_write({d, 9'h1F3}, 16'hCAFE, 16'hD00D); what = "random write into the other half"; reload = 0; end
					endcase
					n0 = n_rt_l;
					rt_read({d, 9'h000}, 1, 512);
					if (reload && n_rt_l == n0) fail($sformatf("phase 13 (%s): split transfer after a %s into its half-row was skipped", mem, what));
					if (!reload && n_rt_l != n0) fail($sformatf("phase 13 (%s): split transfer was not skipped after a %s", mem, what));
				end
				$display("[%0t] phase 13 (%s): split transfers after writes, errors=%0d", $realtime, mem, errors - e0);
			end
			$display("[%0t] phase 13: write masks, split transfers after writes, errors=%0d", $realtime, errors - errors0);
		end

		// 17) random reads after writes into the block ddram.sv last read
		begin
			int errors0;
			bit [8:0] r, src;
			errors0 = errors;
			for (int k = 0; k < 2; k++) begin
				r = rows[k * 2]; src = rows[k * 2 + 1];
				cpu_write({r, 9'h004}, 16'h1111 + 16'(k), 16'h2222 + 16'(k));
				cpu_write({src, 9'h004}, 16'h5555 + 16'(k), 16'h6666 + 16'(k));
				wait_idle();
				cpu_read({r, 9'h004}, "phase 17, before");
				flash_write(r, 16'hABCD, 16'hDCBA);
				wait_idle();
				cpu_read({r, 9'h004}, "phase 17, after a flash write");
				cpu_read({r, 9'h006}, "phase 17, after a flash write");
				cpu_rt(src);
				cpu_mwt(r);
				wait_idle();
				cpu_read({r, 9'h004}, "phase 17, after a page copy");
				cpu_read({r, 9'h005}, "phase 17, after a page copy");
				flash_write(r, 16'h0F0F, 16'hF0F0, 16'h00FF, 16'hFF00);
				wait_idle();
				cpu_read({r, 9'h004}, "phase 17, after a masked flash write");
				cpu_read({src, 9'h104}, "phase 17, another block");
				cpu_read({r, 9'h004}, "phase 17, back to the block");
			end
			$display("[%0t] phase 17: random reads after writes into the read block, errors=%0d", $realtime, errors - errors0);
		end

		$display("tb_vram: %0d words checked; DDR model: %0d write beats, %0d read bursts, %0d commands held by BUSY",
		         checks, ddr_writes, ddr_reads, ddr_busy_cmds);
		if (ddr_busy_cmds == 0) fail("no command met a busy DDR interface (case not exercised)");
		// a failure ends with a non-zero exit status ($fatal), so scripts see it
		if (errors == 0) begin $display("tb_vram: PASS"); $finish; end
		else $fatal(1, "tb_vram: FAIL");
	end

	initial begin
		#400ms;
		$display("tb_vram: TIMEOUT");
		$fatal(1, "tb_vram: FAIL");
	end
endmodule
