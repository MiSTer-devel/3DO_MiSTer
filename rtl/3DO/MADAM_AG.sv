import P3DO_PKG::*; 

module MADAM_AG
(
	input              CLK,
	input              RST_N,
	input              EN,
	
	input              CE_R,
	input              CE_F,
	
	input              PHASE1,
	input              PHASE2,
	
	//CPU
	input      [23: 2] CPU_ADDR,
	input              CPU_ACCESS,
	input              CPU_START,
	input              CPU_DRAM0_SEL,
	input              CPU_DRAM1_SEL,
	input              CPU_VRAM_SEL,
	input              CPU_SPORT_SEL,
	input      [ 3: 0] CPU_WE,
	input              CPU_GRANT,
	
	input      [ 6: 0] MEM_SIZE,
	input              DRAM_EN,
	
	//EXTP
	input              EXTP_GRANT,

	//SPRITE
	input      [23: 1] SE_ADDR_A,
	input      [23: 1] SE_ADDR_B,
	input              SE_RAS_A,
	input              SE_RAS_B,
	input              SE_WRITE_A,
	input              SE_WRITE_B,
	input              SE_READ,
	input              SE_GRANT,

	//PLAYER
	input              PLAYER_GRANT,
	
	//SPORT
	input              LINE0,
	output             CLUTWR_FORCE,
	output             VIDOUT_PFL,
	output reg         LMIDLINE_REQ,
	output reg         RMIDLINE_REQ,
	
	output     [23: 2] MADR,
	input      [31: 0] MDTI,
	output     [31: 0] MDTO,
	output reg         MWR,
	input BusState_t   BUS_STATE,
	input AddrGenCtl_t DMA_CTL,
	output reg         PBI,
	output reg         REG_OVF,
	output reg         REG_ZERO,
	
	//SYSRAM
	output     [23: 2] LA,
	output             LRAS0_N,
	output             LRAS2_N,
	output             LRAS3_N,
	output             LCAS_N,
	output     [ 1: 0] LWE_N,
	output             LOE_N,
	output             LDSF,
	input              LQSF,
	output     [ 3: 0] LCODE,
	output     [23: 2] RA,
	output             RRAS0_N,
	output             RRAS2_N,
	output             RRAS3_N,
	output             RCAS_N,
	output     [ 1: 0] RWE_N,
	output             ROE_N,
	output             RDSF,
	input              RQSF,
	output     [ 3: 0] RCODE,

	output reg [23: 0] DBG_REG100,DBG_REG104,DBG_REG110,DBG_REG114,
	output reg [23: 0] DBG_REG120,DBG_REG124,DBG_REG128,DBG_REG12C,
	output reg         DBG_HOOK
);
	 	
	bit  [23: 2] ADDR_SRC_OUT;
	bit  [23: 2] ADDR_FF_1,ADDR_FF_2;
	bit  [23: 2] OFFS_FF;
	bit  [ 9: 0] BYPASS_FF;
	bit  [23: 2] ADDER_OUT;
	
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) begin
			BYPASS_FF <= '0;
		end
		else if (EN && CE_R) begin
			if (DMA_CTL.BYPASS_EN)
				BYPASS_FF <= !DMA_CTL.BPP_SEL ? MDTI[25:16] : {2'b00,MDTI[31:24]};
		end
	end 
	
	wire [23: 2] LOAD_OUT = DMA_CTL.LOAD_OFFSET_SEL ? {12'h000,BYPASS_FF} : MDTI[23: 2];
	
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) begin
			OFFS_FF <= '0;
		end
		else if (EN && CE_R) begin
//			if (PHASE2)
				OFFS_FF <= LOAD_OUT;
		end
	end 
	
	wire [23: 2] DMA_STACK_IN = DMA_CTL.DMA_ZERO_SEL ? '0 :
	                            DMA_CTL.DMA_OWN_SEL  ? ADDER_OUT :
								                              LOAD_OUT;
		
	bit  [ 1: 0] DMA_ADDR_FF_0;
	bit  [ 6: 2] DMA_ADDR_FF_1;
	
	wire [ 6: 0] DMA_REG_ADDR = DMA_CTL.DMA_GROUP_ADDR_SEL ? DMA_CTL.DMA_GROUP_ADDR : ADDR_SRC_OUT[8:2];
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) begin
			DMA_ADDR_FF_0 <= '0;
			DMA_ADDR_FF_1 <= '0;
		end
		else if (EN && CE_R) begin
			if (DMA_CTL.DMA_GROUP_HOLD)
				DMA_ADDR_FF_1 <= DMA_REG_ADDR[6:2];
			DMA_ADDR_FF_0 <= DMA_REG_ADDR[1:0];
		end
	end 
	wire [ 6: 0] DMA_STACK_RADDR = {DMA_ADDR_FF_1,DMA_CTL.DMA_REG_READ_SEL ? DMA_CTL.DMA_REG_READ_CTL : DMA_ADDR_FF_0};
	wire [ 6: 0] DMA_STACK_WADDR = DMA_CTL.DMA_REG_WRITE_SEL ? {DMA_ADDR_FF_1,DMA_ADDR_FF_0} : {DMA_ADDR_FF_1[6:3],DMA_CTL.DMA_REG_WRITE_CTL};
	wire         DMA_STACK_WE = DMA_CTL.DMA_REG_WRITE_EN;
	
	bit  [23: 2] DMA_STACK_OUT;
	MADAM_DMA_STACK DMA_STACK
	(
		.CLK(CLK),
		.CE(CE_R),
		.EN(EN),
		
		.WADDR(DMA_STACK_WADDR),
		.DIN(DMA_STACK_IN),
		.WE(DMA_STACK_WE),
		
		.RADDR(DMA_STACK_RADDR),
		.DOUT(DMA_STACK_OUT)
	);
	
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) begin
			DBG_REG100 <= '0;
			DBG_REG104 <= '0;
			DBG_REG110 <= '0;
			DBG_REG114 <= '0;
			DBG_REG120 <= '0;
			DBG_REG124 <= '0;
			DBG_REG128 <= '0;
			DBG_REG12C <= '0;
			DBG_HOOK <= 0;
		end
		else if (EN && CE_R) begin
			if (DMA_STACK_WE) begin
				case (DMA_STACK_WADDR)
					7'h40: DBG_REG100 <= {DMA_STACK_IN,2'b00};
					7'h41: DBG_REG104 <= {DMA_STACK_IN,2'b00};
					
					7'h44: DBG_REG110 <= {DMA_STACK_IN,2'b00};
					7'h45: DBG_REG114 <= {DMA_STACK_IN,2'b00};
					
					7'h48: DBG_REG120 <= {DMA_STACK_IN,2'b00};
					7'h49: begin DBG_REG124 <= {DMA_STACK_IN,2'b00}; if ({DMA_STACK_IN,2'b00} == 24'h000020) DBG_HOOK <= 1; end
					7'h4A: DBG_REG128 <= {DMA_STACK_IN,2'b00};
					7'h4B: DBG_REG12C <= {DMA_STACK_IN,2'b00};
				endcase
			end
		end
	end 
	
	wire [23: 2] ADDR_SRC_TEMP = DMA_CTL.CPU_ADDR_SEL ? CPU_ADDR :
	                             //DMA_CTL.SPR_ADDR_SEL ? SE_ADDR_A[23:2] :
								                               ADDR_FF_2;
	assign ADDR_SRC_OUT = DMA_CTL.DMA_ADDR_SEL ? DMA_STACK_OUT : ADDR_SRC_TEMP;
	
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) begin
			ADDR_FF_1 <= '0;
		end
		else if (EN && CE_R) begin
			ADDR_FF_1 <= ADDR_SRC_OUT;
		end
	end 

	always_comb begin
		bit  [21: 0] ADD_A,ADD_B;
		
		case (DMA_CTL.DMA_ADDER_CTL)
			4'b0111: ADD_A = {ADDR_FF_1[23:10],8'b00000000};	//slip half page
			default: ADD_A = ADDR_FF_1;
		endcase
		case (DMA_CTL.DMA_ADDER_CTL)
			4'b0000: ADD_B = 22'h000000;	//+0
			4'b0001: ADD_B = 22'h000001;	//+1
			4'b0010: ADD_B = 22'h3FFFFF;	//-1
			4'b0101: ADD_B = OFFS_FF;		//+OFFS
			4'b0110: ADD_B = OFFS_FF + 22'd1;		//+OFFS+1
			4'b0111: ADD_B = 22'h000100;	//+256 (+ half page)
			4'b1000: ADD_B = 22'h000140;	//+320
			4'b1001: ADD_B = 22'h000180;	//+384
			4'b1010: ADD_B = 22'h000200;	//+512
			4'b1011: ADD_B = 22'h000280;	//+640
			4'b1100: ADD_B = 22'h000400;	//+1024
			4'b1101: ADD_B = 22'h000140;	//+320
			4'b1110: ADD_B = 22'h000140;	//+320
			4'b1111: ADD_B = 22'h000140;	//+320
			default: ADD_B = 22'h000000;
		endcase
		ADDER_OUT = ADD_A + ADD_B;
	end
	
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) begin
			ADDR_FF_2 <= '0;
		end
		else if (EN && CE_R) begin
			ADDR_FF_2 <= ADDER_OUT;
		end
	end 
	
	assign MADR = ADDR_FF_1;
	assign MDTO = {8'h00,ADDR_FF_1,2'b00};
	assign MWR = |CPU_WE;
	
	bit  [23: 2] ADDR_COL_FF;
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) begin
			ADDR_COL_FF <= '0;
		end
		else if (EN && CE_R) begin
			ADDR_COL_FF <= ADDR_SRC_OUT;
		end
	end 
	
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) begin
			PBI <= 0;
		end
		else if (EN && CE_R) begin
			if (PHASE1)
				PBI <= &ADDR_SRC_OUT[10:2];
		end
	end 
	
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) begin
			REG_ZERO <= 0;
		end
		else if (EN && CE_R) begin
			if (DMA_STACK_WE) begin
				REG_ZERO <= ~|DMA_STACK_IN;
				REG_OVF <= DMA_STACK_IN[23];
			end
		end
	end 
	
	BusState_t BUS_STATE_FF;
	always @(posedge CLK or negedge RST_N) begin		
		if (!RST_N) begin
			BUS_STATE_FF <= BUS_IDLE;
		end
		else if (EN && CE_R) begin
			BUS_STATE_FF <= BUS_STATE;
		end
	end 
	
	bit         PFL/*,CFL*/;
	bit         CF;
	always @(posedge CLK or negedge RST_N) begin
		bit         CURR1_LATCH,CURR_FETCHED;
		bit         V480;
		
		if (!RST_N) begin
			PFL <= 0;
