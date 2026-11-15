// synopsys translate_off
`define SIM
// synopsys translate_on

module P3DO
`ifdef SIM
#(
	parameter dsp_nram_file = ""
)
`endif
(
	input              CLK,
	input              RST_N,
	input              EN,
	input              PAUSE,
	input              DSP_PAUSE,
	
	input              PAL,
	
	input              CE_R,
	input              CE_F,
	
	input              PON,
	
	output     [23: 2] LA,
	output             LRAS0_N,
	output             LRAS2_N,
	output             LRAS3_N,
	output             LCAS_N,
	output     [ 1: 0] LWE_N,
	output             LOE_N,
	output             LDSF,
	output             LSC,
	input              LQSF,
	output     [ 3: 0] LCODE,
	output     [23: 2] RA,
	output             RRAS0_N,
	output     [23: 2] LA_COL,       // the memory bus for ddram.sv (MADAM_AG)
	output             LRAS0_COL_N,
	output     [23: 2] RA_COL,
	output             RRAS0_COL_N,
	output             RRAS2_N,
	output             RRAS3_N,
	output             RCAS_N,
	output     [ 1: 0] RWE_N,
	output             ROE_N,
	output             RDSF,
	output             RSC,
	input              RQSF,
	output     [ 3: 0] RCODE,
	input      [31: 0] DI,
	output     [31: 0] DO,
	
	input              PBDIN,
	output             PBDOUT,
	output             PBCLK,
	
	output     [19: 0] PA,
	input      [31: 0] PDI,
	output     [ 7: 0] PDO,
	output             ROMCS_N,
	output             SRAMW_N,
	output             SRAMR_N,
	
	output             ROM_SEL,
	
	input      [ 7: 0] CDDI,
	output reg [ 7: 0] CDDO,
	output reg         CDEN_N,
	output reg         CDCMD_N,
	output reg         CDHWR_N,
	output reg         CDHRD_N,
	output reg         CDRST_N,
	input              CDSTEN_N,
	input              CDDTEN_N,
	input              CDMDCHG,
	
	output             MCLK_CE,
	
	input              VCE,
	input      [31: 0] S,
	
	output             FIELD,
	
	// the VRAM access in progress is the CPU's SPORT access (vram.sv)
	output             VRAM_SP_CPU,

	input              VCLK,
	output     [23: 0] RGB,
	output             HS_N,
	output             VS_N,
	output             HBLK_N,
	output             VBLK_N,
	output             DCLK,
	
	input              ACLK_CE,
	output     [15: 0] AUDIOL,
	output     [15: 0] AUDIOR,
	
	
	input              HINTREPOL_DISABLE,
	input              VINTREPOL_DISABLE,
	input      [ 2: 0] SCRN_EN,
	input      [ 7: 0] DBG_EXT
	
`ifdef DEBUG
	                  ,
	output reg [7: 0] DBG_CLK_DIV,
	output reg [31: 0] DBG_CLK_CNT,
	output reg         DBG_HOOK,
	output reg [ 7: 0] DBG_HOOK2,
	output reg [31: 0] DBG_B8E5C,DBG_B8E8C,DBG_B8D18,DBG_B8D9C,DBG_B8DA0,
	output reg [31: 0] DBG_B9144,DBG_B9148,DBG_B917C,DBG_B9180
