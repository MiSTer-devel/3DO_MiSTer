// Testbench: CLIO interrupt summary, timers and TimerSlack (Game Bub 3DO core).
//
// The real CLIO module, accessed the way MADAM_EXTPIF.sv does it for the
// CPU: the address and write data are put on the bus at a CE_R edge, the
// bus code (CLC) 1 (write) or 3 (read) for exactly one CE_R, and a read's
// data is taken two MCLKs later. Checks:
//   1. INT0 bit 31 is the summary of the enabled INT1 interrupts (Opera
//      opera_clio_peek, as the FIQ already was): not set by a pending INT1
//      interrupt that is not enabled, set by an enabled one of any source
//      (software through 0x60 and the player bus PB_INT), cleared when it is
//      acknowledged or disabled, and not latched by writes to 0x40 / 0x44.
//      The INT0 sources still work.
//   2. The timer controls read back at the set and the clear address of
//      each bank (0x200 / 0x204, 0x208 / 0x20C).
//   3. TimerSlack (0x220) reads back (10 bits, 336 after reset) and sets
//      the count period to 64 + TimerSlack CE_R ticks (Opera opera_clock.c;
//      the OS writes 336 for 16 us at 25 MHz, Portfolio kernel timer.c).
//   4. A cascaded timer takes the borrow of the timer below it in the same
//      count: a pair goes 0001:0000 -> 0000:FFFF -> 0000:FFFE, a chain of
//      three borrows through both, a cascaded timer whose lower timer does
//      not borrow does not count, a timer that is not cascaded ignores the
//      borrow, a timer without reload stops at FFFF with its decrement bit
//      cleared, and odd timers' borrows set their INT0 bits (timer 1: bit
//      10 ... timer 15: bit 3).
//   5. The DSP's output memory: 16-bit CPU reads, and 32-bit reads with the
//      even word in bits 31-16 and the odd one in 15-0 (as 32-bit writes
//      store them; Opera); the output FIFOs' status at 0x3C0-0x3CC
//      (Portfolio clio.h clio_FIFOStatusDSPPtoDMA), the input FIFOs' at
//      0x380-0x3BC. A DSP program (Portfolio StartupCode's MOVE opcodes)
//      writes the output memory and one word into each output FIFO. (5b)
//      The output FIFOs hold 64 words (the hardware's 8: the port pauses
//      the 3DO, MADAM's DMA with it, while the DSP runs on - Killing Time's
//      EZFlix decoder lost output words): 40 words written with the DMA off
//      all wait, the status reads 40, and with the DMA on they come out six
//      per burst with one request per burst and no further DSP write; the
//      DSP's flush (0x3FD) requests the rest. (5c) A pause of the 3DO
//      (IO_EN low) while the DSP runs on through it: a Killing Time-like
//      run of 24 output words finishes during the pause, all wait, and come
//      out in four bursts after it; nothing is lost.
//   6. The FIFOs (CLIO_DSP_FIFO, CLIO_DMA_FIFO): (c) a DSP read of an input
//      FIFO (0x0F0, popped) or a peek (0x070) gives the word the CPU last
//      wrote at 0x070 (once, nothing popped: the audio folio's FIFOHEAD,
//      zeroed with every FIFO reset), else the word at the FIFO's head, an
//      empty FIFO the word last handed over (Opera CPUSupply / fifo_ei; the
//      original gave the word of the previous read, one word late, so a
//      streamer's discard read after a reset lost the FIFO's first word
//      unless the DMA had filled it already: Killing Time's DSP stream
//      decoder got its code table and stream shifted); (a) each module under
//      random requests, including reads of an empty and writes to a full
//      FIFO and both at once there, against a queue: every word read, the
//      count and the pointers; (b) in CLIO, a DSP program reading input
//      FIFO 0 without pause while a DMA refill arrives (MADAM's code 2 / 7
//      bus cycles): a read meeting a write on the empty FIFO must happen,
//      and the DSP must take every DMA word in order, once; once it has
//      drained, the DSP keeps reading the last word.
//   7. The DSP core and its frames, through what DSP programs write to the
//      output memory: (a) instructions without operands (INC, ACC transfer,
//      ADDC) right after a reset and after instructions of other timings;
//      (b) every frame starts with the accumulator and the flags clear
//      (Opera opera_dsp_loop), across CPU resets and the DSP's own frames;
//      (c) an empty input FIFO keeps giving the word it holds (also through
//      the 0x70 alias); (d) the reload value: 565 from power-on, kept across
//      frames and CPU resets once the DSP has written it (Opera
//      opera_dsp_reset), the frame period reload + 1 ticks; (e) audio lock:
//      frames only with the audio word strobe (every 0x180 ACLK_CE), none
//      from the counter, and the counter's frames back when it is cleared.
//   8. Barrel shifts with the shift control from an operand (BS = 1000): the
//      operand (immediate or memory; bits 3-0 the shift, bit 4 logical) is
//      not counted in the instruction's operands (WO 94/16383), so the
//      output address after it is still read and written, once; the stored
//      control is the operand's value, reused under OPMASK.
//  7g. A word read right after an instruction writes it is the new word:
//      an ALU writeback a MOVE's write delays lands in the clock of the next
//      instruction's read (Killing Time's DSP interrupt counter: ADD [108]+1;
//      MOVE; MOVE 3EE <- [108]; the original read the old word), also through
//      the data memory's second address range (0x208 for 0x108).
//  7f. Indirect operands (D_I): the operand is read through the pointer the
//      operand address holds (Opera, MAME), alone and with a direct operand;
//      the output after it is written once.
//  11. ADBIO (0x84) reads back the direction and the pads (Portfolio
//      clio.h RWDIR / RWPADS), so Portfolio's read/modify/write updates
//      (cdipir.c: ROM bank select, mute, watchdog) keep the other bits.
//  10. CSTAT (0x28) writes as Opera takes them: power-on, rollover and
//      DIPIR reset only cleared by a write of 0, the watchdog bits not
//      written, ClearDIPIR not stored, SoftReset with ClearDIPIR sets DIPIR
//      reset (run before section 9).
//   9. The expansion bus (XBUS) control register: the DMA direction, DMA on
//      and reset bits read back at the set and the clear address (Portfolio
//      clio.h, Opera); XB_DMARESET ("also does a flush") on a DMA stalled on
//      its full FIFO stops it and empties the FIFO, so a new transfer's word
//      is the only one the DMA to memory (MADAM's bus cycles here) takes.
//
// Copyright (c) 2026 Adam Polkosnik
// SPDX-License-Identifier: GPL-3.0-or-later