//			CFL <= 1;
			CF <= 0;
			CURR_FETCHED <= 0;
		end
		else if (EN && CE_R) begin
			case (BUS_STATE_FF)
				BUS_IDLE: begin
					if (ADDR_SRC_OUT[8:2] == 7'h60 && DMA_CTL.DMA_REG_WRITE_EN) begin
						CF <= 1;
					end
				end
				
				CLUT_CTRL0: begin
					CF <= 0;
				end
				
				CLUT_CTRL1: begin
					V480 <= MDTI[19];
				end
				
				CLUT_CURR1: begin
					CURR1_LATCH <= MDTI[1];
					CURR_FETCHED <= 1;
				end
				
				VID_PREINIT1: begin
					if (CURR_FETCHED) PFL <= CURR1_LATCH & ~V480;
				end
				
				VID_INIT1: begin
					if (!CURR_FETCHED) PFL <= ~PFL & ~V480;
					CURR_FETCHED <= 0;
				end
				
				VID_CURR1: begin
//					CFL <= ~PFL;
				end
				
				default:;
			endcase
		end
	end 
	assign VIDOUT_PFL = PFL;
	assign CLUTWR_FORCE = CF;
	
	always @(posedge CLK or negedge RST_N) begin
		bit         LQSF_SYNC,RQSF_SYNC;
		bit         LQSF_OLD,RQSF_OLD;
		
		if (!RST_N) begin
			LMIDLINE_REQ <= 0;
			RMIDLINE_REQ <= 0;
		end
		else if (EN && CE_R) begin
			{RQSF_SYNC,LQSF_SYNC} <= {RQSF,LQSF};
			
			{RQSF_OLD,LQSF_OLD} <= {RQSF_SYNC,LQSF_SYNC};
			LMIDLINE_REQ <= 0;
			if (LQSF_SYNC ^ LQSF_OLD)
				LMIDLINE_REQ <= 1;
				
			RMIDLINE_REQ <= 0;
			if (RQSF_SYNC ^ RQSF_OLD)
				RMIDLINE_REQ <= 1;
		end
	end 
	
	wire [23: 2] AOUT = PHASE1 ? ADDR_SRC_OUT : ADDR_COL_FF;
	
	wire         CPU_RAM_SEL = CPU_DRAM0_SEL || CPU_DRAM1_SEL || CPU_VRAM_SEL;
	
	bit  [23: 0] DRAM0_END,DRAM1_START,DRAM1_END,VRAM_START,VRAM_END;
	always_comb begin
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
	end
	
	
	wire         AG_START =  (BUS_STATE_FF == EXTP_INIT1 || BUS_STATE_FF == EXTP_INIT3 || 
	                          BUS_STATE_FF == PLAY_INIT1 || BUS_STATE_FF == PLAY_INIT3 || BUS_STATE_FF == REF_INIT1 ||
									  BUS_STATE_FF == SCOB_INIT1 || BUS_STATE_FF == SCOB_NEXT_REL1 || BUS_STATE_FF == SCOB_SOURCE_REL1 || BUS_STATE_FF == SCOB_PIPPTR_REL1 || 
									  BUS_STATE_FF == SCOB_INIT3 || BUS_STATE_FF == SCOB_INIT5 || BUS_STATE_FF == SCOB_INIT7 ||
									  BUS_STATE_FF == SPR_INIT1 || BUS_STATE_FF == SPR_INIT3);
	wire         AG_ACCESS = (BUS_STATE_FF == EXTP_READ0 || BUS_STATE_FF == EXTP_READ1 || 
	                          BUS_STATE_FF == EXTP_WRITE0 || BUS_STATE_FF == EXTP_WRITE1 ||
									  BUS_STATE_FF == PLAY_READ0 || BUS_STATE_FF == PLAY_READ1 || 
	                          BUS_STATE_FF == PLAY_WRITE0 || BUS_STATE_FF == PLAY_WRITE1 ||
									  BUS_STATE_FF == SCOB_FLAG0 || BUS_STATE_FF == SCOB_FLAG1 || 
	                          BUS_STATE_FF == SCOB_NEXT0 || BUS_STATE_FF == SCOB_NEXT1 ||
									  BUS_STATE_FF == SCOB_SOURCE0 || BUS_STATE_FF == SCOB_SOURCE1 ||
									  BUS_STATE_FF == SCOB_PIPPTR0 || BUS_STATE_FF == SCOB_PIPPTR1 ||
									  BUS_STATE_FF == SCOB_XPOS0 || BUS_STATE_FF == SCOB_XPOS1 ||
									  BUS_STATE_FF == SCOB_YPOS0 || BUS_STATE_FF == SCOB_YPOS1 ||
									  BUS_STATE_FF == SCOB_DX0 || BUS_STATE_FF == SCOB_DX1 ||
									  BUS_STATE_FF == SCOB_DY0 || BUS_STATE_FF == SCOB_DY1 ||
									  BUS_STATE_FF == SCOB_LINEDX0 || BUS_STATE_FF == SCOB_LINEDX1 ||
									  BUS_STATE_FF == SCOB_LINEDY0 || BUS_STATE_FF == SCOB_LINEDY1 ||
									  BUS_STATE_FF == SCOB_DDX0 || BUS_STATE_FF == SCOB_DDX1 ||
									  BUS_STATE_FF == SCOB_DDY0 || BUS_STATE_FF == SCOB_DDY1 ||
									  BUS_STATE_FF == SCOB_PPMP0 || BUS_STATE_FF == SCOB_PPMP1 ||
									  BUS_STATE_FF == SCOB_PRE00 || BUS_STATE_FF == SCOB_PRE01 ||
									  BUS_STATE_FF == SCOB_PRE10 || BUS_STATE_FF == SCOB_PRE11 ||
									  BUS_STATE_FF == SCOB_PIP0 || BUS_STATE_FF == SCOB_PIP1 ||
									  BUS_STATE_FF == SPR_OFFS0 || BUS_STATE_FF == SPR_OFFS1 ||
									  BUS_STATE_FF == SPR_OFFS2 || BUS_STATE_FF == SPR_OFFS3 ||
									  BUS_STATE_FF == SPR_DATA0 || BUS_STATE_FF == SPR_DATA1 ||
									  BUS_STATE_FF == CFB_READ0 || BUS_STATE_FF == CFB_READ1 ||
									  BUS_STATE_FF == CFB_WRITE0 || BUS_STATE_FF == CFB_WRITE1);
	wire [ 1: 0] AG_WE =  {2{BUS_STATE_FF == EXTP_WRITE0 || BUS_STATE_FF == EXTP_WRITE1}} | 
	                      {2{BUS_STATE_FF == PLAY_WRITE0 || BUS_STATE_FF == PLAY_WRITE1}};
	wire         AG_REF =  (BUS_STATE_FF == REF_INIT1 || BUS_STATE_FF == REF_WRITE0 || BUS_STATE_FF == REF_WRITE1 || BUS_STATE_FF == REF_WRITE2 || BUS_STATE_FF == REF_WRITE3);
	wire         AG_DRAM0_SEL = ((AOUT >= (24'h000000>>2) && AOUT <= (DRAM0_END>>2)) || AG_REF) && |MEM_SIZE[4:3] && DRAM_EN;
	wire         AG_DRAM1_SEL = ((AOUT >= (DRAM1_START>>2) && AOUT <= (DRAM1_END>>2)) || AG_REF) && |MEM_SIZE[6:5] && DRAM_EN;
	wire         AG_VRAM_SEL  = (AOUT >= (VRAM_START>>2) && AOUT <= (VRAM_END>>2));
	
	wire         CFB_START = (BUS_STATE_FF == CFB_INIT1);
	wire         CFB_ACCESS = (BUS_STATE_FF == CFB_INIT1 ||
	                           BUS_STATE_FF == CFB_READ0 || BUS_STATE_FF == CFB_READ1 ||
									   BUS_STATE_FF == CFB_WRITE0 || BUS_STATE_FF == CFB_WRITE1);
	wire [ 1: 0] CFB_CAS = {SE_WRITE_A&~SE_ADDR_A[1]&PHASE1,SE_WRITE_A&SE_ADDR_A[1]&PHASE1}|{SE_WRITE_B&~SE_ADDR_B[1]&PHASE2,SE_WRITE_B&SE_ADDR_B[1]&PHASE2};
	wire [ 1: 0] CFB_WE = {2{BUS_STATE_FF == CFB_WRITE0 || BUS_STATE_FF == CFB_WRITE1}}&CFB_CAS;
	wire [ 1: 0] CFB_OE = {2{BUS_STATE_FF == CFB_READ0 || BUS_STATE_FF == CFB_READ1}}&CFB_CAS;
	wire         CFB_DRAM0_SEL = SE_RAS_B || SE_WRITE_B ? (SE_ADDR_B[23:2] >= (24'h000000>>2) && SE_ADDR_B[23:2] <= (DRAM0_END>>2)) : (SE_ADDR_A[23:2] >= (24'h000000>>2) && SE_ADDR_A[23:2] <= (DRAM0_END>>2));
	wire         CFB_DRAM1_SEL = SE_RAS_B || SE_WRITE_B ? (SE_ADDR_B[23:2] >= (DRAM1_START>>2) && SE_ADDR_B[23:2] <= (DRAM1_END>>2)) : (SE_ADDR_A[23:2] >= (DRAM1_START>>2) && SE_ADDR_A[23:2] <= (DRAM1_END>>2));
	wire         CFB_VRAM_SEL  = SE_RAS_B || SE_WRITE_B ? (SE_ADDR_B[23:2] >= (VRAM_START>>2) && SE_ADDR_B[23:2] <= (VRAM_END>>2)) : (SE_ADDR_A[23:2] >= (VRAM_START>>2) && SE_ADDR_A[23:2] <= (VRAM_END>>2));
	
	wire         PREV_TRANS = (BUS_STATE_FF == CLUT_TRANSFER0 || BUS_STATE_FF == CLUT_TRANSFER1 || 
	                           BUS_STATE_FF == VID_PREV0 || BUS_STATE_FF == VID_PREV1);
	wire         CURR_TRANS = (BUS_STATE_FF == CLUT_TRANSFER0 || BUS_STATE_FF == CLUT_TRANSFER1 || 
	                           BUS_STATE_FF == VID_CURR0 || BUS_STATE_FF == VID_CURR1);
	wire         PREV_SPLIT = (BUS_STATE_FF == CLUT_MIDTRANS0 || BUS_STATE_FF == CLUT_MIDTRANS1 || 
	                           BUS_STATE_FF == VID_MIDPREV0 || BUS_STATE_FF == VID_MIDPREV1);
	wire         CURR_SPLIT = (BUS_STATE_FF == CLUT_MIDTRANS0 || BUS_STATE_FF == CLUT_MIDTRANS1 || 
	                           BUS_STATE_FF == VID_MIDCURR0 || BUS_STATE_FF == VID_MIDCURR1);
	
	wire         LEFT_TRANS  = PFL ? (PREV_TRANS || PREV_SPLIT) : (CURR_TRANS || CURR_SPLIT);
	wire         RIGHT_TRANS = PFL ? (CURR_TRANS || CURR_SPLIT) : (PREV_TRANS || PREV_SPLIT);
	wire         LEFT_SPLIT  = PFL ? PREV_SPLIT : CURR_SPLIT;
	wire         RIGHT_SPLIT = PFL ? CURR_SPLIT : PREV_SPLIT;
	wire         CLUT_START = (BUS_STATE_FF == CLUT_INIT1);
	wire         CLUT_RW = (BUS_STATE_FF == CLUT_CTRL0 || BUS_STATE_FF == CLUT_CTRL1 || 
	                        BUS_STATE_FF == CLUT_CURR0 || BUS_STATE_FF == CLUT_CURR1 || 
									BUS_STATE_FF == CLUT_PREV0 || BUS_STATE_FF == CLUT_PREV1 ||
									BUS_STATE_FF == CLUT_NEXT0 || BUS_STATE_FF == CLUT_NEXT1);
	
	assign LA       = SE_GRANT && CFB_ACCESS ? (SE_RAS_B || (SE_WRITE_B && (PHASE2 || !SE_WRITE_A)) ? SE_ADDR_B[23:2] : SE_ADDR_A[23:2]) : CPU_GRANT && CPU_SPORT_SEL ? {4'b0000,AOUT[10:2],9'b000000000} : AOUT;
	assign LRAS0_N  = SE_GRANT && CFB_ACCESS ? ~CFB_VRAM_SEL      : SE_GRANT || EXTP_GRANT || PLAYER_GRANT ? ~((AG_START|AG_ACCESS|AG_REF) & AG_VRAM_SEL )  : CPU_GRANT ? ~(((CPU_START|CPU_ACCESS) & CPU_VRAM_SEL ) | (CPU_ACCESS & CPU_SPORT_SEL)) : ~(LEFT_TRANS | CLUT_START | CLUT_RW);
	assign LRAS2_N  = SE_GRANT && CFB_ACCESS ? ~CFB_DRAM0_SEL     : SE_GRANT || EXTP_GRANT || PLAYER_GRANT ? ~((AG_START|AG_ACCESS|AG_REF) & AG_DRAM0_SEL)  : CPU_GRANT ? ~(((CPU_START|CPU_ACCESS) & CPU_DRAM0_SEL)                               ) : 1'b1;
	assign LRAS3_N  = SE_GRANT && CFB_ACCESS ? ~CFB_DRAM1_SEL     : SE_GRANT || EXTP_GRANT || PLAYER_GRANT ? ~((AG_START|AG_ACCESS|AG_REF) & AG_DRAM1_SEL)  : CPU_GRANT ? ~(((CPU_START|CPU_ACCESS) & CPU_DRAM1_SEL)                               ) : 1'b1;
	assign LCAS_N   = SE_GRANT && CFB_ACCESS ? ~((CFB_WE[1]&CE_R)|(CFB_OE[1]&CE_F)) : SE_GRANT || EXTP_GRANT || PLAYER_GRANT ? ~(AG_ACCESS & PHASE2) : CPU_GRANT ? ~(CPU_ACCESS & (CPU_RAM_SEL | CPU_SPORT_SEL) & PHASE2) : ~((LEFT_TRANS | CLUT_RW) & PHASE2);
	assign LWE_N[1] = SE_GRANT && CFB_ACCESS ? ~(CFB_WE[1]&CE_R)  : SE_GRANT || EXTP_GRANT || PLAYER_GRANT ? ~(AG_ACCESS & AG_WE[1] & PHASE2)        : CPU_GRANT ? ~(CPU_ACCESS & ((CPU_RAM_SEL & CPU_WE[3] & PHASE2) | (CPU_SPORT_SEL & ~CPU_ADDR[13] & CPU_WE[3] & PHASE1))) : 1'b1;
	assign LWE_N[0] = SE_GRANT && CFB_ACCESS ? ~(CFB_WE[1]&CE_R)  : SE_GRANT || EXTP_GRANT || PLAYER_GRANT ? ~(AG_ACCESS & AG_WE[1] & PHASE2)        : CPU_GRANT ? ~(CPU_ACCESS & ((CPU_RAM_SEL & CPU_WE[2] & PHASE2) | (CPU_SPORT_SEL & ~CPU_ADDR[13] & CPU_WE[2] & PHASE1))) : 1'b1;
	assign LOE_N    = SE_GRANT && CFB_ACCESS ? ~(CFB_OE[1]&CE_F)  : SE_GRANT || EXTP_GRANT || PLAYER_GRANT ? ~(AG_ACCESS & ~|AG_WE  & PHASE2)        : CPU_GRANT ? ~(CPU_ACCESS & ((CPU_RAM_SEL & ~|CPU_WE & PHASE2) | (CPU_SPORT_SEL & ~|CPU_ADDR[14:13] & PHASE1))) : ~((LEFT_TRANS & PHASE1) | (CLUT_RW & PHASE2));
	assign LDSF     =                                               SE_GRANT || EXTP_GRANT || PLAYER_GRANT ? 1'b0                                        : CPU_GRANT ? (CPU_ACCESS & CPU_SPORT_SEL & |CPU_ADDR[14:13] /*& PHASE1*/) :  (LEFT_SPLIT & PHASE1);
	assign LCODE    = SE_GRANT && CFB_ACCESS ? {CFB_START,1'b0,CFB_WE[1],CFB_OE[1]} : SE_GRANT || EXTP_GRANT || PLAYER_GRANT ? {AG_START,AG_REF,AG_ACCESS&|AG_WE&PHASE2,AG_ACCESS&~|AG_WE&PHASE1} : CPU_GRANT ? {CPU_START,1'b0,CPU_ACCESS&CPU_RAM_SEL&|CPU_WE&PHASE2,CPU_ACCESS&CPU_RAM_SEL&~|CPU_WE&PHASE1}     : 4'b0000;
	
	assign RA       = SE_GRANT && CFB_ACCESS ? (SE_RAS_B || (SE_WRITE_B && (PHASE2 || !SE_WRITE_A)) ? SE_ADDR_B[23:2] : SE_ADDR_A[23:2]) : CPU_GRANT && CPU_SPORT_SEL ? {4'b0000,AOUT[10:2],9'b000000000} : AOUT;
	assign RRAS0_N  = SE_GRANT && CFB_ACCESS ? ~CFB_VRAM_SEL      : SE_GRANT || EXTP_GRANT || PLAYER_GRANT ? ~((AG_START|AG_ACCESS|AG_REF) & AG_VRAM_SEL )  : CPU_GRANT ? ~(((CPU_START|CPU_ACCESS) & CPU_VRAM_SEL ) | (CPU_ACCESS & CPU_SPORT_SEL)) : ~(RIGHT_TRANS | CLUT_START | CLUT_RW);
	assign RRAS2_N  = SE_GRANT && CFB_ACCESS ? ~CFB_DRAM0_SEL     : SE_GRANT || EXTP_GRANT || PLAYER_GRANT ? ~((AG_START|AG_ACCESS|AG_REF) & AG_DRAM0_SEL)  : CPU_GRANT ? ~(((CPU_START|CPU_ACCESS) & CPU_DRAM0_SEL)                               ) : 1'b1;
	assign RRAS3_N  = SE_GRANT && CFB_ACCESS ? ~CFB_DRAM1_SEL     : SE_GRANT || EXTP_GRANT || PLAYER_GRANT ? ~((AG_START|AG_ACCESS|AG_REF) & AG_DRAM1_SEL)  : CPU_GRANT ? ~(((CPU_START|CPU_ACCESS) & CPU_DRAM1_SEL)                               ) : 1'b1;
	assign RCAS_N   = SE_GRANT && CFB_ACCESS ? ~((CFB_WE[0]&CE_R)|(CFB_OE[0]&CE_F)) : SE_GRANT || EXTP_GRANT || PLAYER_GRANT ? ~(AG_ACCESS & PHASE2) : CPU_GRANT ? ~(CPU_ACCESS & (CPU_RAM_SEL | CPU_SPORT_SEL) & PHASE2) : ~((RIGHT_TRANS | CLUT_RW) & PHASE2);
	assign RWE_N[1] = SE_GRANT && CFB_ACCESS ? ~(CFB_WE[0]&CE_R)  : SE_GRANT || EXTP_GRANT || PLAYER_GRANT ? ~(AG_ACCESS & AG_WE[0] & PHASE2)        : CPU_GRANT ? ~(CPU_ACCESS & ((CPU_RAM_SEL & CPU_WE[1] & PHASE2) | (CPU_SPORT_SEL & ~CPU_ADDR[13] & CPU_WE[1] & PHASE1))) : 1'b1;
	assign RWE_N[0] = SE_GRANT && CFB_ACCESS ? ~(CFB_WE[0]&CE_R)  : SE_GRANT || EXTP_GRANT || PLAYER_GRANT ? ~(AG_ACCESS & AG_WE[0] & PHASE2)        : CPU_GRANT ? ~(CPU_ACCESS & ((CPU_RAM_SEL & CPU_WE[0] & PHASE2) | (CPU_SPORT_SEL & ~CPU_ADDR[13] & CPU_WE[0] & PHASE1))) : 1'b1;
	assign ROE_N    = SE_GRANT && CFB_ACCESS ? ~(CFB_OE[0]&CE_F)  : SE_GRANT || EXTP_GRANT || PLAYER_GRANT ? ~(AG_ACCESS & ~|AG_WE  & PHASE2)        : CPU_GRANT ? ~(CPU_ACCESS & ((CPU_RAM_SEL & ~|CPU_WE & PHASE2) | (CPU_SPORT_SEL & ~|CPU_ADDR[14:13] & PHASE1))) : ~((RIGHT_TRANS & PHASE1) | (CLUT_RW & PHASE2));
	assign RDSF     =                                               SE_GRANT || EXTP_GRANT || PLAYER_GRANT ? 1'b0                                        : CPU_GRANT ? (CPU_ACCESS & CPU_SPORT_SEL & |CPU_ADDR[14:13] /*& PHASE1*/) :  (RIGHT_SPLIT & PHASE1);
	assign RCODE    = SE_GRANT && CFB_ACCESS ? {CFB_START,1'b0,CFB_WE[0],CFB_OE[0]} :SE_GRANT || EXTP_GRANT || PLAYER_GRANT ? {AG_START,AG_REF,AG_ACCESS&|AG_WE&PHASE2,AG_ACCESS&~|AG_WE&PHASE1} : CPU_GRANT ? {CPU_START,1'b0,CPU_ACCESS&CPU_RAM_SEL&|CPU_WE&PHASE2,CPU_ACCESS&CPU_RAM_SEL&~|CPU_WE&PHASE1}     : 4'b0000;
	
endmodule