`endif
);

	bit  [31: 0] CPU_A;
	bit  [31: 0] CPU_DI;
	bit  [31: 0] CPU_DO;
	bit          CPU_nWB;
	bit          CPU_nRW;
	bit          CPU_nMREQ;
	bit          CPU_SEQ;
	bit          CPU_nOPC;
	bit          CPU_nTRANS;
	bit          CPU_LOCK;
	bit          CPU_DBE;
	bit          CPU_nRES;
	bit          MCLK_PH1,MCLK_PH2;
	
	bit  [31: 0] MADAM_DI;
	bit  [31: 0] MADAM_DO;
	bit  [31: 0] MADAM_CPU_DO;
	bit          MADAM_SYSRAM_EN;
	bit          LPSC_N;
	bit          RPSC_N;
	bit  [ 2: 0] CLC;
	bit          PB_INT;
	bit          CLIO_OE;
	
	bit          RESET_N;
	bit  [31: 0] CLIO_DI;
	bit  [31: 0] CLIO_DO;
	bit  [31: 0] CLIO_CPU_DO;
	bit          PCSC;
	bit          DMAREQ;
	bit  [ 4: 0] DMACH;
	bit          CREADY_N;
	bit          FIRQ_N;
	bit  [ 7: 0] EDI;
	bit  [ 7: 0] EDO;
	bit          ESTR_N;
	bit          EWRT_N;
	bit          ECMD_N;
	bit          ESEL_N;
	bit          ERST_N;
	bit          ERDY_N;
	bit          EINT_N;
	bit  [ 3: 0] CLIO_ADBIO_O;
	bit  [15: 0] CLIO_AUDIOL,CLIO_AUDIOR;
	
	bit          HSYNC_N;
	bit          VSYNC_N;
	bit  [23: 0] AD;
	bit          DE;
	
	ARM6_CORE cpu
	(
		.CLK(CLK),
		.RST_N(RST_N),
		.EN(1'b1),
		
		.BIGEND(1'b1),
		
		.CE_R(MCLK_PH1),
		.CE_F(MCLK_PH2),
		
		.nRESET(CPU_nRES),
		.nFIQ(FIRQ_N),
		.nIRQ(1'b1),
		
		.EDI(32'h0),
		
		.A(CPU_A),
		.DI(CPU_DI),
		.DO(CPU_DO),
		.nRW(CPU_nRW),
		.nWB(CPU_nWB),
		.nMREQ(CPU_nMREQ),
		.SEQ(CPU_SEQ),
		.nOPC(CPU_nOPC),
		.nTRANS(CPU_nTRANS),
		.LOCK(CPU_LOCK),
		.DBE(CPU_DBE)
	);
	assign CPU_DI = CPU_A >= 32'h00000000 && CPU_A <= 32'h002FFFFF &&  MADAM_SYSRAM_EN ? DI :
						 CPU_A >= 32'h00000000 && CPU_A <= 32'h002FFFFF && !MADAM_SYSRAM_EN ? MADAM_CPU_DO :
						 CPU_A >= 32'h03000000 && CPU_A <= 32'h030FFFFF ? MADAM_CPU_DO :
						 CPU_A >= 32'h03140000 && CPU_A <= 32'h0317FFFF ? MADAM_CPU_DO :
						 CPU_A >= 32'h03300000 && CPU_A <= 32'h033FFFFF ? MADAM_CPU_DO :
						 CPU_A >= 32'h03400000 && CPU_A <= 32'h034FFFFF ? CLIO_CPU_DO :
						 '0;
	
`ifdef DEBUG
	always @(posedge CLK or negedge RST_N) begin
		
		if (!RST_N) begin
			DBG_HOOK <= 0;
			DBG_HOOK2 <= '0;
		end
		else if (CE_R) begin
			DBG_CLK_DIV <= DBG_CLK_DIV + 8'd1;
			DBG_CLK_CNT <= DBG_CLK_CNT + 32'd1;
			
			if (CPU_A == 32'h000F39EC && CPU_DI == 32'hE58D0018 && !CPU_nRW && MCLK_PH2) DBG_HOOK2 <= DBG_HOOK2 + 1'd1;
//			if (CPU_A == 32'h03300520                           &&  CPU_nRW && MCLK_PH2) DBG_HOOK2 <= DBG_HOOK2 + 1'd1;
			
//			if (CPU_A == 32'h00069F34 && CPU_DI == 32'hE3A05004 && !CPU_nRW && MCLK_PH2) begin DBG_HOOK <= 1; DBG_HOOK2 <= '0; end
//			if (CPU_A == 32'h00035740 && CPU_DI == 32'h001FBB90 && !CPU_nRW && MCLK_PH2) DBG_HOOK <= 1;
//			if (CPU_A == 32'h00029B90 && CPU_DI == 32'hE594005C && !CPU_nRW && MCLK_PH2) DBG_HOOK <= 0;

