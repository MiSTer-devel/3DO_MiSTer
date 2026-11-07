module MADAM
(
	input              CLK,
	input              RST_N,
	input              EN,
	
	input              CE_R,
	input              CE_F,
	
//	input              RESET_N,
	
	input      [31: 0] A,
	input      [31: 0] DI,
	output     [31: 0] DO,
	
	input      [31: 0] CPU_DI,
	output     [31: 0] CPU_DO,
	input              nRW,
	input              nWB,
	input              nMREQ,
	input              SEQ,
	input              nOPC,
	input              nTRANS,
	input              LOCK,
	output             DBE,
	output             nCPURES,
	output             MCLK_PH1,
	output             MCLK_PH2,
	output             PH1,
	
	input              VCE,
	output reg         LPSC_N,
	output reg         RPSC_N,
	
	output     [23: 2] LA,
	output             LRAS0_N,
	output             LRAS2_N,
	output             LRAS3_N,
	output             LCAS_N,
	output     [ 1: 0] LWE_N,
	output             LOE_N,
	output reg         LSC,
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
	output reg         RSC,
	output             RDSF,
	input              RQSF,
	output     [ 3: 0] RCODE,
	
	input              DMAREQ,
	input      [ 4: 0] DMACH,
	output     [ 2: 0] CLC,
	input              CREADY_N,
	input              PCSC,
	input              MIRQ_N,
	output             PB_INT,//
	
	input              PBDIN,
	output             PBDOUT,
	output             PBCLK,
	
	input      [31: 0] PDI,
	output     [ 7: 0] PDO,
	output             ROMCS_N,
	output             SRAMW_N,
	output             SRAMR_N,
	
	output             CLIO_OE,
	
	output             SYSRAM_EN,
	
	output             FIELD,
	
	input              DBG_SPR_EN,
	input      [ 7: 0] DBG_EXT
	
`ifdef DEBUG
	                  ,
	output     [23: 0] DBG_LA,
	output     [23: 0] DBG_RA,
	output reg         FAILED_AREA,
	output reg         DBG_HOOK
`endif
);

	import P3DO_PKG::*; 

	parameter bit [31: 0] REV = 32'h01020000;
	
	bit  [31: 0] MSYS;
	bit  [31: 0] MCTL;
	
	//Math
	bit  [ 3: 0] MATH_CTRL;
	bit  [ 5: 0] MATH_MODE;
	bit  [63: 0] MATH_DIV_N;
	bit  [31: 0] MATH_DIV_Z;
	bit  [63: 0] MATH_DIV_RES;
	bit          MATH_ON;
	bit  [ 1: 0] MATH_MCOL,MATH_MROW;
	bit  [63: 0] MATH_ACC;
	bit  [ 1: 0] MATH_RES_ROW;
	bit          MATH_RES_DONE;
	bit          MATH_BANK,MATH_WORK_BANK;
	
	bit          PHASE1,PHASE2;
	BusState_t   BUS_STATE;
	bit          BUS_PB;
	AddrGenCtl_t DMA_CTL;
	
	//CPU
	bit          CPU_GRANT;
	bit          CPU_READY;
	bit          CPU_ACCESS;
	bit          CPU_START;
	bit  [ 3: 0] CPU_WE;
	AddrGenCtl_t CPU_AG_CTL;
	
	//EXTP
	bit          CLIO_REQ;
	bit          EXTP_REQ;
	bit          EXTP_ACK;
	bit          EXTP_GRANT;
	AddrGenCtl_t EXTP_AG_CTL;
	bit  [ 2: 0] EXTP_NEXT;
	bit  [10: 0] H_CNT;
	bit  [ 9: 0] V_CNT;
	
	//AG
	bit  [23: 2] MADR;
	bit  [31: 0] AG_MDTO;
	bit          MWR;
	bit          LMIDLINE_REQ;
	bit          RMIDLINE_REQ;
	bit          AG_PBI;
	bit          AG_REG_OVF;
	bit          AG_REG_ZERO;

	//SE
	bit  [31: 0] SE_MDTO;
	bit  [ 2: 0] SCOBLD_REQ;
	bit  [ 2: 0] SCOB_SEL;
	bit  [ 1: 0] SPRDATA_REQ;
	bit  [ 1: 0] SPR_SEL;
	bit          SPRDRAW_REQ;
	bit  [ 2: 0] CFB_SEL;
	bit          CFB_SUSPEND;
	bit          SPRPAUS_REQ;
	bit          SPREND_REQ;
	bit          SE_ACK;
	bit  [ 3: 0] SE_STAT;
	AddrGenCtl_t SE_AG_CTL;
	bit          SE_GRANT;
	bit  [23: 1] SE_ADDR_A,SE_ADDR_B;
	bit          SE_WRITE_A,SE_WRITE_B;
	bit          SE_RAS_A,SE_RAS_B;
	bit          SE_READ;

	//S-PORT
	bit          CLUTWR_REQ;
	bit          CLUTWR_ACK;
	bit          CLUTWR_FORCE;
	bit          VIDOUT_REQ;
	bit          VIDOUT_PFL;
	bit          VIDMID_REQ;
	bit          VIDMID_CURR,VIDMID_FIRST;
	bit          VIDOUT_ACK;
	AddrGenCtl_t SPORT_AG_CTL;
	bit          SPORT_GRANT;
	bit          SPORT_LINE0;
	bit          SPORT_LSC,SPORT_RSC;

	//PLAYER BUS
	bit  [31: 0] PLAYER_MDTO;
	AddrGenCtl_t PLAYER_AG_CTL;
	bit          PLAYER_GRANT;
	bit          PLAYER_REQ;
	bit          PLAYER_INT;
	bit          REFRESH_REQ;
	
	//SLOW BUS
	bit          BOOT_ROM;
	
	typedef enum bit [2:0] {
		MATH_IDLE,
		MATH_MUL_MATRIX,
		MATH_MATRIX_WAIT0,
		MATH_MATRIX_WAIT1,
		MATH_DIV,
		MATH_MUL,
		MATH_MUL_WAIT
	} MathState_t;
	MathState_t MATH_ST;
	
	wire CPU_REG_SEL = (A[31:16] == 16'h0330 && CPU_GRANT);
	wire REG_CTRL_SEL = CPU_REG_SEL && A[15:0] >= 16'h0000 && A[15:0] <= 16'h00FF;
	wire REG_SE_SEL = CPU_REG_SEL && A[15:0] >= 16'h0100 && A[15:0] <= 16'h01FF;
	wire REG_DMA_SEL = CPU_REG_SEL && A[15:0] >= 16'h0400 && A[15:0] <= 16'h05FF;
	wire REG_MATRIX_SEL = CPU_REG_SEL && A[15:0] >= 16'h0600 && A[15:0] <= 16'h06FF;
	wire REG_MATH_SEL = CPU_REG_SEL && A[15:0] >= 16'h07F0 && A[15:0] <= 16'h07FF;
	always @(posedge CLK or negedge RST_N) begin
		bit          MATH_START;
		bit  [31: 0] MATH_M,MATH_V;
		bit  [63: 0] MATH_RES;
		bit          MATH_STEP,MATH_CALC_ROW_START,MATH_CALC_ROW_END;
		bit  [ 1: 0] MATH_CALC_ROW;
		bit  [ 1: 0] MATRIX_LAST;
		bit  [ 5: 0] DIV_DELAY;
		
		if (!RST_N) begin
			MSYS <= 32'h00000029;
			MCTL <= 32'h00000000;
			BOOT_ROM <= 1;
			
			MATH_ST <= MATH_IDLE;
			MATH_CTRL <= '0;
			MATH_MODE <= '0;
			MATH_ON <= 0;
			MATH_WORK_BANK <= 0;
		end
		else if (CE_R) begin
			if ((A[31:20] == 12'h030 || A[31:20] == 12'h031) && !nRW) begin//???
				if (BOOT_ROM) BOOT_ROM <= 0;
			end
				
			if (REG_CTRL_SEL && nRW) begin
				case ({A[7:2],2'b00})
					8'h04: MSYS <= CPU_DI;
					8'h08: MCTL <= CPU_DI;
					default:;
				endcase
			end
			
			if (PLAYER_INT) begin
				MCTL[15] <= 0;
			end
			
			
			if (REG_MATH_SEL && nRW && MCLK_PH2) begin
				case ({A[3:2],2'b00})
					4'h0: MATH_CTRL <= MATH_CTRL | CPU_DI[3:0];
					4'h4: MATH_CTRL <= MATH_CTRL & ~CPU_DI[3:0];
					4'hC: begin
						MATH_MODE <= CPU_DI[5:0];
						MATH_START <= |CPU_DI[5:0];
//						MATH_CTRL[3] <= ~MATH_CTRL[3];
						MATH_WORK_BANK <= MATH_BANK;
						MATH_BANK <= ~MATH_BANK;
					end
					default:;
				endcase
			end
			if (REG_MATRIX_SEL && nRW && MCLK_PH2) begin
				case ({A[7:2],2'b00})
					8'h80: MATH_DIV_N[63:32] <= CPU_DI;
					8'h84: MATH_DIV_N[31: 0] <= CPU_DI;
					default:;
				endcase
			end
			MATRIX_LAST = (MATH_MODE[1] ? 2'd2 : 2'd3);
			
			{MATH_STEP,MATH_CALC_ROW_START,MATH_CALC_ROW_END} <= '0;
			case (MATH_ST)
				MATH_IDLE: begin
					MATH_ON <= 0;
					if (MATH_START) begin
						MATH_START <= 0;
						MATH_ON <= 1;
						MATH_ST <= MATH_MUL_MATRIX;
					end
				end
				
				MATH_MUL_MATRIX: begin
					MATH_M <= MATRIX_DO;
					MATH_V <= !MATH_WORK_BANK ? VECTOR0_DO : VECTOR1_DO;
					MATH_STEP <= 1;
					MATH_CALC_ROW_START <= (MATH_MCOL == 2'd0);
					MATH_CALC_ROW_END <= (MATH_MCOL == MATRIX_LAST);
					MATH_CALC_ROW <= MATH_MROW;
					MATH_MCOL <= MATH_MCOL + 2'd1;
					if (MATH_MCOL == MATRIX_LAST) begin
						MATH_MCOL <= '0;
						MATH_MROW <= MATH_MROW + 2'd1;
						if (MATH_MROW == MATRIX_LAST) begin
							MATH_MROW <= '0;
							MATH_ST <= MATH_MATRIX_WAIT0;
						end
					end
				end
				
				MATH_MATRIX_WAIT0: begin
					if (MATH_MODE == 6'h03) begin
						MATH_ST <= MATH_MATRIX_WAIT1;
					end else begin
						MATH_ST <= MATH_IDLE;
					end
				end
				
				MATH_MATRIX_WAIT1: begin
					MATH_DIV_Z <= MATH_ACC[47:16];
					DIV_DELAY <= 6'd5;
					MATH_ST <= MATH_DIV;
				end
				
				MATH_DIV: begin
					DIV_DELAY <= DIV_DELAY - 1'd1;
					if (DIV_DELAY <= 0) begin
						MATH_M <= MATH_DIV_RES[47:16];
						MATH_ST <= MATH_MUL;
					end
				end
				
				MATH_MUL: begin
					MATH_V <= !MATH_WORK_BANK ? MATH_OUT0_DO : MATH_OUT1_DO;
					MATH_STEP <= 1;
					MATH_CALC_ROW_START <= 1;
					MATH_CALC_ROW_END <= 1;
					MATH_CALC_ROW <= MATH_MROW;
					MATH_MROW <= MATH_MROW + 2'd1;
					if (MATH_MROW == 2'd1) begin
						MATH_MROW <= '0;
						MATH_ST <= MATH_MUL_WAIT;
					end
				end
				
				MATH_MUL_WAIT: begin
					MATH_ST <= MATH_IDLE;
				end
			endcase
			
			MATH_RES = ($signed(MATH_M) * $signed(MATH_V)) + (MATH_CALC_ROW_START ? '0 : $signed(MATH_ACC));
			{MATH_RES_DONE} <= '0;
			if (MATH_STEP) begin
				MATH_ACC <= MATH_RES;
				MATH_RES_ROW <= MATH_CALC_ROW;
				MATH_RES_DONE <= MATH_CALC_ROW_END;
			end
		end
	end
	
	madam_div div (/*.clock(CLK),*/ .numer(MATH_DIV_N), .denom(MATH_DIV_Z), .quotient(MATH_DIV_RES));
	
//	wire         MATH_VECTOR_BANK = 0;//MATH_CTRL[4];
	
	wire         MATRIX_WE = REG_MATRIX_SEL && A[7:0] <= 8'h3F && nRW && MCLK_PH2;
	wire [ 3: 0] MATRIX_RA = {MATH_MROW,MATH_MCOL};
	bit  [31: 0] MATRIX_DO;
	MADAM_MATH_MATRIX MATH_MATRIX (.CLK(CLK), .WA(A[5:2]), .DIN(CPU_DI), .WE(MATRIX_WE & CE_R), .RA(MATRIX_RA), .DOUT(MATRIX_DO));
	
	bit  [ 1: 0] VECTOR_N;
	
	wire         VECTOR_WE = REG_MATRIX_SEL && A[7:0] >= 8'h40 && A[7:0] <= 8'h4F && nRW && MCLK_PH2;
	wire [ 1: 0] VECTOR0_RA = !MATH_WORK_BANK && MATH_ON ? MATH_MCOL : A[3:2];
	bit  [31: 0] VECTOR0_DO;
	MADAM_MATH_VECTOR MATH_VECTOR0 (.CLK(CLK), .WA(A[3:2]), .DIN(CPU_DI), .WE(VECTOR_WE & ~MATH_BANK & CE_R), .RA(VECTOR0_RA), .DOUT(VECTOR0_DO));
	
	wire [ 1: 0] VECTOR1_RA =  MATH_WORK_BANK && MATH_ON ? MATH_MCOL : A[3:2];
	bit  [31: 0] VECTOR1_DO;
	MADAM_MATH_VECTOR MATH_VECTOR1 (.CLK(CLK), .WA(A[3:2]), .DIN(CPU_DI), .WE(VECTOR_WE &  MATH_BANK & CE_R), .RA(VECTOR1_RA), .DOUT(VECTOR1_DO));
	
	wire [ 1: 0] MATH_OUT_WA = MATH_RES_ROW;
	wire [31: 0] MATH_OUT_DIN = MATH_ACC[47:16];
	wire         MATH_OUT_WE = MATH_RES_DONE;
	wire [ 1: 0] MATH_OUT0_RA = !MATH_WORK_BANK && MATH_ON ? MATH_MROW : A[3:2];
	wire [ 1: 0] MATH_OUT1_RA =  MATH_WORK_BANK && MATH_ON ? MATH_MROW : A[3:2];
	bit  [31: 0] MATH_OUT0_DO,MATH_OUT1_DO;
	MADAM_MATH_VECTOR MATH_OUT0 (.CLK(CLK), .WA(MATH_OUT_WA), .DIN(MATH_OUT_DIN), .WE(MATH_OUT_WE & ~MATH_WORK_BANK & CE_R), .RA(MATH_OUT0_RA), .DOUT(MATH_OUT0_DO));
	MADAM_MATH_VECTOR MATH_OUT1 (.CLK(CLK), .WA(MATH_OUT_WA), .DIN(MATH_OUT_DIN), .WE(MATH_OUT_WE &  MATH_WORK_BANK & CE_R), .RA(MATH_OUT1_RA), .DOUT(MATH_OUT1_DO));
	
	bit  [31: 0] REG_DO;
	always @(posedge CLK) begin
		if (REG_CTRL_SEL) 
			case ({A[7:2],2'b00})
				8'h00: REG_DO <= REV;
				8'h04: REG_DO <= MSYS;
				8'h08: REG_DO <= MCTL;
				8'h28: REG_DO <= {24'h000000,SE_STAT,4'h0};
				default: REG_DO <= '0;
			endcase
		else if (REG_DMA_SEL)
			REG_DO <= AG_MDTO;
		else if (REG_MATRIX_SEL)
			     if (                   A[7:0] <= 8'h3F) REG_DO <= MATRIX_DO;
			else if (A[7:0] >= 8'h40 && A[7:0] <= 8'h4F) REG_DO <= !MATH_BANK ? VECTOR0_DO : VECTOR1_DO;
			else if (A[7:0] >= 8'h50 && A[7:0] <= 8'h5F) REG_DO <= VECTOR1_DO;
			else if (A[7:0] >= 8'h60 && A[7:0] <= 8'h6F) REG_DO <= !MATH_BANK ? MATH_OUT0_DO : MATH_OUT1_DO;
			else
				case ({A[7:2],2'b00})
					8'h80:   REG_DO <= MATH_DIV_N[63:32];
					8'h84:   REG_DO <= MATH_DIV_N[31: 0];
					default: REG_DO <= '0;
				endcase
		else if (REG_MATH_SEL)
			case ({A[3:2],2'b00})
				4'h0,
				4'h4: REG_DO <= {28'h0000000,MATH_CTRL};
				4'h8: REG_DO <= {31'h00000000,MATH_ON};
				4'hC: REG_DO <= {26'h0000000,MATH_MODE};
				default: REG_DO <= '0;
			endcase
		else
			REG_DO <= '0;
	end
	
	bit  [23: 0] DRAM0_END,DRAM1_START,DRAM1_END,VRAM_START,VRAM_END;
	always_comb begin
		case (MSYS[4:3])
			2'b00: begin DRAM0_END = 24'h000000; DRAM1_START = 24'h000000; end
			2'b01: begin DRAM0_END = 24'h0FFFFF; DRAM1_START = 24'h100000; end
			2'b10: begin DRAM0_END = 24'h3FFFFF; DRAM1_START = 24'h400000; end
			2'b11: begin DRAM0_END = 24'hDFFFFF; DRAM1_START = 24'hE00000; end//??
		endcase
		case (MSYS[6:5])
			2'b00: begin DRAM1_END = DRAM1_START + 24'h000000; VRAM_START = DRAM1_START + 24'h000000; end
			2'b01: begin DRAM1_END = DRAM1_START + 24'h0FFFFF; VRAM_START = DRAM1_START + 24'h100000; end
			2'b10,
			2'b11: begin DRAM1_END = DRAM1_START + 24'h3FFFFF; VRAM_START = DRAM1_START + 24'h400000; end
		endcase
		VRAM_END = VRAM_START + 24'h100000;
	end
	wire CPU_DRAM0_SEL = (A[31:24] == 8'h00 && A[23:0] >= 32'h00000000 && A[23:0] <= DRAM0_END && |MSYS[4:3] && !BOOT_ROM);
	wire CPU_DRAM1_SEL = (A[31:24] == 8'h00 && A[23:0] >= DRAM1_START  && A[23:0] <= DRAM1_END && |MSYS[6:5] && !BOOT_ROM);
	wire CPU_VRAM_SEL  = (A[31:24] == 8'h00 && A[23:0] >= VRAM_START   && A[23:0] <= VRAM_END              );
	wire CPU_CLIO_SEL = (A[31:20] == 12'h034);
	wire CPU_SLOW_SEL = (A[31:20] == 12'h030 || A[31:20] == 12'h031 || (A[31:20] == 12'h000 && BOOT_ROM));
	wire CPU_SPORT_SEL = (A[31:20] == 12'h032 && CPU_GRANT);
	
	MADAM_ARB ARB
	(
		.CLK(CLK),
		.RST_N(RST_N),
		.EN(EN),
		
		.CE_F(CE_F),
		.CE_R(CE_R),
		
		.PHASE1(PHASE1),
		.PHASE2(PHASE2),
		
		.CPU_GRANT(CPU_GRANT),
		.CPU_READY(CPU_READY),
		.CPU_AG_CTL(CPU_AG_CTL),
		
		.PBI(AG_PBI),
		
		.CLIO_REQ(CLIO_REQ),
		.EXTP_REQ(EXTP_REQ),
		.EXTP_ACK(EXTP_ACK),
		.EXTP_GRANT(EXTP_GRANT),
		.EXTP_AG_CTL(EXTP_AG_CTL),
		.EXTP_NEXT(EXTP_NEXT),
		
		.SCOBLD_REQ(SCOBLD_REQ),
		.SCOB_SEL(SCOB_SEL),
		.SPRDATA_REQ(SPRDATA_REQ),
		.SPR_SEL(SPR_SEL),
		.SPRDRAW_REQ(SPRDRAW_REQ),
		.CFB_SEL(CFB_SEL),
		.CFB_SUSPEND(CFB_SUSPEND),
		.SPRPAUS_REQ(SPRPAUS_REQ),
		.SPREND_REQ(SPREND_REQ),
		.SE_ACK(SE_ACK),
		.SE_GRANT(SE_GRANT),
		.SE_AG_CTL(SE_AG_CTL),
		
		.CLUTWR_REQ(CLUTWR_REQ),
		.CLUTWR_ACK(CLUTWR_ACK),
		.VIDOUT_REQ(VIDOUT_REQ),
		.VIDOUT_ACK(VIDOUT_ACK),
		.VIDMID_REQ(VIDMID_REQ),
		.VIDMID_CURR(VIDMID_CURR),
		.VIDMID_FIRST(VIDMID_FIRST),
		.SPORT_GRANT(SPORT_GRANT),
		.SPORT_AG_CTL(SPORT_AG_CTL),
		
		.PLAYER_REQ(PLAYER_REQ),
		.REFRESH_REQ(REFRESH_REQ),
		.PLAYER_GRANT(PLAYER_GRANT),
		.PLAYER_AG_CTL(PLAYER_AG_CTL),
		
		.BUS_STATE(BUS_STATE),
		.BUS_PB(BUS_PB),
		.DMA_CTL(DMA_CTL),
		
		.DBG_EXT(DBG_EXT)
	);
	
	MADAM_CPUIF CPUIF
	(
		.CLK(CLK),
		.RST_N(RST_N),
		.EN(EN),
		
		.CE_R(CE_R),
		.CE_F(CE_F),
		
		.PHASE1(PHASE1),
		.PHASE2(PHASE2),
		
		.A(A),
		.nRW(nRW),
		.nWB(nWB),
		.nMREQ(nMREQ),
		.SEQ(SEQ),
		.nOPC(nOPC),
		.nTRANS(nTRANS),
		.LOCK(LOCK),
		.DBE(DBE),
		.nRES(nCPURES),
		.MCLK_PH1(MCLK_PH1),
		.MCLK_PH2(MCLK_PH2),
		
		.GRANT(CPU_GRANT),
		.READY(CPU_READY),
		.ACCESS(CPU_ACCESS),
		.START(CPU_START),
		.WE(CPU_WE),
		.AG_PBI(AG_PBI),
		.AG_CTL(CPU_AG_CTL),
		
		.SLOW_SEL(0/*CPU_SLOW_SEL*/),
		.CLIO_SEL(CPU_CLIO_SEL),
		.CLIO_RDY(~CREADY_N),
		.WAIT(0)
	);
	
	MADAM_EXTPIF EXTPIF
	(
		.CLK(CLK),
		.RST_N(RST_N),
		.EN(EN),
		
		.CE_R(CE_R),
		.CE_F(CE_F),
		
		.MCLK_PH1(MCLK_PH1),
		.MCLK_PH2(MCLK_PH2),
		.CPU_GRANT(CPU_GRANT),
		.CPU_RW(nRW),
		.CPU_SEL(CPU_CLIO_SEL),
		
		.MDTI(AG_MDTO),
		.BUS_STATE(BUS_STATE),
		.BUS_PB(BUS_PB),
		.GRANT(EXTP_GRANT),
		.DMA_REG_OVF(AG_REG_OVF),
		.DMA_REG_ZERO(AG_REG_ZERO),
		.AG_PBI(AG_PBI),
		.AG_CTL(EXTP_AG_CTL),
		
		.CPU_REQ(CLIO_REQ),
		.DMA_REQ(EXTP_REQ),
		.DMA_ACK(EXTP_ACK),
		.NEXT(EXTP_NEXT),
		
		.PLAYER_INT(PLAYER_INT),
		
		.H_CNT(H_CNT),
		.V_CNT(V_CNT),
		.FORCE_CLUT(),
		
		.VCE(VCE),
		.DMAREQ(DMAREQ),
		.DMACH(DMACH),
		.CCODE(CLC),
		.CREADY_N(CREADY_N),
		.PCSC(PCSC)
	);
	
	bit  [31: 0] A_FF;
	always @(posedge CLK or negedge RST_N) begin
		bit          A_LATCH;
		
		if (!RST_N) begin
			A_LATCH <= 1;
			A_FF <= '0;
		end
		else begin
			A_LATCH <= MCLK_PH2;
			if (A_LATCH) begin
				A_FF <= A;
			end
		end
	end
	
	MADAM_AG AG
	(
		.CLK(CLK),
		.RST_N(RST_N),
		.EN(EN),
		
		.CE_F(CE_F),
		.CE_R(CE_R),
		
		.PHASE1(PHASE1),
		.PHASE2(PHASE2),
		
		.CPU_ADDR(A_FF[23:2]),
		.CPU_ACCESS(CPU_ACCESS),
		.CPU_START(CPU_START),
		.CPU_DRAM0_SEL(CPU_DRAM0_SEL),
		.CPU_DRAM1_SEL(CPU_DRAM1_SEL),
		.CPU_VRAM_SEL(CPU_VRAM_SEL),
		.CPU_SPORT_SEL(CPU_SPORT_SEL),
		.CPU_WE(CPU_WE),
		.CPU_GRANT(CPU_GRANT),
		
		.MEM_SIZE(MSYS[6:0]),
		.DRAM_EN(~BOOT_ROM),
		
		.EXTP_GRANT(EXTP_GRANT),
		
		.SE_ADDR_A(SE_ADDR_A),
		.SE_ADDR_B(SE_ADDR_B),
		.SE_RAS_A(SE_RAS_A),
		.SE_RAS_B(SE_RAS_B),
		.SE_WRITE_A(SE_WRITE_A),
		.SE_WRITE_B(SE_WRITE_B),
		.SE_READ(SE_READ),
		.SE_GRANT(SE_GRANT),
		
		.PLAYER_GRANT(PLAYER_GRANT),
		
		.LINE0(SPORT_LINE0),
		.CLUTWR_FORCE(CLUTWR_FORCE),
		.VIDOUT_PFL(VIDOUT_PFL),
		.LMIDLINE_REQ(LMIDLINE_REQ),
		.RMIDLINE_REQ(RMIDLINE_REQ),
		
		.MADR(MADR),
		.MDTI(DI),
		.MDTO(AG_MDTO),
		.MWR(MWR),
		.BUS_STATE(BUS_STATE),
		.DMA_CTL(DMA_CTL),
		.PBI(AG_PBI),
		.REG_OVF(AG_REG_OVF),
		.REG_ZERO(AG_REG_ZERO),
		
		.LA(LA),
		.LRAS0_N(LRAS0_N),
		.LRAS2_N(LRAS2_N),
		.LRAS3_N(LRAS3_N),
		.LCAS_N(LCAS_N),
		.LWE_N(LWE_N),
		.LOE_N(LOE_N),
		.LDSF(LDSF),
		.LQSF(LQSF),
		.LCODE(LCODE),
		.RA(RA),
		.RRAS0_N(RRAS0_N),
		.RRAS2_N(RRAS2_N),
		.RRAS3_N(RRAS3_N),
		.RCAS_N(RCAS_N),
		.RWE_N(RWE_N),
		.ROE_N(ROE_N),
		.RDSF(RDSF),
		.RQSF(RQSF),
		.RCODE(RCODE)
	);
	
`ifdef DEBUG
	assign DBG_LA = {LA,2'b00};
	assign DBG_RA = {RA,2'b00};
`endif
	
	MADAM_SE SE
	(
		.CLK(CLK),
		.RST_N(RST_N),
		.EN(EN),
		
		.CE_R(CE_R),
		.CE_F(CE_F),
		
		.CPU_DI(CPU_DI),
		.MADR(MADR),
		.MDTI(DI),
		.MDTO(SE_MDTO),
		.MWR(MWR),
		.SEL(REG_SE_SEL),
		.BUS_STATE(BUS_STATE),
		.BUS_PB(BUS_PB),
		.GRANT(SE_GRANT),
		.DMA_REG_ZERO(AG_REG_ZERO),
		.AG_CTL(SE_AG_CTL),
		.CFB_ADDR_A(SE_ADDR_A),
		.CFB_ADDR_B(SE_ADDR_B),
		.CFB_RAS_A(SE_RAS_A),
		.CFB_RAS_B(SE_RAS_B),
		.CFB_WRITE_A(SE_WRITE_A),
		.CFB_WRITE_B(SE_WRITE_B),
		.CFB_READ(SE_READ),
		
		.INT_REQ(~MIRQ_N),
		
		.SCOBLD_REQ(SCOBLD_REQ),
		.SCOB_SEL(SCOB_SEL),
		.SPRDATA_REQ(SPRDATA_REQ),
		.SPR_SEL(SPR_SEL),
		.SPRDRAW_REQ(SPRDRAW_REQ),
		.CFB_SEL(CFB_SEL),
		.CFB_SUSPEND(CFB_SUSPEND),
		.SPRPAUS_REQ(SPRPAUS_REQ),
		.SPREND_REQ(SPREND_REQ),
		.ACK(SE_ACK),
		.STAT(SE_STAT),
		
		.DBG_SPR_EN(DBG_SPR_EN),
		.DBG_EXT(DBG_EXT)
	);
	
	MADAM_SPORT SPORT
	(
		.CLK(CLK),
		.RST_N(RST_N),
		.EN(EN),
		
		.CE_R(CE_R),
		.CE_F(CE_F),
		
		.MDTI(DI),
		.BUS_STATE(BUS_STATE),
		.GRANT(SPORT_GRANT),
		.AG_CTL(SPORT_AG_CTL),
		.LMIDLINE_REQ(LMIDLINE_REQ),
		.RMIDLINE_REQ(RMIDLINE_REQ),
		
		.CLUTXEN(MCTL[13]),
		.VSCTXEN(MCTL[14]),
		
		.LINE0(SPORT_LINE0),
		.CLUTWR_REQ(CLUTWR_REQ),
		.CLUTWR_ACK(CLUTWR_ACK),
		.CLUTWR_FORCE(CLUTWR_FORCE),
		.VIDOUT_REQ(VIDOUT_REQ),
		.VIDOUT_PFL(VIDOUT_PFL),
		.VIDMID_REQ(VIDMID_REQ),
		.VIDMID_CURR(VIDMID_CURR),
		.VIDMID_FIRST(VIDMID_FIRST),
		.VIDOUT_ACK(VIDOUT_ACK),
		
		.VCE(VCE),
		.PCSC(PCSC),
		.LSC(SPORT_LSC),
		.RSC(SPORT_RSC),
		
		.FIELD(FIELD)
	);
	
	MADAM_PLAYER PLAYER
	(
		.CLK(CLK),
		.RST_N(RST_N),
		.EN(EN),
		
		.CE_R(CE_R),
		.CE_F(CE_F),
		
		.MDTI(DI),
		.MDTO(PLAYER_MDTO),
		.BUS_STATE(BUS_STATE),
		.GRANT(PLAYER_GRANT),
		.DMA_REG_OVF(AG_REG_OVF),
		.AG_CTL(PLAYER_AG_CTL),
		
		.PLAYXEN(MCTL[15]),
		
		.VCE(VCE),
		.H_CNT(H_CNT),
		.V_CNT(V_CNT),
		
		.PLAY_REQ(PLAYER_REQ),
		.PLAY_INT(PLAYER_INT),
		
		.REF_REQ(REFRESH_REQ),
		
		.PBDI(PBDIN),
		.PBDO(PBDOUT),
		.PBCLK(PBCLK)
	);
	assign PB_INT = PLAYER_INT;
	
	bit  [31: 0] SLOW_MDTO;
	MADAM_SLOWBUS SLOWBUS
	(
		.CLK(CLK),
		.RST_N(RST_N),
		.EN(EN),
		
		.CE_R(CE_R),
		.CE_F(CE_F),
		
		.ADDR(A[31:16]),
		.WR(nRW),
		.SEL(CPU_SLOW_SEL & CPU_ACCESS),
		.MDTI(CPU_DI),
		.MDTO(SLOW_MDTO),
		
		.PDI(PDI),
		.PDO(PDO),
		.ROMCS_N(ROMCS_N),
		.SRAMW_N(SRAMW_N),
		.SRAMR_N(SRAMR_N)
	);
	
	always @(posedge CLK) begin
//		if (VCE) begin
			LSC <= SPORT_LSC;
			RSC <= SPORT_RSC;
//		end
	end
	assign LPSC_N = ~SPORT_LSC;
	assign RPSC_N = ~SPORT_RSC;
	
	assign DO = SE_GRANT ? SE_MDTO : 
//					EXTP_GRANT ? EXTP_MDTO : '0;
					PLAYER_GRANT ? PLAYER_MDTO : '0;
					
	assign CPU_DO = CPU_SLOW_SEL ? SLOW_MDTO :
					    REG_SE_SEL ? SE_MDTO :
	                CPU_REG_SEL ? REG_DO : '0;
					
	assign CLIO_OE = EXTP_GRANT;
	assign SYSRAM_EN = ~BOOT_ROM;
	
	assign PH1 = PHASE1;
	
`ifdef DEBUG
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N)
			FAILED_AREA <= 0;
		else
			FAILED_AREA <= ~((A >= 32'h00000000 && A <= 32'h001FFFFF) || 
								  (A >= 32'h00200000 && A <= 32'h002FFFFF) ||
								  //(A >= 32'h00300000 && A <= 32'h00FFFFFF) ||//?
								  (A >= 32'h03000000 && A <= 32'h030FFFFF) ||
								  (A >= 32'h03100000 && A <= 32'h0310FFFF) ||
								  (A >= 32'h03140000 && A <= 32'h0315FFFF) ||
								  (A >= 32'h03180000 && A <= 32'h0318FFFF) ||
								  (A >= 32'h03200000 && A <= 32'h032FFFFF) ||
								  (A >= 32'h03300000 && A <= 32'h033007FF) ||
								  (A >= 32'h03400000 && A <= 32'h0340C00F));
								  
			DBG_HOOK <= ((A == 32'h000CD5D4 + 32'h24 || 
			              A == 32'h000CD594 + 32'h24 ||
			              A == 32'h000CDD54 + 32'h24 ||
			              A == 32'h000CDD94 + 32'h24 ||
			              A == 32'h000CDDD4 + 32'h24 ||
			              A == 32'h000CD5D4 + 32'h24 ||
			              A == 32'h000CDE14 + 32'h24 ||
			              A == 32'h000CD554 + 32'h24 ||
			              A == 32'h000CD514 + 32'h24 ||
			              A == 32'h000CD5D4 + 32'h24 ||
			              A == 32'h000CD414 + 32'h24 ||
			              A == 32'h000CD4D4 + 32'h24 ||
			              A == 32'h000CD314 + 32'h24 ||
			              A == 32'h000CD494 + 32'h24 ||
			              A == 32'h000CD454 + 32'h24 ||
			              A == 32'h000CD394 + 32'h24 ||
			              A == 32'h000CD354 + 32'h24 ||
			              A == 32'h000CD0D4 + 32'h24 ||
			              A == 32'h000CD3D4 + 32'h24 ||
			              A == 32'h000CD2D4 + 32'h24 ||
			              A == 32'h000CDD14 + 32'h24 ||
			              A == 32'h000CDCD4 + 32'h24 ||
			              A == 32'h000CDC94 + 32'h24 ||
			              A == 32'h000CDC54 + 32'h24 ||
			              A == 32'h000CD254 + 32'h24 ||
			              A == 32'h000CD214 + 32'h24 ||
			              A == 32'h000CD094 + 32'h24 ||
			              A == 32'h000CD294 + 32'h24 ||
			              A == 32'h000CD054 + 32'h24) && DI[31:16] == 16'h0006 && nRW);
	end
`endif

endmodule