`timescale 1ns/1ps
module tb_clio;
	reg clk = 0;
	always #10 clk = ~clk;                 // clk_sys, 50 MHz
	reg ce_r = 0;                          // MCLK phases, 25 MHz
	always @(posedge clk) ce_r <= ~ce_r;
	wire ce_f = ~ce_r;
	reg rst_n = 0;

	reg  [15:2] a = 0;
	reg  [31:0] di = 0;
	wire [31:0] q;
	reg  [ 2:0] clc = 0;
	reg         pb_int = 0;
	reg         dsp_en = 0;
	reg         io_en = 1;                // IO_EN: MADAM's side of CLIO runs (low: the 3DO is paused)
	reg  [31:0] mem_di = 0;               // MADAM's bus (DMA data to CLIO)
	reg         aclk_ce = 0;              // audio clock enable
	reg  [ 7:0] edi = 8'hFF;              // expansion bus data
	wire [31:0] dma_do;                   // CLIO's DMA data to MADAM
	wire        dmareq, cready_n;
	wire [ 4:0] dmach;
	wire        firq_n;

	CLIO dut (
		.CLK(clk), .RST_N(rst_n), .EN(1'b1), .PAL(1'b0), .CE_R(ce_r), .CE_F(ce_f),
		.IO_EN(io_en), .DSP_EN(dsp_en), .PON(1'b0), .RESET_N(), .MCLK_PH1(ce_r), .MCLK_PH2(ce_f),
		.A(a), .CPU_DI(di), .CPU_DO(q), .DI(mem_di), .DO(dma_do), .CLC(clc), .CREADY_N(cready_n), .DMAREQ(dmareq), .DMACH(dmach),
		.PB_INT(pb_int), .FIRQ_N(firq_n),
		.EDI(edi), .EDO(), .ESTR_N(), .EWRT_N(), .ERST_N(), .ECMD_N(), .ESEL_N(), .ERDY_N(1'b0), .EINT_N(1'b1),
		.ADBIO_I(4'h0), .ADBIO_O(), .ADBIO_D(),
		.VCE(1'b0), .HSYNC_N(1'b1), .VSYNC_N(1'b1), .S(32'h0), .LPSC_N(1'b1), .RPSC_N(1'b1), .PCSC(),
		.AD(), .DE(), .ACLK_CE(aclk_ce), .AUDIOL(), .AUDIOR(),
		.HINTREPOL_DISABLE(1'b1), .VINTREPOL_DISABLE(1'b1), .DBG_EXT(8'h00)
	);

	int errors = 0, checks = 0;
	task automatic check(input string what, input [31:0] got, input [31:0] exp);
		checks++;
		if (got !== exp) begin
			errors++;
			$display("[%0t] TB ERROR: %s: got %08h, expected %08h", $realtime, what, got, exp);
		end else
			$display("[%0t] ok: %s = %08h", $realtime, what, got);
	endtask

	// ---------------- 6a. the FIFO modules against a queue ----------------
	reg         f_wr = 0, f_rd = 0, f_rst = 1;
	reg  [31:0] f_data = 0;
	wire [15:0] f_q16;
	wire [31:0] f_q32;
	wire [ 3:0] f_count;
	wire        f_empty, f_full;
	CLIO_DSP_FIFO fifo16 (.CLK(clk), .EN(1'b1), .RST(f_rst), .DATA(f_data[15:0]), .WRREQ(f_wr), .RDREQ(f_rd), .Q(f_q16), .COUNT(f_count));
	CLIO_DMA_FIFO fifo32 (.CLK(clk), .EN(1'b1), .RST(f_rst), .DATA(f_data), .WRREQ(f_wr), .RDREQ(f_rd), .Q(f_q32), .EMPTY(f_empty), .FULL(f_full));
	int f_reads = 0, f_bypass = 0, f_full_rw = 0, f_refused_wr = 0, f_refused_rd = 0;
	task automatic fifo_step(input bit w, input bit r, inout bit [31:0] qm [$]);
		bit [31:0] d, exp;
		bit        wr_ok, rd_ok;
		d = $urandom();
		@(negedge clk);
		f_wr = w; f_rd = r; f_data = d;
		wr_ok = w && (qm.size() < 8 || r);
		rd_ok = r && (qm.size() != 0 || w);
		#1;
		if (rd_ok) begin
			exp = qm.size() == 0 ? d : qm[0];
			f_reads++;
			if (qm.size() == 0) f_bypass++;
			if (f_q16 !== exp[15:0] || f_q32 !== exp) begin
				errors++;
				$display("[%0t] TB ERROR: FIFO read %0d (%0d words, write %b): got %04h / %08h, expected %04h / %08h",
				         $realtime, f_reads, qm.size(), w, f_q16, f_q32, exp[15:0], exp);
			end
			checks++;
		end
		if (w && r && qm.size() == 8) f_full_rw++;
		if (w && !wr_ok) f_refused_wr++;
		if (r && !rd_ok) f_refused_rd++;
		begin
			bit was_empty;
			was_empty = qm.size() == 0;
			if (rd_ok && !was_empty) void'(qm.pop_front());
			if (wr_ok && !(rd_ok && was_empty)) qm.push_back(d);   // empty: the read took it
		end
		@(posedge clk); #1;
		f_wr = 0; f_rd = 0;
		checks++;
		if (f_count !== 4'(qm.size()) || fifo32.AMOUNT !== 4'(qm.size()) ||
		    3'(fifo16.WADDR - fifo16.RADDR) !== 3'(qm.size()) || 3'(fifo32.WADDR - fifo32.RADDR) !== 3'(qm.size()) ||
		    f_empty !== (qm.size() == 0) || f_full !== (qm.size() == 8)) begin
			errors++;
			$display("[%0t] TB ERROR: FIFO after a step (write %b read %b): %0d words, count %0d / %0d, pointers %0d-%0d / %0d-%0d",
			         $realtime, w, r, qm.size(), f_count, fifo32.AMOUNT, fifo16.WADDR, fifo16.RADDR, fifo32.WADDR, fifo32.RADDR);
		end
	endtask

	// one MCLK: to the next clk edge with CE_R set (CLIO acts on CE_R)
	task automatic mclk(input int n = 1);
		repeat (n) @(posedge clk iff ce_r);
	endtask

	// CPU accesses as MADAM_EXTPIF.sv makes them: CLC for one CE_R
	task automatic wr(input [15:0] adr, input [31:0] val);
		mclk(); #1;
		a = adr[15:2]; di = val; clc = 3'h1;
		mclk(); #1;
		clc = 3'h0;
		mclk(3);
	endtask
	task automatic rd(input [15:0] adr, output [31:0] val);
		mclk(); #1;
		a = adr[15:2]; clc = 3'h3;
		mclk(); #1;
		clc = 3'h0;
		mclk(2);
		val = q;
		mclk(1);
	endtask
	task automatic rd_check(input string what, input [15:0] adr, input [31:0] exp, input [31:0] mask = 32'hFFFFFFFF);
		bit [31:0] r;
		rd(adr, r);
		check($sformatf("%s (read %04h)", what, adr), r & mask, exp);
	endtask

	// CE_R ticks until timer t's counter changes
	task automatic wait_count(input int t, output int ticks);
		bit [15:0] c0;
		c0 = dut.TM_CNT[t];
		ticks = 0;
		while (dut.TM_CNT[t] == c0 && ticks < 5000) begin mclk(); ticks++; end
		if (ticks >= 5000) begin
			errors++;
			$display("[%0t] TB ERROR: timer %0d did not count", $realtime, t);
		end
	endtask

	// timer t's counter does not change for n CE_R ticks
	task automatic no_count(input string what, input int t, input int n);
		bit [15:0] c0;
		bit        changed;
		c0 = dut.TM_CNT[t];
		changed = 0;
		repeat (n) begin mclk(); if (dut.TM_CNT[t] != c0) changed = 1; end
		check(what, {31'h0, changed}, 32'h0);
	endtask

	// timer t's counter and reload value
	task automatic load_timer(input int t, input [15:0] cnt, input [15:0] rel);
		wr(16'h0100 + 16'(t * 8), {16'h0, cnt});
		wr(16'h0104 + 16'(t * 8), {16'h0, rel});
	endtask

	localparam [3:0] DEC = 4'h1, RLD = 4'h2, CAS = 4'h4;

	// DSP program word i (NRAM through the CPU, 0x2000 + 4i)
	task automatic code(input int i, input [15:0] w);
		wr(16'h2000 + 16'(4 * i), {16'h0, w});
	endtask

	// 7: the DSP's frame starts (DSP_RESET pulses), in clk cycles
	longint    clk_n = 0;
	longint    frame_at [$];
	always @(posedge clk) begin
		clk_n++;
		if (rst_n && ce_r && dut.DSP_RESET) frame_at.push_back(clk_n);
	end
	// run the program in NRAM from 0 for n MCLKs, then stop the DSP
	task automatic dsp_run(input int n);
		wr(16'h17FC, 32'h0);
		wr(16'h17E8, 32'h0); wr(16'h17FC, 32'h1);
		mclk(n);
		wr(16'h17FC, 32'h0);
	endtask
	// the periods between the frames recorded (clk cycles)
	task automatic frame_periods(input string what, input int n, input int exp_clk);
		frame_at.delete();
		while (frame_at.size() < n + 1 && clk_n < 64'd10_000_000) mclk();
		for (int i = 1; i <= n; i++)
			check($sformatf("%s: frame period %0d (clk)", what, i), 32'(frame_at[i] - frame_at[i - 1]), 32'(exp_clk));
	endtask
	// no frame for n MCLKs
	task automatic no_frames(input string what, input int n);
		frame_at.delete();
		mclk(n);
		check($sformatf("%s: frames in %0d MCLKs", what, n), 32'(frame_at.size()), 32'h0);
	endtask

	// XBUS: a CPU access, held until CLIO is ready (CREADY_N)
	task automatic xacc(input bit w, input [15:0] adr, input [31:0] val, output [31:0] res);
		int n;
		mclk(); #1;
		a = adr[15:2]; di = val; clc = w ? 3'h1 : 3'h3;
		mclk(); #1;
		clc = 3'h0;
		mclk(2);
		n = 0;
		while (cready_n && n < 200) begin mclk(); n++; end
		if (n == 200) begin errors++; $display("[%0t] TB ERROR: XBUS access %04h not ready", $realtime, adr); end
		mclk(4);
		res = q;
	endtask
	// 9: the words CLIO puts out on DMA channel 0x14 (when MADAM takes them)
	bit [31:0] exp_words [$];
	always @(posedge clk) if (rst_n && ce_r && dut.CLC2 == 3'h2 && dut.CLC1 == 3'h0 && dut.DMA_CHAN == 5'h14) exp_words.push_back(dma_do);
	// 5b: the words CLIO puts out on DMA channel 0x10 (from output FIFO 0)
	bit [31:0] eo_words [$];
	always @(posedge clk) if (rst_n && ce_r && dut.CLC2 == 3'h2 && dut.CLC1 == 3'h0 && dut.DMA_CHAN == 5'h10) eo_words.push_back(dma_do);
	// DSP writes to output FIFO 0 refused because it was full (5b, 5c)
	int eo_lost = 0;
	always @(posedge clk) if (rst_n && dut.EOFIFO0.WRREQ && !dut.EOFIFO0.WR_OK) eo_lost++;
	// 8: output memory word 0 writes
	int eo0_writes = 0;
	always @(posedge clk) if (rst_n && ce_r && dsp_en && dut.DSP_EO_WE && dut.DSP_EO_ADDR == 8'h00) eo0_writes++;

	// 6b: what input FIFO 0 takes from the DMA and gives the DSP
	bit [15:0] fifo0_in [$], fifo0_out [$];
	int        fifo0_collisions = 0, fifo0_bad = 0;
	always @(posedge clk) if (rst_n && ce_r && dsp_en) begin
		if (dut.EIFIFO0.WR_OK) fifo0_in.push_back(dut.EIFIFO_DATA);
		if (dut.EIFIFO0.RD_OK) fifo0_out.push_back(dut.EIFIFO_Q[0]);
		if (dut.EIFIFO0.WRREQ && dut.EIFIFO0.RDREQ && dut.EIFIFO_COUNT[0] == 4'd0) fifo0_collisions++;
	end
	always @(posedge clk) if (rst_n) begin
		#1;
		if (3'(dut.EIFIFO0.WADDR - dut.EIFIFO0.RADDR) !== dut.EIFIFO_COUNT[0][2:0]) fifo0_bad++;
	end

	initial begin
		bit [31:0] r;
		int t0, t1, t2;
		int slacks [4] = '{0, 336, 1023, 5};

		repeat (8) @(posedge clk);
		rst_n = 1;
		mclk(4);

		// ---------------- 1. INT0 bit 31: the summary of the enabled INT1 interrupts ----------------
		rd_check("INT0 pending after reset", 16'h0040, 32'h00000000);
		rd_check("INT0 enables after reset (bit 31 reads 1)", 16'h0048, 32'h80000000);
		check("FIRQ_N after reset", firq_n, 1);
		wr(16'h0060, 32'h00000002);                       // software INT1 source 1 pending, not enabled
		rd_check("INT1 pending", 16'h0060, 32'h00000002);
		rd_check("summary of a pending INT1 interrupt that is not enabled", 16'h0040, 32'h00000000, 32'h80000000);
		check("FIRQ_N, INT1 interrupt not enabled", firq_n, 1);
		wr(16'h0068, 32'h00000002);                       // enable it
		rd_check("summary of an enabled pending INT1 interrupt", 16'h0040, 32'h80000000, 32'h80000000);
		rd_check("summary at the clear address too", 16'h0044, 32'h80000000, 32'h80000000);
		check("FIRQ_N, enabled INT1 interrupt", firq_n, 0);
		wr(16'h0044, 32'h80000000);                       // clearing bit 31 does not clear the INT1 interrupt
		rd_check("summary after writing 0x44 bit 31", 16'h0040, 32'h80000000, 32'h80000000);
		wr(16'h0064, 32'h00000002);                       // acknowledge
		rd_check("summary after the INT1 interrupt is acknowledged", 16'h0040, 32'h00000000, 32'h80000000);
		check("FIRQ_N after the acknowledge", firq_n, 1);
		wr(16'h0060, 32'h00000002);
		wr(16'h006C, 32'h00000002);                       // pending, then disabled
		rd_check("summary after the INT1 interrupt is disabled", 16'h0040, 32'h00000000, 32'h80000000);
		wr(16'h0064, 32'h00000002);
		wr(16'h0040, 32'h80000000);                       // bit 31 cannot be set
		rd_check("INT0 after writing 0x40 bit 31", 16'h0040, 32'h00000000);
		check("FIRQ_N after writing 0x40 bit 31", firq_n, 1);
		// the player bus interrupt (INT1 bit 0)
		@(posedge clk); #1 pb_int = 1;
		mclk(); #1 pb_int = 0;
		mclk(2);
		rd_check("INT1 pending after a player bus interrupt", 16'h0060, 32'h00000001);
		rd_check("summary of a player bus interrupt that is not enabled", 16'h0040, 32'h00000000, 32'h80000000);
		check("FIRQ_N, player bus interrupt not enabled", firq_n, 1);
		wr(16'h0068, 32'h00000001);
		rd_check("summary of an enabled player bus interrupt", 16'h0040, 32'h80000000, 32'h80000000);
		check("FIRQ_N, enabled player bus interrupt", firq_n, 0);
		wr(16'h0064, 32'h00000001);
		rd_check("summary after the player bus interrupt is acknowledged", 16'h0040, 32'h00000000, 32'h80000000);
		check("FIRQ_N after the player bus acknowledge", firq_n, 1);
		wr(16'h006C, 32'hFFFFFFFF);
		// an INT0 source
		wr(16'h0040, 32'h00000020);
		rd_check("INT0 source 5 pending", 16'h0040, 32'h00000020);
		check("FIRQ_N, INT0 source 5 not enabled", firq_n, 1);
		wr(16'h0048, 32'h00000020);
		check("FIRQ_N, INT0 source 5 enabled", firq_n, 0);
		wr(16'h0044, 32'h00000020);
		wr(16'h004C, 32'h00000020);
		check("FIRQ_N after INT0 source 5 is cleared", firq_n, 1);

		// ---------------- 2. timer control read-back ----------------
		wr(16'h0204, 32'hFFFFFFFF); wr(16'h020C, 32'hFFFFFFFF);
		wr(16'h0200, 32'h00000072);
		rd_check("timer controls 0-7 at the set address", 16'h0200, 32'h00000072);
		rd_check("timer controls 0-7 at the clear address", 16'h0204, 32'h00000072);
		wr(16'h0204, 32'h00000002);
		rd_check("timer controls 0-7 after a clear", 16'h0200, 32'h00000070);
		wr(16'h0208, 32'h30000000);
		rd_check("timer controls 8-15 at the set address", 16'h0208, 32'h30000000);
		rd_check("timer controls 8-15 at the clear address", 16'h020C, 32'h30000000);
		rd_check("timer controls 0-7 unchanged by the other bank", 16'h0204, 32'h00000070);
		wr(16'h0204, 32'hFFFFFFFF); wr(16'h020C, 32'hFFFFFFFF);
		rd_check("timer controls 0-7 cleared", 16'h0200, 32'h00000000);
		rd_check("timer controls 8-15 cleared", 16'h0208, 32'h00000000);

		// ---------------- 3. TimerSlack ----------------
		rd_check("TimerSlack after reset", 16'h0220, 32'd336);
		load_timer(0, 16'hFFFF, 16'hFFFF);
		wr(16'h0200, {28'h0, DEC | RLD});
		foreach (slacks[i]) begin
			int slack;
			slack = slacks[i];
			wr(16'h0220, 32'(slack));
			rd_check($sformatf("TimerSlack %0d read back", slack), 16'h0220, 32'(slack));
			wait_count(0, t0);                            // align to a count
			wait_count(0, t1);
			wait_count(0, t2);
			check($sformatf("count period with TimerSlack %0d (CE_R ticks)", slack), 32'(t1), 32'(64 + slack));
			check($sformatf("next count period with TimerSlack %0d (CE_R ticks)", slack), 32'(t2), 32'(64 + slack));
		end
		wr(16'h0220, 32'h0000FFFF);
		rd_check("TimerSlack keeps 10 bits", 16'h0220, 32'h000003FF);
		wr(16'h0220, 32'd336);
		wr(16'h0204, 32'hFFFFFFFF);

		// ---------------- 4. cascaded timers ----------------
		// a pair as the 32-bit countdown 0001:0000
		load_timer(0, 16'h0000, 16'hFFFF);
		load_timer(1, 16'h0001, 16'hFFFF);
		wr(16'h0220, 32'd1023);                          // 43 us between counts: room to read both
		wr(16'h0044, 32'hFFFFFFFF);
		wr(16'h0200, {24'h0, DEC | RLD | CAS, DEC | RLD});
		wait_count(0, t0);
		check("cascaded pair right after the low timer's borrow (internal)", {dut.TM_CNT[1], dut.TM_CNT[0]}, 32'h0000FFFF);
		rd(16'h0108, r); t1 = r[15:0];
		rd(16'h0100, r);
		check("cascaded pair right after the low timer's borrow (read)", {16'(t1), r[15:0]}, 32'h0000FFFF);
		rd_check("timer 1 did not borrow: INT0 bit 10 clear", 16'h0040, 32'h00000000, 32'h00000400);
		wait_count(0, t0);
		check("cascaded pair one count later", {dut.TM_CNT[1], dut.TM_CNT[0]}, 32'h0000FFFE);
		wr(16'h0204, 32'hFFFFFFFF);
		// the high timer borrows too: 0000:0000 -> FFFF:FFFF, timer 1's interrupt
		load_timer(0, 16'h0000, 16'hFFFF);
		load_timer(1, 16'h0000, 16'hFFFF);
		wr(16'h0044, 32'hFFFFFFFF);
		wr(16'h0200, {24'h0, DEC | RLD | CAS, DEC | RLD});
		wait_count(0, t0);
		check("cascaded pair 0000:0000 one count later", {dut.TM_CNT[1], dut.TM_CNT[0]}, 32'hFFFFFFFF);
		rd_check("timer 1's borrow sets INT0 bit 10", 16'h0040, 32'h00000400, 32'h00000400);
		wr(16'h0204, 32'hFFFFFFFF);
		// a chain of three (timers 4, 5, 6), as the OS's clock: 7:0000:0000
		load_timer(4, 16'h0000, 16'h0002);
		load_timer(5, 16'h0000, 16'hFFFF);
		load_timer(6, 16'h0007, 16'hFFFF);
		wr(16'h0044, 32'hFFFFFFFF);
		wr(16'h0200, {4'h0, DEC | RLD | CAS, DEC | RLD | CAS, DEC | RLD, 16'h0});
		wait_count(4, t0);
		check("chain of three after the lowest timer's borrow", {dut.TM_CNT[6], dut.TM_CNT[5], dut.TM_CNT[4]}, {16'h0006, 16'hFFFF, 16'h0002});
		rd_check("timer 5's borrow sets INT0 bit 8", 16'h0040, 32'h00000100, 32'h00000100);
		wait_count(4, t0);
		check("chain of three one count later (no borrow)", {dut.TM_CNT[6], dut.TM_CNT[5], dut.TM_CNT[4]}, {16'h0006, 16'hFFFF, 16'h0001});
		wr(16'h0204, 32'hFFFFFFFF);
		// timer 3 is not cascaded: timer 2's borrow does not make it count twice
		load_timer(2, 16'h0000, 16'h0010);
		load_timer(3, 16'h0020, 16'h0020);
		wr(16'h0200, {16'h0, DEC | RLD, DEC | RLD, 8'h0});
		wait_count(2, t0);
		check("timers 2 and 3, not cascaded, after timer 2's borrow", {dut.TM_CNT[3], dut.TM_CNT[2]}, {16'h001F, 16'h0010});
		wr(16'h0204, 32'hFFFFFFFF);
		// a cascaded timer whose lower timer does not count
		load_timer(8, 16'h0000, 16'hFFFF);
		load_timer(9, 16'h0005, 16'hFFFF);
		load_timer(10, 16'h0100, 16'h0100);
		wr(16'h0208, {20'h0, DEC | RLD, DEC | RLD | CAS, 4'h0});   // 10 counts, 9 cascaded on 8 (stopped)
		wait_count(10, t0);
		mclk(2);
		check("cascaded timer 9 with timer 8 stopped", {16'h0, dut.TM_CNT[9]}, 32'h00000005);
		wr(16'h020C, 32'hFFFFFFFF);
		// without reload: stops at FFFF, its decrement bit cleared; timer 15's interrupt
		load_timer(15, 16'h0000, 16'h1234);
		wr(16'h0044, 32'hFFFFFFFF);
		wr(16'h0208, {DEC, 28'h0});
		wait_count(15, t0);
		mclk(2);
		check("timer 15 without reload after its borrow", {16'h0, dut.TM_CNT[15]}, 32'h0000FFFF);
		rd_check("timer 15's decrement bit cleared", 16'h0208, 32'h00000000);
		rd_check("timer 15's borrow sets INT0 bit 3", 16'h0040, 32'h00000008, 32'h00000008);
		no_count("timer 15 counts no more after it stopped (three periods)", 15, 3 * (64 + 336));

		// ---------------- 5. DSP output memory and output FIFO status ----------------
		dsp_en = 1;
		wr(16'h17FC, 32'h0);                           // DSP stopped
		wr(16'h0300, 32'h000F1FFF);                    // all FIFOs initialised
		code(0, 16'h9B00); code(1, 16'hC111);          // MOVE output memory 0 <- 0x111
		code(2, 16'h9B01); code(3, 16'hC222);
		code(4, 16'h9B02); code(5, 16'hC333);
		code(6, 16'h9B03); code(7, 16'hC444);
		code(8, 16'h9BF0); code(9, 16'hC555);          // MOVE output FIFO 0 <- 0x555
		code(10, 16'h9BF1); code(11, 16'hC666);
		code(12, 16'h9BF2); code(13, 16'hC777);
		code(14, 16'h9BF3); code(15, 16'hC888);
		code(16, 16'h8380); code(17, 16'h8000); code(18, 16'h8000);   // SLEEP, NOP, NOP
		wr(16'h17E8, 32'h0); wr(16'h17FC, 32'h1);      // from 0, run
		mclk(100);
		wr(16'h17FC, 32'h0);                           // stopped before the next frame
		check("DSP program reached its SLEEP", {31'h0, dut.DSP.SLEEP}, 32'h1);
		for (int i = 0; i < 4; i++)
			rd_check($sformatf("16-bit read of output memory word %0d", i), 16'h3C00 + 16'(4 * i), 32'(16'h111 * (i + 1)));
		rd_check("32-bit read of output memory words 0 and 1", 16'h3800, 32'h01110222);
		rd_check("32-bit read of output memory words 2 and 3", 16'h3804, 32'h03330444);
		for (int i = 0; i < 4; i++) begin
			check($sformatf("output FIFO %0d holds one word (internal)", i), 32'(dut.EOFIFO_COUNT[i]), 32'h1);
			rd_check($sformatf("output FIFO %0d status", i), 16'h03C0 + 16'(4 * i), 32'h1);
			rd_check($sformatf("input FIFO %0d status", i), 16'h0380 + 16'(4 * i), 32'h0);
		end

		// ---------------- 5b. the output FIFOs hold 64 words, drained by the DMA ----------------
		// A DSP write to a full output FIFO is lost. The port pauses the 3DO for
		// its slow memory, MADAM and its DMA with it, while the DSP runs on, and
		// Killing Time's EZFlix decoder (8 output words per audio frame per
		// channel) lost words with the hardware's 8-word FIFOs in every pause
		// longer than the two words of room left after a request: 40 words
		// written with the DMA off all wait, the CPU's status reads 40; with the
		// DMA on they come out six per burst, one request per burst, without any
		// further DSP write; the DSP's flush (0x3FD) requests the rest.
		begin
			int bursts, n;
			dsp_en = 1;
			wr(16'h17FC, 32'h0);                           // DSP stopped
			wr(16'h0308, 32'h000F0000);                    // DMA from the output FIFOs off
			wr(16'h0300, 32'h00010000);                    // output FIFO 0 initialised
			for (int i = 0; i < 40; i++) begin
				code(2 * i, 16'h9BF0); code(2 * i + 1, 16'hC100 + 16'(i));   // MOVE output FIFO 0 <- 0x100 + i
			end
			code(80, 16'h8380); code(81, 16'h8000); code(82, 16'h8000);   // SLEEP, NOP, NOP
			eo_lost = 0;
			wr(16'h17E8, 32'h0); wr(16'h17FC, 32'h1);      // from 0, run (no audio frames here: no restart)
			n = 0;
			while (!dut.DSP.SLEEP && n < 2000) begin mclk(); n++; end
			mclk(4);
			wr(16'h17FC, 32'h0);
			check("5b: DSP program reached its SLEEP", {31'h0, dut.DSP.SLEEP}, 32'h1);
			check("5b: output FIFO 0 holds 40 words", 32'(dut.EOFIFO_COUNT[0]), 32'd40);
			check("5b: no write refused", 32'(eo_lost), 32'd0);
			rd_check("5b: output FIFO 0 status (CPU, 0x3C0)", 16'h03C0, 32'd40);
			eo_words.delete();
			bursts = 0;
			wr(16'h0304, 32'h00010000);                    // DMA from output FIFO 0 on
			n = 0;
			while (n < 3000 && bursts < 8) begin
				mclk(); n++; #1;
				if (dut.DMA_ST == 4'd3) begin                // DMA_DSP_READ: channel 0x10 granted
					if (bursts == 0) check("5b: DMA channel of the first request", {27'h0, dmach}, 32'h10);
					repeat (3) begin                           // MADAM reads three 32-bit words
						#1 clc = 3'h2;
						mclk(); #1 clc = 3'h0;
						mclk(3);
					end
					#1 clc = 3'h7;
					mclk(); #1 clc = 3'h0;
					mclk(4);
					bursts++;
				end
			end
			check("5b: DMA bursts from output FIFO 0 (six words each, one request per burst)", 32'(bursts), 32'd6);
			check("5b: words MADAM took", 32'(eo_words.size()), 32'd18);
			for (int k = 0; k < 18 && k < eo_words.size(); k++)
				check($sformatf("5b: DMA word %0d", k), eo_words[k], {16'h100 + 16'(2 * k), 16'h101 + 16'(2 * k)});
			check("5b: four words wait (fewer than a burst)", 32'(dut.EOFIFO_COUNT[0]), 32'd4);
			code(0, 16'h9BFD); code(1, 16'hC001);          // MOVE 0x3FD <- 1: flush output FIFO 0
			code(2, 16'h8380); code(3, 16'h8000); code(4, 16'h8000);
			wr(16'h17E8, 32'h0); wr(16'h17FC, 32'h1);
			n = 0;
			while (!dut.DSP.SLEEP && n < 2000) begin mclk(); n++; end
			mclk(4);
			wr(16'h17FC, 32'h0);
			eo_words.delete();
			n = 0; bursts = 0;
			while (n < 500 && bursts < 1) begin
				mclk(); n++; #1;
				if (dut.DMA_ST == 4'd3) begin
					repeat (2) begin
						#1 clc = 3'h2;
						mclk(); #1 clc = 3'h0;
						mclk(3);
					end
					#1 clc = 3'h7;
					mclk(); #1 clc = 3'h0;
					mclk(4);
					bursts++;
				end
			end
			check("5b: the flush requested a burst", 32'(bursts), 32'd1);
			check("5b: flushed words", 32'(eo_words.size()), 32'd2);
			for (int k = 0; k < 2 && k < eo_words.size(); k++)
				check($sformatf("5b: flushed word %0d", k), eo_words[k], {16'h124 + 16'(2 * k), 16'h125 + 16'(2 * k)});
			check("5b: output FIFO 0 empty after the flush", 32'(dut.EOFIFO_COUNT[0]), 32'h0);
			wr(16'h0308, 32'h00010000);                    // DMA from output FIFO 0 off again
		end

		// ---------------- 5c. a pause of the 3DO while the DSP runs on ----------------
		// The port pauses the 3DO for its slow memory (IO_EN low: MADAM, and with
		// it the DMA that drains the output FIFOs, stops) while the DSP keeps its
		// audio frame rate (DSP_EN high: pausing it with the 3DO loses frames,
		// p3do_gamebub). A Killing Time-like run of 24 output words (its EZFlix
		// decoder writes 8 per frame per channel, ~50 MCLKs apart), then a flush,
		// paused for 800 MCLKs at the first DMA request: the DSP finishes during
		// the pause, all 24 words wait, and come out in four bursts after it,
		// each requested as six words remain; the flush, issued while the first
		// request was pending, is ignored (as in the original). (The program first
		// sets the frame reload to 0, so no counter frame restarts it; a program
		// after it sets 565 back.)
		begin
			int bursts, n;
			bit paused;
			dsp_en = 1;
			wr(16'h17FC, 32'h0);                           // DSP stopped
			wr(16'h0300, 32'h00010000);                    // output FIFO 0 initialised
			code(0, 16'h9BEF); code(1, 16'hC000);          // MOVE 0x3EF <- 0: no counter frames
			for (int i = 0; i < 24; i++) begin
				code(2 + 18 * i, 16'h9BF0); code(3 + 18 * i, 16'hC200 + 16'(i));   // MOVE output FIFO 0 <- 0x200 + i
				for (int j = 2; j < 18; j++) code(2 + 18 * i + j, 16'h8000);       // 16 NOPs between the writes
			end
			code(434, 16'h9BFD); code(435, 16'hC001);      // flush output FIFO 0
			code(436, 16'h8380); code(437, 16'h8000); code(438, 16'h8000);
			eo_words.delete();
			eo_lost = 0; bursts = 0; paused = 0;
			wr(16'h0304, 32'h00010000);                    // DMA from output FIFO 0 on
			wr(16'h17E8, 32'h0); wr(16'h17FC, 32'h1);      // run
			n = 0;
			while (n < 6000 && !(dut.DSP.SLEEP && bursts >= 4)) begin
				mclk(); n++; #1;
				if (dut.DMA_ST == 4'd3) begin                // channel 0x10 granted
					if (!paused) begin                         // the 3DO pauses at the first request
						io_en = 0;
						mclk(800);
						check("5c: the DSP ran through the pause (its program slept)", {31'h0, dut.DSP.SLEEP}, 32'h1);
						check("5c: all 24 words wait in output FIFO 0", 32'(dut.EOFIFO_COUNT[0]), 32'd24);
						io_en = 1;
						paused = 1;
						#1;
					end
					repeat (3) begin                           // MADAM's burst: three 32-bit words
						#1 clc = 3'h2;
						mclk(); #1 clc = 3'h0;
						mclk(3);
					end
					#1 clc = 3'h7;
					mclk(); #1 clc = 3'h0;
					mclk(4);
					bursts++;
				end
			end
			mclk(50);                                      // no further request
			wr(16'h17FC, 32'h0);
			check("5c: the 3DO paused at the first request", {31'h0, paused}, 32'h1);
			check("5c: DMA bursts after the pause", 32'(bursts), 32'd4);
			check("5c: output words lost", 32'(eo_lost), 32'd0);
			check("5c: 32-bit words MADAM took", 32'(eo_words.size()), 32'd12);
			for (int k = 0; k < eo_words.size(); k++)
				check($sformatf("5c: DMA word %0d", k), eo_words[k], {16'h200 + 16'(2 * k), 16'h201 + 16'(2 * k)});
			check("5c: output FIFO 0 empty", 32'(dut.EOFIFO_COUNT[0]), 32'h0);
			wr(16'h0308, 32'h00010000);                    // DMA from output FIFO 0 off again
		end
		begin                                              // the frame reload back to 565
			int n;
			code(0, 16'h9BEF); code(1, 16'hC235); code(2, 16'h8380); code(3, 16'h8000); code(4, 16'h8000);
			wr(16'h17E8, 32'h0); wr(16'h17FC, 32'h1);
			n = 0;
			while (!dut.DSP.SLEEP && n < 200) begin mclk(); n++; end
			wr(16'h17FC, 32'h0);
			check("5c: frame reload back to 565", 32'(dut.RELOAD), 32'd565);
		end

		// ---------------- 6a. the FIFO modules ----------------
		begin
			bit [31:0] qm [$];
			@(negedge clk); f_rst = 1;
			@(negedge clk); f_rst = 0;
			// the audit's sequence: two words through, then a read and a
			// write at once on the empty FIFO, a write, a read
			fifo_step(1, 0, qm); fifo_step(1, 0, qm); fifo_step(0, 1, qm); fifo_step(0, 1, qm);
			fifo_step(1, 1, qm); fifo_step(1, 0, qm); fifo_step(0, 1, qm); fifo_step(0, 1, qm);
			// fill, then a read and a write at once on the full FIFO, and a refused write
			for (int i = 0; i < 8; i++) fifo_step(1, 0, qm);
			fifo_step(1, 1, qm); fifo_step(1, 0, qm);
			for (int i = 0; i < 9; i++) fifo_step(0, 1, qm);
			// random traffic, biased now to the empty end, now to the full end
			for (int k = 0; k < 4000; k++) begin
				int bias;
				bias = (k / 500) % 2 ? 70 : 30;          // % chance of a write
				fifo_step(($urandom() % 100) < bias, ($urandom() % 100) < 50, qm);
			end
			$display("[%0t] FIFO modules: %0d reads (%0d of an empty FIFO with a write), %0d read+write on a full FIFO, %0d writes refused (full), %0d reads refused (empty)",
			         $realtime, f_reads, f_bypass, f_full_rw, f_refused_wr, f_refused_rd);
			checks++;
			if (f_bypass < 10 || f_full_rw < 10 || f_refused_wr < 10 || f_refused_rd < 10) begin
				errors++;
				$display("[%0t] TB ERROR: FIFO boundary cases not all exercised", $realtime);
			end
		end

		// ---------------- 6b. a DSP reading input FIFO 0 during a DMA refill ----------------
		for (int delay = 0; delay < 16 && fifo0_collisions == 0; delay++) begin
			int waited;
			wr(16'h17FC, 32'h0);
			wr(16'h0300, 32'h000F1FFF);
			code(0, 16'h9B00); code(1, 16'h80F0);      // MOVE output memory 0 <- input FIFO 0
			code(2, 16'h8400); code(3, 16'h8000);      // JUMP 0, NOP
			fifo0_in.delete(); fifo0_out.delete();
			wr(16'h17E8, 32'h0); wr(16'h17FC, 32'h1);
			wr(16'h0304, 32'h1);                       // DMA to input FIFO 0 enabled
			waited = 0;
			while (dut.DMA_ST != 2 && waited < 40) begin mclk(); waited++; end
			if (waited == 40) begin errors++; $display("[%0t] TB ERROR: CLIO's DMA did not start (state %0d)", $realtime, dut.DMA_ST); break; end
			mclk(delay);
			// MADAM: three 32-bit words, each a code 2 bus cycle, then code 7
			for (int i = 0; i < 3; i++) begin
				mclk(); #1 mem_di = 32'h11112222 + 32'h11111111 * i; clc = 3'h2;
				mclk(); #1 clc = 3'h0;
				mclk(5);
			end
			mclk(); #1 clc = 3'h7;
			mclk(); #1 clc = 3'h0;
			mclk(8);
			wr(16'h17FC, 32'h0);
			mclk(8);
			checks++;
			if (fifo0_out != fifo0_in || fifo0_in.size() != 6) begin
				errors++;
				$display("[%0t] TB ERROR: input FIFO 0 (DMA delay %0d): %0d words in, %0d taken by the DSP, or not the same order", $realtime, delay, fifo0_in.size(), fifo0_out.size());
				foreach (fifo0_in[i]) $display("    in  %0d: %04h", i, fifo0_in[i]);
				foreach (fifo0_out[i]) $display("    out %0d: %04h", i, fifo0_out[i]);
			end
		end
		checks++;
		if (fifo0_collisions == 0) begin errors++; $display("[%0t] TB ERROR: no DSP read met a DMA write on the empty input FIFO 0 (case not exercised)", $realtime); end
		checks++;
		if (fifo0_bad != 0) begin errors++; $display("[%0t] TB ERROR: input FIFO 0's pointers and count disagreed in %0d clocks", $realtime, fifo0_bad); end
		$display("[%0t] DSP / DMA on input FIFO 0: %0d reads meeting a write on the empty FIFO, words in order", $realtime, fifo0_collisions);
		// the program kept reading after the FIFO drained: it holds the last word
		rd_check("output memory 0 after input FIFO 0 drained (the last DMA word)", 16'h3C00, 32'(fifo0_in[$]));
		check("input FIFO 0 empty", {28'h0, dut.EIFIFO_COUNT[0]}, 32'h0);

		// ---------------- 6c. an input FIFO read gives the CPU's head word, then the FIFO's ----------------
		// MADAM fills input FIFO 0 with six words (DSP stopped), the CPU writes
		// the head word 0x070 (the audio folio's FIFOHEAD, zeroed with every
		// FIFO reset; a streamer's one discard read takes it), then the DSP
		// program moves to the output memory: 0 <- 0x070 (the CPU's word, not
		// popped), 1 <- 0x0F0 (the FIFO's first word, popped), 2 <- 0x070 (the
		// next, not popped), 3..7 <- 0x0F0 (the rest), 8 <- 0x0F0 and 9 <- 0x070
		// (empty: the last word again). The original gave the word of the
		// previous read every time, so the FIFO's first word came out only at
		// the second read, and the CPU's at the first only with the FIFO empty.
		begin
			int waited;
			wr(16'h17FC, 32'h0);
			wr(16'h0300, 32'h000F1FFF);
			wr(16'h0308, 32'hFFFFFFFF);
			code(0, 16'h9B00); code(1, 16'h8070);
			code(2, 16'h9B01); code(3, 16'h80F0);
			code(4, 16'h9B02); code(5, 16'h8070);
			for (int i = 3; i < 9; i++) begin code(2 * i, 16'h9B00 + 16'(i)); code(2 * i + 1, 16'h80F0); end
			code(18, 16'h9B09); code(19, 16'h8070);
			code(20, 16'h8380); code(21, 16'h8000); code(22, 16'h8000);
			wr(16'h0304, 32'h1);                                   // DMA to input FIFO 0: CLIO asks for words
			waited = 0;
			while (dut.DMA_ST != 2 && waited < 40) begin mclk(); waited++; end
			if (waited == 40) begin errors++; $display("[%0t] TB ERROR: 6c: CLIO's DMA did not start (state %0d)", $realtime, dut.DMA_ST); end
			for (int i = 0; i < 3; i++) begin                      // MADAM: three 32-bit words, code 7
				mclk(); #1 mem_di = {16'hA100 + 16'(2 * i), 16'hA101 + 16'(2 * i)}; clc = 3'h2;
				mclk(); #1 clc = 3'h0;
				mclk(5);
			end
			mclk(); #1 clc = 3'h7;
			mclk(); #1 clc = 3'h0;
			mclk(8);
			wr(16'h0308, 32'h1);                                   // no more refills
			check("6c: input FIFO 0 holds six words", {28'h0, dut.EIFIFO_COUNT[0]}, 32'h6);
			wr(16'h35C0, 32'h1234);                                // the CPU's head word (0x070)
			dsp_run(120);
			check("6c: input FIFO 0 empty after the program", {28'h0, dut.EIFIFO_COUNT[0]}, 32'h0);
			rd_check("6c: 0x070 first: the CPU's head word", 16'h3C00, 32'h1234);
			rd_check("6c: first 0x0F0 read: the FIFO's first word", 16'h3C04, 32'hA100);
			rd_check("6c: 0x070 after one read: the next word", 16'h3C08, 32'hA101);
			for (int i = 1; i < 6; i++)
				rd_check($sformatf("6c: 0x0F0 read %0d: word %0d", i + 1, i), 16'h3C08 + 16'(4 * i), 32'hA100 + 32'(i));
			rd_check("6c: 0x0F0 read of the empty FIFO: the last word", 16'h3C20, 32'hA105);
			rd_check("6c: 0x070 on the empty FIFO: the last word", 16'h3C24, 32'hA105);
		end

		// ---------------- 7a. instructions without operands ----------------
		// INC = 0x0060, DEC = 0x0070: ACC +- 1 in the ALU's LSB, 1/16 of an
		// output word (the ALU is 20 bits, words enter it shifted left by 4;
		// Opera, MAME); ACC transfer with a write-back = 0x2000 + address;
		// multiply of two immediates = 0x5C00 (M1 * M2 * 2, bits 31..12)
		begin
			int i;
			i = 0;
			code(i++, 16'h0070); code(i++, 16'h0070);                   // ACC = 0 - 2 = FFFFE
			code(i++, 16'h2000); code(i++, 16'h8300);                   // output memory 0 <- FFFF
			code(i++, 16'h5C00); code(i++, 16'hC800); code(i++, 16'hC800); // ACC = 0x00800 (word 0x80)
			repeat (16) code(i++, 16'h0060);                            // 0x00810
			code(i++, 16'h2000); code(i++, 16'h8301);                   // output memory 1 <- 0x81
			repeat (16) code(i++, 16'h0060);                            // 0x00820, after an ACC transfer
			code(i++, 16'h2000); code(i++, 16'h8302);                   // output memory 2 <- 0x82
			code(i++, 16'h8380); code(i++, 16'h8000); code(i++, 16'h8000); // SLEEP, NOP, NOP
		end
		for (int run = 0; run < 3; run++) begin
			wr(16'h3C00, 32'hDEAD); wr(16'h3C04, 32'hDEAD); wr(16'h3C08, 32'hDEAD);
			dsp_run(200);
			check($sformatf("run %0d: DSP program reached its SLEEP", run), {31'h0, dut.DSP.SLEEP}, 32'h1);
			check($sformatf("run %0d: DSP computation idle at the SLEEP", run), {31'h0, dut.DSP.COMP_ST}, 32'h0);
			check($sformatf("run %0d: ACC at the SLEEP (20 bits)", run), {12'h0, dut.DSP.ACC}, 32'h00820);
			rd_check($sformatf("run %0d: DEC, DEC from a reset", run), 16'h3C00, 32'hFFFF);
			rd_check($sformatf("run %0d: 16 INC after a multiply", run), 16'h3C04, 32'h0081);
			rd_check($sformatf("run %0d: 16 INC after an ACC transfer", run), 16'h3C08, 32'h0082);
		end

		// ---------------- 7b. accumulator and flags clear at every frame ----------------
		// ADDC = 0x2030 (ACC + carry) with a write-back; ADD of two operands = 0x4620
		wr(16'h3400, 32'h0001);                                     // input memory 0 = 1
		wr(16'h3404, 32'h8000);                                     // input memory 1 = 0x8000
		code(0, 16'h2030); code(1, 16'h8301);                       // output memory 1 <- ACC + carry (0 + 0)
		code(2, 16'h4120); code(3, 16'h8000); code(4, 16'h8300);    // output memory 0 <- ACC + 1
		code(5, 16'h4620); code(6, 16'h8001); code(7, 16'h8001);    // 0x8000 + 0x8000: carry
		code(8, 16'h8380); code(9, 16'h8000); code(10, 16'h8000);
		for (int run = 0; run < 3; run++) begin
			wr(16'h3C00, 32'hDEAD); wr(16'h3C04, 32'hDEAD);
			dsp_run(80);
			rd_check($sformatf("CPU reset %0d: ACC + 1 from the frame start", run), 16'h3C00, 32'h0001);
			rd_check($sformatf("CPU reset %0d: ACC + carry from the frame start", run), 16'h3C04, 32'h0000);
			check($sformatf("CPU reset %0d: the program's add set the carry", run), {31'h0, dut.DSP.STATUS[2]}, 32'h1);
		end
		// the DSP's own frames (reload 565): five of them
		wr(16'h3C00, 32'hDEAD); wr(16'h3C04, 32'hDEAD);
		wr(16'h17E8, 32'h0); wr(16'h17FC, 32'h1);
		frame_at.delete();
		while (frame_at.size() < 6) mclk();
		mclk(80);
		wr(16'h17FC, 32'h0);
		rd_check("after five DSP frames: ACC + 1 from the frame start", 16'h3C00, 32'h0001);
		rd_check("after five DSP frames: ACC + carry from the frame start", 16'h3C04, 32'h0000);

		// ---------------- 7c. an empty input FIFO keeps its word ----------------
		wr(16'h0300, 32'h000F1FFF);
		wr(16'h35C0, 32'h1234);                                     // input FIFO 0's word (0x070)
		for (int i = 0; i < 4; i++) begin code(2 * i, 16'h9B00 + 16'(i)); code(2 * i + 1, 16'h80F0); end
		code(8, 16'h9B04); code(9, 16'h8070);                       // through the alias
		code(10, 16'h9B05); code(11, 16'h80F0);
		code(12, 16'h8380); code(13, 16'h8000); code(14, 16'h8000);
		dsp_run(100);
		check("input FIFO 0 empty", {28'h0, dut.EIFIFO_COUNT[0]}, 32'h0);
		for (int i = 0; i < 6; i++)
			rd_check($sformatf("read %0d of the empty input FIFO 0", i), 16'h3C00 + 16'(4 * i), 32'h1234);

		// ---------------- 7d. the reload value ----------------
		code(0, 16'h8380); code(1, 16'h8000); code(2, 16'h8000);
		rd_check("reload value from power-on", 16'h3FBC, 32'd565);
		wr(16'h17E8, 32'h0); wr(16'h17FC, 32'h1);
		frame_periods("reload 565", 2, 2 * 566);
		wr(16'h17FC, 32'h0);
		code(0, 16'h9BEF); code(1, 16'hC080);                       // reload = 128
		code(2, 16'h8380); code(3, 16'h8000); code(4, 16'h8000);
		dsp_run(40);
		rd_check("reload value the DSP wrote", 16'h3FBC, 32'd128);
		code(0, 16'h8380); code(1, 16'h8000); code(2, 16'h8000);   // the write is not made again
		wr(16'h17E8, 32'h0); wr(16'h17FC, 32'h1);
		frame_periods("reload 128", 4, 2 * 129);
		rd_check("reload value after the DSP's frames", 16'h3FBC, 32'd128);
		wr(16'h17E8, 32'h0);                                        // a CPU reset
		rd_check("reload value after a CPU reset", 16'h3FBC, 32'd128);
		frame_periods("reload 128 after a CPU reset", 3, 2 * 129);
		wr(16'h17FC, 32'h0);

		// ---------------- 7e. audio lock ----------------
		code(0, 16'h9BEB); code(1, 16'hF000);                       // audio lock (0x8000)
		code(2, 16'h9BEF); code(3, 16'hC040);                       // reload = 64
		code(4, 16'h8380); code(5, 16'h8000); code(6, 16'h8000);
		dsp_run(40);
		check("audio lock set", {31'h0, dut.AUDLOCK}, 32'h1);
		code(0, 16'h8380); code(1, 16'h8000); code(2, 16'h8000);
		wr(16'h17FC, 32'h1);
		no_frames("audio lock without the word strobe", 10 * 65);
		@(negedge clk) aclk_ce = 1;                                 // a strobe every 0x180 clk
		frame_periods("audio lock with the word strobe", 4, 384);
		@(negedge clk) aclk_ce = 0;
		no_frames("audio lock, the strobe stopped", 10 * 65);
		wr(16'h17FC, 32'h0);
		code(0, 16'h9BEB); code(1, 16'hC000);                       // audio lock cleared
		code(2, 16'h8380); code(3, 16'h8000); code(4, 16'h8000);
		dsp_run(40);
		check("audio lock cleared", {31'h0, dut.AUDLOCK}, 32'h0);
		code(0, 16'h8380); code(1, 16'h8000); code(2, 16'h8000);
		wr(16'h17E8, 32'h0); wr(16'h17FC, 32'h1);
		frame_periods("counter frames after audio lock (reload 64)", 3, 2 * 65);
		wr(16'h17FC, 32'h0);

		// ---------------- 7f. indirect operands ----------------
		code(0, 16'h9BEF); code(1, 16'hC235);                       // reload back to 565 (7e left 64)
		code(2, 16'h8380); code(3, 16'h8000); code(4, 16'h8000);
		dsp_run(40);
		rd_check("reload value 565 for the programs that follow", 16'h3FBC, 32'd565);
		// input memory: 0 = pointer to 2, 1 = 0x0100, 2 = 0x5A3C (a value no
		// earlier section leaves in the output memory, which the CPU cannot write)
		wr(16'h3400, 32'h0002); wr(16'h3404, 32'h0100); wr(16'h3408, 32'h5A3C);
		begin
			int i;
			i = 0;
			code(i++, 16'h4400); code(i++, 16'h8400); code(i++, 16'h8300);                    // output 0 <- [[0]]
			code(i++, 16'h6620); code(i++, 16'h8001); code(i++, 16'h8400); code(i++, 16'h8301); // output 1 <- [1] + [[0]]
			code(i++, 16'h8380); code(i++, 16'h8000); code(i++, 16'h8000);
		end
		eo0_writes = 0;
		dsp_run(80);
		check("indirect operands: program reached its SLEEP", {31'h0, dut.DSP.SLEEP}, 32'h1);
		rd_check("indirect operand alone (through the pointer)", 16'h3C00, 32'h5A3C);
		check("indirect operand alone: output words written", 32'(eo0_writes), 32'h1);
		rd_check("direct + indirect operand", 16'h3C04, 32'h5B3C);

		// ---------------- 8. shifts with the control from an operand ----------------
		// 0x4408: two operands (ALU1 = ACC <- operand, output) + the shift control;
		// 0x6628: three (ALU1 + ALU2, output) + the shift control
		begin
			typedef struct { string what; bit [15:0] inst, a1, a2, shift_op, shift_mem, exp; } shift_case_t;
			shift_case_t sc [6];
			sc[0] = '{"0x11 << 4, immediate control",           16'h4408, 16'h0011, 16'h0000, 16'hC004, 16'h0000, 16'h0110};
			sc[1] = '{"0x11 << 4, control from memory",         16'h4408, 16'h0011, 16'h0000, 16'h8001, 16'h0004, 16'h0110};
			sc[2] = '{"0xF000 >> 4 logical, immediate control",  16'h4408, 16'hF000, 16'h0000, 16'hC01C, 16'h0000, 16'h0F00};
			sc[3] = '{"0xF000 >> 4 arithmetic, from memory",    16'h4408, 16'hF000, 16'h0000, 16'h8001, 16'h000C, 16'hFF00};
			sc[4] = '{"0x11 + 0x22 << 1, immediate control",    16'h6628, 16'h0011, 16'h0022, 16'hC001, 16'h0000, 16'h0066};
			sc[5] = '{"0x4321 << 8, control from memory",       16'h4408, 16'h4321, 16'h0000, 16'h8001, 16'h0006, 16'h2100};
			foreach (sc[k]) begin
				int i;
				wr(16'h3400, {16'h0, sc[k].a1}); wr(16'h3404, {16'h0, sc[k].shift_mem}); wr(16'h3408, {16'h0, sc[k].a2});
				wr(16'h3C00, 32'hDEAD);
				i = 0;
				code(i++, sc[k].inst); code(i++, 16'h8000);
				if (sc[k].inst == 16'h6628) code(i++, 16'h8002);
				code(i++, sc[k].shift_op); code(i++, 16'h8300);
				code(i++, 16'h8000); code(i++, 16'h8000); code(i++, 16'h8380); code(i++, 16'h8000); code(i++, 16'h8000);
				eo0_writes = 0;
				dsp_run(80);
				check($sformatf("shift %s: program reached its SLEEP", sc[k].what), {31'h0, dut.DSP.SLEEP}, 32'h1);
				rd_check($sformatf("shift %s: output", sc[k].what), 16'h3C00, {16'h0, sc[k].exp});
				check($sformatf("shift %s: output words written", sc[k].what), 32'(eo0_writes), 32'h1);
			end
			// the control from memory (4, at input memory 1), then reused under
			// OPMASK.BS (0x8281) by the same instruction without the operand
			wr(16'h3400, 32'h0011); wr(16'h3404, 32'h0004);
			wr(16'h3C00, 32'hDEAD); wr(16'h3C04, 32'hDEAD);
			code(0, 16'h4408); code(1, 16'h8000); code(2, 16'h8001); code(3, 16'h8300);
			code(4, 16'h8000); code(5, 16'h8000); code(6, 16'h8281);
			code(7, 16'h4408); code(8, 16'h8000); code(9, 16'h8301);
			code(10, 16'h8000); code(11, 16'h8000); code(12, 16'h8380); code(13, 16'h8000); code(14, 16'h8000);
			dsp_run(100);
			check("shift control reused: program reached its SLEEP", {31'h0, dut.DSP.SLEEP}, 32'h1);
			rd_check("shift control from memory: output", 16'h3C00, 32'h0110);
			rd_check("shift control reused under OPMASK: output", 16'h3C04, 32'h0110);
		end
		dsp_en = 0;

		// ---------------- 7g. a result read right after it is written ----------------
		// An ALU writeback that a MOVE's write delays by a clock lands in the clock
		// of the next instruction's read of it (Killing Time's DSP interrupt counter:
		// ADD [108]+1; MOVE; MOVE 3EE <- [108]); the original read the old word.
		// (A read in the very next instruction is not checked: the DSP's pipeline
		// has not computed the result yet; Killing Time's program never does it.)
		dsp_en = 1;
		wr(16'h17FC, 32'h0);
		code(0, 16'h9908); code(1, 16'hC041);                       // MOVE 108 <- 0x41
		code(2, 16'h4620); code(3, 16'h8908); code(4, 16'hC001);    // ADD [108 WB] + 1
		code(5, 16'h9909); code(6, 16'h8009);                       // MOVE 109 <- [009]
		code(7, 16'h9B00); code(8, 16'h8108);                       // output 0 <- [108]
		code(9, 16'h4620); code(10, 16'h8908); code(11, 16'hC001);  // ADD [108 WB] + 1
		code(12, 16'h8000);                                         // NOP
		code(13, 16'h9B01); code(14, 16'h8108);                     // output 1 <- [108]
		code(15, 16'h4620); code(16, 16'h8908); code(17, 16'hC001); // ADD [108 WB] + 1
		code(18, 16'h2400); code(19, 16'h8108);                     // TRA A1 <- [108] (not checked)
		code(20, 16'h9B02); code(21, 16'h8108);                     // output 2 <- [108]
		// the data memory's 256 words are at 0x100-0x1FF and again at 0x200-0x2FF
		code(22, 16'h4620); code(23, 16'h8908); code(24, 16'hC001); // ADD [108 WB] + 1
		code(25, 16'h9909); code(26, 16'h8009);                     // MOVE 109 <- [009]
		code(27, 16'h9B03); code(28, 16'h8208);                     // output 3 <- [208]
		code(29, 16'h4620); code(30, 16'h8A08); code(31, 16'hC001); // ADD [208 WB] + 1
		code(32, 16'h9909); code(33, 16'h8009);                     // MOVE 109 <- [009]
		code(34, 16'h9B04); code(35, 16'h8108);                     // output 4 <- [108]
		code(36, 16'h8380); code(37, 16'h8000); code(38, 16'h8000);
		dsp_run(300);
		rd_check("7g: the word two instructions after its writeback (a MOVE between)", 16'h3C00, 32'h42);
		rd_check("7g: the word two instructions after its writeback (a NOP between)", 16'h3C04, 32'h43);
		rd_check("7g: the word two instructions after its writeback (an ALU read between)", 16'h3C08, 32'h44);
		rd_check("7g: the word written at 0x108, read at 0x208", 16'h3C0C, 32'h45);
		rd_check("7g: the word written at 0x208, read at 0x108", 16'h3C10, 32'h46);
		dsp_en = 0;

		// ---------------- 11. ADBIO ----------------
		begin
			bit [31:0] r2;
			wr(16'h0084, 32'h00000024);                              // ROM bank bit, mute enable
			rd_check("ADBIO read back", 16'h0084, 32'h00000024);
			rd(16'h0084, r2); wr(16'h0084, r2 | 32'h22);              // read/modify/write: mute on
			rd_check("ADBIO after a read/modify/write", 16'h0084, 32'h00000026);
			check("ROM bank select kept by the read/modify/write", {28'h0, dut.ADBIO_O}, 32'h6);
			// cdipir.c: save the ROM select, enable it and select the primary ROM, restore
			wr(16'h0084, 32'h000000AE);
			rd(16'h0084, r2); r2 = r2 | 32'h40; wr(16'h0084, r2);
			rd(16'h0084, r2); r2 = r2 & ~32'h04; wr(16'h0084, r2);
			rd_check("ADBIO with the primary ROM selected (others kept)", 16'h0084, 32'h000000EA);
			rd(16'h0084, r2); wr(16'h0084, r2 | 32'h44);
			rd_check("ADBIO with the ROM select restored", 16'h0084, 32'h000000EE);
			wr(16'h0084, 32'h0);
			rd_check("ADBIO cleared", 16'h0084, 32'h00000000);
		end

		// ---------------- 10. CSTAT writes (Opera opera_clio_poke 0x28) ----------------
		begin
			bit [31:0] cs;
			// write, the value CSTAT reads then (bits 6..0; bit 4 = SoftReset
			// runs the reset and clears itself, so a write with it is read later)
			bit [31:0] seq [][2] = '{
				'{32'h00000000, 32'h00000000},   // PON (power-on) cleared by 0
				'{32'h00000001, 32'h00000000},   // PON not set again by a write
				'{32'h00000002, 32'h00000000},   // nor ROLLOVER
				'{32'h0000000C, 32'h00000000},   // the watchdog bits are not written
				'{32'h00000020, 32'h00000000},   // ClearDIPIR alone: not stored
				'{32'h00000040, 32'h00000000},   // DIPIRReset not set by a write
				'{32'h00000030, 32'h00000040},   // SoftReset + ClearDIPIR: DIPIRReset
				'{32'h00000040, 32'h00000040},   // writing 1 keeps it
				'{32'h00000041, 32'h00000040},   // and PON stays clear
				'{32'h00000000, 32'h00000000},   // writing 0 clears it
				'{32'h00000E80, 32'h00000E80}    // other bits are stored
			};
			wr(16'h0028, 32'h0);
			foreach (seq[k]) begin
				wr(16'h0028, seq[k][0]);
				mclk(40);                                            // past a soft reset's own clearing of bit 4
				rd(16'h0028, cs);
				check($sformatf("CSTAT after writing %08h (write %0d)", seq[k][0], k), cs, seq[k][1]);
			end
			wr(16'h0028, 32'h0);
		end

		// ---------------- 9. XBUS control and DMA reset ----------------
		begin
			bit [31:0] x;
			int        n;
			wr(16'h0308, 32'hFFFFFFFF);                              // every DMA channel off (6b left DSP FIFO 0 on)
			if (dut.DMA_ST == 4'd2) begin                            // its last request: MADAM completes it
				mclk(); #1 mem_di = 32'h0; clc = 3'h2;
				mclk(); #1 clc = 3'h0;
				mclk(5); #1 clc = 3'h7;
				mclk(); #1 clc = 3'h0;
			end
			mclk(20);
			check("CLIO DMA idle before the XBUS checks", {28'h0, 4'(dut.DMA_ST)}, 32'h0);
			xacc(1, 16'h0400, 32'h00000200, x);                      // direction memory -> expansion
			xacc(0, 16'h0400, 0, x); check("XBUS direction set: read at the set address", x & 32'h0000CA80, 32'h00000200);
			xacc(0, 16'h0404, 0, x); check("XBUS direction set: read at the clear address", x & 32'h0000CA80, 32'h00000200);
			xacc(1, 16'h0404, 32'h00000200, x);
			xacc(0, 16'h0400, 0, x); check("XBUS direction cleared", x & 32'h0000CA80, 32'h00000000);
			// a 64-byte transfer from the expansion bus stalls on the full FIFO (8 words)
			edi = 8'h11;
			xacc(1, 16'h040C, 32'd64, x);
			xacc(1, 16'h0400, 32'h00000800, x);
			n = 0;
			while (!dut.XBUS_FIFO_FULL && n < 3000) begin mclk(); n++; end
			mclk(200);
			check("expansion DMA stalled on its full FIFO (words)", {28'h0, dut.XBUS_FIFO.AMOUNT}, 32'h8);
			xacc(0, 16'h0400, 0, x); check("XBUS DMA on reads back while it is stalled", x & 32'h0000CA80, 32'h00000800);
			xacc(0, 16'h0404, 0, x); check("XBUS DMA on reads back at the clear address", x & 32'h0000CA80, 32'h00000800);
			// XB_DMARESET
			xacc(1, 16'h0400, 32'h00004000, x);
			mclk(16);
			xacc(0, 16'h0400, 0, x); check("XBUS DMA off after XB_DMARESET", x & 32'h0000CA80, 32'h00000000);
			check("expansion FIFO empty after XB_DMARESET", {31'h0, dut.XBUS_FIFO_EMPTY}, 32'h1);
			mclk(400);
			check("no expansion word after XB_DMARESET (stalled transfer stopped)", {28'h0, dut.XBUS_FIFO.AMOUNT}, 32'h0);
			// a new 4-byte transfer, then the DMA to memory (channel 0x14) takes it
			edi = 8'h22;
			xacc(1, 16'h040C, 32'd4, x);
			xacc(1, 16'h0400, 32'h00000800, x);
			mclk(300);
			check("new transfer finished", {31'h0, dut.DMA_XBUS_ACT}, 32'h0);
			check("expansion FIFO after the new transfer (words)", {28'h0, dut.XBUS_FIFO.AMOUNT}, 32'h1);
			check("expansion DMA pending (requests)", {30'h0, dut.DMA_EXP_PEND}, 32'h1);
			exp_words.delete();
			wr(16'h0304, 32'h00100000);                             // DMA from the expansion bus enabled
			n = 0;
			while (n < 2000) begin
				mclk(); n++; #1;
				if (dut.DMA_ST == 4'd5) begin                         // DMA_EXP_READ: channel 0x14 granted
					check("DMA channel of the expansion request", {27'h0, dmach}, 32'h14);
					#1 clc = 3'h2;                                    // MADAM reads a word
					mclk(); #1 clc = 3'h0;
					mclk(3); #1 clc = 3'h7;
					mclk(); #1 clc = 3'h0;
					mclk(4);
				end
			end
			check("words the DMA to memory took after XB_DMARESET", 32'(exp_words.size()), 32'h1);
			if (exp_words.size() > 0) check("the word is the new transfer's", exp_words[0], 32'h22222222);
			wr(16'h0308, 32'h00100000);
			edi = 8'hFF;
		end

		$display("tb_clio: %0d checks, %0d errors", checks, errors);
		if (errors == 0) begin $display("tb_clio: PASS"); $finish; end
		else $fatal(1, "tb_clio: FAIL");
	end

	initial begin
		#20ms;
		$display("tb_clio: TIMEOUT");
		$fatal(1, "tb_clio: FAIL");
	end
endmodule
