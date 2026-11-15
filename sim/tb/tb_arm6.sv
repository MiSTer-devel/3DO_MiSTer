// Testbench: the ARM60 core (ARM6_CORE, ARM6_RB) against the ARM60 datasheet.
//
// Runs sim/tb/arm6_isa.S (assembled by sim/build_testrom.sh into
// build/sim/arm6_isa.bin; +bin=<file> for another) on the core with a 64 KiB
// big-endian memory (byte stores write the addressed byte lane), as the 3DO
// uses it. The program stores its results at 0x8000; the expected values are
// its table at 0x7000 (written from the datasheet, not computed by the core).
// When the program writes 0xFFFC, every result is compared and printed if it
// differs.
//
// The core is paused (EN low) at pseudo-random points for 2 to 16 clocks
// while its rising/falling enables keep running, as a system clock enable
// would pause it; the bus is paused with it (+no_pause: never). Every pause is
// an even number of clocks, so the enables resume in their order.
//
// nTRANS of every access to 0xA000-0xA0FF is written to the word at the same
// offset from 0xA100, where the program reads it back (LDRT/STRT checks).
//
// +fiq / +irq: nFIQ / nIRQ are taken low at pseudo-random points and released
// when the core fetches the vector (0x1C / 0x18), as an interrupt source
// acknowledged by its handler; for sim/tb/arm6_fiq.S (+bin=build/sim/arm6_fiq.bin),
// which runs a decoder-like kernel with and without them and compares. The
// counts the program kept (0x9000, 0x9004) are printed.
//
// Copyright (c) 2026 Adam Polkosnik
// SPDX-License-Identifier: GPL-3.0-or-later