//			if (CPU_A == 32'h000B9144 && CPU_nRW && MCLK_PH2) DBG_B9144 <= CPU_DO;
//			if (CPU_A == 32'h000B9148 && CPU_nRW && MCLK_PH2) DBG_B9148 <= CPU_DO;
//			if (CPU_A == 32'h000B917C && CPU_nRW && MCLK_PH2) DBG_B917C <= CPU_DO;
//			if (CPU_A == 32'h000B9180 && CPU_nRW && MCLK_PH2) DBG_B9180 <= CPU_DO;
//			
//			if (CPU_A == 32'h000B8E5C && CPU_nRW && MCLK_PH2) DBG_B8E5C <= CPU_DO; 
//			if (CPU_A == 32'h000B8E60 && CPU_nRW && MCLK_PH2) DBG_HOOK <= (DBG_B8E5C[31:20] == 12'h011 && CPU_DO[31:20] == 12'h024) || (DBG_B8E5C[31:20] == 12'h00D && CPU_DO[31:20] == 12'h021);
//			
//			if (CPU_A == 32'h000B8E8C && CPU_nRW && MCLK_PH2) DBG_B8E8C <= CPU_DO; 
//			if (CPU_A == 32'h000B8E90 && CPU_nRW && MCLK_PH2) DBG_HOOK <= (DBG_B8E8C[31:20] == 12'h00D && CPU_DO[31:20] == 12'h021);
//			
//			if (CPU_A == 32'h000B8D9C && CPU_nRW && MCLK_PH2) DBG_B8D9C <= CPU_DO; 
//			if (CPU_A == 32'h000B8DA0 && CPU_nRW && MCLK_PH2) begin DBG_B8DA0 <= CPU_DO; DBG_HOOK <= (DBG_B8D9C[31:20] == 12'h011 && CPU_DO[31:20] == 12'h024) || (DBG_B8D9C[31:20] == 12'h00D && CPU_DO[31:20] == 12'h021); end
			
		end
	end
`endif
	
	MADAM madam
	(
		.CLK(CLK),
		.RST_N(RST_N & RESET_N),
		.EN(EN),
		
		.CE_F(CE_F && ~PAUSE),
		.CE_R(CE_R && ~PAUSE),
		
//		.RESET_N(RESET_N),
		
		.A(CPU_A),
		.DI(MADAM_DI),
		.DO(MADAM_DO),
		
		.CPU_DI(CPU_DO),
		.CPU_DO(MADAM_CPU_DO),
		.nRW(CPU_nRW),
		.nWB(CPU_nWB),
		.nMREQ(CPU_nMREQ),
		.SEQ(CPU_SEQ),
		.nOPC(CPU_nOPC),
		.nTRANS(CPU_nTRANS),
		.LOCK(CPU_LOCK),
		.DBE(CPU_DBE),
		.nCPURES(CPU_nRES),
		.MCLK_PH1(MCLK_PH1),
		.MCLK_PH2(MCLK_PH2),
		.PH1(MCLK_CE),
		
		.LA(LA),
		.LRAS0_N(LRAS0_N),
		.LRAS2_N(LRAS2_N),
		.LRAS3_N(LRAS3_N),
		.LCAS_N(LCAS_N),
		.LWE_N(LWE_N),
		.LOE_N(LOE_N),
		.LSC(LSC),
		.LDSF(LDSF),
		.LQSF(LQSF),
		.LCODE(LCODE),
		.RA(RA),
		.RRAS0_N(RRAS0_N),
		.LA_COL(LA_COL),
		.LRAS0_COL_N(LRAS0_COL_N),
		.RA_COL(RA_COL),
		.RRAS0_COL_N(RRAS0_COL_N),
		.RRAS2_N(RRAS2_N),
		.RRAS3_N(RRAS3_N),
		.RCAS_N(RCAS_N),
		.RWE_N(RWE_N),
		.ROE_N(ROE_N),
		.RSC(RSC),
		.RDSF(RDSF),
		.RQSF(RQSF),
		.RCODE(RCODE),
	
		.VCE(VCE),
		.PCSC(PCSC),
		.LPSC_N(LPSC_N),
		.RPSC_N(RPSC_N),
		
		.CLC(CLC),
		.DMAREQ(DMAREQ),
		.DMACH(DMACH),
		.CREADY_N(CREADY_N),
		.MIRQ_N(FIRQ_N),
		.PB_INT(PB_INT),////
		
		.PBDIN(PBDIN),
		.PBDOUT(PBDOUT),
		.PBCLK(PBCLK),
		
		.PDI(PDI),
		.PDO(PDO),
		.ROMCS_N(ROMCS_N),
		.SRAMW_N(SRAMW_N),
		.SRAMR_N(SRAMR_N),
		
		.CLIO_OE(CLIO_OE),
		
		.SYSRAM_EN(MADAM_SYSRAM_EN),
		
		.FIELD(FIELD),
		
		.VRAM_SP_CPU(VRAM_SP_CPU),
		
		.DBG_SPR_EN(SCRN_EN[1]),
		.DBG_EXT(DBG_EXT)
	);
	assign MADAM_DI = CPU_DBE ? CPU_DO : DI;
	
	bit  [31: 0] CPU_DO_FF;//to reduce combination path
	always @(posedge CLK) begin
		if (MCLK_PH1) begin
			CPU_DO_FF <= CPU_DO;
		end
	end
	assign DO = CPU_DBE ? CPU_DO_FF : 
	            CLIO_OE ? CLIO_DO :
	            MADAM_DO;
	
	assign PA = CPU_A[19:0];
		
	CLIO 
`ifdef SIM
	#(dsp_nram_file)
