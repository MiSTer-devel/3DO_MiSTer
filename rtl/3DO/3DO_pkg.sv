package P3DO_PKG;

	//MADAM
	
	//Sprite registers
	typedef bit [31:0] SprStrt_t;	//R/W,0x03300100
	parameter bit [31:0] SprStrt_WMASK = 32'h00000000;
	parameter bit [31:0] SprStrt_RMASK = 32'h00000000;
	parameter bit [31:0] SprStrt_INIT = 32'h00000000;
	
	typedef bit [31:0] SprStop_t;	//R/W,0x03300104
	parameter bit [31:0] SprStop_WMASK = 32'h00000000;
	parameter bit [31:0] SprStop_RMASK = 32'h00000000;
	parameter bit [31:0] SprStop_INIT = 32'h00000000;
	
	typedef bit [31:0] SprCntu_t;	//R/W,0x03300108
	parameter bit [31:0] SprCntu_WMASK = 32'h00000000;
	parameter bit [31:0] SprCntu_RMASK = 32'h00000000;
	parameter bit [31:0] SprCntu_INIT = 32'h00000000;
	
	typedef bit [31:0] SprPaus_t;	//R/W,0x0330010C
	parameter bit [31:0] SprPaus_WMASK = 32'h00000000;
	parameter bit [31:0] SprPaus_RMASK = 32'h00000000;
	parameter bit [31:0] SprPaus_INIT = 32'h00000000;
	
	typedef struct packed		//R/W,0x03300110
	{
		bit [ 1: 0] B15POS;
		bit [ 1: 0] B0POS;
		bit         SWAPHV;
		bit         ASCALL;
		bit         UNUSED;
		bit         CFBDSUB;
		bit [ 1: 0] CFBDLSB;
		bit [ 1: 0] IPNLSB;
		bit [19: 0] UNUSED2;
	} SCoBCtl_t; 
	parameter bit [31:0] SCoBCtl_WMASK = 32'hFDF00000;
	parameter bit [31:0] SCoBCtl_RMASK = 32'hFDF00000;
	parameter bit [31:0] SCoBCtl_INIT = 32'h00000000;
	
	typedef struct packed		//R/W,0x03300120
	{
		bit         S1;
		bit [ 1: 0] MS;
		bit [ 2: 0] MXF;
		bit [ 1: 0] DV1;
		bit [ 1: 0] S2;
		bit [ 4: 0] AV;
		bit         DV2;
	} PPMPCx_t; 
	parameter bit [15:0] PPMPCx_WMASK = 16'hFFFF;
	parameter bit [15:0] PPMPCx_RMASK = 16'hFFFF;
	parameter bit [15:0] PPMPCx_INIT = 16'h0000;
	
	typedef struct packed		//R/W,0x03300130
	{
		bit [15: 0] UNUSED;
		bit [ 3: 0] DSTG2;
		bit [ 3: 0] DSTG1;
		bit [ 3: 0] CFBDG2;
		bit [ 3: 0] CFBDG1;
	} RegCtl0_t; 
	parameter bit [31:0] RegCtl0_WMASK = 32'h0000FFFF;
	parameter bit [31:0] RegCtl0_RMASK = 32'h0000FFFF;
	parameter bit [31:0] RegCtl0_INIT = 32'h00000000;
	
	typedef struct packed		//R/W,0x03300134
	{
		bit [ 4: 0] UNUSED;
		bit [10: 0] CLIPY;
		bit [ 4: 0] UNUSED2;
		bit [10: 0] CLIPX;
	} RegCtl1_t; 
	parameter bit [31:0] RegCtl1_WMASK = 32'h07FF07FF;
	parameter bit [31:0] RegCtl1_RMASK = 32'h07FF07FF;
	parameter bit [31:0] RegCtl1_INIT = 32'h00000000;
	
	typedef bit [31:0] RegCtl2_t;	//R/W,0x03300138
	parameter bit [31:0] RegCtl2_WMASK = 32'h00FFFFFC;
	parameter bit [31:0] RegCtl2_RMASK = 32'h00FFFFFC;
	parameter bit [31:0] RegCtl2_INIT = 32'h00000000;
	
	typedef bit [31:0] RegCtl3_t;	//R/W,0x0330013C
	parameter bit [31:0] RegCtl3_WMASK = 32'h00FFFFFC;
	parameter bit [31:0] RegCtl3_RMASK = 32'h00FFFFFC;
	parameter bit [31:0] RegCtl3_INIT = 32'h00000000;
	
	//DMA registers
	parameter bit [10:0] DMA_CLUT_GROUP = 11'h580;
	parameter bit [10:0] DMA_SPR_GROUP = 11'h5A0;
	
	
	typedef struct packed
	{
		bit         SKIP;
		bit         LAST;
		bit         NPABS;
		bit         SPABS;
		bit         PPABS;
		bit         LDSIZE;
		bit         LDPRS;
		bit         LDPPMP;
		bit         LDPIP;
		bit         SCOBPRE;
		bit         YOXY;
		bit         ACSC;
		bit         ALSC;
		bit         ACW;
		bit         ACCW;
		bit         TWD;
		bit         LCE;
		bit         ACE;
		bit         UNUSED;//ASC ??
		bit         MARIA;
		bit         PXOR;
		bit         USEAV;
		bit         PACKED;
		bit [ 1: 0] DOVER;
		bit         PIPPOS;
		bit         BGND;
		bit         NOBLK;
		bit [ 3: 0] PIPA;
	} SCoBFlag_t;
	parameter bit [31:0] SCoBFlag_WMASK = 32'hFFFFDFFF;
	parameter bit [31:0] SCoBFlag_RMASK = 32'hFFFFDFFF;
	parameter bit [31:0] SCoBFlag_INIT = 32'h00000000; 
	
	typedef struct packed
	{
		bit         LITERAL;
		bit         BGND;
		bit [ 1: 0] PRESERVED;
		bit [ 3: 0] SKPX;
		bit [ 7: 0] UNUSED2;
		bit [ 9: 0] VCNT;
		bit         UNUSED;
		bit         LINEAR;
		bit         REP8;
		bit [ 2: 0] BPP;
	} SCoBPre0_t;
	parameter bit [31:0] SCoBPre0_WMASK = 32'hFF00FFDF;
	parameter bit [31:0] SCoBPre0_RMASK = 32'hFF00FFDF;
	parameter bit [31:0] SCoBPre0_INIT = 32'h00000000;
	
	typedef struct packed
	{
		bit [ 7: 0] WOFFSET8;
		bit [ 7: 0] WOFFSET10;
		bit         UNUSED;
		bit         NOSWAP;
		bit [ 1: 0] TLLSBIPN;
		bit         LRFORM;
		bit [10: 0] TLHPCNT;
	} SCoBPre1_t;
	parameter bit [31:0] SCoBPre1_WMASK = 32'hFFFF7FFF;
	parameter bit [31:0] SCoBPre1_RMASK = 32'hFFFF7FFF;
	parameter bit [31:0] SCoBPre1_INIT = 32'h00000000;
	
	
	typedef struct packed
	{
		bit         BPP_SEL;
		bit         BYPASS_EN;
		bit         LOAD_OFFSET_SEL;
		bit         DMA_ZERO_SEL;
		bit         DMA_OWN_SEL;
		bit [ 6: 0] DMA_GROUP_ADDR;
		bit         DMA_GROUP_ADDR_SEL;
		bit         DMA_GROUP_HOLD;
		bit         DMA_REG_READ_SEL;
		bit [ 1: 0] DMA_REG_READ_CTL;
		bit         DMA_REG_WRITE_SEL;
		bit [ 2: 0] DMA_REG_WRITE_CTL;
		bit         DMA_REG_WRITE_EN;
		bit [ 3: 0] DMA_ADDER_CTL;
		bit         CPU_ADDR_SEL;
		bit         SPR_ADDR_SEL;
		bit         DMA_ADDR_SEL;
	} AddrGenCtl_t; 
	
	typedef enum bit [7:0] {
		BUS_IDLE,
		
		EXTP_PREINIT1,
		EXTP_INIT0,EXTP_INIT1,
		EXTP_READ0,EXTP_READ1,
		EXTP_PREINIT3,
		EXTP_INIT2,EXTP_INIT3,
		EXTP_WRITE0,EXTP_WRITE1,
		EXTP_LOOP0,EXTP_LOOP1,
		EXTP_LOOP2,EXTP_LOOP3,
		EXTP_REINIT0,EXTP_REINIT1,
		
		PLAY_PREINIT1,
		PLAY_INIT0,PLAY_INIT1,
		PLAY_READ0,PLAY_READ1,
		PLAY_PREINIT3,
		PLAY_INIT2,PLAY_INIT3,
		PLAY_WRITE0,PLAY_WRITE1,
		
		REF_PREINIT1,
		REF_INIT0,REF_INIT1,
		REF_WRITE0,REF_WRITE1,
		REF_WRITE2,REF_WRITE3,
		
		SCOB_PREINIT1,
		SCOB_INIT0, SCOB_INIT1,
		SCOB_FLAG0, SCOB_FLAG1,
		SCOB_NEXT0, SCOB_NEXT1,
		SCOB_NEXT_REL0,SCOB_NEXT_REL1,
		SCOB_SOURCE0, SCOB_SOURCE1,
		SCOB_SOURCE_REL0,SCOB_SOURCE_REL1,
		SCOB_PIPPTR0, SCOB_PIPPTR1,
		SCOB_PIPPTR_REL0, SCOB_PIPPTR_REL1,
		SCOB_XPOS0, SCOB_XPOS1,
		SCOB_YPOS0, SCOB_YPOS1,
		
		SCOB_PREINIT3,
		SCOB_INIT2, SCOB_INIT3,
		SCOB_DX0, SCOB_DX1,
		SCOB_DY0, SCOB_DY1,
		SCOB_LINEDX0, SCOB_LINEDX1,
		SCOB_LINEDY0, SCOB_LINEDY1,
		SCOB_DDX0, SCOB_DDX1,
		SCOB_DDY0, SCOB_DDY1,
		SCOB_PPMP0, SCOB_PPMP1,
		
		SCOB_PREINIT5,
		SCOB_INIT4, SCOB_INIT5,
		SCOB_PRE00, SCOB_PRE01,
		SCOB_PRE10, SCOB_PRE11,
		
		SCOB_PREINIT7,
		SCOB_INIT6, SCOB_INIT7,
		SCOB_PIP0, SCOB_PIP1,
		
		SPR_PREINIT1,
		SPR_INIT0, SPR_INIT1,
		SPR_OFFS0, SPR_OFFS1,
		SPR_OFFS2, SPR_OFFS3,
		SPR_CALC0, SPR_CALC1,
		SPR_PREINIT3,
		SPR_INIT2, SPR_INIT3,
		SPR_DATA0, SPR_DATA1,
		
		CFB_INIT0, CFB_INIT1,
		CFB_READ0, CFB_READ1,
		CFB_WRITE0, CFB_WRITE1,
		
		CLUT_PREINIT1, 
		CLUT_INIT0, CLUT_INIT1, 
		CLUT_CTRL0, CLUT_CTRL1, 
		CLUT_CURR0,  CLUT_CURR1, 
		CLUT_PREV0, CLUT_PREV1,
		CLUT_NEXT0, CLUT_NEXT1,
		CLUT_NEXT_REL0, CLUT_NEXT_REL1,
		CLUT_TRANSFER0, CLUT_TRANSFER1,
		CLUT_MIDINIT0, CLUT_MIDINIT1,
		CLUT_MIDTRANS0, CLUT_MIDTRANS1,
		
		VID_PREINIT1,
		VID_INIT0, VID_INIT1,
		VID_PREV0, VID_PREV1,
		VID_CALC0, VID_CALC1,
		VID_CURR0, VID_CURR1,
		VID_MIDPREINIT1,
		VID_MIDINIT0, VID_MIDINIT1,
		VID_MIDPREV0, VID_MIDPREV1,
		VID_MIDCURR0, VID_MIDCURR1
	} BusState_t;

	//Sprite engine
	typedef struct packed
	{
		bit         D;
		bit [ 4: 0] R;
		bit [ 4: 0] G;
		bit [ 4: 0] B;
		bit         T;
		bit [ 2: 0] MR;
		bit [ 2: 0] MG;
		bit [ 2: 0] MB;
		bit         RMODE;
		bit         SPH;
		bit         SPV;
	} IPN_t; 
	
	typedef struct packed
	{
		bit [15: 0] INT;
		bit [15: 0] FRAC;
	} Coord_t; 
	
	typedef struct packed
	{
		bit [11: 0] INT;
		bit [15: 0] FRAC;
		bit [ 3: 0] UNUSED;
	} Delta_t; 
	
	typedef struct packed
	{
		bit         A0CH_INIT;
		bit         A0CL_INIT;
		bit         A3CH_INIT;
		bit         A3CL_INIT;
		bit         A0DH_INIT;
		bit         A0DL_INIT;
		bit         A3DH_INIT;
		bit         A3DL_INIT;
		bit         A3CH_SAVE;
		bit         A3CL_SAVE;
		bit         A3DH_SAVE;
		bit         A3DL_SAVE;
		bit         A12C_PRECALC;
		bit         A12C_CALC;
		bit         MUNK_STEP;
		bit [ 2: 0] X_ADD01_ASEL;
		bit [ 2: 0] X_ADD01_BSEL;
		bit         X_ADD01_SUB;
		bit [ 2: 0] X_ADD23_ASEL;
		bit [ 2: 0] X_ADD23_BSEL;
		bit         X_ADD23_SUB;
		bit [ 2: 0] Y_ADD01_ASEL;
		bit [ 2: 0] Y_ADD01_BSEL;
		bit         Y_ADD01_SUB;
		bit [ 2: 0] Y_ADD23_ASEL;
		bit [ 2: 0] Y_ADD23_BSEL;
		bit         Y_ADD23_SUB;
		bit         X1_UPD;
		bit         X1F_UPD;
		bit [ 1: 0] X1_MUNK_SEL;
		bit [ 1: 0] X2_MUNK_SEL;
		bit         X1_MUNK;
		bit         X2_MUNK;
		bit         X2_UPD;
		bit         X2F_UPD;
		bit         DX1_UPD;
		bit         DY1_UPD;
		bit         DX2_UPD;
		bit         DY2_UPD;
		bit [ 1: 0] Y_T1_SEL;
		bit         Y_UPD;
		bit         Y_INC;
		bit [ 1: 0] T2_SEL;
	} MathCtl_t;
	
	typedef struct packed
	{
		bit         MF;
		bit         MCW;
		bit         NP;
		bit         LC;
		bit         RC;
		bit         VC;
		bit         CW;
		bit         CCW;
		bit         COMPT1;
		bit         COMPT2;
		bit         YADD01N;
		bit         YADD23N;
		bit         DXA10N;
		bit         DXA10E;
		bit         DXA23N;
		bit         DXA23E;
		bit         DXA30N;
		bit         DXA30E;
		bit         DYA10N;
		bit         DYA10E;
		bit         DYA23N;
		bit         DYA23E;
		bit         DYA30N;
		bit         DYA30E;
		bit         DX1N;
		bit         DX1E;
		bit         DX2N;
		bit         DX2E;
		bit         DY1N;
		bit         DY1E;
		bit         DY2N;
		bit         DY2E;
		bit         DY12ONEP;
		bit         DY12ONEM;
		bit         DY12ZERO;
		bit [ 1: 0] YTOP;
	} MathStat_t;
	
	typedef struct packed
	{
		bit [10: 0] Y;
		bit [11: 0] XL;
		bit [11: 0] XR;
	} YXX_t; 
	
	typedef struct packed
	{
		bit [10: 0] Y;
		bit [11: 0] X;
	} YX_t; 
	
	function bit [11:0] MathClipCoord(input bit [15:0] c);
		return c[15:11] != 5'b00000 && c[15:11] != 5'b11111 ? {c[15],{11{~c[15]}}} : c[11:0];
	endfunction
	
	function bit [16:0] MathAdder16(input bit [15:0] a, input bit [15:0] b);
		bit  [16:0] res;
		
		res = {1'b0,a} + {1'b0,b};
		
		return res;
	endfunction
	
	function bit [2:0] MathAdder2(input bit [1:0] a, input bit [1:0] b, input bit c);
		bit  [2:0] res;
		
		res = {1'b0,a} + {1'b0,b} + {2'b00,c};
		
		return res;
	endfunction
	
	
	//CLIO
	typedef struct packed
	{
		bit [ 4: 0] UNUSED;
		bit         H640;
		bit [ 2: 0] DISPMODE;
		bit         SLIPEN;
		bit         ENVIDDMA;
		bit         SLIPCOMM;
		bit         V480;
		bit         NPABS;
		bit         PREVSEL;
		bit         LDCURR;
		bit         LDPREV;
		bit [ 5: 0] LEN;
		bit [ 8: 0] LINE;
	} CLUTCtrl_t; 
	
	typedef struct packed
	{
		bit         NULL;
		bit         PAL;
		bit         S640;
		bit         BYPASS;
		bit         SLPDCEL;
		bit         FORCETRANS;
		bit         BACKTRANS;
		bit         WSWAPHV;
		bit [ 1: 0] WVSUB;
		bit [ 1: 0] WHSUB;
		bit [ 1: 0] WBLSB;
		bit         WVION;
		bit         WHION;
		bit         RNDM;
		bit         MSBREP;
		bit         SWAPHV;
		bit [ 1: 0] VSUB;
		bit [ 1: 0] HSUB;
		bit [ 1: 0] BLSB;
		bit         VION;
		bit         HION;
		bit         COLONLY;
		bit         VIOFF;
	} DispCtrl_t; 
	
	//DSP
	typedef struct packed
	{
		bit         A_C;
		bit [ 1: 0] NUM_OPS;
		bit         M2SEL;
		bit [ 1: 0] AMX_A;
		bit [ 1: 0] AMX_B;
		bit [ 3: 0] ALU;
		bit [ 3: 0] BS;
	} ALUInst_t; 
	
	typedef struct packed
	{
		bit         A_C;
		bit [ 1: 0] MODE;
		bit         FLGSEL;
		bit [ 1: 0] FLAG_MASK;
		bit [ 9: 0] BCH_ADDR;
	} CtrlInst_t; 
	
	typedef struct packed
	{
		bit [ 1: 0] UNUSED;
		bit         JSTFY;
		bit [12: 0] IMM_VAL;
	} ImmOper_t; 
	
	typedef struct packed
	{
		bit [ 1: 0] TYPE;
		bit         R_IM;
		bit         X;
		bit         WB1;
		bit         D_I;
		bit [ 9: 0] OP_ADDR;
	} AddrOper_t;
	
	typedef struct packed
	{
		bit [ 1: 0] TYPE;
		bit         R_IM;
		bit         WB2;
		bit         WB1;
		bit         NUMRGS;
		bit         R2D_I;
		bit [ 3: 0] R2;
		bit         R1D_I;
		bit [ 3: 0] R1;
	} Reg12Oper_t;
	
	typedef struct packed
	{
		bit         MSB;
		bit         R3D_I;
		bit [ 3: 0] R3;
		bit         R2D_I;
		bit [ 3: 0] R2;
		bit         R1D_I;
		bit [ 3: 0] R1;
	} Reg3Oper_t;
	
	typedef struct packed
	{
		bit         MULT1;
		bit         MULT2;
		bit         ALU1;
		bit         ALU2;
		bit         BS;
	} OpMask_t;
	
	typedef struct packed
	{
		bit         N;
		bit         V;
		bit         C;
		bit         Z;
		bit         X;
	} ALUStat_t;
	
	function bit ExactlyOne(input bit [4:0] array);
		bit ret;
		case (array)
			5'b00001,
			5'b00010,
			5'b00100,
			5'b01000,
			5'b10000: ret = 1;
			default: ret = 0;
		endcase
		
		return ret;
	endfunction
	
	function bit [19:0] BarrelShifter(input bit [19:0] DATA, input bit [3:0] N, input bit T, input bit V);
		bit  [19:0] res;
		
		case (N)
			4'h0: res = DATA;
			4'h1: res = {DATA[18:0],{1{1'b0}}};
			4'h2: res = {DATA[17:0],{2{1'b0}}};
			4'h3: res = {DATA[16:0],{3{1'b0}}};
			4'h4: res = {DATA[15:0],{4{1'b0}}};
			4'h5: res = {DATA[14:0],{5{1'b0}}};
			4'h6: res = {DATA[11:0],{8{1'b0}}};
			4'h7: res = !V ? DATA : ({~DATA[19],{19{DATA[19]}}});
			4'h8: res = {DATA[18:4],DATA[19],DATA[3:0]};
			4'h9: res = {{16{DATA[19]&~T}},DATA[19:16]};
			4'hA: res = {{ 8{DATA[19]&~T}},DATA[19: 8]};
			4'hB: res = {{ 5{DATA[19]&~T}},DATA[19: 5]};
			4'hC: res = {{ 4{DATA[19]&~T}},DATA[19: 4]};
			4'hD: res = {{ 3{DATA[19]&~T}},DATA[19: 3]};
			4'hE: res = {{ 2{DATA[19]&~T}},DATA[19: 2]};
			4'hF: res = {{ 1{DATA[19]&~T}},DATA[19: 1]};
		endcase
		
		return res;
	endfunction

	// MADAM's memory map by megabyte, from MSYS[6:0] (the memory sizes): bit 0
	// DRAM bank 0, bit 1 DRAM bank 1, bit 2 VRAM. Every region bound is on a
	// megabyte boundary, so the megabyte of an address (bits 23:20) decides.
	// It replaces 22-bit range compares of each address against the bounds,
	// which were on the address path to the memories (VRAM is its megabyte
	// only: the compares also took the first word after it).
	function automatic bit [2:0] MemRegionSel(input [6:0] MSIZE, input [3:0] MB);
		bit [23:0] D0E,D1S,D1E,VS;
		bit [23:0] LO,HI;
		bit [2:0] res;

		case (MSIZE[4:3])
			2'b00: begin D0E = 24'h000000; D1S = 24'h000000; end
			2'b01: begin D0E = 24'h0FFFFF; D1S = 24'h100000; end
			2'b10: begin D0E = 24'h3FFFFF; D1S = 24'h400000; end
			2'b11: begin D0E = 24'hDFFFFF; D1S = 24'hE00000; end
		endcase
		case (MSIZE[6:5])
			2'b00: begin D1E = D1S + 24'h000000; VS = D1S + 24'h000000; end
			2'b01: begin D1E = D1S + 24'h0FFFFF; VS = D1S + 24'h100000; end
			2'b10,
			2'b11: begin D1E = D1S + 24'h3FFFFF; VS = D1S + 24'h400000; end
		endcase
		LO = {MB,20'h00000};
		HI = {MB,20'hFFFFF};
		res[0] = (HI <= D0E);
		res[1] = (LO >= D1S && HI <= D1E);
		res[2] = (MB == VS[23:20]) && (VS[23:20] != 4'hF);   // VRAM in the last megabyte: its end bound wrapped and nothing was selected
		return res;
	endfunction

endpackage
