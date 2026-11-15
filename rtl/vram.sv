module P3DO_VRAM #(parameter USE_BRAM = 0) (
	input          CLK,
	input          CLK_MEM,
	input          RST_N,
	
	input  [17: 0] A,
	input  [15: 0] D,
	output [15: 0] Q,
	input          RAS_N,
	input          CAS_N,
	input  [ 1: 0] WE_N,
	input          OE_N,
	input          DSF1,
	output bit     RDY,
	
	input          SC,
	input          SE_N,
	output bit [15: 0] SQ,
	output         QSF,
	
	input  [15: 0] EQ,
	output [17: 0] ESADDR,
	output [31: 0] ESDATA,
	output         ESWR,
	output         ESRD,
	output         ESFW,
	input  [31: 0] ESQ,
	input          ESTE,
	
	input  [ 3: 0] BRAM4_OFFS,
	input  [ 3: 0] BRAM2_OFFS,
	input  [ 3: 0] BRAM1_OFFS,

	input          SP_CPU,      // Game Bub port: the access is the CPU's (MADAM SPORT space)
	// Game Bub port: the other VRAM half (write masks). DP: its data bus;
	// PEER_BUSY: its transfer in progress; XBUSY: this half's.
	input  [15: 0] DP,
	input          PEER_BUSY,
	output         XBUSY,

	output bit [ 7: 0] DBG_WAIT_CNT
);

	bit  [17: 0] A_FF;
	bit  [15: 0] D_FF;
	
	// On-chip windows: BRAM4 blocks OFFS..OFFS+3, BRAM2 OFFS..OFFS+1, BRAM1
	// OFFS up to xBFFF, and FC000-FFFFF (BRAM1 too). They are whole 64 KiB
	// blocks but for BRAM1's quarters, so each is a 16-bit map of the block
	// (address [17:14]), kept in registers (the offsets are static): the
	// address only selects a bit (it went through adders and 18-bit compares,
	// on MADAM's address timing path).
	bit  [15: 0] MAP4, MAP2, MAP1;
	always @(posedge CLK_MEM) begin
		for (int b=0; b<16; b++) begin
			MAP4[b] <= USE_BRAM && b >= BRAM4_OFFS && b <= BRAM4_OFFS + 3;
			MAP2[b] <= USE_BRAM && b >= BRAM2_OFFS && b <= BRAM2_OFFS + 1;
			MAP1[b] <= (b == BRAM1_OFFS);
		end
	end
	function automatic bit in_ram1(input [15:0] map1, input [5:0] a);
		return (map1[a[5:2]] && a[1:0] != 2'b11) || (&a);
	endfunction
	wire         USE_INT_RAM4 = MAP4[A[17:14]];
	wire         USE_INT_RAM2 = MAP2[A[17:14]];
	wire         USE_INT_RAM1 = in_ram1(MAP1, A[17:12]);

//	bit  [15: 0] MASK;
	bit  [15: 0] COLOR;
	
	bit  [ 8: 0] SR_WA;
	bit  [31: 0] SR_WD;
	bit          SR_WE;
	bit  [ 8: 0] SR_RA;
	bit [255: 0] SR_Q;
	bit [255: 0] SC_Q;      //CPU shift register output (Game Bub port)

	bit  [ 8: 0] MEM_ROW;
	bit  [ 8: 0] MEM_COL;
	bit  [ 8: 0] SREG_POS;
	bit          RT_REQ;
	bit          RT_EXEC;	//read transfer
	bit          MWT_EXEC;	//masked write transfer
	bit          FW_EXEC;	//flash write
//	bit          SIM;			//serial input mode
	bit          SOM;			//serial output mode
	bit          SPLIT;		//serial split transfer mode
	bit          ISTE;
	// Game Bub port: the CPU's SPORT transfers (a page copy is a read
	// transfer, then a write transfer, as two CPU accesses) use a shift
	// register of their own. On real hardware the OS copies pages during
	// vertical blanking, when no video or CLUT/VDL transfer uses the shift
	// register. Here VRAM is mostly in SDRAM, a page copy takes ~30 us and
	// a frame's copies run on into the picture: a video or VDL transfer
	// between a copy's read and write transfer reloaded the shared shift
	// register and the write transfer stored that data (OS VDL words in a
	// game's background). With two registers the copy keeps the source row
	// however long it takes, and the CPU's transfers leave the video shift
	// register, its tap and serial mode alone.
	// A split read transfer of the half-row the video shift register already
	// holds is skipped (as in the MiSTer core). A copy into that row
	// invalidates the tag, so the next one reloads the copied data (with one
	// shared register, the copy had left it there).
	bit          PEND_CPU;   //the pending transfer is the CPU's
	bit          XFER_CPU;   //the transfer in progress is the CPU's
	bit  [ 9: 0] VSR_TAG;    //row and half the video shift register holds
	bit          VSR_V;      //VSR_TAG is valid: a split transfer to it is skipped
	bit          SR_WCPU;    //SR_WE writes the CPU shift register
	// Game Bub port: write-per-bit masks. A write transfer or flash write
	// takes a mask from the data bus (MADAM: the CPU's write data to the
	// SPORT address; VRAM latches it as RAS falls, the core has it on the
	// bus from CAS: see XWAIT below); a 1 bit is written, a 0 bit keeps the
	// row's bit (US patent 5,502,462). The original ignored the mask (MASK was
	// commented out), so a copy or flash write with a partial or zero mask
	// overwrote the protected bits. Mask FFFF: as before. Mask 0000: no
	// write. Otherwise the new data is merged with the row's: on-chip VRAM
	// by a read and a write of each 16-column block (WR_PH); VRAM outside
	// (SDRAM / SRAM through ddram.sv) by first reading the destination row
	// into a third shift register (MRD_EXEC, an ordinary read transfer
	// through the cache) and then writing it with the merged data. Flash
	// writes outside: ddram.sv's lazy flash fill (ESFW, the left half's only)
	// sets the row's flag and colour for both halves at once and has no
	// per-bit mask, so it is used only when both halves have mask FFFF and
	// take the command together (as before); otherwise each half writes its
	// colour into the row itself (FWM: a write burst, merged as above when
	// its mask is partial).
	bit  [15: 0] MASK;
	bit  [15: 0] MASKP;      //the other half's mask
	bit  [15: 0] DP_FF;
	bit          RAS_SYNC;   //both halves were idle when the command's RAS fell
	bit          MASKED;     //the write in progress has a partial mask
	bit          FWM;        //the masked write in progress is a flash write (new data: COLOR)
	bit          MRD_EXEC;   //reading the destination row for a masked write outside
	// An on-chip write of a 16-column block takes two clocks, a masked one
	// three: [read the block,] register the data to write (MEM_SDATA_R), write
	// it. The write enables are registers too. (It was one clock, two masked,
	// with the shift register read, the merge and 3-4 ns of routing to the
	// block RAMs in it.)
	bit  [ 1: 0] WR_PH;
	wire [ 1: 0] WR_PH_LAST = MASKED ? 2'd2 : 2'd1;
	wire         WR_STEP = (WR_PH == WR_PH_LAST);
	bit          SR_WSCR;    //SR_WE writes the scratch shift register (MRD)
	// the access's row is on chip, from the address registered a clock before
	// (A_FF; the address is stable while RAS is low): keeps MADAM's address
	// bus (clk_sys) out of the transfer state's clk_mem paths
	wire         INT_NOW = MAP4[A_FF[17:14]] | MAP2[A_FF[17:14]] | in_ram1(MAP1, A_FF[17:12]);
	always @(posedge CLK_MEM or negedge RST_N) begin
		bit        RAS_N_OLD,SC_OLD;
		bit        RDY_OLD;
		bit        RT_PEND,MWT_PEND,FW_PEND;
		bit        XWAIT,XGO;
		bit  [1:0] XKIND;
		bit  [1:0] WE_N_OLD_M;
		
		if (!RST_N) begin
			{RT_PEND,MWT_PEND,FW_PEND,XWAIT,XGO,XKIND} <= '0;
			{MASK,MASKP,DP_FF,RAS_SYNC,MASKED,FWM,MRD_EXEC,WR_PH,SR_WSCR} <= '0;
			WE_N_OLD_M <= 2'b11;
			RDY <= 1;
			MEM_ROW <= '0;
			MEM_COL <= '0;
			RT_REQ <= 0;
			{RT_EXEC,MWT_EXEC,FW_EXEC} <= '0;
//			SIM <= 0;
			SOM <= 0;
			SPLIT <= 0;
			SREG_POS <= '0;
			SR_WA <= '0;
			SR_WE <= 0;
			SR_RA <= '0;
			ISTE <= 0;
			{PEND_CPU,XFER_CPU,SR_WCPU} <= '0;
			VSR_TAG <= '0;
			VSR_V <= 0;
		end else begin
			RT_REQ <= 0;
			
			A_FF <= A;
			D_FF <= D;
			DP_FF <= DP;
			RAS_N_OLD <= RAS_N;
			RDY_OLD <= RDY;
			WE_N_OLD_M <= WE_N;
			// Game Bub port: a random write into the half-row the video shift
			// register holds changes it: the next split transfer of that half
			// must reload it (the skip below assumed it unchanged)
			if (!RAS_N && !RAS_N_OLD && WE_N != 2'b11 && WE_N_OLD_M == 2'b11 && A[17:8] == VSR_TAG) VSR_V <= 0;
			if (!RAS_N && RAS_N_OLD) RAS_SYNC <= !XBUSY && !PEER_BUSY;
			if ((!RAS_N && RAS_N_OLD) || (RDY && !RDY_OLD)) begin
				if (RT_EXEC || MWT_EXEC || FW_EXEC || MRD_EXEC) begin
					if (!OE_N || !WE_N || DSF1 || !(USE_INT_RAM4 || USE_INT_RAM2 || USE_INT_RAM1)) RDY <= 0;
				end else if (!OE_N && WE_N) begin
					RT_PEND <= 1;
					PEND_CPU <= SP_CPU;
				end else if (!OE_N && !WE_N /*&& !DSF1*/) begin
					MWT_PEND <= 1;
					PEND_CPU <= SP_CPU;
				end else if (OE_N && !WE_N /*&& DSF1*/) begin
					FW_PEND <= 1;
				end else if (OE_N && WE_N) begin
					if (DSF1) begin
						XWAIT <= 1;              //colour load: the colour comes with CAS
						XKIND <= 2'd2;
					end
				end
			end 
			else if (!RDY && !RT_EXEC && !MWT_EXEC && !FW_EXEC && !MRD_EXEC) begin
				RDY <= 1;
			end
			
			if (RT_PEND) begin
				RT_PEND <= 0;
				if (PEND_CPU || !VSR_V || VSR_TAG != A_FF[17:8] || !DSF1) begin
					{MEM_ROW,MEM_COL} <= A_FF[17:0];
					RT_EXEC <= 1;
					RT_REQ <= 1;
					XFER_CPU <= PEND_CPU;
//					SIM <= 0;
					if (!PEND_CPU) begin
						VSR_TAG <= A_FF[17:8];
						VSR_V <= 1;
						SOM <= 1;
					end
					SPLIT <= DSF1;
					SREG_POS <= {A_FF[8:1],1'b0};
					ISTE <= INT_NOW;
				end
				if (!DSF1 && !PEND_CPU) SR_RA <= A_FF[8:0];
			end else if (MWT_PEND) begin
				MWT_PEND <= 0;
				MEM_ROW <= A_FF[17:9];
//				MEM_COL <= A_FF[8:0];
				XFER_CPU <= PEND_CPU;
//				SIM <= 1;
				SPLIT <= DSF1;
				SREG_POS <= '0;
				XWAIT <= 1;                      //the mask comes with CAS
				XKIND <= 2'd0;
			end else if (FW_PEND) begin
				FW_PEND <= 0;
				MEM_ROW <= A_FF[17:9];
//				MEM_COL <= A_FF[8:0];
				SPLIT <= 0;
				SREG_POS <= '0;
				if (DSF1) begin
					XWAIT <= 1;                  //the mask comes with CAS
					XKIND <= 2'd1;
				end
			end
			
			// Game Bub port: a write transfer, flash write or colour load
			// takes its data (mask, colour) from the data bus once CAS is
			// low: the core puts the CPU's write data on the bus from PHASE2
			// of the access (P3DO.sv CPU_DO_FF, MADAM_AG.sv: CAS in PHASE2 of
			// every SPORT access), not yet when RAS falls. Level, not edge:
			// a command taken late (RAS fell while this half was busy, RDY
			// held the 3DO) may find CAS low already. No CAS before RAS
			// rises: nothing happens (MADAM always gives one).
			if (XWAIT && !CAS_N) begin
				XWAIT <= 0;
				XGO <= 1;
			end else if (XWAIT && RAS_N) begin
				XWAIT <= 0;
			end
			if (XGO) begin
				XGO <= 0;
				case (XKIND)
					2'd0: begin   // write transfer
						MASK <= D_FF;
						MASKED <= D_FF != 16'hFFFF;
						FWM <= 0;
						WR_PH <= '0;
						if (D_FF != 16'h0000) begin   //mask 0000: nothing is written
							if (D_FF == 16'hFFFF || INT_NOW) begin
								MWT_EXEC <= !SE_N;
							end else begin
								MRD_EXEC <= !SE_N;      //masked, outside: read the destination row first
								RT_REQ <= !SE_N;
							end
							if (!XFER_CPU) begin
								// the video shift register now holds the row, unless
								// a partial mask kept some of the row's bits
								if (D_FF == 16'hFFFF) VSR_TAG <= {MEM_ROW,VSR_TAG[0]};
								else VSR_V <= 0;
								SOM <= 0;
							end else if (MEM_ROW == VSR_TAG[9:1]) begin
								VSR_V <= 0;   //a copy into the row the video shift register holds: reload it
							end
							ISTE <= INT_NOW;
						end
					end
					2'd1: begin   // flash write
						MASK <= D_FF;
						MASKP <= DP_FF;
						if (D_FF != 16'h0000) begin   //mask 0000: nothing is written
							MASKED <= D_FF != 16'hFFFF;
							WR_PH <= '0;
							ISTE <= INT_NOW;
							// XFER_CPU: the video shift register's read address stays
							// at its tap during the write (SR_RADDR)
							XFER_CPU <= 1;
							if (INT_NOW || (D_FF == 16'hFFFF && DP_FF == 16'hFFFF && RAS_SYNC)) begin
								FW_EXEC <= 1;            //on-chip, or both halves' lazy flash fill
								FWM <= 0;
							end else if (D_FF == 16'hFFFF) begin
								MWT_EXEC <= 1;           //this half's colour into the whole row
								FWM <= 1;
							end else begin
								MRD_EXEC <= 1;           //masked: read the row, then write it merged
								RT_REQ <= 1;
								FWM <= 1;
							end
							if (MEM_ROW == VSR_TAG[9:1]) VSR_V <= 0;   //the held row changes: reload it
						end
					end
					default: COLOR <= D_FF;   // colour load
				endcase
			end

			SC_OLD <= SC;
			if (!SC && SC_OLD && SOM) begin
				SR_RA <= SR_RA + 9'h1;
				case (SR_RA[0])
					1'b0: SQ <= SR_DATA[31:16];
					1'b1: SQ <= SR_DATA[15: 0];
				endcase
			end
			
			if (RT_EXEC || MWT_EXEC || FW_EXEC || MRD_EXEC) DBG_WAIT_CNT <= DBG_WAIT_CNT + 1'd1;
			
			// on-chip writes: the clocks of a block (see WR_PH)
			if ((MWT_EXEC || FW_EXEC) && ISTE) WR_PH <= WR_STEP ? 2'd0 : WR_PH + 2'd1;

			SR_WE <= 0;
			if (FW_EXEC) begin
				if (!ISTE || WR_STEP) begin
					SREG_POS <= SREG_POS + (ISTE ? 9'h10 : 9'h20);
					if ((SREG_POS[8:5] == 4'hF && !ISTE) || (SREG_POS[8:4] == 5'h1F && ISTE)) begin
						FW_EXEC <= 0;
						ISTE <= 0;
					end
				end
			end else if ((RT_EXEC || MWT_EXEC || MRD_EXEC) && (ESTE || (ISTE && (!MWT_EXEC || WR_STEP)))) begin
				SR_WA <= SREG_POS;
				SR_WD <= ESQ;
				SR_WE <= RT_EXEC || MRD_EXEC;
				SR_WCPU <= XFER_CPU;
				SR_WSCR <= MRD_EXEC;
				
				SREG_POS <= SREG_POS + (ISTE ? 9'h10 : 9'h2);
				if (((SREG_POS[7:0] == 8'hFE && ESTE) || (SREG_POS[7:4] == 4'hF && ISTE)) && SPLIT) begin
					RT_EXEC <= 0;
					ISTE <= 0;
				end
				if (((SREG_POS[8:0] == 9'h0FE && ESTE) || (SREG_POS[8:4] == 5'h0F && ISTE)) && !SPLIT) begin
					if (RT_EXEC || MRD_EXEC) RT_REQ <= 1;
				end
				if (((SREG_POS[8:0] == 9'h1FE && ESTE) || (SREG_POS[8:4] == 5'h1F && ISTE)) && !SPLIT) begin
					RT_EXEC <= 0;
					MWT_EXEC <= 0;
					ISTE <= 0;
					if (MRD_EXEC) begin
						MRD_EXEC <= 0;           //destination row read: now write it, merged
						MWT_EXEC <= 1;
					end
				end
				
				DBG_WAIT_CNT <= '0;
			end
		end
	end
	
	bit        RAS_N_OLD,WE_N_OLD;
	always @(posedge CLK) begin
		RAS_N_OLD <= RAS_N;
		WE_N_OLD <= &WE_N;
	end
	
	// the same windows as USE_INT_RAM*, for the transfer address
	wire         MEM4_SSEL = MAP4[ESADDR[17:14]];
	wire         MEM2_SSEL = MAP2[ESADDR[17:14]];
	wire         MEM1_SSEL = in_ram1(MAP1, ESADDR[17:12]);
	
	wire [15: 4] MEM_SWADDR = ESADDR[15:4];
	wire[255: 0] MWT_Q = XFER_CPU ? SC_Q : SR_Q;   // write transfer source (Game Bub port)
	wire[255: 0] MEM_SDATA_NEW = FW_EXEC ? {16{COLOR}} : {MWT_Q[239:224],MWT_Q[255:240],MWT_Q[207:192],MWT_Q[223:208],MWT_Q[175:160],MWT_Q[191:176],MWT_Q[143:128],MWT_Q[159:144],MWT_Q[111:96],MWT_Q[127:112],MWT_Q[79:64],MWT_Q[95:80],MWT_Q[47:32],MWT_Q[63:48],MWT_Q[15:0],MWT_Q[31:16]};//SR_Q;
	// on-chip masked write: the block read in the cycle before, merged
	wire[255: 0] MEM_SQ_RAW = MEM4_SQ_SEL ? MEM4_SQ : MEM2_SQ_SEL ? MEM2_SQ : MEM1_SQ;
	wire[255: 0] MEM_SDATA = MASKED ? (MEM_SDATA_NEW & {16{MASK}}) | (MEM_SQ_RAW & ~{16{MASK}}) : MEM_SDATA_NEW;
	wire         MEM_SWR = (MWT_EXEC | FW_EXEC) & ISTE & WR_STEP;   //the block's write clock
	// the data and the write enables, registered in the clock before it
	bit [255: 0] MEM_SDATA_R;
	bit          MEM4_SWREN,MEM2_SWREN,MEM1_SWREN;
	wire         MEM_SWR_NEXT = (MWT_EXEC | FW_EXEC) & ISTE & (WR_PH + 2'd1 == WR_PH_LAST);
	always @(posedge CLK_MEM) begin
		MEM_SDATA_R <= MEM_SDATA;
		MEM4_SWREN <= MEM_SWR_NEXT & MEM4_SSEL;
		MEM2_SWREN <= MEM_SWR_NEXT & MEM2_SSEL;
		MEM1_SWREN <= MEM_SWR_NEXT & MEM1_SSEL;
	end
	
	bit  [15: 0] MEM4_Q;
	bit [255: 0] MEM4_SQ;
	VRAM_MEM #(16) mem4
	(
		.CLK(CLK),
		.ADDR(A[15:0]),
		.DATA(D),
		.WREN(~WE_N & {2{~RAS_N&~RAS_N_OLD&WE_N_OLD&USE_INT_RAM4}}),
		.Q(MEM4_Q),
		
		.SCLK(CLK_MEM),
		.SADDR(MEM_SWADDR[15:4]),
		.SDATA(MEM_SDATA_R),
		.SWREN(MEM4_SWREN),
		.SQ(MEM4_SQ)
	);
	
	bit  [15: 0] MEM2_Q;
	bit [255: 0] MEM2_SQ;
	VRAM_MEM #(15) mem2
	(
		.CLK(CLK),
		.ADDR(A[14:0]),
		.DATA(D),
		.WREN(~WE_N & {2{~RAS_N&~RAS_N_OLD&WE_N_OLD&USE_INT_RAM2}}),
		.Q(MEM2_Q),
		
		.SCLK(CLK_MEM),
		.SADDR(MEM_SWADDR[14:4]),
		.SDATA(MEM_SDATA_R),
		.SWREN(MEM2_SWREN),
		.SQ(MEM2_SQ)
	);
	
	bit  [15: 0] MEM1_Q;
	bit [255: 0] MEM1_SQ;
	VRAM_MEM #(14) mem1
	(
		.CLK(CLK),
		.ADDR(A[13:0]),
		.DATA(D),
		.WREN(~WE_N & {2{~RAS_N&~RAS_N_OLD&WE_N_OLD&USE_INT_RAM1}}),
		.Q(MEM1_Q),
		
		.SCLK(CLK_MEM),
		.SADDR(MEM_SWADDR[13:4]),
		.SDATA(MEM_SDATA_R),
		.SWREN(MEM1_SWREN),
		.SQ(MEM1_SQ)
	);
	assign Q = USE_INT_RAM4 ? MEM4_Q : USE_INT_RAM2 ? MEM2_Q : USE_INT_RAM1 ? MEM1_Q : EQ;

	bit          ISTE_DELAYED;
	bit          MEM4_SQ_SEL,MEM2_SQ_SEL;
	always @(posedge CLK_MEM) begin
		ISTE_DELAYED <= ISTE;
		MEM4_SQ_SEL <= MEM4_SSEL;
		MEM2_SQ_SEL <= MEM2_SSEL;
	end
	
	// video shift register: serial output at the tap; a write transfer that
	// is not the CPU's (none in MADAM) reads it as before
	wire [ 8: 1] SR_RADDR = MWT_EXEC && !XFER_CPU ? SREG_POS[8:1] : SR_RA[8:1];
	wire[255: 0] MEM_SQ = MEM4_SQ_SEL ? {MEM4_SQ[239:224],MEM4_SQ[255:240],MEM4_SQ[207:192],MEM4_SQ[223:208],MEM4_SQ[175:160],MEM4_SQ[191:176],MEM4_SQ[143:128],MEM4_SQ[159:144],MEM4_SQ[111:96],MEM4_SQ[127:112],MEM4_SQ[79:64],MEM4_SQ[95:80],MEM4_SQ[47:32],MEM4_SQ[63:48],MEM4_SQ[15:0],MEM4_SQ[31:16]} :
	                      MEM2_SQ_SEL ? {MEM2_SQ[239:224],MEM2_SQ[255:240],MEM2_SQ[207:192],MEM2_SQ[223:208],MEM2_SQ[175:160],MEM2_SQ[191:176],MEM2_SQ[143:128],MEM2_SQ[159:144],MEM2_SQ[111:96],MEM2_SQ[127:112],MEM2_SQ[79:64],MEM2_SQ[95:80],MEM2_SQ[47:32],MEM2_SQ[63:48],MEM2_SQ[15:0],MEM2_SQ[31:16]} :
	                                    {MEM1_SQ[239:224],MEM1_SQ[255:240],MEM1_SQ[207:192],MEM1_SQ[223:208],MEM1_SQ[175:160],MEM1_SQ[191:176],MEM1_SQ[143:128],MEM1_SQ[159:144],MEM1_SQ[111:96],MEM1_SQ[127:112],MEM1_SQ[79:64],MEM1_SQ[95:80],MEM1_SQ[47:32],MEM1_SQ[63:48],MEM1_SQ[15:0],MEM1_SQ[31:16]};
	// A block read from on-chip VRAM goes through a register (MEM_SQ_R) into
	// the shift registers, a clock after the RAM gives it (it went from the
	// block RAM's output through the window select straight into the shift
	// register's write port, with 3-4 ns of routing). SR_WE2 and the others
	// are that write's controls; a transfer from outside writes as before.
	bit [255: 0] MEM_SQ_R;
	bit          SR_WE2,SR_WCPU2;
	bit  [ 8: 4] SR_WA2;
	always @(posedge CLK_MEM) begin
		MEM_SQ_R <= MEM_SQ;
		SR_WE2 <= SR_WE & ISTE_DELAYED;
		SR_WCPU2 <= SR_WCPU;
		SR_WA2 <= SR_WA[8:4];
	end
	wire [ 8: 4] SR_WADDR = SR_WE2 ? SR_WA2 : SR_WA[8:4];
	wire[255: 0] SR_WDATA = SR_WE2 ? MEM_SQ_R : {8{SR_WD}};
	wire         SR_WSELC = SR_WE2 ? SR_WCPU2 : SR_WCPU;                    //the CPU's shift register
	wire [ 7: 0] SR_WREN = SR_WE2 ? 8'hFF : ISTE_DELAYED ? 8'h00 : {7'b0000000,SR_WE}<<SR_WA[3:1];
	VRAM_SHIFTREG #(9) shiftreg
	(
		.CLK(CLK_MEM),
		.WADDR(SR_WADDR),
		.DATA(SR_WDATA),
		.WREN(SR_WREN & {8{~SR_WSELC & ~(SR_WSCR & ~SR_WE2)}}),
		.RADDR(SR_RADDR[8:4]),
		.Q(SR_Q)
	);

	// Game Bub port: the CPU's shift register (SPORT read transfers fill it,
	// write transfers store it)
	wire [ 8: 1] SC_RADDR = SREG_POS[8:1];
	VRAM_SHIFTREG #(9) shiftreg_cpu
	(
		.CLK(CLK_MEM),
		.WADDR(SR_WADDR),
		.DATA(SR_WDATA),
		.WREN(SR_WREN & {8{SR_WSELC & ~(SR_WSCR & ~SR_WE2)}}),
		.RADDR(SC_RADDR[8:4]),
		.Q(SC_Q)
	);

	// Game Bub port: the destination row of a masked write outside (MRD)
	bit [255: 0] SCR_Q;
	VRAM_SHIFTREG #(9) shiftreg_scr
	(
		.CLK(CLK_MEM),
		.WADDR(SR_WA[8:4]),
		.DATA({8{SR_WD}}),
		.WREN(SR_WREN & {8{SR_WSCR & ~SR_WE2}}),
		.RADDR(SC_RADDR[8:4]),
		.Q(SCR_Q)
	);

	bit  [31: 0] SR_DATA, SC_DATA, SCR_DATA;
	always_comb begin
		case (SR_RADDR[3:1])
			3'h0: SR_DATA = SR_Q[031:000];
			3'h1: SR_DATA = SR_Q[063:032];
			3'h2: SR_DATA = SR_Q[095:064];
			3'h3: SR_DATA = SR_Q[127:096];
			3'h4: SR_DATA = SR_Q[159:128];
			3'h5: SR_DATA = SR_Q[191:160];
			3'h6: SR_DATA = SR_Q[223:192];
			3'h7: SR_DATA = SR_Q[255:224];
		endcase
		case (SC_RADDR[3:1])
			3'h0: SC_DATA = SC_Q[031:000];
			3'h1: SC_DATA = SC_Q[063:032];
			3'h2: SC_DATA = SC_Q[095:064];
			3'h3: SC_DATA = SC_Q[127:096];
			3'h4: SC_DATA = SC_Q[159:128];
			3'h5: SC_DATA = SC_Q[191:160];
			3'h6: SC_DATA = SC_Q[223:192];
			3'h7: SC_DATA = SC_Q[255:224];
		endcase
		case (SC_RADDR[3:1])
			3'h0: SCR_DATA = SCR_Q[031:000];
			3'h1: SCR_DATA = SCR_Q[063:032];
			3'h2: SCR_DATA = SCR_Q[095:064];
			3'h3: SCR_DATA = SCR_Q[127:096];
			3'h4: SCR_DATA = SCR_Q[159:128];
			3'h5: SCR_DATA = SCR_Q[191:160];
			3'h6: SCR_DATA = SCR_Q[223:192];
			3'h7: SCR_DATA = SCR_Q[255:224];
		endcase
	end

	assign ESADDR = {MEM_ROW,SREG_POS};
	// a write transfer's data outside; masked: merged with the row read before
	wire [31: 0] ES_NEW = FW_EXEC || FWM ? {2{COLOR}} : XFER_CPU ? SC_DATA : SR_DATA;
	assign ESDATA = MASKED && MWT_EXEC ? (ES_NEW & {2{MASK}}) | (SCR_DATA & ~{2{MASK}}) : ES_NEW;
	assign ESWR = MWT_EXEC & ~ISTE;
	assign ESRD = RT_REQ & ~ISTE;
	assign ESFW = FW_EXEC & ~ISTE;
	
	assign QSF = SR_RA[8];
	assign XBUSY = RT_EXEC | MWT_EXEC | FW_EXEC | MRD_EXEC;

endmodule
