// Testbench: the memory bus that ddram.sv takes from MADAM.
// ddram.sv acts on the OE/WE strobes of random VRAM accesses; it takes the
// address and the VRAM RAS of the access's second phase (MADAM_AG LA_COL /
// LRAS0_COL_N, from the generator's address register) and the RAS of the
// previous clk_sys edge from a clk_sys register (3DO.sv), instead of the
// generator's first-phase address path, which is too slow for a clk_mem
// register. This runs the real MADAM (arbiter, CPU interface, address
// generator, DMA) with random CPU bus cycles to VRAM, DRAM, the SPORT space
// and MADAM's DMA registers, random DMA requests and random pauses, into two
// ddram.sv, one wired each way, each on its own DDR model with the same busy
// pattern, and compares every output of the two in every clk_mem cycle.
//
// SPDX-License-Identifier: GPL-3.0-or-later

`timescale 1ns/1ps

module tb_ddrbus;
	import P3DO_PKG::*;

	reg clk_mem = 0, clk_sys = 0;
	always #5 clk_mem = ~clk_mem;
	always @(posedge clk_mem) clk_sys <= ~clk_sys;
	reg rst = 1;

	// ---------------- MADAM and a CPU bus model ----------------
	reg         CLK_DIV = 0, PAUSE = 0;
	wire        CE_R = CLK_DIV & ~PAUSE, CE_F = ~CLK_DIV & ~PAUSE;
	reg  [31:0] a = 0, di = 0;
	reg         nrw = 0, nmreq = 1, nwb = 1;
	wire [31:0] q;
	wire        ph1, ph2;
	reg  [31:0] RAM_DO = 0, RAM_DI = 0;
	reg         dmareq = 0;
	reg  [ 4:0] dmach = 0;
	reg  [ 3:0] BRAM4_OFFS = 4'h0, BRAM2_OFFS = 4'h4, BRAM1_OFFS = 4'h6;
	reg  [ 5:0] pause_rate = 6'd16;

	wire [23:2] LA, RA, LA_COL, RA_COL;
	wire        LRAS0_N, RRAS0_N, LRAS0_COL_N, RRAS0_COL_N, LOE_N, ROE_N;
	wire [ 1:0] LWE_N, RWE_N;

	MADAM dut (
		.CLK(clk_sys), .RST_N(~rst), .EN(1'b1), .CE_R(CE_R), .CE_F(CE_F),
		.A(a), .DI(RAM_DI), .CPU_DI(di), .CPU_DO(q), .nRW(nrw), .nWB(nwb), .nMREQ(nmreq), .SEQ(1'b0), .nOPC(1'b0),
		.nTRANS(1'b1), .LOCK(1'b0), .MCLK_PH1(ph1), .MCLK_PH2(ph2), .VCE(1'b0), .LQSF(1'b0), .RQSF(1'b0),
		.DMAREQ(dmareq), .DMACH(dmach), .CREADY_N(1'b0), .PCSC(1'b0), .MIRQ_N(1'b1), .PBDIN(1'b1), .PDI(32'd0),
		.LA(LA), .LRAS0_N(LRAS0_N), .LWE_N(LWE_N), .LOE_N(LOE_N),
		.RA(RA), .RRAS0_N(RRAS0_N), .RWE_N(RWE_N), .ROE_N(ROE_N),
		.LA_COL(LA_COL), .LRAS0_COL_N(LRAS0_COL_N), .RA_COL(RA_COL), .RRAS0_COL_N(RRAS0_COL_N),
		.DBG_SPR_EN(1'b1), .DBG_EXT(8'd0)
	);

	always @(posedge clk_sys) begin
		CLK_DIV <= ~CLK_DIV;
		if (CLK_DIV) PAUSE <= !rst && pause_rate != 0 && ($urandom() % pause_rate) == 0;   // PAUSE changes with the CE_F cycle, as in 3DO.sv
		RAM_DO <= $urandom();
		RAM_DI <= $urandom();
	end

	// a CPU bus cycle: the address (and data) with nMREQ, held to MCLK phase 2
	task automatic cpu(input [31:0] addr, input bit wr, input bit byt, input [31:0] d);
		int to;
		@(negedge clk_sys); a = addr; di = d; nrw = wr; nwb = ~byt; nmreq = 0;
		to = 0;
		do begin @(posedge clk_sys); to++; end while (!ph2 && to < 4000);
		#1; nrw = 0; nmreq = 1; nwb = 1;
		repeat ($urandom() % 6) @(posedge clk_sys);
	endtask
	function automatic [31:0] vram_addr();
		// mostly a few 128-word blocks, so that reads hit ddram.sv's block as well
		return {12'h002, 4'($urandom() % 3 == 0 ? $urandom() : 4'h1), 2'($urandom()), 5'($urandom() % 4 == 0 ? $urandom() : 5'h03), 7'($urandom()), 2'($urandom())};
	endfunction

	int n_cpu = 0, n_sport = 0, n_dma = 0;
	initial begin
		int n;
		if (!$value$plusargs("accesses=%d", n)) n = 300000;
		repeat (9000) @(posedge clk_mem);
		rst = 0;
		repeat (40) @(posedge clk_sys);
		for (int i = 0; i < n; i++) begin
			int k;
			if (i % 20000 == 0) pause_rate = 6'($urandom() % 3 == 0 ? 0 : 4 + $urandom() % 40);
			k = $urandom() % 32;
			if (k < 14)       begin cpu(vram_addr(), $urandom() % 2, $urandom() % 4 == 0, $urandom()); n_cpu++; end
			else if (k < 17)  cpu({12'h000, 20'($urandom())}, $urandom() % 2, 0, $urandom());                       // DRAM
			else if (k < 23)  begin cpu({12'h032, 3'b000, 3'($urandom()), 14'($urandom() << 2)}, $urandom() % 2, 0, $urandom()); n_sport++; end   // SPORT space
			else if (k < 28)  cpu(32'h03300400 + ($urandom() % 128) * 4, 1, 0, vram_addr() & 32'h00FFFFFC);        // DMA registers: VRAM addresses and lengths
			else if (k < 30)  cpu(32'h03300400 + ($urandom() % 128) * 4, 0, 0, 0);
			else begin
				// a DMA request (CLIO's), on a channel whose registers hold VRAM addresses
				@(negedge clk_sys); dmach = 5'($urandom()); dmareq = 1;
				repeat (2 + $urandom() % 8) @(posedge clk_sys);
				@(negedge clk_sys); dmareq = 0;
				repeat (30 + $urandom() % 60) @(posedge clk_sys);
				n_dma++;
			end
		end
		done = 1;
	end
	bit done = 0;

	// ---------------- the two wirings ----------------
	reg  [15:0] k0, k1;
	always @(posedge clk_sys) begin
		for (int b = 0; b < 16; b++) begin
			bit full;
			full = (b >= BRAM4_OFFS && b <= BRAM4_OFFS + 3) || (b >= BRAM2_OFFS && b <= BRAM2_OFFS + 1);
			k0[b] <= full || (b == BRAM1_OFFS);
			k1[b] <= full || (b == 15);
		end
	end
	function automatic bit luse(input [23:2] a);
		return ~(&a[15:14] ? k1[a[19:16]] : k0[a[19:16]]);
	endfunction

	// as it was: the bus itself, and the RAS of the clk_mem cycle before
	wire        a_luse = luse(LA), a_ruse = luse(RA);
	reg         a_lras_d = 0, a_rras_d = 0;
	always @(posedge clk_mem) begin a_lras_d <= !LRAS0_N; a_rras_d <= !RRAS0_N; end
	// as 3DO.sv wires it now
	wire        b_luse = luse(LA_COL), b_ruse = luse(RA_COL);
	reg         b_lras_d = 0, b_rras_d = 0;
	always @(posedge clk_sys) begin b_lras_d <= !LRAS0_N; b_rras_d <= !RRAS0_N; end

	// the DDR interface's busy pattern, the same for both
	reg         ddr_busy = 0;
	int         busy_left = 0;
	wire        a_rd_act, b_rd_act;
	always @(posedge clk_mem) begin
		if (busy_left != 0) begin
			busy_left--;
			if (busy_left == 0) ddr_busy <= 0;
		end else if (!a_rd_act && !b_rd_act && !rst && ($urandom() % 24) == 0) begin
			ddr_busy <= 1;
			busy_left = 1 + ($urandom() % 6);
		end
	end

	wire [15:0] a_ldout, a_rdout, b_ldout, b_rdout;
	wire        a_busy, b_busy;
	wire [ 7:0] a_cnt, a_be, b_cnt, b_be;
	wire [28:0] a_addr, b_addr;
	wire [63:0] a_din, b_din, a_q, b_q;
	wire        a_rd, a_we, b_rd, b_we, a_qv, b_qv;

	ddram ddram_a (
		.DDRAM_CLK(), .DDRAM_BUSY(ddr_busy), .DDRAM_BURSTCNT(a_cnt), .DDRAM_ADDR(a_addr), .DDRAM_DOUT(a_q), .DDRAM_DOUT_READY(a_qv),
		.DDRAM_RD(a_rd), .DDRAM_DIN(a_din), .DDRAM_BE(a_be), .DDRAM_WE(a_we),
		.clk(clk_mem), .rst(rst),
		.io_addr('0), .io_din('0), .io_we('0), .io_rd(1'b0), .io_dout(), .io_busy(),
		.nvram_addr('0), .nvram_din('0), .nvram_wr(1'b0), .nvram_rd(1'b0), .nvram_dout(), .nvram_busy(), .sclk(1'b0),
		.laddr(LA[19:2]), .ldin(RAM_DO[31:16]), .lras(!LRAS0_N), .lras_d(a_lras_d), .lwe(a_luse ? ~LWE_N : 2'b00), .lrd(a_luse ? ~LOE_N : 1'b0), .ldout(a_ldout),
		.raddr(RA[19:2]), .rdin(RAM_DO[15:0]), .rras(!RRAS0_N), .rras_d(a_rras_d), .rwe(a_ruse ? ~RWE_N : 2'b00), .rrd(a_ruse ? ~ROE_N : 1'b0), .rdout(a_rdout),
		.busy(a_busy),
		.bladdr('0), .blwr(1'b0), .blrd(1'b0), .braddr('0), .brwr(1'b0), .brrd(1'b0), .bfw(1'b0), .ba(), .bin('0), .bout(), .blte(), .brte(), .bbusy()
	);
	ddram ddram_b (
		.DDRAM_CLK(), .DDRAM_BUSY(ddr_busy), .DDRAM_BURSTCNT(b_cnt), .DDRAM_ADDR(b_addr), .DDRAM_DOUT(b_q), .DDRAM_DOUT_READY(b_qv),
		.DDRAM_RD(b_rd), .DDRAM_DIN(b_din), .DDRAM_BE(b_be), .DDRAM_WE(b_we),
		.clk(clk_mem), .rst(rst),
		.io_addr('0), .io_din('0), .io_we('0), .io_rd(1'b0), .io_dout(), .io_busy(),
		.nvram_addr('0), .nvram_din('0), .nvram_wr(1'b0), .nvram_rd(1'b0), .nvram_dout(), .nvram_busy(), .sclk(1'b0),
		.laddr(LA_COL[19:2]), .ldin(RAM_DO[31:16]), .lras(!LRAS0_COL_N), .lras_d(b_lras_d), .lwe(b_luse ? ~LWE_N : 2'b00), .lrd(b_luse ? ~LOE_N : 1'b0), .ldout(b_ldout),
		.raddr(RA_COL[19:2]), .rdin(RAM_DO[15:0]), .rras(!RRAS0_COL_N), .rras_d(b_rras_d), .rwe(b_ruse ? ~RWE_N : 2'b00), .rrd(b_ruse ? ~ROE_N : 1'b0), .rdout(b_rdout),
		.busy(b_busy),
		.bladdr('0), .blwr(1'b0), .blrd(1'b0), .braddr('0), .brwr(1'b0), .brrd(1'b0), .bfw(1'b0), .ba(), .bin('0), .bout(), .blte(), .brte(), .bbusy()
	);

	// DDR models (as tb_vram's), one each
	ddr_model m_a (.clk(clk_mem), .busy(ddr_busy), .cnt(a_cnt), .addr(a_addr), .din(a_din), .be(a_be), .we(a_we), .rd(a_rd), .q(a_q), .qv(a_qv), .rd_act(a_rd_act));
	ddr_model m_b (.clk(clk_mem), .busy(ddr_busy), .cnt(b_cnt), .addr(b_addr), .din(b_din), .be(b_be), .we(b_we), .rd(b_rd), .q(b_q), .qv(b_qv), .rd_act(b_rd_act));

	// ---------------- comparison ----------------
	int errors = 0, cycles = 0;
	int n_wr = 0, n_rd = 0, n_busy = 0, n_wr_dma = 0, n_rd_dma = 0, n_trig_p1 = 0;
	always @(posedge clk_mem) if (!rst) begin
		cycles++;
		if (a_we && !ddr_busy) n_wr++;
		if (a_rd && !ddr_busy) n_rd++;
		if (a_busy) n_busy++;
		if (!dut.CPU_GRANT && ddram_a.write_lpend) n_wr_dma++;
		if (!dut.CPU_GRANT && ddram_a.read_lbusy) n_rd_dma++;
		if ({a_we, a_rd, a_busy} !== {b_we, b_rd, b_busy} ||
		    ((a_we || a_rd) && {a_addr, a_cnt} !== {b_addr, b_cnt}) ||
		    (a_we && {a_din, a_be} !== {b_din, b_be}) ||
		    a_ldout !== b_ldout || a_rdout !== b_rdout) begin
			errors++;
			if (errors < 12)
				$display("[%0t] MISMATCH: we %b/%b rd %b/%b busy %b/%b addr %h/%h din %h/%h be %h/%h ldout %h/%h rdout %h/%h (PHASE1 %b, CPU grant %b, bus state %0d, CPU address %h, LA %h LA_COL %h, RAS %b/%b)",
				         $realtime, a_we, b_we, a_rd, b_rd, a_busy, b_busy, a_addr, b_addr, a_din, b_din, a_be, b_be, a_ldout, b_ldout, a_rdout, b_rdout,
				         dut.PHASE1, dut.CPU_GRANT, dut.BUS_STATE, a, {LA, 2'b00}, {LA_COL, 2'b00}, !LRAS0_N, !LRAS0_COL_N);
		end
	end

	initial begin
		wait (done);
		repeat (2000) @(posedge clk_mem);
		$display("tb_ddrbus: %0d clk_mem cycles; %0d CPU VRAM accesses, %0d SPORT accesses, %0d DMA requests; %0d DDR writes, %0d DDR reads, busy %0d cycles; ddram accesses latched without the CPU's grant: %0d writes, %0d reads; %0d mismatches",
		         cycles, n_cpu, n_sport, n_dma, n_wr, n_rd, n_busy, n_wr_dma, n_rd_dma, errors);
		if (n_wr < 1000 || n_rd < 1000) begin $display("tb_ddrbus: too little traffic"); errors++; end
		if (errors == 0) begin $display("tb_ddrbus: PASS"); $finish; end
		else $fatal(1, "tb_ddrbus: FAIL");
	end
	initial begin
		#20s;
		$fatal(1, "tb_ddrbus: TIMEOUT");
	end
endmodule

// The MiSTer DDRAM interface (see tb_vram.sv), busy from outside
module ddr_model (
	input             clk,
	input             busy,
	input      [ 7:0] cnt,
	input      [28:0] addr,
	input      [63:0] din,
	input      [ 7:0] be,
	input             we,
	input             rd,
	output reg [63:0] q,
	output reg        qv,
	output            rd_act
);
	bit [63:0] mem [bit [28:0]];
	int        wleft = 0, rleft = 0, rlat = 0;
	bit [28:0] wa, ra;
	assign rd_act = (rleft != 0) || qv || (rd && !busy);
	initial begin q = '0; qv = 0; end
	always @(posedge clk) begin
		qv <= 0;
		if (!busy && we) begin
			bit [28:0] a;
			bit [63:0] d;
			if (wleft == 0) begin a = addr; wleft = cnt; end
			else a = wa;
			d = mem.exists(a) ? mem[a] : 64'h0;
			for (int b = 0; b < 8; b++) if (be[b]) d[b*8 +: 8] = din[b*8 +: 8];
			mem[a] = d;
			wa = a + 29'd1;
			wleft--;
		end
		else if (!busy && rd && rleft == 0) begin
			ra = addr;
			rleft = cnt;
			rlat = 6;
		end
		if (rleft != 0) begin
			if (rlat != 0) rlat--;
			else begin
				q <= mem.exists(ra) ? mem[ra] : 64'h0;
				qv <= 1;
				ra = ra + 29'd1;
				rleft--;
			end
		end
	end
endmodule
