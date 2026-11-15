// synopsys translate_off
`define SIM
`define DEBUG
// synopsys translate_on

import P3DO_PKG::*;

module CLIO_VIDEO
(
	input              CLK,
	input              RST_N,
	input              EN,
	
	input              PAL,
	
	input              VCE,
	input              HSYNC_N,
	input              VSYNC_N,
	
	output     [10: 0] HCNT,
	output     [ 8: 0] VCNT,
	output             FLD,
	
	input      [31: 0] S,
	input              LSC_N,
	input              RSC_N,
	output             PCSC,
	
	output     [23: 0] AD,
	output             DE,
	
	input              HINTREPOL_DISABLE,
	input              VINTREPOL_DISABLE,
	input      [ 7: 0] DBG_EXT
`ifdef DEBUG
                      ,
	output reg [15: 0] DBG_PREV_PIX,
	output reg [15: 0] DBG_CURR_PIX
`endif
);
	
	bit  [ 2: 0] HSTART;
	bit  [ 6: 0] INFO;
	always @(posedge CLK or negedge RST_N) begin
		bit          HSYNC_N_OLD;
		bit          CHS;
		
		if (!RST_N) begin
			HSTART <= '0;
		end
		else if (EN && VCE) begin
			HSYNC_N_OLD <= HSYNC_N;
			CHS = HSYNC_N & ~HSYNC_N_OLD;
			
			HSTART <= {HSTART[1:0],CHS};			
			INFO <= {INFO[5:0],HSTART[2]};
		end
	end 
	
	bit  [10: 0] HCOUNT;
	bit  [ 8: 0] VCOUNT;
	bit          FIELD;
	always @(posedge CLK or negedge RST_N) begin
		bit          VSYNC_N_OLD;
		
		if (!RST_N) begin
			HCOUNT <= '0;
			VCOUNT <= '0;
			FIELD <= 0;
			VSYNC_N_OLD <= 1;
		end
		else if (EN && VCE) begin
			HCOUNT <= HCOUNT + 11'd1;
			if (HSTART[2]) begin
				HCOUNT <= '0;
				VCOUNT <= VCOUNT + 9'd1;
				if (!VSYNC_N && VSYNC_N_OLD) begin
					VCOUNT <= '0;
					FIELD <= ~FIELD;
				end
				VSYNC_N_OLD <= VSYNC_N;
			end
		end
	end 
	wire VZ = (VCOUNT == 9'd0);
	wire VN = VCOUNT[0];
	wire FN = FIELD;
	wire FC = (VCOUNT == 9'd5);
	wire VR = 0;
	wire VD = PAL;
	wire VL = (VCOUNT == !(PAL ? 9'd262 : 9'd312));
	assign PCSC = |HSTART | (INFO[0] & VZ) | 
	                        (INFO[1] & VN) | 
									(INFO[2] & FN) | 
									(INFO[3] & FC) |
									(INFO[4] & VR) |
									(INFO[5] & VD) |
									(INFO[6] & VL);
									
	assign HCNT = HCOUNT;
	assign VCNT = VCOUNT;
	assign FLD = FIELD;
	
	
	bit          READ_START,READ_EN;
	bit          COPY_EN;
	bit          WRITE_EN;
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) begin
			READ_START <= 0;
			READ_EN <= 0;
			COPY_EN <= 0;
			WRITE_EN <= 0;
		end
		else if (EN && VCE) begin
			if (HSTART[2]) begin
//				WRITE_EN <= 0;
			end else begin
				if (HCOUNT == 11'd10 - 1) begin
					READ_START <= 1;
				end
				
				if (HCOUNT == 11'd11 - 1) begin
					READ_START <= 0;
					READ_EN <= 1;
				end
				if (HCOUNT == 11'd1293 - 1) begin
					READ_EN <= 0;
				end
				
				if (HCOUNT == 11'd1295 - 1) begin//
					COPY_EN <= 1;
				end
				if (HCOUNT == 11'd1295 + 33 - 1) begin
					COPY_EN <= 0;
				end
				
				if (HCOUNT == 11'd1340 - 1) begin
					WRITE_EN <= 1;
				end
				if (HCOUNT == 11'd1400 - 1) begin
					WRITE_EN <= 0;
				end
			end
		end
	end 
	wire FIRST_LINE = (VCOUNT == 9'd24);
	
	
	bit          LSCAP_N;
	bit          RSCAP_N;
	bit          SCAP_SEL;
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) begin
			LSCAP_N <= 0;
			RSCAP_N <= 0;
			SCAP_SEL <= 0;
		end
		else if (EN && VCE) begin
			LSCAP_N <= LSC_N;
			RSCAP_N <= RSC_N;
			if (!LSCAP_N)
				SCAP_SEL <= 1;
			else if (!RSCAP_N)
				SCAP_SEL <= 0;
		end
	end 
	wire CAPCLKEN_N = LSCAP_N & RSCAP_N;
	// a VDL word: both ports captured together (lines up with CAPEND1_N and SCAP).
	// It writes the palette wherever it falls: MADAM starts a pending download
	// at any time from HCOUNT 1339 on (MADAM_SPORT), so a late one ran past the
	// end of the WRITE_EN window and lost its last entries (a fade left entries
	// 24-31 and the background at their old colours). Pixels never write it.
	bit          CLUT_CAP;
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) CLUT_CAP <= 0;
		else if (EN && VCE) CLUT_CAP <= ~LSCAP_N & ~RSCAP_N;
	end
	
	bit  [15: 0] LSCAP_BUF;
	bit  [15: 0] RSCAP_BUF;
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) begin
			LSCAP_BUF <= '0;
			RSCAP_BUF <= '0;
		end
		else if (EN && VCE) begin
			if (!LSCAP_N) begin
				LSCAP_BUF <= S[31:16];
			end
			if (!RSCAP_N) begin
				RSCAP_BUF <= S[15:0];
			end
		end
	end 
	wire [31: 0] SCAP = {LSCAP_BUF,RSCAP_BUF};
	
	bit          CAPEND1_N,CAPEND2_N,CAPEND3_N,CAPEND4_N;
	always @(posedge CLK or negedge RST_N) begin		
		if (!RST_N) begin
			{CAPEND1_N,CAPEND2_N,CAPEND3_N,CAPEND4_N} <= '0;
		end
		else if (EN && VCE) begin
			CAPEND1_N <= CAPCLKEN_N;
			CAPEND2_N <= CAPEND1_N;
			CAPEND3_N <= CAPEND2_N;
			CAPEND4_N <= CAPEND3_N;
		end
	end 
	
//	bit  [ 9: 0] AMYCTL;
	// Game Bub port: in the display control word, 11 in a 2-bit source
	// field (vertical and horizontal subposition source, blue pen LSB source,
	// for the line and for the window) means "maintain prior setting" (US
	// patent 5,502,462 Table 6; the SDK's VDL_*_NOP). The original stored 11
	// as a setting of its own.
	// Game Bub port: COLONLY ("Colors Only after this point. Ignore optional
	// download words that are other than color-defining words", US patent
	// 5,502,462 Table 6 bit 1) locks out further display control words for
	// the rest of the VDL entry's download, i.e. until the next CLUT download
	// window (WRITE_EN) opens (the Opera emulator: per VDL entry). The
	// original kept loading them.
	DispCtrl_t   DISPCTL;
	bit          COLONLY_LOCK;
	always @(posedge CLK or negedge RST_N) begin
		bit          LOAD;
		bit          WRITE_EN_OLD;
		DispCtrl_t   W;

		if (!RST_N) begin
//			AMYCTL <= '0;
			DISPCTL <= '0;
			COLONLY_LOCK <= 0;
			WRITE_EN_OLD <= 0;
		end
		else if (EN && VCE) begin
			LOAD <= ~LSCAP_N & ~RSCAP_N;
			WRITE_EN_OLD <= WRITE_EN;
			if (WRITE_EN && !WRITE_EN_OLD) COLONLY_LOCK <= 0;
			if (LOAD && !CAPEND1_N) begin
				if (!SCAP[30] && SCAP[31]) begin
//					AMYCTL <= SCAP[9:0];
				end
				if (!SCAP[29] && SCAP[30] && SCAP[31] && !COLONLY_LOCK) begin
					W = SCAP[28:0];
					if (W.VSUB  == 2'b11) W.VSUB  = DISPCTL.VSUB;
					if (W.HSUB  == 2'b11) W.HSUB  = DISPCTL.HSUB;
					if (W.BLSB  == 2'b11) W.BLSB  = DISPCTL.BLSB;
					if (W.WVSUB == 2'b11) W.WVSUB = DISPCTL.WVSUB;
					if (W.WHSUB == 2'b11) W.WHSUB = DISPCTL.WHSUB;
					if (W.WBLSB == 2'b11) W.WBLSB = DISPCTL.WBLSB;
					DISPCTL <= W;
					if (W.COLONLY) COLONLY_LOCK <= 1;
				end
			end
		end
	end
	
	bit  [15: 0] INPUT;
	always_comb begin
		bit  [15: 0] TEMP;
		bit          B0;
		
		case (SCAP_SEL)
			1'b1: TEMP = LSCAP_BUF;
			1'b0: TEMP = RSCAP_BUF;
		endcase
		// Game Bub port: display control word bit 10 (SwapPENms, SDK
		// swapPenVH) swaps the pen halfword's MSB and LSB before CLIO
		// interprets it (US patent 5,502,462 Table 6); the original ignored it
		if (DISPCTL.SWAPHV) TEMP = {TEMP[0],TEMP[14:1],TEMP[15]};
		
		// SDK: VDL_BLSB_ZERO, _GREEN (green LSB, bit 5), _BLUE (bit 0); 11
		// (NOP) keeps the prior setting and is never stored
		case (DISPCTL.BLSB)
			2'b00: B0 = 0;
			2'b01: B0 = TEMP[5];
			2'b10: B0 = TEMP[0];
			2'b11: B0 = TEMP[0];
		endcase
		INPUT = {TEMP[15:1],B0};
//		LSB = TEMP[0]&DISPCTL[4];
//		MSB = TEMP[15];
	end
	
	bit          CURR_PREV;
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) begin
			CURR_PREV <= 0;
		end
		else if (EN && VCE) begin
			if (HSTART[0]) begin
				CURR_PREV <= 0;
			end
			
			if (!CAPEND2_N) begin
				CURR_PREV <= ~CURR_PREV;
`ifdef DEBUG
				if (!CURR_PREV) DBG_PREV_PIX <= INPUT;
				if ( CURR_PREV) DBG_CURR_PIX <= INPUT;
`endif
			end
		end
	end 
	
`ifdef DEBUG
	bit          DBG_HL_DOT;
	bit  [10: 0] DBG_HCNT;
	bit  [ 9: 0] DBG_HL_HPOS;
	bit  [ 8: 0] DBG_HL_VPOS;
	always @(posedge CLK or negedge RST_N) begin
		bit  [ 7: 0] DBG_EXT_OLD;
		
		if (!RST_N) begin
			DBG_HCNT <= '0;
			DBG_HL_HPOS <= 5;
			DBG_HL_VPOS <= 5;
		end
		else if (EN && VCE) begin
			if (HSTART[0]) begin
				DBG_HCNT <= '0;
			end
			if (READ_EN && !CAPEND1_N) begin
				DBG_HCNT <= DBG_HCNT + 1'd1;
			end
			
			DBG_EXT_OLD <= DBG_EXT;
			if (DBG_EXT[4] && !DBG_EXT_OLD[4]) begin
				DBG_HL_HPOS <= DBG_HL_HPOS - 1'd1;
			end
			if (DBG_EXT[5] && !DBG_EXT_OLD[5]) begin
				DBG_HL_HPOS <= DBG_HL_HPOS + 1'd1;
			end
			if (DBG_EXT[6] && !DBG_EXT_OLD[6]) begin
				DBG_HL_VPOS <= DBG_HL_VPOS - 1'd1;
			end
			if (DBG_EXT[7] && !DBG_EXT_OLD[7]) begin
				DBG_HL_VPOS <= DBG_HL_VPOS + 1'd1;
			end
		end
	end 
	assign DBG_HL_DOT = DBG_HCNT[10:1] == DBG_HL_HPOS && VCOUNT == (DBG_HL_VPOS + 22);
`else
	wire DBG_HL_DOT = 0;
`endif
	
	wire         BG_DET = ~|INPUT[14:0];
	bit  [23: 0] CLUT_OUTPUT;
	CLIO_CLUT CLUT
	(
		.CLK(CLK),
		.RST_N(RST_N),
		.EN(EN),
		
		.CE(VCE),
		
		.INPUT(INPUT ^ {1'b0,{15{DBG_HL_DOT}}}),
		
		.SCAP(SCAP),
		.WRITE(CLUT_CAP),
		.READCLKEN(~CAPEND2_N),
		.COPY_EN(COPY_EN),
		.WRITE_EN(WRITE_EN | CLUT_CAP),
		.CURR_PREV(CURR_PREV),
//		.BG_CTL(DISPCTL[29]),
		.BG_DET(BG_DET),
		
		.OUTPUT(CLUT_OUTPUT)
	);
	
	// Game Bub port: CLUT bypass (pen MSB set). The 5-bit components fill the
	// 5 MSBs of the 8-bit outputs; their 3 LSBs are zero, the 3 MSBs again
	// with MSBREP, or a pseudo-random value with RNDM (US patent 6,191,772;
	// SDK VDLDisplayCtlWord bits 11 and 12). The original took each
	// component's own 3 LSBs. The console's random generator is not
	// documented: here a 15-bit LFSR, one 3-bit value per pixel for all three
	// components ("a 3-bit value"), RNDM taking precedence over MSBREP.
	bit  [23: 0] BYPASS_OUTPUT;
	bit          BYPASS_EN;
	bit  [14: 0] BYPASS_RND;
	always @(posedge CLK or negedge RST_N) begin
		bit  [ 2: 0] LR,LG,LB;

		if (!RST_N) begin
			BYPASS_OUTPUT <= '0;
			BYPASS_EN <= 0;
			BYPASS_RND <= 15'h0001;
		end
		else if (EN && VCE) begin
			if (!CAPEND2_N) begin
				BYPASS_RND <= {BYPASS_RND[13:0], BYPASS_RND[14] ^ BYPASS_RND[13]};
				if (DISPCTL.RNDM) begin
					{LR,LG,LB} = {3{BYPASS_RND[2:0]}};
				end else if (DISPCTL.MSBREP) begin
					{LR,LG,LB} = {INPUT[14:12],INPUT[9:7],INPUT[4:2]};
				end else begin
					{LR,LG,LB} = '0;
				end
				BYPASS_EN <= (DISPCTL.BYPASS && INPUT[15]) /*|| DISPCTL[12]*/;
				BYPASS_OUTPUT <= {INPUT[14:10],LR,INPUT[9:5],LG,INPUT[4:0],LB};
			end
		end
	end
	
	bit [23: 0] RGB;
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) begin
			RGB <= '0;
		end
		else if (EN && VCE) begin
			if (!CAPEND4_N)
				RGB <= BYPASS_EN ? BYPASS_OUTPUT : CLUT_OUTPUT;
		end
	end 
	
	// Pixel captures: one serial port at a time, inside the line's read window.
	// A VDL download captures both ports together in the horizontal blanking
	// (US 5,502,462); it is decoded above and is not picture data, so it must
	// not clock the destacker or the line buffer (a late one ran into the next
	// line's first dots). VIDEO_CAP[k] lines up with CAPEND(k+1)_N.
	bit  [ 8: 0] VIDEO_CAP;
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) VIDEO_CAP <= '0;
		else if (EN && VCE) VIDEO_CAP <= {VIDEO_CAP[7:0], READ_EN & (LSCAP_N ^ RSCAP_N)};
	end
	bit          CAPEN_DIV;
	always @(posedge CLK or negedge RST_N) begin		
		if (!RST_N) begin
			CAPEN_DIV <= 0;
		end
		else if (EN && VCE) begin
			if (READ_START)
				CAPEN_DIV <= 0;
			else if (VIDEO_CAP[4] || VIDEO_CAP[6])
				CAPEN_DIV <= ~CAPEN_DIV;
		end
	end 
	
	wire PDS_CLK1 = (VIDEO_CAP[4] | VIDEO_CAP[6]) & ~CAPEN_DIV;
	wire PDS_CLK2 = (VIDEO_CAP[6] | VIDEO_CAP[8]) &  CAPEN_DIV;
	bit  [23: 0] LP0,LP1,LP2,LP3;
	bit          PDESTACKER_DE;
	CLIO_24DESTACKER PDESTACKER(CLK, VCE, EN, READ_START, PDS_CLK1, PDS_CLK2, RGB, VIDEO_CAP[6], LP0, LP1, LP2, LP3, PDESTACKER_DE);
	
	wire ION = ~FIRST_LINE;
	bit  [23: 0] INTERPOL_OUT;
	bit          INTERPOL_DE;
	CLIO_INTERPOL INTERPOL
	(
		.CLK(CLK),
		.RST_N(RST_N),
		.EN(EN),
		
		.CE(VCE),
		
		.ACLK1(1'b0),
		.ACLK2(1'b0),
		
		.HION(DISPCTL.HION & ION & ~HINTREPOL_DISABLE),
		.VION(DISPCTL.VION & ION & ~VINTREPOL_DISABLE),
		.SPH(DISPCTL.HSUB == 2'h1),
		.SPV(DISPCTL.VSUB == 2'h1),
		
		.LP0(LP0),
		.LP1(LP1),
		.LP2(LP2),
		.LP3(LP3),
		.DE_IN(PDESTACKER_DE),
		
		.OUT(INTERPOL_OUT),
		.DE(INTERPOL_DE)
	);
	assign AD = INTERPOL_OUT;
	assign DE = INTERPOL_DE;

endmodule


module CLIO_24DESTACKER (
	input             CLK,
	input             CE,
	input             EN,
	
	input             INIT,
	
	input             CLK1,
	input             CLK2,
	
	input     [23: 0] IN,
	input             DE_IN,
	output    [23: 0] LP0,
	output    [23: 0] LP1,
	output    [23: 0] LP2,
	output    [23: 0] LP3,
	output            DE_OUT
);

	bit [23: 0] LATCH0,LATCH1,LATCH2,LATCH3,LATCH4;
	bit         DE_LATCH0,DE_LATCH1,DE_LATCH2,DE_LATCH3,DE_LATCH4,DE_LATCH5;
	always @(posedge CLK) begin
		if (EN && CE) begin
			if (INIT) begin
				{LATCH0,LATCH1,LATCH2,LATCH3,LATCH4} <= '0;
				{DE_LATCH0,DE_LATCH1,DE_LATCH2,DE_LATCH3,DE_LATCH4,DE_LATCH5} <= '0;
			end
			
			if (CLK1) begin
				LATCH4 <= IN;
			end
			
			if (CLK2) begin
				LATCH2 <= IN;
				LATCH1 <= LATCH4;
				LATCH0 <= LATCH1;
				LATCH3 <= LATCH2;
			end
			
			DE_LATCH0 <= DE_IN;
			DE_LATCH1 <= DE_LATCH0;
			DE_LATCH2 <= DE_LATCH1;
			DE_LATCH3 <= DE_LATCH2;
			DE_LATCH4 <= DE_LATCH3;
			DE_LATCH5 <= DE_LATCH4;
		end
	end

	assign {LP0,LP1,LP2,LP3} = {LATCH0,LATCH1,LATCH2,LATCH3};
	assign DE_OUT = DE_LATCH5;

endmodule