`endif
	clio
	(
		.CLK(CLK),
		.RST_N(RST_N),
		.EN(EN),
		
		.PAL(PAL),
		
		.CE_R(CE_R),
		.CE_F(CE_F),
		.IO_EN(~PAUSE),
		.DSP_EN(~DSP_PAUSE),
		
		.RESET_N(RESET_N),
		.PON(PON),
		
		.MCLK_PH1(MCLK_PH1),
		.MCLK_PH2(MCLK_PH2),
		.A(CPU_A[15:2]),
		.CPU_DI(CPU_DO),
		.CPU_DO(CLIO_CPU_DO),
		
		.DI(CLIO_DI),
		.DO(CLIO_DO),
		.CLC(CLC),
		.CREADY_N(CREADY_N),
		.DMAREQ(DMAREQ),
		.DMACH(DMACH),
		.PB_INT(PB_INT),////
		
		.FIRQ_N(FIRQ_N),
		
		.EDI(EDI),
		.EDO(EDO),
		.ESTR_N(ESTR_N),
		.EWRT_N(EWRT_N),
		.ECMD_N(ECMD_N),
		.ESEL_N(ESEL_N),
		.ERST_N(ERST_N),
		.ERDY_N(ERDY_N),
		.EINT_N(EINT_N),
		
		.ADBIO_I('0),
		.ADBIO_O(CLIO_ADBIO_O),
		
		.VCE(VCE),
		.HSYNC_N(HSYNC_N),
		.VSYNC_N(VSYNC_N),
		
		.S(S),
		.LPSC_N(LPSC_N),
		.RPSC_N(RPSC_N),
		.PCSC(PCSC),
		
		.AD(AD),
		.DE(DE),
		
		.ACLK_CE(ACLK_CE),
		.AUDIOL(CLIO_AUDIOL),
		.AUDIOR(CLIO_AUDIOR),
		
		.HINTREPOL_DISABLE(HINTREPOL_DISABLE),
		.VINTREPOL_DISABLE(VINTREPOL_DISABLE),
		.DBG_EXT(DBG_EXT)
	);
	assign CLIO_DI = CPU_DBE ? CPU_DO : DI;
	
	wire         MUTE = 0;//CLIO_ADBIO_O[1];
	assign AUDIOL = CLIO_AUDIOL & {16{~MUTE}};
	assign AUDIOR = CLIO_AUDIOR & {16{~MUTE}};
	
	assign ROM_SEL = CLIO_ADBIO_O[2];
	
	OSA osa
	(
		.CLK(CLK),
		.RST_N(RST_N),
		.EN(EN),
		
		.CE_R(CE_R),
		.CE_F(CE_F),
		
		.EDI(EDO),
		.EDO(EDI),
		.ESTR_N(ESTR_N),
		.EWRT_N(EWRT_N),
		.ECMD_N(ECMD_N),
		.ESEL_N(ESEL_N),
		.ERST_N(ERST_N),
		.ERDY_N(ERDY_N),
		.EINT_N(EINT_N),
		
		.CDDI(CDDI),
		.CDDO(CDDO),
		.CDEN_N(CDEN_N),
		.CDCMD_N(CDCMD_N),
		.CDHWR_N(CDHWR_N),
		.CDHRD_N(CDHRD_N),
		.CDRST_N(CDRST_N),
		.CDSTEN_N(CDSTEN_N),
		.CDDTEN_N(CDDTEN_N),
		.CDMDCHG(CDMDCHG)
	);
	
	VE ve
	(
		.MCLK(CLK),
		.VCLK(VCLK),
		.RST_N(RST_N & RESET_N),
		.EN(EN),
		
		.PAL(PAL),
		
		.VCE(VCE),
		.AD(AD),
		.DE(DE),
		.HSYNC_N(HSYNC_N),
		.VSYNC_N(VSYNC_N),
		
		.RGB(RGB),
		.HS_N(HS_N),
		.VS_N(VS_N),
		.HBLK_N(HBLK_N),
		.VBLK_N(VBLK_N),
		.DCLK(DCLK),
		
		.DBG_EXT(DBG_EXT),
		.DBG_BORD_DIS(SCRN_EN[2])
	);

	

endmodule