`timescale 1ns/1ps

module tb_arm6;
	reg clk = 0;
	always #5 clk = ~clk;
	// MADAM's CPU interface gives the core alternate rising/falling enables
	reg phase = 0;
	always @(negedge clk) phase <= ~phase;
	reg rst_n = 0, nreset = 0;
	reg en = 1;
	reg nfiq = 1, nirq = 1;

	wire [31:0] a, dout;
	wire        nrw, nwb, nmreq, seq, nopc, ntrans, lock;
	reg  [31:0] mem [0:16383];
	wire [31:0] din = mem[a[15:2]];

	ARM6_CORE dut (
		.CLK(clk), .RST_N(rst_n), .EN(en), .BIGEND(1'b1),
		.CE_R(phase), .CE_F(~phase),
		.nRESET(nreset), .nFIQ(nfiq), .nIRQ(nirq),
		.EDI(32'd0), .A(a), .DI(din), .DO(dout), .nRW(nrw), .nWB(nwb),
		.nMREQ(nmreq), .SEQ(seq), .nOPC(nopc), .nTRANS(ntrans), .LOCK(lock), .DBE(1'b1)
	);

	int  errors = 0, checks = 0;
	bit  done = 0;
	string bin;

	// EN pauses: one starts on 1 clock in 16 and lasts 2, 4, ... 16 clocks
	bit        pause_on;
	bit [15:0] lfsr = 16'hACE1;
	int        pause_left = 0, pauses = 0, paused_clks = 0;
	initial pause_on = !$test$plusargs("no_pause");
	always @(negedge clk) begin
		lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
		if (pause_left != 0) begin
			pause_left <= pause_left - 1;
			if (pause_left == 1) en <= 1;
		end
		else if (pause_on && rst_n && nreset && !done && lfsr[3:0] == 4'h0) begin
			en <= 0;
			pause_left <= 2 * (lfsr[6:4] + 1);
			pauses++;
		end
	end
	always @(posedge clk) if (!en) paused_clks++;

	// interrupts: nFIQ/nIRQ taken low on one clock in 512 (each its own
	// phase of the second LFSR) and released on the fetch of the vector
	bit        fiq_on, irq_on;
	bit [15:0] lfsr2 = 16'h7A3B;
	int        fiq_asserted = 0, irq_asserted = 0;
	initial begin fiq_on = $test$plusargs("fiq"); irq_on = $test$plusargs("irq"); end
	always @(posedge clk) begin
		lfsr2 <= {lfsr2[14:0], lfsr2[15] ^ lfsr2[13] ^ lfsr2[12] ^ lfsr2[10]};
		if (rst_n && nreset && !done) begin
			if (fiq_on && nfiq && lfsr2[8:0] == 9'h000) begin nfiq <= 0; fiq_asserted++; end
			if (irq_on && nirq && lfsr2[9:1] == 9'h0A5) begin nirq <= 0; irq_asserted++; end
		end
		if (rst_n && nreset && !phase && en && mreq_now && !nrw) begin
			if (a[15:0] == 16'h001C) nfiq <= 1;
			if (a[15:0] == 16'h0018) nirq <= 1;
		end
	end

	task automatic load(input string f);
		int fd, n;
		byte b [65536];
		fd = $fopen(f, "rb");
		if (fd == 0) $fatal(1, "tb_arm6: cannot open %s (run sim/build_testrom.sh)", f);
		n = $fread(b, fd);
		$fclose(fd);
		for (int i = 0; i + 3 < n; i += 4)
			mem[i / 4] = {b[i], b[i + 1], b[i + 2], b[i + 3]};
		$display("tb_arm6: %s, %0d bytes", f, n);
	endtask

	// +trace=<address>: every bus cycle at or after the first access to that word
	bit [31:0] tr_addr; bit tr_on = 0, tr_go = 0;
	initial tr_on = $value$plusargs("trace=%h", tr_addr);
	always @(posedge clk) if (tr_on && rst_n && nreset && !phase && en) begin
		if (!nmreq && a[15:2] == tr_addr[15:2]) tr_go = 1;
		if (tr_go) $display("[%0t] bus A=%08h %s%s memory cycle=%b next=%b seq=%b lock=%b nTRANS=%b DO=%08h DI=%08h", $realtime, a,
		                    nrw ? "W" : "R", nwb ? "w" : "b", mreq_now, !nmreq, seq, lock, ntrans, dout, din);
	end

	// bus: one access per two clocks; stores at the end of the cycle. nMREQ is
	// pipelined (ARM60 datasheet: LOW means a memory access in the following
	// cycle), as MADAM's CPU interface uses it. Paused with the core.
	bit mreq_now = 0;
	always @(posedge clk) begin
		if (rst_n && nreset && !phase && en) mreq_now <= !nmreq;
		if (rst_n && nreset && !phase && en && mreq_now && a[31:8] == 24'h0000A0)
			mem[(32'hA100 >> 2) + a[7:2]] <= {31'd0, ntrans};
		if (rst_n && nreset && !phase && en && nrw && mreq_now) begin
			if (nwb) mem[a[15:2]] <= dout;
			else case (a[1:0])                    // big endian: byte 0 is bits 31:24
				2'd0: mem[a[15:2]][31:24] <= dout[31:24];
				2'd1: mem[a[15:2]][23:16] <= dout[23:16];
				2'd2: mem[a[15:2]][15: 8] <= dout[15: 8];
				2'd3: mem[a[15:2]][ 7: 0] <= dout[ 7: 0];
			endcase
			if (a == 32'h0000FFFC) done <= 1;
		end
	end

	initial begin
		int n;
		if (!$value$plusargs("bin=%s", bin)) bin = "build/sim/arm6_isa.bin";
		foreach (mem[i]) mem[i] = 32'hE1A00000;   // MOV r0,r0
		load(bin);
		#22 rst_n = 1;
		#100 nreset = 1;
		fork
			wait (done);
			begin #5ms; $display("tb_arm6: TB ERROR: the program did not finish (PC near %08h)", a); errors++; end
		join_any
		disable fork;
		#100;
		n = mem[32'h7000 >> 2];
		for (int k = 0; k < n; k++) begin
			bit [31:0] got, exp;
			got = mem[(32'h8000 >> 2) + k];
			exp = mem[(32'h7004 >> 2) + k];
			checks++;
			if (got !== exp) begin
				errors++;
				$display("tb_arm6: TB ERROR: result %0d = %08h, expected %08h (see sim/tb/arm6_isa.S)", k, got, exp);
			end
		end
		$display("tb_arm6: %0d EN pauses, %0d clocks paused", pauses, paused_clks);
		if (fiq_on || irq_on) begin
			$display("tb_arm6: FIQs asserted %0d, taken by the program %0d; IRQs asserted %0d, taken %0d",
			         fiq_asserted, mem[32'h9000 >> 2], irq_asserted, mem[32'h9004 >> 2]);
			if (fiq_on && mem[32'h9000 >> 2] < 20) begin errors++; $display("tb_arm6: TB ERROR: too few FIQs taken"); end
			if (irq_on && mem[32'h9004 >> 2] < 20) begin errors++; $display("tb_arm6: TB ERROR: too few IRQs taken"); end
		end
		$display("tb_arm6: %0d results checked, %0d errors", checks, errors);
		// a failure ends with a non-zero exit status ($fatal), so scripts see it
		if (errors == 0 && checks > 0) begin $display("tb_arm6: PASS"); $finish; end
		else $fatal(1, "tb_arm6: FAIL");
	end
endmodule
