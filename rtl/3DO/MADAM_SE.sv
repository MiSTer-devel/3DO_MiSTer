// synopsys translate_off
`define SIM
// synopsys translate_on

import P3DO_PKG::*;

module MADAM_SE
(
	input              CLK,
	input              RST_N,
	input              EN,
	
	input              CE_R,
	input              CE_F,
	
	input      [31: 0] CPU_DI,
	input      [23: 2] MADR,
	input      [31: 0] MDTI,
	output     [31: 0] MDTO,
	input              MWR,
	input              SEL,
	input BusState_t   BUS_STATE,
	input              BUS_PB,
	input              GRANT,
	input              DMA_REG_ZERO,
	output AddrGenCtl_t AG_CTL,
	output     [23: 1] CFB_ADDR_A,
	output     [23: 1] CFB_ADDR_B,
	output             CFB_RAS_A,
	output             CFB_RAS_B,
	output             CFB_WRITE_A,
	output             CFB_WRITE_B,
	output             CFB_READ,
	
	input              INT_REQ,
	
	output reg [ 2: 0] SCOBLD_REQ,
	output reg [ 2: 0] SCOB_SEL,
	output reg [ 1: 0] SPRDATA_REQ,
	output reg [ 1: 0] SPR_SEL,
	output reg         SPRDRAW_REQ,
	output reg [ 2: 0] CFB_SEL,
	input              CFB_SUSPEND,
	output reg         SPRPAUS_REQ,
	output reg         SPREND_REQ,
	input              ACK,
	output reg [ 3: 0] STAT,
	
	input              DBG_SPR_EN,
	input      [ 7: 0] DBG_EXT
	
`ifdef DEBUG
	                   ,
	output reg [31: 0] DBG_XPOS,
	output reg [31: 0] DBG_YPOS,
	output reg [31: 0] DBG_LDX,
	output reg [31: 0] DBG_LDY,
	output reg [31: 0] DBG_DDX,
	output reg [31: 0] DBG_DDY,
	output reg [31: 0] DBG_DX,
	output reg [31: 0] DBG_DY,
	output reg         DBG_SPRITE_INIT,
	output reg [ 7: 0] DBG_SPRITE_NUM,DBG_SPRITE_CNT,
	output reg [ 7: 0] DBG_START_CNT,
	output reg [23: 0] DBG_SCOB_ADDR,
	output reg [23: 0] DBG_SCOB_SOURCE,
	output reg [31: 0] DBG_SCOB_PPMPC,
	output reg [31: 0] DBG_SCOB_PRE0,
	output reg [31: 0] DBG_SCOB_PRE1,
	output reg [ 9: 0] DBG_WAIT_CNT,
	output reg [11: 0] DBG_ROW_WAIT_CNT,DBG_ROW_B_WAIT_CNT,
	output reg [ 7: 0] DBG_ROWFULL_WAIT_CNT,
	output IPN_t       DBG_IPS_FIFO_OUT,DBG_IPS_FIFO_B_OUT,
	output YX_t        DBG_XY_FIFO_A_OUT,DBG_XY_FIFO_B_OUT,
	output             DBG_XY_FIFO_A_LAST,DBG_XY_FIFO_A_DOLO,DBG_XY_FIFO_A_DRAW,DBG_XY_FIFO_B_LAST,DBG_XY_FIFO_B_DOLO,DBG_XY_FIFO_B_DRAW,
	output reg         DBG_DRAW_OUT,
	output reg         DBG_CLIP_A,DBG_CLIP_B,
	output reg         DBG_LDX_BIG,DBG_LDY_BIG,DBG_DX_BIG,DBG_DY_BIG,
	output reg         DBG_SPRITE_HIT,
	output reg [ 7: 0] DBG_REGIS_A_Y_CNT
`endif
);

	bit          SPRPRQ,SPREND,SPRPAUS,SPRON;
	SCoBCtl_t    SCOBCTL;
	RegCtl0_t    REGCTL0;
	RegCtl1_t    REGCTL1;
	RegCtl2_t    REGCTL2;
	RegCtl3_t    REGCTL3;
	PPMPCx_t     PPMPCA,PPMPCB;
	
	SCoBFlag_t   SCOB_FLAG;
	SCoBPre0_t   SCOB_PRE0;
	SCoBPre1_t   SCOB_PRE1;
	
	wire         LRFORM = (SCOB_PRE1.LRFORM && !SCOB_FLAG.PACKED);
	
	wire CTRL_SEL = SEL && MADR[7:2] >= (8'h00>>2) && MADR[7:2] <= (8'h3F>>2);//Sprite engine control
	wire PM_SEL = SEL && MADR[7:2] >= (8'h40>>2) && MADR[7:2] <= (8'h7F>>2);//Points mapper
	wire PLUT_SEL = SEL && MADR[7:2] >= (8'h80>>2) && MADR[7:2] <= (8'hFF>>2);//PLUT
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) begin
			SCOBCTL <= SCoBCtl_INIT;
			REGCTL0 <= RegCtl0_INIT;
			REGCTL1 <= RegCtl1_INIT;
			REGCTL2 <= RegCtl2_INIT;
			REGCTL3 <= RegCtl3_INIT;
//			PPMPCA <= PPMPCx_INIT;
//			PPMPCB <= PPMPCx_INIT;
		end
		else begin
			if (CE_R) begin
				if (CTRL_SEL && MWR) begin
					case ({MADR[7:2],2'b00})
						8'h10: SCOBCTL <= CPU_DI & SCoBCtl_WMASK;
	//					8'h20: {PPMPCB,PPMPCA} <= CPU_DI & {PPMPCx_WMASK,PPMPCx_WMASK};
						8'h30: REGCTL0 <= CPU_DI & RegCtl0_WMASK;
						8'h34: REGCTL1 <= CPU_DI & RegCtl1_WMASK;
						8'h38: REGCTL2 <= CPU_DI & RegCtl2_WMASK;
						8'h3C: REGCTL3 <= CPU_DI & RegCtl3_WMASK;
						default:;
					endcase
				end
			end
		end
	end
	wire FB_IN_DRAM = (REGCTL3[23:20] <= 4'h1);
	
	bit  [31: 0] REG_DO,PM_DO,PLUT_DO;
	bit  [31: 0] PEN_DO;
	always_comb begin
		case ({MADR[7:2],2'b00})
			8'h10: REG_DO <= SCOBCTL & SCoBCtl_RMASK;
			8'h20: REG_DO <= {PPMPCB,PPMPCA} & {PPMPCx_RMASK,PPMPCx_RMASK};
			8'h30: REG_DO <= REGCTL0 & RegCtl0_RMASK;
			8'h34: REG_DO <= REGCTL1 & RegCtl1_RMASK;
			8'h38: REG_DO <= REGCTL2 & RegCtl2_RMASK;
			8'h3C: REG_DO <= REGCTL3 & RegCtl3_RMASK;
			default: REG_DO <= '0;
		endcase
	end
	
	assign MDTO = GRANT    ? PEN_DO :
	              CTRL_SEL ? REG_DO :
	              PM_SEL   ? PM_DO : 
					  PLUT_SEL ? PLUT_DO : 
					             '0;
	
	typedef enum bit [4:0] {
		MS_IDLE,
		MS_SCOB_LOAD_1,MS_SCOB_LOAD_2,MS_SCOB_LOAD_3,MS_SCOB_LOAD_4,
		MS_SPRDATA_INIT,MS_SPRDATA_A_REQ,MS_SPRDATA_A_WAIT,MS_SPRDATA_B_REQ,MS_SPRDATA_B_WAIT,MS_SPRDATA_NEXT,
		MS_SPR_DRAW_START,MS_SPR_DRAW_WAIT,
		MS_LINE_A_WAIT,MS_LINE_B_WAIT,
		MS_END
	} MainState_t;
	MainState_t MAIN_ST;
	
	
	BusState_t BUS_STATE_FF;
	always @(posedge CLK or negedge RST_N) begin		
		if (!RST_N) begin
			BUS_STATE_FF <= BUS_IDLE;
		end
		else if (EN && CE_R) begin
			BUS_STATE_FF <= BUS_STATE;
		end
	end 
	
	wire BUS_INIT0 = (BUS_STATE_FF == SCOB_INIT1 || BUS_STATE_FF == SCOB_INIT2 || BUS_STATE_FF == SCOB_INIT4 || BUS_STATE_FF == SCOB_INIT6 || 
			           BUS_STATE_FF == SPR_INIT0 || BUS_STATE_FF == SPR_INIT2 || BUS_STATE_FF == CFB_INIT0) && !BUS_PB;
//	wire BUS_INIT = (BUS_STATE_FF == SCOB_INIT1 || BUS_STATE_FF == SCOB_INIT3 || BUS_STATE_FF == SCOB_INIT5 || BUS_STATE_FF == SCOB_INIT7 || 
//			           BUS_STATE_FF == SPR_INIT1 || BUS_STATE_FF == SPR_INIT3 || BUS_STATE_FF == CFB_INIT1);
	wire FLAG_FETCH = (BUS_STATE_FF == SCOB_FLAG1);
	wire REG_FETCH = ((BUS_STATE_FF == SCOB_XPOS1 && SCOB_FLAG.YOXY && !SCOB_FLAG.SKIP) || (BUS_STATE_FF == SCOB_YPOS1 && SCOB_FLAG.YOXY && !SCOB_FLAG.SKIP) ||
	                  BUS_STATE_FF == SCOB_DX1 || BUS_STATE_FF == SCOB_DY1 ||
							BUS_STATE_FF == SCOB_LINEDX1 || BUS_STATE_FF == SCOB_LINEDY1 ||
							BUS_STATE_FF == SCOB_DDX1 || BUS_STATE_FF == SCOB_DDY1);
//	wire YPOS_FETCH = (BUS_STATE_FF == SCOB_YPOS1);
	wire PPMP_FETCH = (BUS_STATE_FF == SCOB_PPMP1);
	wire PRE0_FETCH = (BUS_STATE_FF == SCOB_PRE01);
	wire PRE1_FETCH = (BUS_STATE_FF == SCOB_PRE11);
	wire PIP_FETCH = (BUS_STATE_FF == SCOB_PIP1);
	wire POFFS_FETCH = (BUS_STATE_FF == SPR_OFFS1);
	wire PDATA_FETCH = (BUS_STATE_FF == SPR_OFFS3 || BUS_STATE_FF == SPR_DATA1);
	wire PIX_READ0 = (BUS_STATE_FF == CFB_READ0);
	wire PIX_READ1 = (BUS_STATE_FF == CFB_READ1);
	wire PIX_WRITE = (BUS_STATE_FF == CFB_WRITE1);
	
	wire SPRSTRT_WRITE = SEL && MADR[7:2] == (8'h00>>2) && MWR;
	wire SPRSTOP_WRITE = SEL && MADR[7:2] == (8'h04>>2) && MWR;
	wire SPRCNTU_WRITE = SEL && MADR[7:2] == (8'h08>>2) && MWR;
	wire SPRPAUS_WRITE = SEL && MADR[7:2] == (8'h0C>>2) && MWR;

	// Game Bub port: SPRSTOP (0x03300104) aborts the cel engine (the SDK's
	// DrawSprytes writes it when a list runs too long; the Opera emulator:
	// engine idle). It resets the engine's state (main and corner engines,
	// unpackers, FIFOs, pixel pipes, math, region fill, frame buffer
	// addresses; SPRON and the pause clear) but not the registers the CPU and
	// the CCB DMA write. The CPU writes it while the engine has released the
	// bus (paused by an interrupt or between cels), not in a transfer. The
	// original did not decode it, so the engine could not be aborted.
	bit          ENG_STOP;
	always @(posedge CLK or negedge RST_N) begin
		bit          SPRSTOP_WRITE_OLD;

		if (!RST_N) begin
			SPRSTOP_WRITE_OLD <= 0;
			ENG_STOP <= 0;
		end
		else begin
			ENG_STOP <= 0;
			if (EN && CE_R) begin
				SPRSTOP_WRITE_OLD <= SPRSTOP_WRITE;
				if (SPRSTOP_WRITE && SPRSTOP_WRITE_OLD) ENG_STOP <= 1;
			end
		end
	end
	wire         ENG_RST_N = RST_N & ~ENG_STOP;
	
	bit          CRNA_READY,CRNB_READY;
	bit          CRNA_FINISH,CRNB_FINISH;
	bit          ROW_A_START,ROW_B_START;
	bit          ROW_A_FULL_LOADED,ROW_B_FULL_LOADED;
	
	bit          PAUSE;
	bit          ENGINE_B,ENGINE_B_FF;
	bit          SPR_NEXT;
	bit          SPRITE_END;
	bit  [ 9: 0] LINE_CNT;
	bit          DRAW_REQ;
	wire [ 9: 0] LINE_LAST = SCOB_PRE0.VCNT;
	wire         SPRDATA_ACK = (BUS_STATE_FF == SPR_PREINIT1 || BUS_STATE_FF == SPR_PREINIT3) && !BUS_PB;
	wire         SPRDRAW_ACK = (BUS_STATE_FF == CFB_INIT0);
	wire         SPRDATA_LAST = ((BUS_STATE_FF == SPR_OFFS3 || BUS_STATE_FF == SPR_CALC1 || BUS_STATE_FF == SPR_DATA1) && DMA_REG_ZERO);
	wire         SPRDATA_BURST_LAST = (BUS_STATE_FF == SPR_OFFS3 || (BUS_STATE_FF == SPR_DATA1 && BURST_LAST) || (BUS_STATE_FF == SPR_DATA1 && DMA_REG_ZERO));
	always @(posedge CLK or negedge ENG_RST_N) begin
		bit          SPRSTRT_WRITE_OLD,SPRCNTU_WRITE_OLD,SPRPAUS_WRITE_OLD;
		bit  [ 1: 0] SPRDATA_DELAY;
		bit          SPRDATA_BURST_LAST_FF;
		bit          SPRDATA_A_FIRST,SPRDATA_B_FIRST;
		bit          SPRDATA_A_RUN,SPRDATA_B_RUN;
		bit          SPRDATA_ENG_NEXT;
		bit          SPRDATA_ENG_SEL;
		bit          SPRDATA_ENG_B_DISABLE;
		bit          SPRDRAW_RUN;
		bit          NEXT_LINE_A_PEND,NEXT_LINE_B_PEND;
`ifdef DEBUG
		bit  [ 7: 0] DBG_EXT_OLD;
`endif
		
		if (!ENG_RST_N) begin
			MAIN_ST <= MS_IDLE;
			SCOBLD_REQ <= '0;
			SPRDATA_REQ <= '0;
			SPRDRAW_REQ <= 0;
			SPRPAUS_REQ <= 0;
			SPREND_REQ <= 0;
			{SPRPRQ,SPREND,SPRPAUS,SPRON} <= '0;
			PAUSE <= 0;
			ENGINE_B <= 0;
			SPR_NEXT <= 0;
			LINE_CNT <= '0;
			{SPRDATA_A_FIRST,SPRDATA_B_FIRST} <= '0;
			{SPRDATA_A_RUN,SPRDATA_B_RUN} <= '0;
			{NEXT_LINE_A_PEND,NEXT_LINE_B_PEND} <= '0;
			SPRITE_END <= 0;
			{ROW_A_START,ROW_B_START} <= '0;
			{ROW_A_FULL_LOADED,ROW_B_FULL_LOADED} <= '0;
			{SPRDRAW_RUN} <= '0;
`ifdef DEBUG
			{DBG_SPRITE_NUM,DBG_SPRITE_HIT} <= '0;
			DBG_SPRITE_CNT <= 8'd255;
`endif
		end
		else if (EN) begin
			if (CE_R) begin
`ifdef DEBUG
				if (SPRON && !PAUSE /*&& ROW_A_FULL_LOADED*/) DBG_WAIT_CNT <= DBG_WAIT_CNT + 1'd1;
`endif
				SPRDATA_BURST_LAST_FF <= SPRDATA_BURST_LAST;

				SPRITE_END <= 0;
			end
			
			
			case (MAIN_ST)
				MS_IDLE: if (CE_R) begin
					if (SPR_NEXT && !SCOBLD_REQ) begin
						SPR_NEXT <= 0;
						SPREND_REQ <= 0;
						SCOBLD_REQ <= 3'd1;
						MAIN_ST <= MS_SCOB_LOAD_1;
`ifdef DEBUG
						DBG_WAIT_CNT <= '0;
`endif
					end
				end
				
				MS_SCOB_LOAD_1: if (CE_F) begin
					if (BUS_STATE_FF == SCOB_YPOS1) begin
						if (SCOB_FLAG.SKIP) begin
							MAIN_ST <= MS_END;
						end else if (SCOB_FLAG.LDPPMP || SCOB_FLAG.LDPRS || SCOB_FLAG.LDSIZE) begin
							SCOBLD_REQ <= 3'd2;
							MAIN_ST <= MS_SCOB_LOAD_2;
						end else begin
							SCOBLD_REQ <= 3'd3;
							MAIN_ST <= MS_SCOB_LOAD_3;
						end
`ifdef DEBUG
						DBG_SPRITE_HIT <= DBG_SPRITE_NUM == DBG_SPRITE_CNT;
`endif
					end
				end
				
				MS_SCOB_LOAD_2: if (CE_F) begin
					if ((BUS_STATE_FF == SCOB_LINEDY1 && !SCOB_SEL[1] && !SCOB_SEL[2]) || (BUS_STATE_FF == SCOB_DDY1 && !SCOB_SEL[2]) || (BUS_STATE_FF == SCOB_PPMP1)) begin
						SCOBLD_REQ <= 3'd3;
						MAIN_ST <= MS_SCOB_LOAD_3;
					end
				end
				
				MS_SCOB_LOAD_3: if (CE_F) begin
					if ((BUS_STATE_FF == SCOB_PRE01 && !SCOB_SEL[0]) || BUS_STATE_FF == SCOB_PRE11) begin
						if (SCOB_FLAG.LDPIP) begin
							SCOBLD_REQ <= 3'd4;
							MAIN_ST <= MS_SCOB_LOAD_4;
						end else begin
							MAIN_ST <= MS_SPRDATA_INIT;
						end
					end
				end
				
				MS_SCOB_LOAD_4: if (CE_F) begin
					if (BUS_STATE_FF == SCOB_PIP1 && SCOB_SEL[0]) begin
						if (!LAST_PIP) begin
							SCOBLD_REQ <= 3'd4;
							MAIN_ST <= MS_SCOB_LOAD_4;
						end else begin
							//Load first portion of sprite data
							LINE_CNT <= 10'd0;
							SPRDATA_A_FIRST <= 1;
							SPRDATA_ENG_B_DISABLE <= 1;
							if (LINE_LAST && !LRFORM) begin
								LINE_CNT <= 10'd1;
								SPRDATA_B_FIRST <= 1;
								SPRDATA_ENG_B_DISABLE <= FB_IN_DRAM;
							end
							{ROW_A_FULL_LOADED,ROW_B_FULL_LOADED} <= '0;
							{NEXT_LINE_A_PEND,NEXT_LINE_B_PEND} <= 0;
							{SPRDATA_A_RUN,SPRDATA_B_RUN} <= 0;
							MAIN_ST <= MS_SPRDATA_A_REQ;
						end
					end
				end
				
				MS_SPRDATA_INIT: if (CE_F) begin
					//Load first portion of sprite data
					LINE_CNT <= 10'd0;
					SPRDATA_A_FIRST <= 1;
					SPRDATA_ENG_B_DISABLE <= 1;
					if (LINE_LAST && !LRFORM) begin
						LINE_CNT <= 10'd1;
						SPRDATA_B_FIRST <= 1;
						SPRDATA_ENG_B_DISABLE <= FB_IN_DRAM;
					end
					{ROW_A_FULL_LOADED,ROW_B_FULL_LOADED} <= '0;
					{NEXT_LINE_A_PEND,NEXT_LINE_B_PEND} <= 0;
					{SPRDATA_A_RUN,SPRDATA_B_RUN} <= 0;
					MAIN_ST <= MS_SPRDATA_A_REQ;
				end
				
				MS_SPRDATA_A_REQ: if (CE_R) begin
					if (!SPRDATA_REQ) begin
						if (!ROW_A_FULL_LOADED) begin
							SPRDATA_ENG_SEL <= 0;
							SPRDATA_A_FIRST <= 0;
							SPRDATA_REQ <= SPRDATA_A_FIRST ? 2'd1 : 2'd2;
							SPRDATA_A_RUN <= 1;
							MAIN_ST <= MS_SPRDATA_A_WAIT;
						end else begin
							MAIN_ST <= MS_SPRDATA_NEXT;
						end
`ifdef DEBUG
						DBG_WAIT_CNT <= '0;
						DBG_SPRITE_INIT <= 1;
`endif
					end
				end
				
				MS_SPRDATA_A_WAIT: if (CE_R) begin
					if (!SPRDATA_REQ) begin
						MAIN_ST <= MS_SPRDATA_NEXT;
`ifdef DEBUG
						DBG_SPRITE_INIT <= 0;
`endif
					end
				end
				
				MS_SPRDATA_B_REQ: if (CE_R) begin
					if (!SPRDATA_REQ) begin
						if (!ROW_B_FULL_LOADED) begin
							SPRDATA_ENG_SEL <= 1;
							SPRDATA_B_FIRST <= 0;
							SPRDATA_REQ <= SPRDATA_B_FIRST ? 2'd1 : 2'd2;
							SPRDATA_B_RUN <= 1;
							MAIN_ST <= MS_SPRDATA_B_WAIT;
						end else begin
							MAIN_ST <= MS_SPRDATA_NEXT;
						end
`ifdef DEBUG
						DBG_WAIT_CNT <= '0;
						DBG_SPRITE_INIT <= 1;
`endif
					end
				end
				
				MS_SPRDATA_B_WAIT: if (CE_R) begin
					if (!SPRDATA_REQ) begin
						MAIN_ST <= MS_SPRDATA_NEXT;
`ifdef DEBUG
						DBG_SPRITE_INIT <= 0;
`endif
					end
				end
				
				MS_SPRDATA_NEXT: if (CE_R) begin
					if (NEXT_LINE_A_PEND && !SPRDATA_A_RUN /*&& (NEXT_LINE_B_PEND || !LRFORM)*/ && LINE_CNT != LINE_LAST) begin
						MAIN_ST <= MS_LINE_A_WAIT;
					end
					else if (NEXT_LINE_B_PEND && !SPRDATA_B_RUN && !SPRDATA_ENG_B_DISABLE && LINE_CNT != LINE_LAST) begin
						MAIN_ST <= MS_LINE_B_WAIT;
					end
					else if ((CRNA_READY || CRNB_READY) && !SPRDRAW_RUN) begin
						MAIN_ST <= MS_SPR_DRAW_START;
					end
					else if (SPR_FIFO_A_HALF && (SPR_FIFO_B_HALF || !LRFORM) && !ROW_A_FULL_LOADED && !SPRDATA_A_RUN) begin
						MAIN_ST <= MS_SPRDATA_A_REQ;
					end
					else if (SPR_FIFO_B_HALF && !ROW_B_FULL_LOADED && !SPRDATA_B_RUN && !SPRDATA_ENG_B_DISABLE) begin
						MAIN_ST <= MS_SPRDATA_B_REQ;
					end
					else if (NEXT_LINE_A_PEND && (NEXT_LINE_B_PEND || !LINE_LAST || SPRDATA_ENG_B_DISABLE) && LINE_CNT == LINE_LAST) begin
						MAIN_ST <= MS_END;
					end
`ifdef DEBUG
					if (!PAUSE) DBG_WAIT_CNT <= DBG_WAIT_CNT + 1'd1;
`endif
				end
				
				MS_SPR_DRAW_START: if (CE_F) begin
					if (!SPRDRAW_REQ) begin
						SPRDRAW_REQ <= 1;
						SPRDRAW_RUN <= 1;
						MAIN_ST <= MS_SPR_DRAW_WAIT;
`ifdef DEBUG
						DBG_WAIT_CNT <= '0;
`endif
					end
				end
				
				MS_SPR_DRAW_WAIT: if (CE_R) begin
					if (!SPRDRAW_REQ) begin
						MAIN_ST <= MS_SPRDATA_NEXT;
`ifdef DEBUG
						DBG_WAIT_CNT <= '0;
`endif
					end
				end
				
				MS_LINE_A_WAIT: if (CE_R) begin
					if (NEXT_LINE_A_PEND && (NEXT_LINE_B_PEND || !LRFORM)) begin
						NEXT_LINE_A_PEND <= 0;
						ROW_A_FULL_LOADED <= 0;
						if (LRFORM) begin
							NEXT_LINE_B_PEND <= 0;
							ROW_B_FULL_LOADED <= 0;
						end 
						if (LINE_CNT == LINE_LAST) begin
							MAIN_ST <= MS_SPRDATA_NEXT;
						end else begin
							LINE_CNT <= LINE_CNT + 1'd1;
							SPRDATA_A_FIRST <= 1;
							MAIN_ST <= MS_SPRDATA_A_REQ;
						end
`ifdef DEBUG
						DBG_WAIT_CNT <= '0;
`endif
					end
				end
				
				MS_LINE_B_WAIT: if (CE_R) begin
					if (NEXT_LINE_B_PEND) begin
						NEXT_LINE_B_PEND <= 0;
						ROW_B_FULL_LOADED <= 0;
						if (SPRDATA_ENG_B_DISABLE || LRFORM) begin
							MAIN_ST <= MS_SPRDATA_NEXT;
						end else if (LINE_CNT == LINE_LAST) begin
							MAIN_ST <= MS_SPRDATA_NEXT;
						end else begin
							LINE_CNT <= LINE_CNT + 1'd1;
							SPRDATA_B_FIRST <= 1;
							MAIN_ST <= MS_SPRDATA_B_REQ;
						end
					end
				end
				
				MS_END: if (CE_R) begin
					SPRITE_END <= 1;
					MAIN_ST <= MS_IDLE;
				end
				
			endcase
			
			if (CE_R) begin
			SPRSTRT_WRITE_OLD <= SPRSTRT_WRITE;
			SPRCNTU_WRITE_OLD <= SPRCNTU_WRITE;
			SPRPAUS_WRITE_OLD <= SPRPAUS_WRITE;
			if (SPRSTRT_WRITE && SPRSTRT_WRITE_OLD && DBG_SPR_EN) begin
				SPR_NEXT <= 1;
				SPRON <= 1;
`ifdef DEBUG
				DBG_SPRITE_NUM <= '0;
`endif
			end
			if (SPRCNTU_WRITE && SPRCNTU_WRITE_OLD && PAUSE) begin
				PAUSE <= 0;
				SPREND_REQ <= 0;
				SPRPAUS_REQ <= 0;
				if (!SPRPAUS_REQ) SPR_NEXT <= 1;
`ifdef DEBUG
				DBG_WAIT_CNT <= '0;
`endif
			end
			if (SPRPAUS_WRITE && SPRPAUS_WRITE_OLD && !PAUSE) begin
				SPRPAUS <= 1;
			end
			{SPRPRQ,SPREND} <= '0;//TODO
			
			//SCOB read
			if (SCOBLD_REQ && (BUS_STATE_FF == SCOB_INIT1 || BUS_STATE_FF == SCOB_INIT3 || BUS_STATE_FF == SCOB_INIT5 || BUS_STATE_FF == SCOB_INIT7) && !BUS_PB/*ACK*/) begin
				SCOBLD_REQ <= '0;
			end
			
			//Sprite data read
			if (CRNA_ST == CRN_ROW_INIT10 && CE_R) begin ROW_A_START <= 0; if (LRFORM) ROW_B_START <= 1; end
			if (CRNB_ST == CRN_ROW_INIT10 && CE_R) begin ROW_B_START <= 0; end
			if (POFFS_FETCH) begin
				if (!ENGINE_B) ROW_A_START <= 1;
				if ( ENGINE_B) ROW_B_START <= 1;
			end
			if (SPRDATA_LAST) begin
				if (!ENGINE_B) begin ROW_A_FULL_LOADED <= 1; if (LRFORM) ROW_B_FULL_LOADED <= 1; end
				if ( ENGINE_B) begin ROW_B_FULL_LOADED <= 1; end
			end
			
			if (CSA_ST == CS_NEXT_LINE && CRNA_FINISH) begin
				NEXT_LINE_A_PEND <= 1;
			end
			if (CSB_ST == CS_NEXT_LINE && CRNB_FINISH) begin
				NEXT_LINE_B_PEND <= 1;
			end

			if (SPRDATA_BURST_LAST_FF) begin
				if (!ENGINE_B_FF) SPRDATA_A_RUN <= 0;
				if ( ENGINE_B_FF) SPRDATA_B_RUN <= 0;
			end
			if (SPRDATA_REQ && SPRDATA_ACK) begin
				SPRDATA_REQ <= '0;
			end
			
			ENGINE_B_FF <= ENGINE_B;
			
			//Framebuffer read/write
			if (SPRDRAW_REQ && SPRDRAW_ACK) begin
				SPRDRAW_REQ <= 0;
			end
			if (BUS_STATE_FF == CFB_WRITE1 && (DST_LAST_A || DST_SUSPEND)) begin
				SPRDRAW_RUN <= 0;
			end
			
			//Pause/resume/end 
			if (SPRITE_END) begin
				if (SCOB_FLAG.LAST) begin
					SPRON <= 0;
					SPREND_REQ <= 1;
				end else if (SPRPAUS) begin
					PAUSE <= 1;
					SPRPAUS_REQ <= 1;
				end else begin
					SPR_NEXT <= 1;
`ifdef DEBUG
					DBG_SPRITE_NUM <= DBG_SPRITE_NUM + 1'd1;
`endif
				end
				SPRPAUS <= 0;
			end
			else if (INT_REQ && !PAUSE && SPRON) begin
				PAUSE <= 1;
				SPRPAUS_REQ <= 1;
			end
			
`ifdef DEBUG
			DBG_EXT_OLD <= DBG_EXT;
			if (DBG_EXT[4] && !DBG_EXT_OLD[4]) begin
				DBG_SPRITE_CNT <= DBG_SPRITE_CNT - 1'd1;
			end
			if (DBG_EXT[5] && !DBG_EXT_OLD[5]) begin
				DBG_SPRITE_CNT <= DBG_SPRITE_CNT + 1'd1;
			end
`endif
			end
			
			if (CE_F) begin
			if (SPRDATA_ACK) begin
				ENGINE_B <= SPRDATA_ENG_SEL;
			end
			end
		end
	end 
	assign STAT = {SPRPRQ,SPREND,SPRPAUS,SPRON};
	
	
	bit          REG_LOAD_A0;
	bit  [ 3: 0] PIP_LOAD_CNT;
	bit          PDATA_LOAD_A0;
	bit  [15: 0] LOAD_BUF;
	wire         PLUT_WRITE = PLUT_SEL && MWR;
	bit          CPU_PLUT_ODD;
	bit  [ 3: 0] CPU_PLUT_PAIR;
	bit  [15: 0] CPU_PLUT_LO;
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) begin
			SCOB_FLAG <= SCoBFlag_INIT;
			PPMPCA <= PPMPCx_INIT;
			PPMPCB <= PPMPCx_INIT;
			SCOB_PRE0 <= SCoBPre0_INIT;
			SCOB_PRE1 <= SCoBPre1_INIT;
			REG_LOAD_A0 <= 0;
			PIP_LOAD_CNT <= '0;
			PDATA_LOAD_A0 <= 0;
			CPU_PLUT_ODD <= 0;
			CPU_PLUT_PAIR <= '0;
			CPU_PLUT_LO <= '0;
			// synopsys translate_off
			LOAD_BUF <= '0;
			// synopsys translate_on
`ifdef DEBUG
			DBG_START_CNT <= '0;
`endif
		end
		else if (EN && CE_R) begin
			if (FLAG_FETCH) begin
				SCOB_FLAG <= MDTI & SCoBFlag_WMASK;
				PIP_LOAD_CNT <= '0;
			end
			
			REG_LOAD_A0 <= 0;
			if (REG_FETCH) begin
				REG_LOAD_A0 <= 1;
				LOAD_BUF <= MDTI[15:0];
			end
			
			if (PPMP_FETCH) begin
				{PPMPCB,PPMPCA} <= MDTI & {PPMPCx_WMASK,PPMPCx_WMASK};
`ifdef DEBUG
				DBG_SCOB_PPMPC <= MDTI;
`endif
			end
			
			if (PRE0_FETCH) begin
				SCOB_PRE0 <= MDTI & SCoBPre0_WMASK;
				SCOB_PRE1 <= 32'h00000000;
`ifdef DEBUG
				DBG_SCOB_PRE0 <= MDTI;
`endif
			end
			if (PRE1_FETCH) begin
				SCOB_PRE1 <= MDTI & SCoBPre1_WMASK;
`ifdef DEBUG
				DBG_SCOB_PRE1 <= MDTI;
`endif
			end
			
			PIP_WA[0] <= 0;
			if (PIP_FETCH) begin
				PIP_WA[0] <= 1;
				LOAD_BUF <= MDTI[15:0];
			end
			// CPU write of a PLUT pair (0x180 + 4n: entries 2n in bits 31-16,
			// 2n+1 in 15-0, SDK madam.h plut_write): the odd entry next tick
			CPU_PLUT_ODD <= PLUT_WRITE;
			if (PLUT_WRITE) begin
				CPU_PLUT_PAIR <= MADR[5:2];
				CPU_PLUT_LO <= CPU_DI[15:0];
			end
			if (PIP_FETCH) begin
				PIP_LOAD_CNT <= PIP_LOAD_CNT + 4'd1;
			end
			PIP_WA[4:1] <= PIP_LOAD_CNT;
			
			PDATA_LOAD_A0 <= 0;
			if ((POFFS_FETCH || PDATA_FETCH) && !LRFORM) begin
				PDATA_LOAD_A0 <= 1;
				LOAD_BUF <= MDTI[15:0];
			end
			
			//debug
`ifdef DEBUG
			if (FLAG_FETCH) begin
				DBG_SCOB_ADDR <= {MADR,2'b00};
				if ({MADR,2'b00} == 24'h0FBA4C) DBG_START_CNT <= DBG_START_CNT + 1'd1;
			end
			if (BUS_STATE_FF == SCOB_SOURCE1) begin
				DBG_SCOB_SOURCE <= MDTI[23:0];
			end
`endif
		end
	end 
	wire         LAST_PIP = (PIP_LOAD_CNT == 4'h3 && SCOB_PRE0.BPP <= 3'd2) || (PIP_LOAD_CNT == 4'h7 && SCOB_PRE0.BPP == 3'd3) || (PIP_LOAD_CNT == 4'hF && SCOB_PRE0.BPP >= 3'd4);
	
	bit  [ 4: 0] PIP_WA;
	wire [15: 0] PIP_DMA_DIN = !PIP_WA[0] ? MDTI[31:16] : LOAD_BUF;
	// the CPU's PLUT writes (even entry, then odd), else the CEL's PLUT DMA
	wire [ 4: 0] PIP_WADDR = PLUT_WRITE ? {MADR[5:2],1'b0} : CPU_PLUT_ODD ? {CPU_PLUT_PAIR,1'b1} : PIP_WA;
	wire [15: 0] PIP_DIN   = PLUT_WRITE ? CPU_DI[31:16]    : CPU_PLUT_ODD ? CPU_PLUT_LO          : PIP_DMA_DIN;
	wire         PIP_WE = PIP_FETCH || PLUT_WRITE || PIP_WA[0] || CPU_PLUT_ODD;
	// CPU reads: one entry per word, 0x180 + 4n = entry n (SDK plut_read)
	wire [ 4: 0] PIP_CPU_RA = MADR[6:2];
	bit  [ 4: 0] PIP_A_RA;
	bit  [15: 0] PIP_DOUT;
	MADAM_PIP PIP 
	(
		.CLK(CLK),
		.EN(EN),
		
		.WA(PIP_WADDR),
		.DIN(PIP_DIN),
		.WE(PIP_WE & CE_R),
		
		.RA(PLUT_SEL ? PIP_CPU_RA : PIP_A_RA),
		.DOUT(PIP_DOUT)
	);
	assign PLUT_DO = {16'h0000,PIP_DOUT};
	
	bit  [ 4: 0] PIP_B_RA;
	bit  [15: 0] PIP_B_DOUT;
	MADAM_PIP PIP_B
	(
		.CLK(CLK),
		.EN(EN),
		
		.WA(PIP_WADDR),
		.DIN(PIP_DIN),
		.WE(PIP_WE & CE_R),
		
		.RA(PLUT_SEL ? PIP_CPU_RA : PIP_B_RA),
		.DOUT(PIP_B_DOUT)
	);
	
	bit  [ 1: 0] BURST_CNT;
	bit          BURST0;
	always @(posedge CLK or negedge ENG_RST_N) begin
		if (!ENG_RST_N) begin
			BURST_CNT <= '0;
			BURST0 <= 0;
		end
		else if (EN && CE_R) begin
			BURST0 <= 0;
			if (PIP_FETCH || PDATA_FETCH || PIX_WRITE) begin
				BURST_CNT <= BURST_CNT + 2'd1;
			end
			if (BUS_INIT0) begin
				BURST_CNT <= 2'd0;
				BURST0 <= 1;
			end
		end
	end 
	wire         BURST_LAST = (BURST_CNT == 2'd3);
	
	//Control
	bit          SYNC_FIFO_RDREQ;
	
	
	typedef enum bit [2:0] {
		CS_IDLE,
		CS_START,
		CS_INIT,
		CS_DATA_READ,
		CS_NEXT_LINE,
		CS_END
	} CtrlState_t;
	CtrlState_t CSA_ST,CSB_ST;
	
	bit          CORNER_SEL;
	
	bit          UNPACKER_A_NEWL_EN,UNPACKER_B_NEWL_EN;
	bit          UNPACKER_A_TAK_EN,UNPACKER_B_TAK_EN;
	bit          UNPACKER_A_LOAD_NEXT,UNPACKER_B_LOAD_NEXT;
	bit          UNPACKER_A_EOL,UNPACKER_B_EOL;
	bit          UNPACKER_A_READY,UNPACKER_B_READY;
	always @(posedge CLK or negedge ENG_RST_N) begin
		
		if (!ENG_RST_N) begin
			CSA_ST <= CS_IDLE;
			CSB_ST <= CS_IDLE;
			UNPACKER_A_NEWL_EN <= 0;
			UNPACKER_B_NEWL_EN <= 0;
			CORNER_SEL <= 0;
		end
		else if (EN && CE_R) begin
			UNPACKER_A_NEWL_EN <= 0;
			case (CSA_ST)
				CS_IDLE: begin
`ifdef DEBUG
					if (SPRON && !PAUSE) DBG_ROW_WAIT_CNT <= DBG_ROW_WAIT_CNT + 1'd1;
					else DBG_ROW_WAIT_CNT <= '0;
`endif
					
					if (ROW_A_START) begin
						UNPACKER_A_NEWL_EN <= 1;
						CSA_ST <= CS_START;
						
`ifdef DEBUG
						DBG_ROW_WAIT_CNT <= '0;
`endif
					end

`ifdef DEBUG
					DBG_ROWFULL_WAIT_CNT <= '0;
`endif
				end
				
				CS_START: begin
					CSA_ST <= CS_INIT;
					
`ifdef DEBUG
					DBG_ROW_WAIT_CNT <= '0;
`endif
				end
				
				CS_INIT: begin
					if (UNPACKER_A_READY) begin
						CSA_ST <= CS_DATA_READ;
					end else if (UNPACKER_A_EOL) begin
						CSA_ST <= CS_NEXT_LINE;
					end
				end
				
				CS_DATA_READ: begin
					if (UNPACKER_A_READY && (CRNA_ST == CRN_PRECALC || CRNA_ST == CRN_CALC) && (!LF_A_RUN && XY_FIFO_A_EMPTY)) begin
						CSA_ST <= CS_DATA_READ;
					end else if (UNPACKER_A_EOL || CRNA_ST == CRN_END || CRNA_FINISH) begin
						CSA_ST <= CS_NEXT_LINE;
					end
					
`ifdef DEBUG
					if (UNPACKER_A_LOAD_NEXT && ROW_A_FULL_LOADED) DBG_ROWFULL_WAIT_CNT <= DBG_ROWFULL_WAIT_CNT + 1'd1;
					
//					DBG_ROW_WAIT_CNT <= DBG_ROW_WAIT_CNT + 1'd1;
//					if (UNPACKER_A_TAK_EN || PAUSE) DBG_ROW_WAIT_CNT <= '0;
`endif
				end
				
				CS_NEXT_LINE: begin
					if (CRNA_FINISH) begin
						CSA_ST <= CS_IDLE;
					end
					
`ifdef DEBUG
//					DBG_ROW_WAIT_CNT <= DBG_ROW_WAIT_CNT + 1'd1;
//					if (PAUSE) DBG_ROW_WAIT_CNT <= '0;
`endif
				end
			endcase
			
			UNPACKER_B_NEWL_EN <= 0;
			case (CSB_ST)
				CS_IDLE: begin
`ifdef DEBUG
					if (SPRON && !PAUSE) DBG_ROW_B_WAIT_CNT <= DBG_ROW_B_WAIT_CNT + 1'd1;
					else DBG_ROW_B_WAIT_CNT <= '0;
`endif
					
					if (ROW_B_START) begin
						UNPACKER_B_NEWL_EN <= 1;
						CSB_ST <= CS_START;
						
`ifdef DEBUG
						DBG_ROW_B_WAIT_CNT <= '0;
`endif
					end
				end
				
				CS_START: begin
					CSB_ST <= CS_INIT;
				end
				
				CS_INIT: begin
					if (UNPACKER_B_READY) begin
						CSB_ST <= CS_DATA_READ;
					end else if (UNPACKER_B_EOL) begin
						CSB_ST <= CS_NEXT_LINE;
					end
				end
				
				CS_DATA_READ: begin
					if (UNPACKER_B_READY && (CRNB_ST == CRN_PRECALC || CRNB_ST == CRN_CALC) && (!LF_B_RUN && XY_FIFO_A_EMPTY)) begin
						CSB_ST <= CS_DATA_READ;
					end else if (UNPACKER_B_EOL || CRNB_ST == CRN_END || CRNB_FINISH) begin
						CSB_ST <= CS_NEXT_LINE;
					end
				end
				
				CS_NEXT_LINE: if (CRNB_FINISH) begin
					CSB_ST <= CS_IDLE;
				end
			endcase
			
			CORNER_SEL <= ~CORNER_SEL;
		end
	end 
	assign UNPACKER_A_TAK_EN = (CRNA_ST == CRN_CALC && UNPACKER_A_READY && (CRNB_ST == CRN_CALC || !LRFORM));
	assign UNPACKER_B_TAK_EN = (CRNB_ST == CRN_CALC && UNPACKER_B_READY && (CRNA_ST == CRN_CALC || !LRFORM)); 
	
	//Color mapping path
	wire [15: 0] SPR_FIFO_A_DIN = LRFORM ? MDTI[31:16] : !PDATA_LOAD_A0 ? MDTI[31:16] : LOAD_BUF;
	wire         SPR_FIFO_A_WE = (POFFS_FETCH || PDATA_FETCH || PDATA_LOAD_A0) && (~ENGINE_B_FF || LRFORM);
	wire         SPR_FIFO_A_RES = (BUS_STATE_FF == SPR_INIT1 && !BUS_PB && (!ENGINE_B || LRFORM)) || SPRITE_END;
	wire         SPR_FIFO_A_RDREQ = UNPACKER_A_LOAD_NEXT;
	bit  [15: 0] SPR_FIFO_A_OUT;
	bit          SPR_FIFO_A_HALF;
	bit          SPR_FIFO_A_EMPTY;
	MADAM_SPRYTE_DATA_FIFO SPR_FIFO_A 
	(
		.CLK(CLK),
		.EN(EN),
		.RST(SPR_FIFO_A_RES | ~ENG_RST_N),
		
		.DIN(SPR_FIFO_A_DIN),
		.WRREQ(SPR_FIFO_A_WE & CE_R),
		
		.RDREQ(SPR_FIFO_A_RDREQ & CE_F),
		.DOUT(SPR_FIFO_A_OUT),
		.LESSHALF(SPR_FIFO_A_HALF),
		.EMPTY(SPR_FIFO_A_EMPTY)
	);
	
	wire [15: 0] SPR_FIFO_B_DIN = LRFORM ? MDTI[15:0] : !PDATA_LOAD_A0 ? MDTI[31:16] : LOAD_BUF;
	wire         SPR_FIFO_B_WE = (POFFS_FETCH || PDATA_FETCH || PDATA_LOAD_A0) && (ENGINE_B_FF || LRFORM);
	wire         SPR_FIFO_B_RES = (BUS_STATE_FF == SPR_INIT1 && !BUS_PB && (ENGINE_B || LRFORM)) || SPRITE_END;
	wire         SPR_FIFO_B_RDREQ = UNPACKER_B_LOAD_NEXT;
	bit  [15: 0] SPR_FIFO_B_OUT;
	bit          SPR_FIFO_B_HALF;
	bit          SPR_FIFO_B_EMPTY;
	MADAM_SPRYTE_DATA_FIFO SPR_FIFO_B 
	(
		.CLK(CLK),
		.EN(EN),
		.RST(SPR_FIFO_B_RES | ~ENG_RST_N),
		
		.DIN(SPR_FIFO_B_DIN),
		.WRREQ(SPR_FIFO_B_WE & CE_R),
		
		.RDREQ(SPR_FIFO_B_RDREQ & CE_F),
		.DOUT(SPR_FIFO_B_OUT),
		.LESSHALF(SPR_FIFO_B_HALF),
		.EMPTY(SPR_FIFO_B_EMPTY)
	);
	
	//613a,613b
	bit  [15: 0] UNPACKER_A_OUT,UNPACKER_B_OUT;
	bit          UNPACKER_A_T,UNPACKER_B_T;
	MADAM_UNPACKER UNPACKER_A
	(
		.CLK(CLK),
		.RST(SPR_FIFO_A_RES | ~ENG_RST_N),
		.EN(EN),
		
		.CE(CE_R),
		
		.PRE0_BPP(SCOB_PRE0.BPP),
		.PRE0_SKPX(SCOB_PRE0.SKPX),
		.PRE1_PCNT(SCOB_PRE1.TLHPCNT),
		.PACKED(SCOB_FLAG.PACKED),
		
		.IN(SPR_FIFO_A_EMPTY && ROW_A_FULL_LOADED ? '0 : SPR_FIFO_A_OUT),
		.AVAIL(~SPR_FIFO_A_EMPTY | ROW_A_FULL_LOADED),
		.NEWL(UNPACKER_A_NEWL_EN),
		.TAK(UNPACKER_A_TAK_EN),
		
		.T(UNPACKER_A_T),
		.OUT(UNPACKER_A_OUT),
		.NEXT(UNPACKER_A_LOAD_NEXT),
		.EOL(UNPACKER_A_EOL),
		.READY(UNPACKER_A_READY)
	);
	
	MADAM_UNPACKER UNPACKER_B
	(
		.CLK(CLK),
		.RST(SPR_FIFO_B_RES | ~ENG_RST_N),
		.EN(EN),
		
		.CE(CE_R),
		
		.PRE0_BPP(SCOB_PRE0.BPP),
		.PRE0_SKPX(SCOB_PRE0.SKPX),
		.PRE1_PCNT(SCOB_PRE1.TLHPCNT),
		.PACKED(SCOB_FLAG.PACKED),
		
		.IN(SPR_FIFO_B_EMPTY && ROW_B_FULL_LOADED ? '0 : SPR_FIFO_B_OUT),
		.AVAIL(~SPR_FIFO_B_EMPTY | ROW_B_FULL_LOADED),
		.NEWL(UNPACKER_B_NEWL_EN),
		.TAK(UNPACKER_B_TAK_EN),
		
		.T(UNPACKER_B_T),
		.OUT(UNPACKER_B_OUT),
		.NEXT(UNPACKER_B_LOAD_NEXT),
		.EOL(UNPACKER_B_EOL),
		.READY(UNPACKER_B_READY)
	);
	
	wire [15: 0] PIN_A = UNPACKER_A_OUT;
	wire [15: 0] PIN_B = UNPACKER_B_OUT;
	wire         TRANSPARENT = UNPACKER_A_T;
	wire         TRANSPARENT_B = UNPACKER_B_T;
	
	//IPS
	wire IPS_A_EN = (CRNA_ST == CRN_OUT);
	wire IPS_B_EN = (CRNB_ST == CRN_OUT);
	
	IPN_t        IPN_A,IPN_B;
	always_comb begin
		case (SCOB_PRE0.BPP)
			3'h0,
			3'h1:    PIP_A_RA = {SCOB_FLAG.PIPA[3:0],PIN_A[0:0]};
			3'h2:    PIP_A_RA = {SCOB_FLAG.PIPA[3:1],PIN_A[1:0]};
			3'h3:    PIP_A_RA = {SCOB_FLAG.PIPA[3:3],PIN_A[3:0]};
			default: PIP_A_RA = {                    PIN_A[4:0]};
		endcase
		case (SCOB_PRE0.BPP)
			3'h0,
			3'h1:    PIP_B_RA = {SCOB_FLAG.PIPA[3:0],PIN_B[0:0]};
			3'h2:    PIP_B_RA = {SCOB_FLAG.PIPA[3:1],PIN_B[1:0]};
			3'h3:    PIP_B_RA = {SCOB_FLAG.PIPA[3:3],PIN_B[3:0]};
			default: PIP_B_RA = {                    PIN_B[4:0]};
		endcase
	end
	
	always @(posedge CLK or negedge ENG_RST_N) begin
		PPMPCx_t     PPMPC;
		bit          PPMPC_SEL;
		bit          D,T,RMODE,SPH,SPV;
		bit  [ 4: 0] R,G,B;
		bit  [ 2: 0] MR,MG,MB;
		
		if (!ENG_RST_N) begin
			IPN_A <= '0;
		end
		else if (IPS_A_EN && EN && CE_F) begin
			casex ({SCOB_PRE0.LINEAR,SCOB_PRE0.BPP})
				4'bx100: D =      PIN_A[ 5];
				4'b011x: D =      PIN_A[15];
				4'b1101: D =            0;
				4'b111x: D =      PIN_A[15];
				default: D = PIP_DOUT[15];
			endcase
			case (SCOB_FLAG.DOVER)
				2'b00,
				2'b01: PPMPC_SEL = D;   // Game Bub port: 01 = no override (see MADAM_PPMP)
				2'b10: PPMPC_SEL = 0;
				2'b11: PPMPC_SEL = 1;
			endcase
			PPMPC = !PPMPC_SEL ? PPMPCA : PPMPCB;
			
			casex ({SCOB_PRE0.LINEAR,SCOB_PRE0.BPP})
				4'b1101: {R,G,B} = {{PIN_A[7:5],PIN_A[7:6]&{2{SCOB_PRE0.REP8}}},{PIN_A[4:2],PIN_A[4:3]&{2{SCOB_PRE0.REP8}}},{PIN_A[1:0],PIN_A[1:0]&{2{SCOB_PRE0.REP8}},PIN_A[1]&SCOB_PRE0.REP8}};
				4'b111x: {R,G,B} = {PIN_A[14:10],PIN_A[9:5],PIN_A[4:0]};
				default: {R,G,B} = {PIP_DOUT[14:10],PIP_DOUT[ 9: 5],PIP_DOUT[ 4: 0]};
			endcase
			T = (~|{R,G,B} & ~SCOB_FLAG.BGND) | TRANSPARENT;
			casex ({SCOB_PRE0.LINEAR,SCOB_PRE0.BPP})
				4'b0101: {MR,MG,MB} = {PIN_A[ 7: 5],PIN_A[ 7: 5],PIN_A[ 7: 5]};
				4'b011x: {MR,MG,MB} = {PIN_A[13:11],PIN_A[10: 8],PIN_A[ 7: 5]};
				default: {MR,MG,MB} = {    3'b000,    3'b000,    3'b000};
			endcase
			RMODE = PPMPC.S1 == 1'd1 || PPMPC.S2 == 2'd2;
			SPH = SCOB_FLAG.PIPPOS ? B[0] : SUB_H;
			SPV = SCOB_FLAG.PIPPOS ? D : SUB_V;
		
			IPN_A <= {D,R,G,B,T,MR,MG,MB,RMODE,SPH,SPV};
		end
	end
	
	always @(posedge CLK or negedge ENG_RST_N) begin
		PPMPCx_t     PPMPC;
		bit          PPMPC_SEL;
		bit          D,T,RMODE,SPH,SPV;
		bit  [ 4: 0] R,G,B;
		bit  [ 2: 0] MR,MG,MB;
		
		if (!ENG_RST_N) begin
			IPN_B <= '0;
		end
		else if (IPS_B_EN && EN && CE_F) begin
			casex ({SCOB_PRE0.LINEAR,SCOB_PRE0.BPP})
				4'bx100: D =      PIN_B[ 5];
				4'b011x: D =      PIN_B[15];
				4'b1101: D =            0;
				4'b111x: D =      PIN_B[15];
				default: D = PIP_B_DOUT[15];
			endcase
			case (SCOB_FLAG.DOVER)
				2'b00,
				2'b01: PPMPC_SEL = D;   // Game Bub port: 01 = no override (see MADAM_PPMP)
				2'b10: PPMPC_SEL = 0;
				2'b11: PPMPC_SEL = 1;
			endcase
			PPMPC = !PPMPC_SEL ? PPMPCA : PPMPCB;
			
			casex ({SCOB_PRE0.LINEAR,SCOB_PRE0.BPP})
				4'b1101: {R,G,B} = {{PIN_B[7:5],PIN_B[7:6]&{2{SCOB_PRE0.REP8}}},{PIN_B[4:2],PIN_B[4:3]&{2{SCOB_PRE0.REP8}}},{PIN_B[1:0],PIN_B[1:0]&{2{SCOB_PRE0.REP8}},PIN_B[1]&SCOB_PRE0.REP8}};
				4'b111x: {R,G,B} = {PIN_B[14:10],PIN_B[9:5],PIN_B[4:0]};
				default: {R,G,B} = {PIP_B_DOUT[14:10],PIP_B_DOUT[ 9: 5],PIP_B_DOUT[ 4: 0]};
			endcase
			T = (~|{R,G,B} & ~SCOB_FLAG.BGND) | TRANSPARENT_B;
			casex ({SCOB_PRE0.LINEAR,SCOB_PRE0.BPP})
				4'b0101: {MR,MG,MB} = {PIN_B[ 7: 5],PIN_B[ 7: 5],PIN_B[ 7: 5]};
				4'b011x: {MR,MG,MB} = {PIN_B[13:11],PIN_B[10: 8],PIN_B[ 7: 5]};
				default: {MR,MG,MB} = {    3'b000,    3'b000,    3'b000};
			endcase
			RMODE = PPMPC.S1 == 1'd1 || PPMPC.S2 == 2'd2;
			SPH = SCOB_FLAG.PIPPOS ? B[0] : SUB_H;
			SPV = SCOB_FLAG.PIPPOS ? D : SUB_V;
		
			IPN_B <= {D,R,G,B,T,MR,MG,MB,RMODE,SPH,SPV};
		end
	end
	
	IPN_t        IPN_A_FF,IPN_B_FF;
	always @(posedge CLK or negedge ENG_RST_N) begin		
		if (!ENG_RST_N) begin
			IPN_A_FF <= '0;
			IPN_B_FF <= '0;
		end
		else if (EN && CE_R) begin
			IPN_A_FF <= IPN_A;
			IPN_B_FF <= IPN_B;
		end
	end
	
	bit          IPS_FIFO_FULL,IPS_FIFO_EMPTY;
	IPN_t        IPS_FIFO_A_OUT;
	MADAM_SYNC_FIFO #(29) IPS_FIFO 
	(
		.CLK(CLK),
		.EN(EN),
		.RST(SPR_NEXT | ~ENG_RST_N),
		
		.DIN(LF_A_REQ ? IPN_A : IPN_A_FF),
		.WRREQ(XY_FIFO_A_WRREQ & CE_R),
		
		.RDREQ(SYNC_FIFO_RDREQ & CE_F),
		.DOUT(IPS_FIFO_A_OUT),
		
		.FULL(IPS_FIFO_FULL),
		.EMPTY(IPS_FIFO_EMPTY)
	);
	
	IPN_t        IPS_FIFO_B_OUT;
	MADAM_SYNC_FIFO #(29) IPS_FIFO_B 
	(
		.CLK(CLK),
		.EN(EN),
		.RST(SPR_NEXT | ~ENG_RST_N),
		
		.DIN(LF_B_REQ ? IPN_B : IPN_B_FF),
		.WRREQ(XY_FIFO_A_WRREQ & CE_R),
		
		.RDREQ(SYNC_FIFO_RDREQ & CE_F),
		.DOUT(IPS_FIFO_B_OUT),
		
		.FULL(),
		.EMPTY()
	);
	
	IPN_t        IPN_PIPE;
	
	bit  [15: 0] CFBD_PIPE,CFBD_PIPE_A,CFBD_PIPE_B;
	always @(posedge CLK or negedge ENG_RST_N) begin
		IPN_t        IPS_FIFO_B_OUT_FF;
		
		if (!ENG_RST_N) begin
			IPN_PIPE <= '0;
			CFBD_PIPE_A <= '0;
			CFBD_PIPE_B <= '0;
		end
		else if (EN && CE_R) begin
			IPS_FIFO_B_OUT_FF <= IPS_FIFO_B_OUT;
			IPN_PIPE <= BUS_STATE_FF == CFB_INIT0 || BUS_STATE_FF == CFB_WRITE0 || BUS_STATE_FF == CFB_READ0 ? IPS_FIFO_A_OUT : IPS_FIFO_B_OUT_FF;
			if (PIX_READ0) begin
				CFBD_PIPE_A <= !DST_ADDR_A[1] ? MDTI[31:16] : MDTI[15:0];
			end
			if (PIX_READ1) begin
				CFBD_PIPE_B <= !DST_ADDR_B[1] ? MDTI[31:16] : MDTI[15:0];
			end
		end
	end
	assign CFBD_PIPE = BUS_STATE_FF == CFB_WRITE1 || BUS_STATE_FF == CFB_READ1 ? CFBD_PIPE_A : CFBD_PIPE_B;
`ifdef DEBUG
	assign DBG_IPS_FIFO_OUT = IPS_FIFO_A_OUT;
	assign DBG_IPS_FIFO_B_OUT = IPS_FIFO_B_OUT;
`endif

	//PPMP
	bit  [15: 0] PPMP_PEN;
	MADAM_PPMP PPMP	
	(
		.CLK(CLK),
		.RST(~ENG_RST_N),
		.EN(EN),
		
		.CE(CE_R),
		
		.SCOBCTL(SCOBCTL),
		.SCOB_FLAG(SCOB_FLAG),
		.SCOB_PRE1(SCOB_PRE1),
		.PPMPCA(PPMPCA),
		.PPMPCB(PPMPCB),
		
		.IPN(IPN_PIPE),
		.CFBD(CFBD_PIPE),
		.PEN(PPMP_PEN)
	);
	assign PEN_DO = {PPMP_PEN,PPMP_PEN};
	
	//Points mapping path
	bit          PFIFO_A_YXX_EN;
	bit          XY_FIFO_A_WRREQ;
	bit          XY_FIFO_A_LESSHALF;
	
	YX_t         LF_A_XY,LF_B_XY;
	bit          LF_A_LAST,LF_B_LAST;
	bit          LF_A_RUN,LF_B_RUN;
	bit          LF_DOLO;
	bit          LF_A_REQ,LF_B_REQ;
	
	typedef enum bit [4:0] {
		CRN_IDLE,
		CRN_ROW_INIT0,CRN_ROW_INIT1,CRN_ROW_INIT2,CRN_ROW_INIT3,CRN_ROW_INIT4,CRN_ROW_INIT5,CRN_ROW_INIT6,CRN_ROW_INIT7,CRN_ROW_INIT8,CRN_ROW_INIT9,CRN_ROW_INIT10,
		CRN_PRECALC,CRN_CALC,
		CRN_REGIS,
		CRN_OUT,
		CRN_REGIS_DONE,
		CRN_END
	} CornerState_t;
	CornerState_t CRNA_ST,CRNB_ST;
	
	MathStat_t   MATH_A_STAT,MATH_B_STAT;
	// Face culling (ACW/ACCW). The region fill's edge walkers give a span
	// from right to left for a counterclockwise quad, so the span's
	// direction selects the flag. The 1:1 path (MF: HDX or HDY +-1.0, VDY
	// or VDX +-1.0, no HDDX/HDDY) spans corner 0 to corner 2, whose
	// direction is the sign of HDX (or VDX) only; there the winding is the
	// sign of HDX * VDY - HDY * VDX (MATH STAT.MCW: clockwise, Opera
	// TestInitVisual), for both directions of the span.
	wire         ACW_A_EN  = MATH_A_STAT.MF ? (MATH_A_STAT.MCW ? SCOB_FLAG.ACW : SCOB_FLAG.ACCW) : SCOB_FLAG.ACW;
	wire         ACCW_A_EN = MATH_A_STAT.MF ? (MATH_A_STAT.MCW ? SCOB_FLAG.ACW : SCOB_FLAG.ACCW) : SCOB_FLAG.ACCW;
	wire         ACW_B_EN  = MATH_B_STAT.MF ? (MATH_B_STAT.MCW ? SCOB_FLAG.ACW : SCOB_FLAG.ACCW) : SCOB_FLAG.ACW;
	wire         ACCW_B_EN = MATH_B_STAT.MF ? (MATH_B_STAT.MCW ? SCOB_FLAG.ACW : SCOB_FLAG.ACCW) : SCOB_FLAG.ACCW;
	MathCtl_t    MATH_A_CTL,MATH_B_CTL;
	
	bit          REGIS_A_OUT,REGIS_B_OUT;
	bit  [11: 0] Y_A,Y_B,REGIS_A_Y,REGIS_B_Y;
	bit          CLIPX_A,CLIPY_A,CLIPX_B,CLIPY_B;
	
	bit          REGIS_A_START,REGIS_A_TERMINATE;
	always_comb begin		
		Y_A = REGIS_A_OUT ? REGIS_A_Y : MATH_A_Y;
				
		CLIPX_A = ($signed(MATH_A_XL) > $signed({1'b0,REGCTL1.CLIPX}) && $signed(MATH_A_XR) > $signed({1'b0,REGCTL1.CLIPX})) || ($signed(MATH_A_XL) < 0 && $signed(MATH_A_XR) < 0);
		CLIPY_A = $signed(Y_A) > $signed({1'b0,REGCTL1.CLIPY}) || $signed(Y_A) < 0;
		REGIS_A_START = (CRNA_ST == CRN_CALC && !UNPACKER_A_EOL && !MATH_A_STAT.NP && !(MATH_A_STAT.MF || SCOB_FLAG.MARIA) && !MATH_A_STAT.RC);
		// Game Bub port: the clip Y limit (REGCTL1, 11 bits, the last row) is
		// unsigned, as in CLIPY_A above; signed, a limit of 1024..2047 was
		// negative and ended every regional fill at once
		REGIS_A_TERMINATE = ($signed(MATH_A_Y) > $signed({1'b0,REGCTL1.CLIPY})) && SCOBCTL.ASCALL;
	end
	bit          REGIS_A_LF_REQ;
	bit          REGIS_A_DONE;
	MADAM_REGIS REGIS_A 
	(
		.CLK(CLK),
		.RST(~ENG_RST_N),
		.EN(EN),
		
		.CE(CE_R),
		
		.START(REGIS_A_START),
		.TERMINATE(REGIS_A_TERMINATE),
		.PAUSE(CRNA_ST != CRN_REGIS),
		.STAT(MATH_A_STAT),
		.LF_AVAIL(~LF_A_RUN),
		.LF_REQ(REGIS_A_LF_REQ),
		
		.CTL(REGIS_A_CTL),
		.DONE(REGIS_A_DONE)
	);
	
	bit          REGIS_B_START,REGIS_B_TERMINATE;
	always_comb begin		
		Y_B = REGIS_B_OUT ? REGIS_B_Y : MATH_B_Y;
				
		CLIPX_B = ($signed(MATH_B_XL) > $signed({1'b0,REGCTL1.CLIPX}) && $signed(MATH_B_XR) > $signed({1'b0,REGCTL1.CLIPX})) || ($signed(MATH_B_XL) < 0 && $signed(MATH_B_XR) < 0);
		CLIPY_B = $signed(Y_B) > $signed({1'b0,REGCTL1.CLIPY}) || $signed(Y_B) < 0;
		REGIS_B_START = (CRNB_ST == CRN_CALC && !UNPACKER_B_EOL && !MATH_B_STAT.NP && !(MATH_B_STAT.MF || SCOB_FLAG.MARIA) && !MATH_B_STAT.RC);
		REGIS_B_TERMINATE = ($signed(MATH_B_Y) > $signed({1'b0,REGCTL1.CLIPY})) && SCOBCTL.ASCALL;
	end
	bit          REGIS_B_LF_REQ;
	bit          REGIS_B_DONE;
	MADAM_REGIS REGIS_B 
	(
		.CLK(CLK),
		.RST(~ENG_RST_N),
		.EN(EN),
		
		.CE(CE_R),
		
		.START(REGIS_B_START),
		.TERMINATE(REGIS_B_TERMINATE),
		.PAUSE(CRNB_ST != CRN_REGIS),
		.STAT(MATH_B_STAT),
		.LF_AVAIL(~LF_B_RUN),
		.LF_REQ(REGIS_B_LF_REQ),
		
		.CTL(REGIS_B_CTL),
		.DONE(REGIS_B_DONE)
	);
	
	bit          CRNA_DONE,CRNB_DONE;
	bit          LF_SKIP;
	always @(posedge CLK or negedge ENG_RST_N) begin	
		bit  [11: 0] X1_A_CLIPPED,X2_A_CLIPPED,X1_B_CLIPPED,X2_B_CLIPPED,LF_A_X2,LF_B_X2;
		
		if (!ENG_RST_N) begin
			CRNA_ST <= CRN_IDLE;
			CRNB_ST <= CRN_IDLE;
			{LF_A_REQ,LF_B_REQ} <= '0;
			{CRNA_DONE,CRNB_DONE} <= '0;
			// synopsys translate_off
			// synopsys translate_on
		end
		else if (EN) begin
			if (CE_R) LF_A_REQ <= 0;
			case (CRNA_ST)
				CRN_IDLE: if (CE_R) begin
					if (ROW_A_START && !ROW_B_START) begin
						CRNA_DONE <= 0;
						CRNA_ST <= CRN_ROW_INIT0;
					end
				end
				
				CRN_ROW_INIT0: if (CE_R) begin
					CRNA_ST <= CRN_ROW_INIT1;
				end
				CRN_ROW_INIT1: if (CE_R) begin
					CRNA_ST <= CRN_ROW_INIT2;
				end
				CRN_ROW_INIT2: if (CE_R) begin
					CRNA_ST <= CRN_ROW_INIT3;
				end
				CRN_ROW_INIT3: if (CE_R) begin
					CRNA_ST <= CRN_ROW_INIT4;
				end
				CRN_ROW_INIT4: if (CE_R) begin
					CRNA_ST <= CRN_ROW_INIT5;
				end
				CRN_ROW_INIT5: if (CE_R) begin
					CRNA_ST <= CRN_ROW_INIT6;
				end
				CRN_ROW_INIT6: if (CE_R) begin
					CRNA_ST <= CRN_ROW_INIT7;
				end
				CRN_ROW_INIT7: if (CE_R) begin
					CRNA_ST <= CRN_ROW_INIT8;
				end
				CRN_ROW_INIT8: if (CE_R) begin
					CRNA_ST <= CRN_ROW_INIT9;
				end
				CRN_ROW_INIT9: if (CE_R) begin
					CRNA_ST <= CRN_ROW_INIT10;
				end
				CRN_ROW_INIT10: if (CE_R) begin
					CRNA_ST <= CRN_PRECALC;
				end
				
				CRN_PRECALC: if (CE_R) begin
					if (CRNB_ST == CRN_PRECALC || !LRFORM) begin
						if (MATH_A_STAT.LC && (MATH_B_STAT.LC || !LRFORM)) begin
							CRNA_ST <= CRN_END;
						end else begin
							CRNA_ST <= CRN_CALC;
						end
					end
				end
				CRN_CALC: if (CE_R) begin
					if (UNPACKER_A_EOL)
						CRNA_ST <= CRN_END;
					else if (UNPACKER_A_READY && (CRNB_ST == CRN_CALC || !LRFORM)) begin
						if (MATH_A_STAT.MF || SCOB_FLAG.MARIA) begin
							REGIS_A_Y <= MATH_A_Y;
							CRNA_ST <= !MATH_A_STAT.RC ? CRN_OUT : CRN_CALC;
						end else if (!REGIS_A_START) begin
							CRNA_ST <= CRN_CALC;
						end else begin
							CRNA_ST <= CRN_REGIS;
						end
					end
`ifdef DEBUG
					DBG_REGIS_A_Y_CNT <= '0;
`endif
				end
				
				CRN_REGIS: if (CE_R) begin
					if (REGIS_A_LF_REQ) begin
						REGIS_A_Y <= MATH_A_Y;
						REGIS_A_OUT <= 1;
						CRNA_ST <= CRN_OUT;
					end else if (REGIS_A_DONE) begin
						CRNA_ST <= CRN_CALC;
					end
				end
				
				CRN_OUT: if (!XY_FIFO_A_FULL && !LF_A_RUN && !LF_SKIP && CE_F) begin
					LF_A_LAST <= 0;
`ifdef DEBUG
					DBG_CLIP_A <= 0;
`endif
					if (CLIPX_A || CLIPY_A) begin
						CRNA_ST <= !REGIS_A_OUT ? CRN_CALC : UNPACKER_A_EOL && REGIS_A_DONE ? CRN_END : REGIS_A_DONE ? CRN_REGIS_DONE : CRN_REGIS;
`ifdef DEBUG
						DBG_CLIP_A <= 1;
`endif
					end else begin
						if ($signed(MATH_A_XR) < $signed(MATH_A_XL) && $signed(MATH_A_XL) > 0) begin
							X1_A_CLIPPED = !MATH_A_XR[11] ? MATH_A_XR : '0;
							X2_A_CLIPPED = $signed(MATH_A_XL) <= {1'b0,REGCTL1.CLIPX} ? $signed(MATH_A_XL) - 12'd1 : {1'b0,REGCTL1.CLIPX};
							if ($signed(X2_A_CLIPPED) != $signed(X1_A_CLIPPED)) begin LF_A_RUN <= ACCW_A_EN & ~SCOB_FLAG.MARIA; end
							else begin LF_A_LAST <= UNPACKER_A_EOL && REGIS_A_DONE; end
							LF_A_REQ <= ACCW_A_EN;
						end else if ($signed(MATH_A_XR) > $signed(MATH_A_XL) && $signed(MATH_A_XR) > 0) begin
							X1_A_CLIPPED = !MATH_A_XL[11] ? MATH_A_XL : '0;
							X2_A_CLIPPED = $signed(MATH_A_XR) <= {1'b0,REGCTL1.CLIPX} ? $signed(MATH_A_XR) - 12'd1 : {1'b0,REGCTL1.CLIPX};
							if ($signed(X1_A_CLIPPED) != $signed(X2_A_CLIPPED)) begin LF_A_RUN <= ACW_A_EN & ~SCOB_FLAG.MARIA; end
							else begin LF_A_LAST <= UNPACKER_A_EOL && REGIS_A_DONE; end
							LF_A_REQ <= ACW_A_EN;
						end else begin 
							X1_A_CLIPPED = MATH_A_XL;
							X2_A_CLIPPED = MATH_A_XR;
						end
						LF_A_XY.X <= X1_A_CLIPPED;
						LF_A_X2 <= X2_A_CLIPPED;
						LF_A_XY.Y <= Y_A[10:0];
`ifdef DEBUG
						DBG_REGIS_A_Y_CNT <= DBG_REGIS_A_Y_CNT + 1'd1;
`endif
					end 
					REGIS_A_OUT <= 0;
					CRNA_ST <= !REGIS_A_OUT ? CRN_CALC : UNPACKER_A_EOL && REGIS_A_DONE ? CRN_END : REGIS_A_DONE ? CRN_REGIS_DONE : CRN_REGIS; 
				end
				
				CRN_REGIS_DONE: if (CE_R) begin
					CRNA_ST <= CRN_CALC; 
				end
				
				CRN_END: if (!LF_A_RUN && CE_R) begin
					CRNA_DONE <= 1;
					CRNA_ST <= CRN_IDLE;
				end
			endcase
			
			if (CE_F) begin
					if (LF_A_RUN && !XY_FIFO_A_FULL && !LF_SKIP) begin
						LF_A_XY.X <= LF_A_XY.X + 12'd1;
						if (LF_A_XY.X + 12'd1 == LF_A_X2) begin 
							LF_A_LAST <= UNPACKER_A_EOL && REGIS_A_DONE; 
							LF_A_RUN <= 0; 
						end
						LF_A_REQ <= 1;						
					end
			end

			if (CE_R) LF_B_REQ <= 0;
			case (CRNB_ST)
				CRN_IDLE: if (CE_R) begin
					if (ROW_B_START && !ROW_A_START) begin
						CRNB_DONE <= 0;
						CRNB_ST <= CRN_ROW_INIT0;
					end
				end
				
				CRN_ROW_INIT0: if (CE_R) begin
					CRNB_ST <= CRN_ROW_INIT1;
				end
				CRN_ROW_INIT1: if (CE_R) begin
					CRNB_ST <= CRN_ROW_INIT2;
				end
				CRN_ROW_INIT2: if (CE_R) begin
					CRNB_ST <= CRN_ROW_INIT3;
				end
				CRN_ROW_INIT3: if (CE_R) begin
					CRNB_ST <= CRN_ROW_INIT4;
				end
				CRN_ROW_INIT4: if (CE_R) begin
					CRNB_ST <= CRN_ROW_INIT5;
				end
				CRN_ROW_INIT5: if (CE_R) begin
					CRNB_ST <= CRN_ROW_INIT6;
				end
				CRN_ROW_INIT6: if (CE_R) begin
					CRNB_ST <= CRN_ROW_INIT7;
				end
				CRN_ROW_INIT7: if (CE_R) begin
					CRNB_ST <= CRN_ROW_INIT8;
				end
				CRN_ROW_INIT8: if (CE_R) begin
					CRNB_ST <= CRN_ROW_INIT9;
				end
				CRN_ROW_INIT9: if (CE_R) begin
					CRNB_ST <= CRN_ROW_INIT10;
				end
				CRN_ROW_INIT10: if (CE_R) begin
					CRNB_ST <= CRN_PRECALC;
				end
				
				CRN_PRECALC: if (CE_R) begin
					if (CRNA_ST == CRN_PRECALC || !LRFORM) begin
						if (MATH_B_STAT.LC && (MATH_A_STAT.LC || !LRFORM)) begin
							CRNB_ST <= CRN_END;
						end else begin
							CRNB_ST <= CRN_CALC;
						end
					end
				end
				CRN_CALC: if (CE_R) begin
					if (UNPACKER_B_EOL)
						CRNB_ST <= CRN_END;
					else if (UNPACKER_B_READY && (CRNA_ST == CRN_CALC || !LRFORM)) begin
						if (MATH_B_STAT.MF || SCOB_FLAG.MARIA) begin
							REGIS_B_Y <= MATH_B_Y;
							CRNB_ST <= !MATH_B_STAT.RC ? CRN_OUT : CRN_CALC;
						end else if (!REGIS_B_START) begin
							CRNB_ST <= CRN_CALC;
						end else begin
							CRNB_ST <= CRN_REGIS;
						end
					end
				end
				
				CRN_REGIS: if (CE_R) begin
					if (REGIS_B_LF_REQ) begin
						REGIS_B_Y <= MATH_B_Y;
						REGIS_B_OUT <= 1;
						CRNB_ST <= CRN_OUT;
					end else if (REGIS_B_DONE) begin
						CRNB_ST <= CRN_CALC;
					end
				end
				
				CRN_OUT: if (!XY_FIFO_A_FULL && !LF_B_RUN && !LF_SKIP && CE_F) begin
					LF_B_LAST <= 0;
`ifdef DEBUG
					DBG_CLIP_B <= 0;
`endif
					if (CLIPX_B || CLIPY_B) begin
						CRNB_ST <= !REGIS_B_OUT ? CRN_CALC : UNPACKER_B_EOL && REGIS_B_DONE ? CRN_END : REGIS_B_DONE ? CRN_REGIS_DONE : CRN_REGIS;
`ifdef DEBUG
						DBG_CLIP_B <= 1;
`endif
					end else begin
						if ($signed(MATH_B_XR) < $signed(MATH_B_XL) && $signed(MATH_B_XL) > 0) begin
							X1_B_CLIPPED = !MATH_B_XR[11] ? MATH_B_XR : '0;
							X2_B_CLIPPED = $signed(MATH_B_XL) <= {1'b0,REGCTL1.CLIPX} ? $signed(MATH_B_XL) - 12'd1 : {1'b0,REGCTL1.CLIPX};
							if ($signed(X2_B_CLIPPED) != $signed(X1_B_CLIPPED)) begin LF_B_RUN <= ACCW_B_EN & ~SCOB_FLAG.MARIA; end
							else begin LF_B_LAST <= UNPACKER_B_EOL && REGIS_B_DONE; end
							LF_B_REQ <= ACCW_B_EN;
						end else if ($signed(MATH_B_XR) > $signed(MATH_B_XL) && $signed(MATH_B_XR) > 0) begin
							X1_B_CLIPPED = !MATH_B_XL[11] ? MATH_B_XL : '0;
							X2_B_CLIPPED = $signed(MATH_B_XR) <= {1'b0,REGCTL1.CLIPX} ? $signed(MATH_B_XR) - 12'd1 : {1'b0,REGCTL1.CLIPX};
							if ($signed(X1_B_CLIPPED) != $signed(X2_B_CLIPPED)) begin LF_B_RUN <= ACW_B_EN & ~SCOB_FLAG.MARIA; end
							else begin LF_B_LAST <= UNPACKER_B_EOL && REGIS_B_DONE; end
							LF_B_REQ <= ACW_B_EN;
						end else begin 
							X1_B_CLIPPED = MATH_B_XL;
							X2_B_CLIPPED = MATH_B_XR;
						end
						LF_B_XY.X <= X1_B_CLIPPED;
						LF_B_X2 <= X2_B_CLIPPED;
						LF_B_XY.Y <= Y_B[10:0];
					end
					REGIS_B_OUT <= 0;
					CRNB_ST <= !REGIS_B_OUT ? CRN_CALC : UNPACKER_B_EOL && REGIS_B_DONE ? CRN_END : REGIS_B_DONE ? CRN_REGIS_DONE : CRN_REGIS; 
				end
				
				CRN_REGIS_DONE: if (CE_R) begin
					CRNB_ST <= CRN_CALC; 
				end
				
				CRN_END: if (!LF_B_RUN && CE_R) begin
//					Y_A_CONFLICT <= 0;
					CRNB_DONE <= 1;
					CRNB_ST <= CRN_IDLE;
				end
			endcase
			
			if (CE_F) begin
				if (LF_B_RUN && !XY_FIFO_A_FULL && !LF_SKIP) begin
					LF_B_XY.X <= LF_B_XY.X + 12'd1;
					if (LF_B_XY.X + 12'd1 == LF_B_X2) begin 
						LF_B_LAST <= UNPACKER_B_EOL && REGIS_B_DONE; 
						LF_B_RUN <= 0;  
					end
					LF_B_REQ <= 1;						
				end
			end
			
			if (CE_R) begin
				LF_SKIP <= 0;
				if ((XY_A_REQ && IPN_A_RMODE) || (XY_B_REQ && IPN_B_RMODE)) begin
					LF_SKIP <= 1;
				end
			end
		end
	end 
	assign CRNA_READY = !XY_FIFO_A_LESSHALF || (CRNA_DONE && !XY_FIFO_A_EMPTY);
	assign CRNB_READY = !XY_FIFO_A_LESSHALF || (CRNB_DONE && !XY_FIFO_A_EMPTY);
	assign CRNA_FINISH = (CRNA_ST == CRN_IDLE && XY_FIFO_A_EMPTY && (CRNB_ST == CRN_IDLE || !LRFORM));
	assign CRNB_FINISH = (CRNB_ST == CRN_IDLE && XY_FIFO_A_EMPTY && (CRNA_ST == CRN_IDLE || !LRFORM));
	
	wire         MUNKEE_A_LF_REQ = (CRNA_ST == CRN_CALC && (MATH_A_STAT.MF || SCOB_FLAG.MARIA) && UNPACKER_A_READY && (CRNB_ST == CRN_CALC || !LRFORM));
	wire         MUNKEE_B_LF_REQ = (CRNB_ST == CRN_CALC && (MATH_B_STAT.MF || SCOB_FLAG.MARIA) && UNPACKER_B_READY && (CRNA_ST == CRN_CALC || !LRFORM));
	MathCtl_t    REGIS_A_CTL,REGIS_B_CTL;
	always_comb begin
		MATH_A_CTL = '0;
		case (CRNA_ST)
			CRN_ROW_INIT1: if (CE_R) begin
				MATH_A_CTL.A0CH_INIT = 1;
			end
			CRN_ROW_INIT2: if (CE_R) begin
				MATH_A_CTL.A0CL_INIT = 1;
			end
			CRN_ROW_INIT3: if (CE_R) begin
				MATH_A_CTL.A3CH_INIT = 1;
			end
			CRN_ROW_INIT4: if (CE_R) begin
				MATH_A_CTL.A3CL_INIT = 1;
			end
			CRN_ROW_INIT5: if (CE_R) begin
				MATH_A_CTL.A0DH_INIT = 1;
				MATH_A_CTL.A3CH_SAVE = 1;
			end
			CRN_ROW_INIT6: if (CE_R) begin
				MATH_A_CTL.A0DL_INIT = 1;
				MATH_A_CTL.A3CL_SAVE = 1;
			end
			CRN_ROW_INIT7: if (CE_R) begin
				MATH_A_CTL.A3DH_INIT = 1;
			end
			CRN_ROW_INIT8: if (CE_R) begin
				MATH_A_CTL.A3DL_INIT = 1;
			end
			CRN_ROW_INIT9: if (CE_R) begin
				MATH_A_CTL.A3DH_SAVE = 1;
			end
			CRN_ROW_INIT10: if (CE_R) begin
				MATH_A_CTL.A3DL_SAVE = 1;
			end
			CRN_PRECALC: if (CE_R) begin
				MATH_A_CTL.A12C_PRECALC = 1;
				MATH_A_CTL.X1_MUNK_SEL = 2'b00;
				MATH_A_CTL.X1_MUNK = 1;
				MATH_A_CTL.X1_UPD = 1;
				MATH_A_CTL.X2_MUNK_SEL = 2'b11;
				MATH_A_CTL.X2_MUNK = 1;
				MATH_A_CTL.X2_UPD = 1;
				MATH_A_CTL.Y_T1_SEL = 2'b00;
				MATH_A_CTL.Y_UPD = 1;
			end
			CRN_CALC: if (UNPACKER_A_READY && (CRNB_ST == CRN_CALC || !LRFORM) && CE_R) begin
				MATH_A_CTL.X1_MUNK_SEL = 2'd0;
				MATH_A_CTL.X1_MUNK = MUNKEE_A_LF_REQ;////////////////
				MATH_A_CTL.X_ADD01_ASEL = 3'd0;
				MATH_A_CTL.X_ADD01_BSEL = 3'd4;
				MATH_A_CTL.X_ADD01_SUB = 0;
				MATH_A_CTL.X1_UPD = 1;
				MATH_A_CTL.X2_MUNK_SEL = 2'd2;
				MATH_A_CTL.X2_MUNK = 1;
				MATH_A_CTL.X2_UPD = 1;
				MATH_A_CTL.Y_T1_SEL = MATH_A_STAT.YTOP;
				MATH_A_CTL.Y_UPD = 1;
				if (!REGIS_A_START) begin
					MATH_A_CTL.A12C_CALC = 1;
				end
			end
			CRN_REGIS: begin
				if (REGIS_A_DONE) begin
					if (CE_R) MATH_A_CTL.A12C_CALC = 1;
				end else begin
					MATH_A_CTL = REGIS_A_CTL;
				end
			end
			CRN_REGIS_DONE: if (CE_R) begin
				MATH_A_CTL.A12C_CALC = 1;
			end
			default:;
		endcase
		
		MATH_B_CTL = '0;
		case (CRNB_ST)
			CRN_ROW_INIT1: if (CE_R) begin
				MATH_B_CTL.A0CH_INIT = 1;
			end
			CRN_ROW_INIT2: if (CE_R) begin
				MATH_B_CTL.A0CL_INIT = 1;
			end
			CRN_ROW_INIT3: if (CE_R) begin
				MATH_B_CTL.A3CH_INIT = 1;
			end
			CRN_ROW_INIT4: if (CE_R) begin
				MATH_B_CTL.A3CL_INIT = 1;
			end
			CRN_ROW_INIT5: if (CE_R) begin
				MATH_B_CTL.A0DH_INIT = 1;
				MATH_B_CTL.A3CH_SAVE = 1;
			end
			CRN_ROW_INIT6: if (CE_R) begin
				MATH_B_CTL.A0DL_INIT = 1;
				MATH_B_CTL.A3CL_SAVE = 1;
			end
			CRN_ROW_INIT7: if (CE_R) begin
				MATH_B_CTL.A3DH_INIT = 1;
			end
			CRN_ROW_INIT8: if (CE_R) begin
				MATH_B_CTL.A3DL_INIT = 1;
			end
			CRN_ROW_INIT9: if (CE_R) begin
				MATH_B_CTL.A3DH_SAVE = 1;
			end
			CRN_ROW_INIT10: if (CE_R) begin
				MATH_B_CTL.A3DL_SAVE = 1;
			end
			CRN_PRECALC: if (CE_R) begin
				MATH_B_CTL.A12C_PRECALC = 1;
				MATH_B_CTL.X1_MUNK_SEL = 2'b00;
				MATH_B_CTL.X1_MUNK = 1;
				MATH_B_CTL.X1_UPD = 1;
				MATH_B_CTL.X2_MUNK_SEL = 2'b11;
				MATH_B_CTL.X2_MUNK = 1;
				MATH_B_CTL.X2_UPD = 1;
				MATH_B_CTL.Y_T1_SEL = 2'b00;
				MATH_B_CTL.Y_UPD = 1;
			end
			CRN_CALC: if (UNPACKER_B_READY && (CRNA_ST == CRN_CALC || !LRFORM) && CE_R) begin
				MATH_B_CTL.X1_MUNK_SEL = 2'd0;
				MATH_B_CTL.X1_MUNK = MUNKEE_B_LF_REQ;////////////////
				MATH_B_CTL.X_ADD01_ASEL = 3'd0;
				MATH_B_CTL.X_ADD01_BSEL = 3'd4;
				MATH_B_CTL.X_ADD01_SUB = 0;
				MATH_B_CTL.X1_UPD = 1;
				MATH_B_CTL.X2_MUNK_SEL = 2'd2;
				MATH_B_CTL.X2_MUNK = 1;
				MATH_B_CTL.X2_UPD = 1;
				MATH_B_CTL.Y_T1_SEL = MATH_B_STAT.YTOP;
				MATH_B_CTL.Y_UPD = 1;
				if (!REGIS_B_START) begin
					MATH_B_CTL.A12C_CALC = 1;
				end
			end
			CRN_REGIS: begin
				if (REGIS_B_DONE) begin
					if (CE_R) MATH_B_CTL.A12C_CALC = 1;
				end else begin
					MATH_B_CTL = REGIS_B_CTL;
				end
			end
			CRN_REGIS_DONE: if (CE_R) begin
				MATH_B_CTL.A12C_CALC = 1;
			end
			default:;
		endcase
	end
	
	bit          SUB_H,SUB_V;
	always @(posedge CLK or negedge ENG_RST_N) begin
		if (!ENG_RST_N) begin
			{SUB_H,SUB_V} <= '0;
		end
		else if (EN && CE_R) begin
			if (BUS_STATE_FF == SCOB_XPOS1) begin
				SUB_H <= MDTI[15];
			end
			if (BUS_STATE_FF == SCOB_YPOS1) begin
				SUB_V <= MDTI[15];
			end
		end
	end 
	
	wire [ 2: 0] REG_STACK_ADDR_H = (BUS_STATE_FF == SCOB_DDX1    || BUS_STATE_FF == SCOB_DDY1   ) ? 3'h2 :
	                                (BUS_STATE_FF == SCOB_DX1     || BUS_STATE_FF == SCOB_DY1    ) ? 3'h3 :
											  (BUS_STATE_FF == SCOB_LINEDX1 || BUS_STATE_FF == SCOB_LINEDY1) ? 3'h6 :
											  (BUS_STATE_FF == SCOB_XPOS1   || BUS_STATE_FF == SCOB_YPOS1  ) ? 3'h7 : 3'h0;
	wire         REG_STACK_HALF_H = (BUS_STATE_FF == SCOB_DDY1 || BUS_STATE_FF == SCOB_DY1 || BUS_STATE_FF == SCOB_LINEDY1 || BUS_STATE_FF == SCOB_YPOS1);

	bit  [ 2: 0] REG_STACK_ADDR_L;
	bit          REG_STACK_HALF_L;
	always @(posedge CLK or negedge ENG_RST_N) begin			
		if (!ENG_RST_N) begin
			// synopsys translate_off
			REG_STACK_ADDR_L <= '0;
			REG_STACK_HALF_L <= 0;
			// synopsys translate_on
		end
		else if (EN && CE_R) begin
			REG_STACK_ADDR_L <= REG_STACK_ADDR_H - 3'h2;
			REG_STACK_HALF_L <= REG_STACK_HALF_H;
		end
	end
	
	bit  [ 2: 0] SCU_WA;
	bit  [ 2: 0] SCU_RA;
	bit  [ 1: 0] SCU_WE;
	bit          SCU_LOAD_D;
	bit          SCU_INIT;
	always_comb begin
		SCU_LOAD_D = 0;
		SCU_INIT = 0;
		if (CRNA_ST == CRN_IDLE && CRNB_ST == CRN_IDLE) begin
			SCU_WA = !REG_LOAD_A0 ? REG_STACK_ADDR_H : REG_STACK_ADDR_L;
			SCU_RA = '0;//TODO
			SCU_WE = !REG_LOAD_A0 ? {~REG_STACK_HALF_H,REG_STACK_HALF_H} & {2{REG_FETCH}} : {~REG_STACK_HALF_L,REG_STACK_HALF_L};
			SCU_LOAD_D = 1;
		end
		else begin
			SCU_WA = '0;
			SCU_RA = '0;
			SCU_WE = '0;
			case (CRNA_ST)
				CRN_ROW_INIT0: begin
					SCU_RA = 3'h7;
					SCU_INIT = 1;
				end
				CRN_ROW_INIT1: begin
					SCU_RA = 3'h5;
					SCU_INIT = 1;
				end
				CRN_ROW_INIT2: begin
					SCU_RA = 3'h6;
					SCU_INIT = 1;
				end
				CRN_ROW_INIT3: begin
					SCU_RA = 3'h4;
					SCU_INIT = 1;
				end
				CRN_ROW_INIT4: begin
					SCU_RA = 3'h3;
					SCU_INIT = 1;
				end
				CRN_ROW_INIT5: begin
					SCU_RA = 3'h1;
					SCU_WA = 3'h7;
					SCU_WE = '1;
					SCU_INIT = 1;
				end
				CRN_ROW_INIT6: begin
					SCU_RA = 3'h2;
					SCU_WA = 3'h5;
					SCU_WE = '1;
					SCU_INIT = 1;
				end
				CRN_ROW_INIT7: begin
					SCU_RA = 3'h0;
					SCU_INIT = 1;
				end
				CRN_ROW_INIT8: begin
					SCU_INIT = 1;
				end
				CRN_ROW_INIT9: begin
					SCU_RA = 3'h2;
					SCU_WA = 3'h3;
					SCU_WE = '1;
					SCU_INIT = 1;
				end
				CRN_ROW_INIT10: begin
					SCU_RA = 3'h2;
					SCU_WA = 3'h1;
					SCU_WE = '1;
					SCU_INIT = 1;
				end
				
				default:;
			endcase
			
			case (CRNB_ST)
				CRN_ROW_INIT0: begin
					SCU_RA = 3'h7;
					SCU_INIT = 1;
				end
				CRN_ROW_INIT1: begin
					SCU_RA = 3'h5;
					SCU_INIT = 1;
				end
				CRN_ROW_INIT2: begin
					SCU_RA = 3'h6;
					SCU_INIT = 1;
				end
				CRN_ROW_INIT3: begin
					SCU_RA = 3'h4;
					SCU_INIT = 1;
				end
				CRN_ROW_INIT4: begin
					SCU_RA = 3'h3;
					SCU_INIT = 1;
				end
				CRN_ROW_INIT5: begin
					SCU_RA = 3'h1;
					SCU_WA = 3'h7;
					SCU_WE = '1;
					SCU_INIT = 1;
				end
				CRN_ROW_INIT6: begin
					SCU_RA = 3'h2;
					SCU_WA = 3'h5;
					SCU_WE = '1;
					SCU_INIT = 1;
				end
				CRN_ROW_INIT7: begin
					SCU_RA = 3'h0;
					SCU_INIT = 1;
				end
				CRN_ROW_INIT8: begin
					SCU_INIT = 1;
				end
				CRN_ROW_INIT9: begin
					SCU_RA = 3'h2;
					SCU_WA = 3'h3;
					SCU_WE = '1;
					SCU_INIT = 1;
				end
				CRN_ROW_INIT10: begin
					SCU_RA = 3'h2;
					SCU_WA = 3'h1;
					SCU_WE = '1;
					SCU_INIT = 1;
				end
				
				default:;
			endcase
		end
	end
	wire CRN_ROW_INIT_SEL = (CRNB_ST == CRN_ROW_INIT0 || CRNB_ST == CRN_ROW_INIT1 || CRNB_ST == CRN_ROW_INIT2 || CRNB_ST == CRN_ROW_INIT3 || CRNB_ST == CRN_ROW_INIT4 ||
	                         CRNB_ST == CRN_ROW_INIT5 || CRNB_ST == CRN_ROW_INIT6 || CRNB_ST == CRN_ROW_INIT7 || CRNB_ST == CRN_ROW_INIT8 || CRNB_ST == CRN_ROW_INIT9 || CRNB_ST == CRN_ROW_INIT10);
	
	wire [15: 0] REG_DIN = !REG_LOAD_A0 ? MDTI[31:16] : LOAD_BUF;
	bit  [15: 0] XA,YA;
	bit  [15: 0] XS0,YS0;
	wire [15: 0] REG_STACK_XIN = SCU_LOAD_D ? REG_DIN :
	                             SCU_INIT ? XA :
										  XS0;
	wire [15: 0] REG_STACK_YIN = SCU_LOAD_D ? REG_DIN :
	                             SCU_INIT ? YA :
										  YS0;
	bit  [31: 0] REG_DOUT;
	MADAM_MATH_STACK MATH_REG_STACK 
	(
		.CLK(CLK),
		.EN(EN),
		
		.WA(SCU_WA),
		.DIN({REG_STACK_XIN,REG_STACK_YIN}),
		.WE(SCU_WE & {2{CE_R}}),
		
		.RA(SCU_RA),
		.DOUT(REG_DOUT)
	);
	
`ifdef DEBUG
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) begin
			DBG_XPOS <= '0;
			DBG_YPOS <= '0;
			DBG_LDX <= '0;
			DBG_LDY <= '0;
			DBG_DDX <= '0;
			DBG_DDY <= '0;
			DBG_DX <= '0;
			DBG_DY <= '0;
		end
		else if (EN && CE_R) begin
			case (SCU_WA)
				3'h0: begin
					if (SCU_WE[1]) DBG_DDX[15:0] <= REG_STACK_XIN;
					if (SCU_WE[0]) DBG_DDY[15:0] <= REG_STACK_YIN;
				end
				3'h1: begin
					if (SCU_WE[1]) DBG_DX[15:0] <= REG_STACK_XIN;
					if (SCU_WE[0]) DBG_DY[15:0] <= REG_STACK_YIN;
				end
				3'h2: begin
					if (SCU_WE[1]) DBG_DDX[31:16] <= REG_STACK_XIN;
					if (SCU_WE[0]) DBG_DDY[31:16] <= REG_STACK_YIN;
				end
				3'h3: begin
					if (SCU_WE[1]) DBG_DX[31:16] <= REG_STACK_XIN;
					if (SCU_WE[0]) DBG_DY[31:16] <= REG_STACK_YIN;
				end
				3'h4: begin
					if (SCU_WE[1]) DBG_LDX[15:0] <= REG_STACK_XIN;
					if (SCU_WE[0]) DBG_LDY[15:0] <= REG_STACK_YIN;
				end
				3'h5: begin
					if (SCU_WE[1]) DBG_XPOS[15:0] <= REG_STACK_XIN;
					if (SCU_WE[0]) DBG_YPOS[15:0] <= REG_STACK_YIN;
				end
				3'h6: begin
					if (SCU_WE[1]) DBG_LDX[31:16] <= REG_STACK_XIN;
					if (SCU_WE[0]) DBG_LDY[31:16] <= REG_STACK_YIN;
				end
				3'h7: begin
					if (SCU_WE[1]) DBG_XPOS[31:16] <= REG_STACK_XIN;
					if (SCU_WE[0]) DBG_YPOS[31:16] <= REG_STACK_YIN;
				end
			endcase
			DBG_LDX_BIG <= $signed(DBG_LDX[31:16]) > 320 || $signed(DBG_LDX[31:16]) < -320;
			DBG_LDY_BIG <= $signed(DBG_LDY[31:16]) > 240 || $signed(DBG_LDY[31:16]) < -240;
			DBG_DX_BIG <= $signed(DBG_DX[31:20]) > 320 || $signed(DBG_DX[31:20]) < -320;
			DBG_DY_BIG <= $signed(DBG_DY[31:20]) > 240 || $signed(DBG_DY[31:20]) < -240;
		end
	end 
`endif
	
	bit  [15: 0] REG_XOUT_FF,REG_YOUT_FF;
	always @(posedge CLK or negedge ENG_RST_N) begin
		if (!ENG_RST_N) begin
			REG_XOUT_FF <= '0;
			REG_YOUT_FF <= '0;
		end
		else if (EN && CE_R) begin
			{REG_XOUT_FF,REG_YOUT_FF} <= REG_DOUT;
		end
	end 
	assign {XS0,YS0} = {~REG_XOUT_FF,~REG_YOUT_FF};
	assign PM_DO = {~REG_XOUT_FF,~REG_YOUT_FF};
	
		
	bit  [15: 0] MATH_A_XA,MATH_A_YA;
	bit  [11: 0] MATH_A_Y;
	bit  [11: 0] MATH_A_XL,MATH_A_XR;
	MADAM_MATH_PLATFORM MATH_A 
	(
		.CLK(CLK),
		.RST(~ENG_RST_N),
		.EN(EN),
		
		.CE(CE_R),
		
		.LSC(SCOB_FLAG.ALSC & SCOBCTL.ASCALL),
		.CLIPX(REGCTL1.CLIPX),
		.CLIPY(REGCTL1.CLIPY),
		
		.CTL(MATH_A_CTL),
		
		.XS0(REG_XOUT_FF),
		.YS0(REG_YOUT_FF),
		.XA(MATH_A_XA),
		.YA(MATH_A_YA),
		
		.STAT(MATH_A_STAT),
		
		.YO(MATH_A_Y),
		.XLO(MATH_A_XL),
		.XRO(MATH_A_XR)
	);
	
	bit  [15: 0] MATH_B_XA,MATH_B_YA;
	bit  [11: 0] MATH_B_Y;
	bit  [11: 0] MATH_B_XL,MATH_B_XR;
	MADAM_MATH_PLATFORM MATH_B 
	(
		.CLK(CLK),
		.RST(~ENG_RST_N),
		.EN(EN),
		
		.CE(CE_R),
		
		.LSC(SCOB_FLAG.ALSC & SCOBCTL.ASCALL),
		.CLIPX(REGCTL1.CLIPX),
		.CLIPY(REGCTL1.CLIPY),
		
		.CTL(MATH_B_CTL),
		
		.XS0(REG_XOUT_FF),
		.YS0(REG_YOUT_FF),
		.XA(MATH_B_XA),
		.YA(MATH_B_YA),
		
		.STAT(MATH_B_STAT),
		
		.YO(MATH_B_Y),
		.XLO(MATH_B_XL),
		.XRO(MATH_B_XR)
	);
	assign {XA,YA} = !CRN_ROW_INIT_SEL ? {MATH_A_XA,MATH_A_YA} : {MATH_B_XA,MATH_B_YA};
	
	YX_t         XY_A,XY_B;
	bit          XY_A_REQ,XY_B_REQ;
	bit          IPN_A_RMODE,IPN_B_RMODE;

	assign XY_A = LF_A_XY;
	assign XY_B =  LF_B_XY;
	assign XY_A_REQ = LF_A_REQ&~IPN_A.T;
	assign XY_B_REQ = LF_B_REQ&~IPN_B.T;
	assign IPN_A_RMODE = IPN_A.RMODE;
	assign IPN_B_RMODE = IPN_B.RMODE;
	wire         IPN_RMODE = (XY_A_REQ & IPN_A_RMODE) | (XY_B_REQ & IPN_B_RMODE);
	
	YX_t         XY_A_LATCH,XY_B_LATCH;
	bit          XY_A_REQ_LATCH,XY_B_REQ_LATCH;
	always @(posedge CLK or negedge ENG_RST_N) begin
		if (!ENG_RST_N) begin
			{XY_A_LATCH,XY_B_LATCH} <= '0;
			{XY_A_REQ_LATCH,XY_B_REQ_LATCH} <= '0;
		end
		else if (EN && CE_R) begin
			XY_A_LATCH <= XY_A;
			XY_B_LATCH <= XY_B;
			XY_A_REQ_LATCH <= XY_A_REQ&IPN_RMODE;
			XY_B_REQ_LATCH <= XY_B_REQ&IPN_RMODE;
		end
	end 
	
	
	YX_t         XY_FIFO_A_OUT;
	bit          XY_FIFO_A_LAST;
	bit          XY_FIFO_A_DOLO;
	bit          XY_FIFO_A_DRAW;
	bit          XY_FIFO_CORNER;
	bit          XY_FIFO_A_FULL,XY_FIFO_A_EMPTY;
	assign XY_FIFO_A_WRREQ = XY_A_REQ | XY_B_REQ | XY_A_REQ_LATCH | XY_B_REQ_LATCH;
	MADAM_SYNC_FIFO #(26) XY_FIFO_A 
	(
		.CLK(CLK),
		.EN(EN),
		.RST(SPR_NEXT | ~ENG_RST_N),
		
		.DIN(XY_A_REQ ? {1'b1,IPN_RMODE,LF_A_LAST&~IPN_RMODE,XY_A} : {XY_A_REQ_LATCH,1'b0,LF_A_LAST,XY_A_LATCH}),
		.WRREQ(XY_FIFO_A_WRREQ & CE_R),
		
		.RDREQ(SYNC_FIFO_RDREQ & CE_F),
		.DOUT({XY_FIFO_A_DRAW,XY_FIFO_A_DOLO,XY_FIFO_A_LAST,XY_FIFO_A_OUT}),
		
		.FULL(XY_FIFO_A_FULL),
		.LESSHALF(XY_FIFO_A_LESSHALF),
		.EMPTY(XY_FIFO_A_EMPTY)
	);
	
	YX_t         XY_FIFO_B_OUT;
	bit          XY_FIFO_B_LAST;
	bit          XY_FIFO_B_DOLO;
	bit          XY_FIFO_B_DRAW;
	MADAM_SYNC_FIFO #(26) XY_FIFO_B 
	(
		.CLK(CLK),
		.EN(EN),
		.RST(SPR_NEXT | ~ENG_RST_N),
		
		.DIN(XY_B_REQ ? {1'b1,IPN_RMODE,LF_B_LAST&~IPN_RMODE,XY_B} : {XY_B_REQ_LATCH,1'b0,LF_B_LAST,XY_B_LATCH}),
		.WRREQ(XY_FIFO_A_WRREQ & CE_R),
		
		.RDREQ(SYNC_FIFO_RDREQ & CE_F),
		.DOUT({XY_FIFO_B_DRAW,XY_FIFO_B_DOLO,XY_FIFO_B_LAST,XY_FIFO_B_OUT}),
		
		.FULL(),
		.LESSHALF(),
		.EMPTY()
	);
`ifdef DEBUG
	assign DBG_XY_FIFO_A_OUT = XY_FIFO_A_OUT;
	assign DBG_XY_FIFO_A_DOLO = XY_FIFO_A_DOLO;
	assign DBG_XY_FIFO_A_LAST = XY_FIFO_A_LAST;
	assign DBG_XY_FIFO_A_DRAW = XY_FIFO_A_DRAW;
	assign DBG_XY_FIFO_B_OUT = XY_FIFO_B_OUT;
	assign DBG_XY_FIFO_B_DOLO = XY_FIFO_B_DOLO;
	assign DBG_XY_FIFO_B_LAST = XY_FIFO_B_LAST;
	assign DBG_XY_FIFO_B_DRAW = XY_FIFO_B_DRAW;
`endif
	
	wire         IPS_FIFO_RMODE = (XY_FIFO_A_DRAW & !XY_FIFO_A_EMPTY & XY_FIFO_A_DOLO) | (XY_FIFO_B_DRAW & !XY_FIFO_A_EMPTY & XY_FIFO_B_DOLO);
	bit          DOLO_CYCLE;
	bit          SYNC_FIFO_READ;
	always @(posedge CLK or negedge ENG_RST_N) begin
		bit          XY_FIFO_CORNER_PREV;
		
		if (!ENG_RST_N) begin
			DOLO_CYCLE <= 0;
			SYNC_FIFO_READ <= '0;
		end
		else if (EN && CE_R) begin
			SYNC_FIFO_READ <= 0;
			if (((BUS_STATE_FF == CFB_WRITE0 || BUS_STATE_FF == CFB_READ0) || (BUS_STATE_FF == CFB_INIT0)) && !XY_FIFO_A_EMPTY) begin
				SYNC_FIFO_READ <= 1;
				DOLO_CYCLE <= IPS_FIFO_RMODE;
			end

			if (BUS_STATE_FF == CFB_READ1 || BUS_STATE_FF == BUS_IDLE) begin
				DOLO_CYCLE <= 0;
			end
		end
	end 
	assign SYNC_FIFO_RDREQ = SYNC_FIFO_READ && !DST_LAST_A && !DST_SUSPEND;
	
	bit          DRAW_A_FF,DRAW_B_FF;
	bit  [23: 1] DST_ADDR_A,DST_ADDR_B;
	bit          DST_WRITE_A,DST_WRITE_B;
	bit          DST_READ;
	bit          DST_LAST_A,DST_LAST_B,DST_SUSPEND;
	always @(posedge CLK or negedge ENG_RST_N) begin	
		bit  [ 3: 0] G1,G2;
		bit  [23: 2] BASE;
		bit  [23: 1] ADDR_FF_A,ADDR_FF_B;
		bit  [20: 0] YOFFS1_A,YOFFS2_A,YOFFS1_B,YOFFS2_B;
		bit  [23: 1] DST_ADDR_A_NEW,DST_ADDR_B_NEW;
		bit  [23:11] DST_PAGE_A,DST_PAGE_B;
		bit          DST_PB_A,DST_PB_B;
		
		if (!ENG_RST_N) begin
			{DST_ADDR_A,DST_ADDR_B} <= '0;
			{DST_WRITE_A,DST_WRITE_B} <= '0;
			{DST_LAST_A,DST_LAST_B} <= '0;
			// synopsys translate_off
			{YOFFS1_A,YOFFS2_A,YOFFS1_B,YOFFS2_B} <= '0;
			// synopsys translate_on
`ifdef DEBUG
			DBG_DRAW_OUT <= 0;
`endif
		end
		else if (EN && CE_R) begin
			if ((IPS_FIFO_RMODE && (BUS_STATE_FF == CFB_INIT0 || BUS_STATE_FF == CFB_WRITE0)) || (DOLO_CYCLE && (BUS_STATE_FF == CFB_INIT1 || BUS_STATE_FF == CFB_WRITE1))) begin
				G1   = REGCTL0.CFBDG1;
				G2   = REGCTL0.CFBDG2;
				BASE = REGCTL2[23:2];
			end else begin
				G1   = REGCTL0.DSTG1;
				G2   = REGCTL0.DSTG2;
				BASE = REGCTL3[23:2];
			end
			
			//step1
			if (G1[3])      begin YOFFS1_A <= {1'b0,XY_FIFO_A_OUT.Y[10:1],10'b0000000000}; YOFFS1_B <= {1'b0,XY_FIFO_B_OUT.Y[10:1],10'b0000000000}; end
			else if (G1[2]) begin YOFFS1_A <= {3'b000,XY_FIFO_A_OUT.Y[10:1],8'b00000000};  YOFFS1_B <= {3'b000,XY_FIFO_B_OUT.Y[10:1],8'b00000000}; end
			else if (G1[1]) begin YOFFS1_A <= {2'b00,XY_FIFO_A_OUT.Y[10:1],9'b000000000};  YOFFS1_B <= {2'b00,XY_FIFO_B_OUT.Y[10:1],9'b000000000}; end
			else if (G1[0]) begin YOFFS1_A <= {6'b000000,XY_FIFO_A_OUT.Y[10:1],5'b00000};  YOFFS1_B <= {6'b000000,XY_FIFO_B_OUT.Y[10:1],5'b00000}; end
			else            begin YOFFS1_A <= '0;                                          YOFFS1_B <= '0; end
			
			if (G2[2])      begin YOFFS2_A <= {3'b000,XY_FIFO_A_OUT.Y[10:1],8'b00000000};  YOFFS2_B <= {3'b000,XY_FIFO_B_OUT.Y[10:1],8'b00000000}; end
			else if (G2[1]) begin YOFFS2_A <= {4'b0000,XY_FIFO_A_OUT.Y[10:1],7'b0000000};  YOFFS2_B <= {4'b0000,XY_FIFO_B_OUT.Y[10:1],7'b0000000}; end
			else if (G2[0]) begin YOFFS2_A <= {5'b00000,XY_FIFO_A_OUT.Y[10:1],6'b000000};  YOFFS2_B <= {5'b00000,XY_FIFO_B_OUT.Y[10:1],6'b000000}; end
			else            begin YOFFS2_A <= '0;                                          YOFFS2_B <= '0; end
		
			ADDR_FF_A <= {BASE,1'b0} + {10'b0000000000,XY_FIFO_A_OUT.X,XY_FIFO_A_OUT.Y[0]}; ADDR_FF_B <= {BASE,1'b0} + {10'b0000000000,XY_FIFO_B_OUT.X,XY_FIFO_B_OUT.Y[0]};
			DRAW_A_FF <= XY_FIFO_A_DRAW;
			DRAW_B_FF <= XY_FIFO_B_DRAW;
			
			//step2
			DST_ADDR_A_NEW = ADDR_FF_A + {YOFFS1_A,1'b0} + {YOFFS2_A,1'b0};
			DST_ADDR_B_NEW = ADDR_FF_B + {YOFFS1_B,1'b0} + {YOFFS2_B,1'b0};
			if (DRAW_A_FF  && (BUS_STATE_FF == CFB_INIT0)) begin DST_PAGE_A <= DST_ADDR_A_NEW[23:11]; end
			if (DRAW_B_FF  && (BUS_STATE_FF == CFB_INIT0)) begin DST_PAGE_B <= DST_ADDR_B_NEW[23:11]; end
			if (DRAW_A_FF  && (BUS_STATE == CFB_INIT0 || BUS_STATE_FF == CFB_INIT1 || BUS_STATE_FF == CFB_WRITE1 || BUS_STATE_FF == CFB_READ1)) begin DST_ADDR_A <= DST_ADDR_A_NEW; DST_PB_A <= &DST_ADDR_A_NEW[10:2]; end
			if (DRAW_B_FF  && (BUS_STATE == CFB_INIT0 || BUS_STATE_FF == CFB_INIT1 || BUS_STATE_FF == CFB_WRITE1 || BUS_STATE_FF == CFB_READ1)) begin DST_ADDR_B <= DST_ADDR_B_NEW; DST_PB_B <= &DST_ADDR_B_NEW[10:2]; end
			DST_READ <= DOLO_CYCLE;
			if (BUS_STATE_FF == CFB_WRITE0 && (XY_FIFO_A_EMPTY || DST_PB_A || DST_PB_B) && !DST_LAST_A) DST_LAST_A <= 1;
			if (((DRAW_A_FF && DST_ADDR_A_NEW[23:11] != DST_PAGE_A) || (DRAW_B_FF && DST_ADDR_B_NEW[23:11] != DST_PAGE_B)) && FB_IN_DRAM && !DST_LAST_A) DST_LAST_A <= 1;
			if (DST_LAST_A && !DST_LAST_B) DST_LAST_B <= 1;
			if (CFB_SUSPEND && BUS_STATE_FF == CFB_WRITE0 && !DST_SUSPEND) begin DST_SUSPEND <= 1; end
			if (BUS_STATE_FF == CFB_INIT0) {DST_LAST_A,DST_LAST_B,DST_SUSPEND} <= '0;
			
			if (BUS_STATE_FF == CFB_INIT0 || BUS_STATE_FF == CFB_WRITE1) DST_WRITE_A <= 0;
			if ((BUS_STATE_FF == CFB_INIT1 && DRAW_A_FF) || ((BUS_STATE_FF == CFB_WRITE1 || BUS_STATE_FF == CFB_READ1) && DRAW_A_FF && !DST_LAST_A && !DST_SUSPEND)) begin
				DST_WRITE_A <= 1;
			end
			
			if (BUS_STATE_FF == CFB_INIT0 || BUS_STATE_FF == CFB_WRITE1) DST_WRITE_B <= 0;
			if ((BUS_STATE_FF == CFB_INIT1 && DRAW_B_FF) || ((BUS_STATE_FF == CFB_WRITE1 || BUS_STATE_FF == CFB_READ1) && DRAW_B_FF && !DST_LAST_A && !DST_SUSPEND)) begin
				DST_WRITE_B <= 1;
			end
			
`ifdef DEBUG
			DBG_DRAW_OUT <= 0;
//			if ((DST_ADDR_A < (24'h200000>>1) || DST_ADDR_A >= (24'h24B000>>1) && DST_WRITE_A) || 
//			    (DST_ADDR_B < (24'h200000>>1) || DST_ADDR_B >= (24'h24B000>>1) && DST_WRITE_B)) DBG_DRAW_OUT <= 1;
				 
			if (((DST_ADDR_A < (DBG_REGCTL3>>1) || DST_ADDR_A >= ((DBG_REGCTL3+24'h000E00)>>1)) && DST_WRITE_A && DBG_REGCTL3) || 
			    ((DST_ADDR_B < (DBG_REGCTL3>>1) || DST_ADDR_B >= ((DBG_REGCTL3+24'h000E00)>>1)) && DST_WRITE_B && DBG_REGCTL3)) DBG_DRAW_OUT <= 1;
`endif
		end
	end 
	assign CFB_ADDR_A  = DST_ADDR_A;
	assign CFB_ADDR_B = DST_ADDR_B;
`ifdef DEBUG
	assign CFB_WRITE_A  = DST_WRITE_A & ~DBG_SPRITE_HIT;
	assign CFB_WRITE_B = DST_WRITE_B & ~DBG_SPRITE_HIT;
	assign CFB_RAS_A  = (BUS_STATE_FF == CFB_INIT1 && DRAW_A_FF) & ~DBG_SPRITE_HIT;
	assign CFB_RAS_B = (BUS_STATE_FF == CFB_INIT1 && DRAW_B_FF) & ~DBG_SPRITE_HIT;
`else
	assign CFB_WRITE_A  = DST_WRITE_A;
	assign CFB_WRITE_B = DST_WRITE_B;
	assign CFB_RAS_A  = (BUS_STATE_FF == CFB_INIT1 && DRAW_A_FF);
	assign CFB_RAS_B = (BUS_STATE_FF == CFB_INIT1 && DRAW_B_FF);
`endif
	assign CFB_READ = DST_READ;
	
	always_comb begin
		AG_CTL = '0;
		SCOB_SEL = 3'b000;
		SPR_SEL = {1'b0,1'b0};
		CFB_SEL = 2'b00;
		
		case (BUS_STATE)
			SCOB_PREINIT1: begin
				AG_CTL.DMA_GROUP_ADDR = 7'h68;
				AG_CTL.DMA_GROUP_ADDR_SEL = 1;
				AG_CTL.DMA_GROUP_HOLD = 1;
				AG_CTL.DMA_ADDR_SEL = 1;
				AG_CTL.DMA_ADDER_CTL = 4'b0000;
			end
			
			SCOB_INIT0: begin
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = BUS_PB ? 2'h0 : 2'h1;
				AG_CTL.DMA_ADDR_SEL = 1;
				AG_CTL.DMA_ADDER_CTL = 4'b0000;
			end
			
			SCOB_INIT1: begin
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = BUS_PB ? 2'h0 : 2'h1;
				AG_CTL.DMA_ADDR_SEL = 1;
				AG_CTL.DMA_ADDER_CTL = 4'b0000;
			end
			
			SCOB_FLAG0: begin
				AG_CTL.DMA_OWN_SEL = 1;
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = 2'h1;
				AG_CTL.DMA_REG_WRITE_SEL = 0;
				AG_CTL.DMA_REG_WRITE_CTL = 3'h0;
				AG_CTL.DMA_REG_WRITE_EN = 1;
				AG_CTL.DMA_ADDR_SEL = 1;
				AG_CTL.DMA_ADDER_CTL = 4'b0001;
			end
			
			SCOB_FLAG1: begin
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = 2'h0;
				AG_CTL.DMA_ADDER_CTL = 4'b0001;
			end
			
			SCOB_NEXT0,
			SCOB_SOURCE0,
			SCOB_PIPPTR0,
			SCOB_XPOS0,
			SCOB_YPOS0: begin
				AG_CTL.DMA_OWN_SEL = 1;
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = 2'h0;
				AG_CTL.DMA_REG_WRITE_SEL = 0;
				AG_CTL.DMA_REG_WRITE_CTL = 3'h0;
				AG_CTL.DMA_REG_WRITE_EN = 1;
				AG_CTL.DMA_ADDR_SEL = 1;
				AG_CTL.DMA_ADDER_CTL = 4'b0001;
			end
			
			SCOB_NEXT1: begin
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = 2'h0;
				AG_CTL.DMA_REG_WRITE_SEL = 0;
				AG_CTL.DMA_REG_WRITE_CTL = 3'h1;
				AG_CTL.DMA_REG_WRITE_EN = 1;
				AG_CTL.DMA_ADDER_CTL = 4'b0000;
				SCOB_SEL = {1'b0,1'b0,~SCOB_FLAG.NPABS};
			end
			
			SCOB_NEXT_REL0: begin
				AG_CTL.DMA_OWN_SEL = 1;
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = 2'h0;
				AG_CTL.DMA_REG_WRITE_SEL = 0;
				AG_CTL.DMA_REG_WRITE_CTL = 3'h1;
				AG_CTL.DMA_REG_WRITE_EN = 1;
				AG_CTL.DMA_ADDR_SEL = 1;
				AG_CTL.DMA_ADDER_CTL = 4'b0101;
			end
			
			SCOB_NEXT_REL1: begin
				AG_CTL.DMA_OWN_SEL = 1;
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = 2'h0;
				AG_CTL.DMA_ADDR_SEL = 1;
				AG_CTL.DMA_ADDER_CTL = 4'b0001;
			end
			
			SCOB_SOURCE1: begin
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = 2'h0;
				AG_CTL.DMA_REG_WRITE_SEL = 0;
				AG_CTL.DMA_REG_WRITE_CTL = 3'h3;
				AG_CTL.DMA_REG_WRITE_EN = 1;
				AG_CTL.DMA_ADDER_CTL = 4'b0000;
				SCOB_SEL = {1'b0,1'b0,~SCOB_FLAG.SPABS&~SCOB_FLAG.SKIP};
			end
			
			SCOB_SOURCE_REL0: begin
				AG_CTL.DMA_OWN_SEL = 1;
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = 2'h0;
				AG_CTL.DMA_REG_WRITE_SEL = 0;
				AG_CTL.DMA_REG_WRITE_CTL = 3'h3;
				AG_CTL.DMA_REG_WRITE_EN = 1;
				AG_CTL.DMA_ADDR_SEL = 1;
				AG_CTL.DMA_ADDER_CTL = 4'b0101;
			end
			
			SCOB_SOURCE_REL1: begin
				AG_CTL.DMA_OWN_SEL = 1;
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = 2'h0;
				AG_CTL.DMA_ADDR_SEL = 1;
				AG_CTL.DMA_ADDER_CTL = 4'b0001;
			end
			
			SCOB_PIPPTR1: begin
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = 2'h0;
				AG_CTL.DMA_REG_WRITE_SEL = 0;
				AG_CTL.DMA_REG_WRITE_CTL = 3'h2;
				AG_CTL.DMA_REG_WRITE_EN = 1;
				AG_CTL.DMA_ADDER_CTL = 4'b0001;
				SCOB_SEL = {1'b0,1'b0,~SCOB_FLAG.PPABS&~SCOB_FLAG.SKIP};
			end
			
			SCOB_PIPPTR_REL0: begin
				AG_CTL.DMA_OWN_SEL = 1;
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = 2'h0;
				AG_CTL.DMA_REG_WRITE_SEL = 0;
				AG_CTL.DMA_REG_WRITE_CTL = 3'h2;
				AG_CTL.DMA_REG_WRITE_EN = 1;
				AG_CTL.DMA_ADDR_SEL = 1;
				AG_CTL.DMA_ADDER_CTL = 4'b0101;
			end
			
			SCOB_PIPPTR_REL1: begin
				AG_CTL.DMA_OWN_SEL = 1;
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = 2'h0;
				AG_CTL.DMA_ADDR_SEL = 1;
				AG_CTL.DMA_ADDER_CTL = 4'b0001;
			end
			
			SCOB_XPOS1: begin
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = 2'h0;
				AG_CTL.DMA_ADDER_CTL = 4'b0001;
			end
			
			SCOB_YPOS1: begin
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = 2'h0;
				AG_CTL.DMA_ADDER_CTL = 4'b0001;
				SCOB_SEL = {1'b0,SCOB_FLAG.LDPPMP|SCOB_FLAG.LDPRS|SCOB_FLAG.LDSIZE,SCOB_FLAG.SKIP};
			end
			
			SCOB_PREINIT3: begin
				AG_CTL.DMA_GROUP_ADDR = 7'h68;
				AG_CTL.DMA_GROUP_ADDR_SEL = 1;
				AG_CTL.DMA_GROUP_HOLD = 1;
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = 2'h0;
				AG_CTL.DMA_ADDR_SEL = 1;
				AG_CTL.DMA_ADDER_CTL = 4'b0001;
			end
			
			SCOB_INIT2: begin
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = 2'h0;
				AG_CTL.DMA_ADDR_SEL = 1;
				AG_CTL.DMA_ADDER_CTL = 4'b0001;
			end
			
			SCOB_INIT3: begin
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = 2'h0;
				AG_CTL.DMA_ADDR_SEL = 1;
				AG_CTL.DMA_ADDER_CTL = 4'b0000;
				SCOB_SEL = {SCOB_FLAG.LDPPMP,SCOB_FLAG.LDPRS,SCOB_FLAG.LDSIZE};
			end
			
			SCOB_DX0,
			SCOB_DY0,
			SCOB_LINEDX0,
			SCOB_LINEDY0,
			SCOB_DDX0,
			SCOB_DDY0,
			SCOB_PPMP0: begin
				AG_CTL.DMA_OWN_SEL = 1;
				AG_CTL.DMA_REG_WRITE_SEL = 0;
				AG_CTL.DMA_REG_WRITE_CTL = 3'h0;
				AG_CTL.DMA_REG_WRITE_EN = 1;
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = 2'h0;
				AG_CTL.DMA_ADDR_SEL = BURST0;
				AG_CTL.DMA_ADDER_CTL = 4'b0001;
			end
			
			SCOB_DX1,
			SCOB_DY1,
			SCOB_LINEDX1,
			SCOB_LINEDY1,
			SCOB_DDX1,
			SCOB_DDY1,
			SCOB_PPMP1: begin
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = 2'h0;
				AG_CTL.DMA_ADDER_CTL = 4'b0001;
				SCOB_SEL = {SCOB_FLAG.LDPPMP,SCOB_FLAG.LDPRS,SCOB_FLAG.LDSIZE};
			end
			
			SCOB_PREINIT5: begin
				AG_CTL.DMA_GROUP_ADDR = 7'h68;
				AG_CTL.DMA_GROUP_ADDR_SEL = 1;
				AG_CTL.DMA_GROUP_HOLD = 1;
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = SCOB_FLAG.SCOBPRE ? 2'h0 : 2'h3;
				AG_CTL.DMA_ADDR_SEL = 1;
				AG_CTL.DMA_ADDER_CTL = 4'b0000;
			end
			
			SCOB_INIT4: begin
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = SCOB_FLAG.SCOBPRE ? 2'h0 : 2'h3;
				AG_CTL.DMA_ADDR_SEL = 1;
				AG_CTL.DMA_ADDER_CTL = 4'b0000;
			end
			
			SCOB_INIT5: begin
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = SCOB_FLAG.SCOBPRE ? 2'h0 : 2'h3;
				AG_CTL.DMA_ADDR_SEL = 1;
				AG_CTL.DMA_ADDER_CTL = 4'b0000;
			end
			
			SCOB_PRE00,
			SCOB_PRE10: begin
				AG_CTL.DMA_OWN_SEL = 1;
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = SCOB_FLAG.SCOBPRE ? 2'h0 : 2'h3;
				AG_CTL.DMA_REG_WRITE_SEL = 0;
				AG_CTL.DMA_REG_WRITE_CTL = SCOB_FLAG.SCOBPRE ? 3'h0 : 3'h3;
				AG_CTL.DMA_REG_WRITE_EN = 1;
				AG_CTL.DMA_ADDR_SEL = BURST0;
				AG_CTL.DMA_ADDER_CTL = 4'b0001;
				SCOB_SEL = {1'b0,SCOB_FLAG.LDPIP,~SCOB_FLAG.PACKED};
			end
			
			SCOB_PRE01: begin
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = SCOB_FLAG.SCOBPRE ? 2'h0 : 2'h3;
				AG_CTL.DMA_ADDER_CTL = 4'b0001;
				SCOB_SEL = {1'b0,SCOB_FLAG.LDPIP,~SCOB_FLAG.PACKED};
			end
			
			SCOB_PRE11: begin
				AG_CTL.BPP_SEL = (SCOB_PRE0.BPP <= 3'h4);
				AG_CTL.BYPASS_EN = 1;
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = SCOB_FLAG.SCOBPRE ? 2'h0 : 2'h3;
				AG_CTL.DMA_ADDER_CTL = 4'b0001;
				SCOB_SEL = {1'b0,SCOB_FLAG.LDPIP,~SCOB_FLAG.PACKED};
			end
			
			SCOB_PREINIT7: begin
				AG_CTL.DMA_GROUP_ADDR = 7'h68;
				AG_CTL.DMA_GROUP_ADDR_SEL = 1;
				AG_CTL.DMA_GROUP_HOLD = 1;
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = 2'h2;
				AG_CTL.DMA_ADDR_SEL = 1;
				AG_CTL.DMA_ADDER_CTL = 4'b0000;
			end
			
			SCOB_INIT6: begin
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = 2'h2;
				AG_CTL.DMA_ADDR_SEL = 1;
				AG_CTL.DMA_ADDER_CTL = 4'b0000;
			end
			
			SCOB_INIT7: begin
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = 2'h2;
				AG_CTL.DMA_ADDR_SEL = 1;
				AG_CTL.DMA_ADDER_CTL = 4'b0000;
			end
			
			SCOB_PIP0: begin
				AG_CTL.DMA_OWN_SEL = 1;
				AG_CTL.DMA_REG_WRITE_SEL = 0;
				AG_CTL.DMA_REG_WRITE_CTL = 3'h2;
				AG_CTL.DMA_REG_WRITE_EN = 1;
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = 2'h2;
				AG_CTL.DMA_ADDR_SEL = BURST0;
				AG_CTL.DMA_ADDER_CTL = 4'b0001;
				SCOB_SEL = {~LAST_PIP,SCOB_FLAG.LDPIP,BURST_LAST};
			end
			
			SCOB_PIP1: begin
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = 2'h2;
				AG_CTL.DMA_ADDER_CTL = 4'b0001;
				SCOB_SEL = {~LAST_PIP,SCOB_FLAG.LDPIP,BURST_LAST};
			end
			
			//Sprite data fetch (first two words)
			SPR_PREINIT1: begin
				AG_CTL.DMA_GROUP_ADDR = 7'h68;
				AG_CTL.DMA_GROUP_ADDR_SEL = 1;
				AG_CTL.DMA_GROUP_HOLD = 1;
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = 2'h3;
				AG_CTL.DMA_ADDR_SEL = 1;
				AG_CTL.DMA_ADDER_CTL = 4'b0000;
			end
			
			SPR_INIT0: begin
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = 2'h3;
				AG_CTL.DMA_ADDR_SEL = 1;
				AG_CTL.DMA_ADDER_CTL = 4'b0000;
			end
			
			SPR_INIT1: begin
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = 2'h3;
				AG_CTL.DMA_ADDR_SEL = 1;
				AG_CTL.DMA_ADDER_CTL = 4'b0000;
			end
			
			SPR_OFFS0: begin							//
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = 2'h3;
				AG_CTL.DMA_ADDR_SEL = 1;
				AG_CTL.DMA_ADDER_CTL = 4'b0001;
			end
			
			SPR_OFFS1: begin							//*SPRYTE_DATA_ADDRESS(3)->BYPASS, SPRYTE_DATA_ADDRESS(3)+1->SPRYTE_DATA_ADDRESS(3)
				AG_CTL.BPP_SEL = (SCOB_PRE0.BPP <= 3'h4);
				AG_CTL.BYPASS_EN = SCOB_FLAG.PACKED;
				AG_CTL.DMA_OWN_SEL = 1;
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = 2'h3;
				AG_CTL.DMA_REG_WRITE_SEL = 0;
				AG_CTL.DMA_REG_WRITE_CTL = 3'h3;
				AG_CTL.DMA_REG_WRITE_EN = 1;
				AG_CTL.DMA_ADDER_CTL = 4'b0001;
			end
			
			SPR_OFFS2: begin							//
				AG_CTL.DMA_OWN_SEL = 1;
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = 2'h3;
				AG_CTL.DMA_ADDR_SEL = 1;
				AG_CTL.DMA_ADDER_CTL = 4'b0010;
			end
			
			SPR_OFFS3: begin							//SPRYTE_DATA_ADDRESS(3)->ENGINE_A_FETCH_ADDRESS(4/6)
				AG_CTL.DMA_OWN_SEL = 1;
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = 2'h3;
				AG_CTL.DMA_REG_WRITE_SEL = 0;
				AG_CTL.DMA_REG_WRITE_CTL = {1'b1,ENGINE_B,1'b0};
				AG_CTL.DMA_REG_WRITE_EN = 1;
				AG_CTL.DMA_ADDR_SEL = 1;
				AG_CTL.DMA_ADDER_CTL = 4'b0001;
			end
			
			SPR_CALC0: begin							//BYPASS->ENGINE_A_LENGTH(5/7), BYPASS->OFFSET
				AG_CTL.LOAD_OFFSET_SEL = 1;
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = 2'h0;
				AG_CTL.DMA_REG_WRITE_SEL = 0;
				AG_CTL.DMA_REG_WRITE_CTL = {1'b1,ENGINE_B,1'b1};
				AG_CTL.DMA_REG_WRITE_EN = 1;
				AG_CTL.DMA_ADDER_CTL = 4'b0000;
			end
			
			SPR_CALC1: begin							//SPRYTE_DATA_ADDRESS(3)+OFFSET->SPRYTE_DATA_ADDRESS(3)
				AG_CTL.DMA_OWN_SEL = 1;
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = 2'h1;
				AG_CTL.DMA_REG_WRITE_SEL = 0;
				AG_CTL.DMA_REG_WRITE_CTL = 3'h3;
				AG_CTL.DMA_REG_WRITE_EN = 1;
				AG_CTL.DMA_ADDR_SEL = 1;
				AG_CTL.DMA_ADDER_CTL = 4'b0101;
			end
			
			//Sprite data fetch (next words)
			SPR_PREINIT3: begin
				AG_CTL.DMA_GROUP_ADDR = 7'h6C;
				AG_CTL.DMA_GROUP_ADDR_SEL = 1;
				AG_CTL.DMA_GROUP_HOLD = 1;
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = 2'h0;
				AG_CTL.DMA_ADDR_SEL = 1;
				AG_CTL.DMA_ADDER_CTL = 4'b0000;
			end
			
			SPR_INIT2: begin
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = {ENGINE_B,1'b0};
				AG_CTL.DMA_ADDR_SEL = 1;
				AG_CTL.DMA_ADDER_CTL = 4'b0000;
			end
			
			SPR_INIT3: begin
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = {ENGINE_B,1'b1};
				AG_CTL.DMA_ADDR_SEL = 1;
				AG_CTL.DMA_ADDER_CTL = 4'b0000;
			end
			
			SPR_DATA0: begin							//ENGINE_A_LENGTH(5/7)-1->ENGINE_A_LENGTH(5/7)
				AG_CTL.DMA_OWN_SEL = 1;
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = {ENGINE_B,1'b0};
				AG_CTL.DMA_REG_WRITE_SEL = 0;
				AG_CTL.DMA_REG_WRITE_CTL = {1'b1,ENGINE_B,1'b1};
				AG_CTL.DMA_REG_WRITE_EN = 1;
				AG_CTL.DMA_ADDR_SEL = 1;
				AG_CTL.DMA_ADDER_CTL = 4'b0010;
			end
			
			SPR_DATA1: begin							//ENGINE_A_FETCH_ADDRESS(4/6)+1->ENGINE_A_FETCH_ADDRESS(4/6)
				AG_CTL.DMA_OWN_SEL = 1;
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = {ENGINE_B,1'b1};
				AG_CTL.DMA_REG_WRITE_SEL = 0;
				AG_CTL.DMA_REG_WRITE_CTL = {1'b1,ENGINE_B,1'b0};
				AG_CTL.DMA_REG_WRITE_EN = 1;
				AG_CTL.DMA_ADDR_SEL = 1;
				AG_CTL.DMA_ADDER_CTL = 4'b0001;
				SPR_SEL[0] = (BURST_LAST|DMA_REG_ZERO);
			end
			
			//Pixel read/write
			CFB_INIT0,
			CFB_INIT1: begin
				AG_CTL.SPR_ADDR_SEL = 1;
				AG_CTL.DMA_ADDR_SEL = 0;
				CFB_SEL = {DOLO_CYCLE,2'b00};
			end
			
			CFB_READ0: begin
				AG_CTL.SPR_ADDR_SEL = 1;
				AG_CTL.DMA_ADDR_SEL = 0;
				CFB_SEL = {2'b00,DST_WRITE_A};
			end
			CFB_READ1: begin
				AG_CTL.SPR_ADDR_SEL = 1;
				AG_CTL.DMA_ADDR_SEL = 0;
				CFB_SEL = {2'b00,DST_WRITE_B};
			end
			
			CFB_WRITE0: begin
				AG_CTL.SPR_ADDR_SEL = 1;
				AG_CTL.DMA_ADDR_SEL = 0;
				CFB_SEL = {2'b00,DST_READ&DST_WRITE_A};
			end
			CFB_WRITE1: begin
				AG_CTL.SPR_ADDR_SEL = 1;
				AG_CTL.DMA_ADDR_SEL = 0;
				CFB_SEL = {DOLO_CYCLE,DST_SUSPEND,DST_LAST_A};
			end
			
			default:;
		endcase
	end
	
endmodule

	
module MADAM_UNPACKER (
	input              CLK,
	input              RST,
	input              EN,
	
	input              CE,
	
	input      [ 2: 0] PRE0_BPP,
	input      [ 3: 0] PRE0_SKPX,
	input      [10: 0] PRE1_PCNT,
	input              PACKED,
	
	input      [15: 0] IN,
	input              AVAIL,
	input              NEWL,
	input              TAK,
	
	output reg         T,
	output reg         EOL,
	output reg [15: 0] OUT,
	output reg         NEXT,
	output             READY
	
`ifdef DEBUG
	                   ,
	output reg [10: 0] DBG_PIX_CNT
`endif
);

	typedef enum bit [2:0] {
		UP_IDLE,
		UP_PRELOAD,
		UP_OFFS_READ,
		UP_CTRL_READ,
		UP_TRANSPARENT,
		UP_DATA_READ,
		UP_DATA_REPEAT
	} UnpackerState_t;
	UnpackerState_t UP_ST;
	
	bit  [ 2: 0] BPP;
	bit  [ 1: 0] TYPE;
	bit  [ 5: 0] COUNT;
	bit  [ 3: 0] SKIP_CNT;
	wire SKIP = (SKIP_CNT != PRE0_SKPX);
	
	always @(posedge CLK) begin
		bit  [ 3: 0] BIT_CNT;
		bit  [ 4: 0] BITS_BY_BPP;
		bit  [ 3: 0] BIT_CNT_NEXT;
		bit          BIT_CNT_OVER;
		bit  [31: 0] BUF;
		bit          BUF_LOAD;
		bit          CODE_NEXT,CODE_OUT;
		bit  [10: 0] PIX_CNT;
		bit  [31: 0] TEMP;
		bit  [15: 0] CODE;
	
		if (RST) begin
			UP_ST <= UP_IDLE;
			BIT_CNT <= '0;
			SKIP_CNT <= '0;
			OUT <= '0;
			T <= 0;
			EOL <= 1;
			NEXT <= 0;
			// synopsys translate_off
			BUF <= '0;
			// synopsys translate_on
		end
		else if (EN && CE) begin
			case (BPP)
				3'h1: BITS_BY_BPP = 5'd1;
				3'h2: BITS_BY_BPP = 5'd2;
				3'h3: BITS_BY_BPP = 5'd4;
				3'h4: BITS_BY_BPP = 5'd6;
				3'h5: BITS_BY_BPP = 5'd8;
				3'h6: BITS_BY_BPP = 5'd16;
				default: BITS_BY_BPP = 5'd0;
			endcase
			{BIT_CNT_OVER,BIT_CNT_NEXT} = {1'b0,BIT_CNT} + BITS_BY_BPP;
			
			TEMP = BUF << BIT_CNT;
			case (BPP)
				3'h1: CODE = {15'b0000_0000_0000_000,TEMP[31:31]};
				3'h2: CODE = {14'b0000_0000_0000_00, TEMP[31:30]};
				3'h3: CODE = {12'b0000_0000_0000,    TEMP[31:28]};
				3'h4: CODE = {10'b0000_0000_00,      TEMP[31:26]};
				3'h5: CODE = { 8'b0000_0000,         TEMP[31:24]};
				3'h6: CODE = {                       TEMP[31:16]};
				default: CODE = 15'h0000;
			endcase
			
			
			BUF_LOAD = 0;
			CODE_NEXT = 0;
			CODE_OUT = 0;
			case (UP_ST)
				UP_IDLE: begin
					if (AVAIL && !EOL) begin
						BUF_LOAD = 1;
						UP_ST <= UP_PRELOAD;
					end
					
`ifdef DEBUG
					DBG_PIX_CNT <= '0;
`endif
				end
				
				UP_PRELOAD: if (AVAIL) begin
					BUF_LOAD = 1;
//					{TYPE,COUNT} <= '0;
					PIX_CNT <= '0;
					if (PACKED) begin
						BPP <= PRE0_BPP <= 3'h4 ? 3'h5 : 3'h6;
						UP_ST <= UP_OFFS_READ;
					end else begin
						BPP <= PRE0_BPP;
						UP_ST <= UP_DATA_READ;
					end
				end
				
				UP_OFFS_READ: if (AVAIL) begin
					BUF_LOAD = BIT_CNT_OVER;
					CODE_NEXT = 1;
					BPP <= 3'h5;
//					{TYPE,COUNT} <= '0;
					UP_ST <= UP_CTRL_READ;
				end
				
				UP_CTRL_READ: if (AVAIL) begin
					BUF_LOAD = BIT_CNT_OVER;
					CODE_NEXT = 1;
					{TYPE,COUNT} <= CODE[7:0];
					BPP <= PRE0_BPP;
					if (CODE[7:6] == 2'b00) begin
						BUF_LOAD = 0;
						EOL <= 1;
						UP_ST <= UP_IDLE;
					end else if (CODE[7:6] == 2'b10) begin
						UP_ST <= UP_TRANSPARENT;
					end else begin
						UP_ST <= UP_DATA_READ;
					end
				end
				
				UP_TRANSPARENT: if ((TAK || SKIP) && AVAIL) begin
					if (SKIP) SKIP_CNT <= SKIP_CNT + 4'd1;
					CODE_OUT = 1;
					COUNT <= COUNT - 6'd1;
					PIX_CNT <= PIX_CNT + 11'd1;
					if (!COUNT) begin
						BPP <= 3'h5;
						{TYPE,COUNT} <= '0;
						UP_ST <= UP_CTRL_READ;
					end else begin
						UP_ST <= UP_DATA_REPEAT;
					end
				end
				
				UP_DATA_READ: if ((TAK || SKIP) && AVAIL) begin
					if (SKIP) SKIP_CNT <= SKIP_CNT + 4'd1;
					BUF_LOAD = BIT_CNT_OVER;
					CODE_NEXT = 1;
					CODE_OUT = 1;
					COUNT <= COUNT - 6'd1;
					PIX_CNT <= PIX_CNT + 11'd1;
					if (!PACKED) begin
						if (PIX_CNT == PRE1_PCNT) begin
							BUF_LOAD = 0;
							EOL <= 1;
							UP_ST <= UP_IDLE;
						end else begin
							UP_ST <= UP_DATA_READ;
						end
					end else if (!COUNT) begin
						BPP <= 3'h5;
						{TYPE,COUNT} <= '0;
						UP_ST <= UP_CTRL_READ;
					end else if (TYPE == 2'b11) begin
						UP_ST <= UP_DATA_REPEAT;
					end
					
`ifdef DEBUG
					DBG_PIX_CNT <= DBG_PIX_CNT + 1'd1;
`endif
				end
				
				UP_DATA_REPEAT: if (TAK || SKIP) begin
					if (SKIP) SKIP_CNT <= SKIP_CNT + 4'd1;
					COUNT <= COUNT - 6'd1;
					PIX_CNT <= PIX_CNT + 11'd1;
					if (!COUNT) begin
						BPP <= 3'h5;
						{TYPE,COUNT} <= '0;
						UP_ST <= UP_CTRL_READ;
					end
					
`ifdef DEBUG
					DBG_PIX_CNT <= DBG_PIX_CNT + 1'd1;
`endif
				end
			endcase
			
			if (NEWL) begin
				EOL <= 0;
				SKIP_CNT <= '0;
				UP_ST <= UP_IDLE;
			end
			
			NEXT <= 0;
			if (BUF_LOAD) begin
				BUF <= {BUF[15:0],IN};
				NEXT <= 1;
			end
			
			if (NEWL) begin
				BIT_CNT <= '0;
			end
			if (CODE_NEXT) begin
				BIT_CNT <= BIT_CNT_NEXT[3:0];
			end
			
			if (CODE_OUT) begin
				if (UP_ST == UP_TRANSPARENT) begin
					OUT <= '0;
					T <= 1;
				end else begin 
					OUT <= CODE;
					T <= 0;
				end
			end
		end
	end 
	assign READY = ((UP_ST == UP_DATA_READ || UP_ST == UP_TRANSPARENT) && AVAIL && !SKIP) || (UP_ST == UP_DATA_REPEAT && !SKIP);

endmodule
	
module MADAM_PPMP (
	input             CLK,
	input             RST,
	input             EN,
	
	input             CE,
	
	input SCoBCtl_t   SCOBCTL,
	input SCoBFlag_t  SCOB_FLAG,
	input SCoBPre1_t  SCOB_PRE1,     // Game Bub port: NOSWAP, TLLSBIPN of an unpacked cel
	input PPMPCx_t    PPMPCA,
	input PPMPCx_t    PPMPCB,
	
	input IPN_t       IPN,
	input     [15: 0] CFBD,
	output reg    [15: 0] PEN
);

	PPMPCx_t  PPMPC;
	always_comb begin
		bit          PPMPC_SEL;
		
		case (SCOB_FLAG.DOVER)
			// Game Bub port: POVER 01 is not an override (Opera: only 10 and 11
			// force the P-mode; SDK PMODE_PDC 00, ZERO 10, ONE 11, i.e. bit 8
			// enables the override, bit 7 is its value). The original forced
			// the first PIXC half.
			2'b00,
			2'b01: PPMPC_SEL = IPN.D;
			2'b10: PPMPC_SEL = 0;
			2'b11: PPMPC_SEL = 1;
		endcase
		PPMPC = !PPMPC_SEL ? PPMPCA : PPMPCB;
	end

	bit          DV2_PIPE;
	bit  [ 6: 0] ADDA_R_PIPE,ADDA_G_PIPE,ADDA_B_PIPE;
	bit  [ 4: 0] ADDB_R_PIPE,ADDB_G_PIPE,ADDB_B_PIPE;
	bit          ADDB6_R_PIPE,ADDB6_G_PIPE,ADDB6_B_PIPE;
	bit          SPH_PIPE,SPV_PIPE;
	bit          NEG_PIPE;
	bit          CLIP_PIPE;
	bit          NOBLK_PIPE;
	always @(posedge CLK or posedge RST) begin
		bit  [ 4: 0] AV;
		bit  [ 2: 0] MV_R,MV_G,MV_B;
		bit  [ 1: 0] DV1_R,DV1_G,DV1_B;
		bit  [ 7: 0] MRES_R,MRES_G,MRES_B;
		bit  [ 4: 0] TEMPA_R,TEMPA_G,TEMPA_B;
		bit  [ 4: 0] TEMPB_R,TEMPB_G,TEMPB_B;
		bit  [ 6: 0] DIVA_R,DIVA_G,DIVA_B;
		bit  [ 4: 0] DIVB_R,DIVB_G,DIVB_B;
		bit  [ 4: 0] PXORB_R,PXORB_G,PXORB_B;
		bit  [ 6: 0] ADDA_R,ADDA_G,ADDA_B;
		bit  [ 4: 0] ADDB_R,ADDB_G,ADDB_B;
		bit          ADDB6_R,ADDB6_G,ADDB6_B;
		bit  [ 4: 0] IPN_BLUE,CFB_BLUE;
		bit          SWAP,SUB_H,SUB_V;
		
		if (RST) begin
			DV2_PIPE <= 0;
			{ADDA_R_PIPE,ADDA_G_PIPE,ADDA_B_PIPE} <= '0;
			{ADDB_R_PIPE,ADDB_G_PIPE,ADDB_B_PIPE} <= '0;
			NEG_PIPE <= 0;
			CLIP_PIPE <= 0;
		end
		else if (EN) begin
			// Game Bub port: the blue components' LSB as they enter the pixel
			// processor, by the engine control word (WO 94/10642 Table VI;
			// SDK PDCLSB_* for the decoder's pixel (IPNLSB), CFBDLSB_* for
			// the frame buffer's): 0, bit 0, bit 4, bit 5 of the 16-bit
			// pixel. An unpacked ("totally literal") cel's second preamble
			// word has its own selection (TLLSB, Table IX; as in the Opera
			// emulator); PRE1 is cleared for packed cels. The original always
			// used bit 0 (the SDK default).
			case (!SCOB_FLAG.PACKED ? SCOB_PRE1.TLLSBIPN : SCOBCTL.IPNLSB)
				2'd0: IPN_BLUE = {IPN.B[4:1],1'b0};
				2'd1: IPN_BLUE = IPN.B;
				2'd2: IPN_BLUE = {IPN.B[4:1],IPN.B[4]};
				2'd3: IPN_BLUE = {IPN.B[4:1],IPN.G[0]};
			endcase
			case (SCOBCTL.CFBDLSB)
				2'd0: CFB_BLUE = {CFBD[4:1],1'b0};
				2'd1: CFB_BLUE = CFBD[4:0];
				2'd2: CFB_BLUE = {CFBD[4:1],CFBD[4]};
				2'd3: CFB_BLUE = {CFBD[4:1],CFBD[5]};
			endcase
			AV = SCOB_FLAG.USEAV ? PPMPC.AV : 5'b00000;
			case (PPMPC.MS)
				2'b00: {MV_R,MV_G,MV_B} = {PPMPC.MXF,PPMPC.MXF,PPMPC.MXF};
				2'b01: {MV_R,MV_G,MV_B} = {IPN.MR,IPN.MG,IPN.MB};
				2'b10,
				2'b11: {MV_R,MV_G,MV_B} = {IPN.R[4:2],IPN.G[4:2],IPN_BLUE[4:2]};
			endcase
			// Game Bub port: with MS = 10 the divider code is the decoder
			// component's two LSBs, 00 (/16) included (as DF; the Opera
			// emulator's PPROC). The original used PIXC DF when they were 00.
			{DV1_R,DV1_G,DV1_B} = {PPMPC.DV1,PPMPC.DV1,PPMPC.DV1};
			if (PPMPC.MS == 2'b10) {DV1_R,DV1_G,DV1_B} = {IPN.R[1:0],IPN.G[1:0],IPN_BLUE[1:0]};
			
			case (PPMPC.S1)
				1'b0: {TEMPA_R,TEMPA_G,TEMPA_B} = {IPN.R,IPN.G,IPN_BLUE};
				1'b1: {TEMPA_R,TEMPA_G,TEMPA_B} = {CFBD[14:10],CFBD[ 9: 5],CFB_BLUE};
			endcase
			MRES_R = TEMPA_R * (MV_R + 1'd1);
			case (DV1_R)
				2'b00: DIVA_R = {3'b000,MRES_R[7:4]};
				2'b01: DIVA_R = {MRES_R[7:1]};
				2'b10: DIVA_R = {1'b0,MRES_R[7:2]};
				2'b11: DIVA_R = {2'b00,MRES_R[7:3]};
			endcase
			MRES_G = TEMPA_G * (MV_G + 1'd1);
			case (DV1_G)
				2'b00: DIVA_G = {3'b000,MRES_G[7:4]};
				2'b01: DIVA_G = {MRES_G[7:1]};
				2'b10: DIVA_G = {1'b0,MRES_G[7:2]};
				2'b11: DIVA_G = {2'b00,MRES_G[7:3]};
			endcase
			MRES_B = TEMPA_B * (MV_B + 1'd1);
			case (DV1_B)
				2'b00: DIVA_B = {3'b000,MRES_B[7:4]};
				2'b01: DIVA_B = {MRES_B[7:1]};
				2'b10: DIVA_B = {1'b0,MRES_B[7:2]};
				2'b11: DIVA_B = {2'b00,MRES_B[7:3]};
			endcase
			{ADDA_R,ADDA_G,ADDA_B} = {DIVA_R,DIVA_G,DIVA_B} & {7*3{~SCOB_FLAG.PXOR}};
			
			case (PPMPC.S2)
				2'b00: {TEMPB_R,TEMPB_G,TEMPB_B} = '0;
				2'b01: {TEMPB_R,TEMPB_G,TEMPB_B} = {PPMPC.AV,PPMPC.AV,PPMPC.AV};
				2'b10: {TEMPB_R,TEMPB_G,TEMPB_B} = {CFBD[14:10],CFBD[ 9: 5],CFB_BLUE};
				2'b11: {TEMPB_R,TEMPB_G,TEMPB_B} = {IPN.R,IPN.G,IPN_BLUE};
			endcase
			case (AV[4:3])
				2'b00: {DIVB_R,DIVB_G,DIVB_B} = {{TEMPB_R[4:0]},{TEMPB_G[4:0]},{TEMPB_B[4:0]}};
				2'b01: {DIVB_R,DIVB_G,DIVB_B} = {{1'b0,TEMPB_R[4:1]},{1'b0,TEMPB_G[4:1]},{1'b0,TEMPB_B[4:1]}};
				2'b10,
				2'b11: {DIVB_R,DIVB_G,DIVB_B} = {{2'b00,TEMPB_R[4:2]},{2'b00,TEMPB_G[4:2]},{2'b00,TEMPB_B[4:2]}};
			endcase
			{PXORB_R,PXORB_G,PXORB_B} = ({DIVA_R[4:0],DIVA_G[4:0],DIVA_B[4:0]} & {5*3{SCOB_FLAG.PXOR}}) | {5*3{AV[0]}};
			{ADDB_R,ADDB_G,ADDB_B} = {DIVB_R,DIVB_G,DIVB_B} ^ {PXORB_R,PXORB_G,PXORB_B};
			{ADDB6_R,ADDB6_G,ADDB6_B} = ({ADDB_R[4],ADDB_G[4],ADDB_B[4]} & {3{AV[1]}}) | ({3{AV[0]}} & {3{~AV[1]}});
			
			DV2_PIPE <= PPMPC.DV2;
			{ADDA_R_PIPE,ADDA_G_PIPE,ADDA_B_PIPE} <= {ADDA_R,ADDA_G,ADDA_B};
			{ADDB_R_PIPE,ADDB_G_PIPE,ADDB_B_PIPE} <= {ADDB_R,ADDB_G,ADDB_B};
			{ADDB6_R_PIPE,ADDB6_G_PIPE,ADDB6_B_PIPE} <= {ADDB6_R,ADDB6_G,ADDB6_B};
			NEG_PIPE <= AV[0];
			CLIP_PIPE <= AV[2];
			NOBLK_PIPE <= SCOB_FLAG.NOBLK;
			// Game Bub port: the subposition bits H (pen bit 0) and V (bit 15)
			// for B0POS / B15POS = 3. SWAPHV swaps the decoder's ("prior to
			// their entry into the PPMP"), except for an unpacked cel whose
			// PRE1 has NOSWAP (Table IX). With CFBDSUB and the frame buffer
			// pixel a pixel processor source (1S = 1 or 2S = 2), its bits 0
			// and 15 replace them (Table VI: "CFBDsel = (S1=1) OR (S2=2)"),
			// already in frame buffer form, so not swapped. The original
			// swapped at the output and ignored NOSWAP and CFBDSUB.
			SWAP = SCOBCTL.SWAPHV && !(!SCOB_FLAG.PACKED && SCOB_PRE1.NOSWAP);
			{SUB_H,SUB_V} = SWAP ? {IPN.SPV,IPN.SPH} : {IPN.SPH,IPN.SPV};
			if (SCOBCTL.CFBDSUB && (PPMPC.S1 || PPMPC.S2 == 2'b10)) {SUB_H,SUB_V} = {CFBD[0],CFBD[15]};
			SPH_PIPE <= SUB_H;
			SPV_PIPE <= SUB_V;
		end
	end
	
	// Game Bub port: the final sum is 9 bits wide. The first source term is
	// 0..124, the secondary one -32..31 (subtracted or sign extended), so the
	// sum is -32..155. The original's 8 bits could not tell a sum of 128..155
	// from a negative one, and when not subtracting it tested for overflow
	// before testing the sign: with a sign-extended secondary source
	// (AV[1]) a negative sum gave 31 (white) instead of 0.
	always @(posedge CLK or posedge RST) begin
		bit  [ 8: 0] ADD_R,ADD_G,ADD_B;
		bit  [ 8: 0] DIVR_R,DIVR_G,DIVR_B;
		bit  [ 4: 0] PEN_R,PEN_G,PEN_B;
		bit          PEN15;

		if (RST) begin
			PEN <= '0;
		end
		else if (EN && CE) begin
			ADD_R = {2'b00,ADDA_R_PIPE} + {{4{ADDB6_R_PIPE}},ADDB_R_PIPE} + {8'b00000000,NEG_PIPE};
			ADD_G = {2'b00,ADDA_G_PIPE} + {{4{ADDB6_G_PIPE}},ADDB_G_PIPE} + {8'b00000000,NEG_PIPE};
			ADD_B = {2'b00,ADDA_B_PIPE} + {{4{ADDB6_B_PIPE}},ADDB_B_PIPE} + {8'b00000000,NEG_PIPE};
			case (DV2_PIPE)
				1'b0: {DIVR_R,DIVR_G,DIVR_B} = {ADD_R,ADD_G,ADD_B};
				1'b1: {DIVR_R,DIVR_G,DIVR_B} = {{ADD_R[8],ADD_R[8:1]},{ADD_G[8],ADD_G[8:1]},{ADD_B[8],ADD_B[8:1]}};
			endcase
			// clamp to 0..31 (negative: 0), unless AV[2] lets the result wrap
			PEN_R = CLIP_PIPE ? DIVR_R[4:0] : DIVR_R[8] ? 5'h00 : |DIVR_R[7:5] ? 5'h1F : DIVR_R[4:0];
			PEN_G = CLIP_PIPE ? DIVR_G[4:0] : DIVR_G[8] ? 5'h00 : |DIVR_G[7:5] ? 5'h1F : DIVR_G[4:0];
			PEN_B = CLIP_PIPE ? DIVR_B[4:0] : DIVR_B[8] ? 5'h00 : |DIVR_B[7:5] ? 5'h1F : DIVR_B[4:0];
			// Game Bub port: NOBLK clear writes a black result as 100 (red 1),
			// which looks black but is not taken for background (SDK "The
			// NOBLK Flag"). The computed blue LSB takes part in the black
			// detector only when B0POS = 2 puts it in the pen (WO 94/10642,
			// after Table VI).
			if (!NOBLK_PIPE && {PEN_R,PEN_G,PEN_B[4:1]} == 14'd0 && (SCOBCTL.B0POS != 2'b10 || !PEN_B[0])) PEN_R = 5'd1;

			case (SCOBCTL.B0POS)
				2'b00: PEN_B[0] = 0;
				2'b01: PEN_B[0] = 1;
				2'b10: ;
				2'b11: PEN_B[0] = SPH_PIPE;
			endcase
			case (SCOBCTL.B15POS)
				2'b00: PEN15 = 0;
				2'b01: PEN15 = 1;
				2'b10: PEN15 = 0;//?
				2'b11: PEN15 = SPV_PIPE;
			endcase
			PEN <= {PEN15,PEN_R,PEN_G,PEN_B};
		end
	end
	
endmodule

module MADAM_MATH_PLATFORM (
	input             CLK,
	input             RST,
	input             EN,
	
	input             CE,
	
	input             START,
	
	input MathCtl_t   CTL,
	input             LSC,//Line super-clipping
	input     [11: 0] CLIPX,
	input     [10: 0] CLIPY,
	
	input     [15: 0] XS0,
	input     [15: 0] YS0,
	output    [15: 0] XA,
	output    [15: 0] YA,
	
	output MathStat_t STAT,
	
	output    [11: 0] YO,
	output    [11: 0] XLO,
	output    [11: 0] XRO
	
`ifdef DEBUG
	                   ,
	output            DBG_Xa0_OVER,
	output            DBG_Xa1_OVER,
	output            DBG_Xa2_OVER,
	output            DBG_Xa3_OVER,
	output            DBG_DY1_BIG,DBG_DY2_BIG
`endif
);

	typedef enum bit [6:0] {
		DRAW_IDLE,
		DRAW_MONKEE,
		DRAW_REGIS
	} DrawState_t;
	
	bit          CX_N,CY_N,CX_CLIP,CY_CLIP;
	bit          LDX_Z,LDY_Z,LDX_N,LDY_N,LDX_ONE,LDY_ONE;
	bit          DX_Z,DY_Z,DX_N,DY_N,DX_ONE,DY_ONE;
	bit          DDX_Z,DDY_Z,DDX_N,DDY_N;
	
	
	bit  [31: 0] Xa0,Xa1,Xa2,Xa3;
	bit  [31: 0] Ya0,Ya1,Ya2,Ya3;
	bit  [31: 0] DXa0,DXa3;
	bit  [31: 0] DYa0,DYa3;

	bit  [15: 0] X1,X2;
	bit  [15: 0] X1F,X2F;
	bit  [15: 0] DX1,DX2;
	bit  [15: 0] Y;
	bit  [15: 0] DY1,DY2;
	
	bit  [31: 0] X_ADD01_A,X_ADD01_B,X_ADD01_RES;
	bit  [31: 0] X_ADD23_A,X_ADD23_B,X_ADD23_RES;
	bit  [31: 0] Y_ADD01_A,Y_ADD01_B,Y_ADD01_RES;
	bit  [31: 0] Y_ADD23_A,Y_ADD23_B,Y_ADD23_RES;
	bit  [15: 0] MUNK_X1,MUNK_X2;
	bit  [15: 0] MUNK_DY12_RES;
	bit  [15: 0] TEMP_Y_T1,TEMP_T2;
	always_comb begin
	
		case (CTL.X_ADD01_ASEL)
			3'd0: X_ADD01_A = {Xa0[31:16],16'h0000};
			3'd1: X_ADD01_A = {Xa1[31:16],16'h0000};
			3'd2: X_ADD01_A = {Xa2[31:16],16'h0000};
			3'd3: X_ADD01_A = {Xa3[31:16],16'h0000};
			3'd4: X_ADD01_A = {X1,16'h0000};
			default: X_ADD01_A = '0;
		endcase
		case (CTL.X_ADD01_BSEL)
			2'd0: X_ADD01_B = {Xa0[31:16],16'h0000};
			2'd1: X_ADD01_B = {Xa1[31:16],16'h0000};
			2'd2: X_ADD01_B = {Xa2[31:16],16'h0000};
			2'd3: X_ADD01_B = {Xa3[31:16],16'h0000};
			3'd4: X_ADD01_B = 32'h00000000;
			3'd5: X_ADD01_B = 32'h00010000;
			default: X_ADD01_B = '0;
		endcase
		X_ADD01_RES = CTL.X_ADD01_SUB ? X_ADD01_A - X_ADD01_B : X_ADD01_A + X_ADD01_B;
		
		case (CTL.X_ADD23_ASEL)
			3'd0: X_ADD23_A = {Xa0[31:16],16'h0000};
			3'd1: X_ADD23_A = {Xa1[31:16],16'h0000};
			3'd2: X_ADD23_A = {Xa2[31:16],16'h0000};
			3'd3: X_ADD23_A = {Xa3[31:16],16'h0000};
			3'd4: X_ADD23_A = {X2,16'h0000};
			default: X_ADD23_A = '0;
		endcase
		case (CTL.X_ADD23_BSEL)
			2'd0: X_ADD23_B = {Xa0[31:16],16'h0000};
			2'd1: X_ADD23_B = {Xa1[31:16],16'h0000};
			2'd2: X_ADD23_B = {Xa2[31:16],16'h0000};
			2'd3: X_ADD23_B = {Xa3[31:16],16'h0000};
			3'd4: X_ADD23_B = 32'h00000000;
			3'd5: X_ADD23_B = 32'h00010000;
			default: X_ADD23_B = '0;
		endcase
		X_ADD23_RES = CTL.X_ADD23_SUB ? X_ADD23_A - X_ADD23_B : X_ADD23_A + X_ADD23_B;
		
		case (CTL.Y_ADD01_ASEL)
			3'd0: Y_ADD01_A = {Ya0[31:16],16'h0000};
			3'd1: Y_ADD01_A = {Ya1[31:16],16'h0000};
			3'd2: Y_ADD01_A = {Ya2[31:16],16'h0000};
			3'd3: Y_ADD01_A = {Ya3[31:16],16'h0000};
			3'd4: Y_ADD01_A = {X1F,16'h0000};
			default: Y_ADD01_A = '0;
		endcase
		case (CTL.Y_ADD01_BSEL)
			2'd0: Y_ADD01_B = {Ya0[31:16],16'h0000};
			2'd1: Y_ADD01_B = {Ya1[31:16],16'h0000};
			2'd2: Y_ADD01_B = {Ya2[31:16],16'h0000};
			2'd3: Y_ADD01_B = {Ya3[31:16],16'h0000};
			3'd4: Y_ADD01_B = {DX1,16'h0000};
			3'd5: Y_ADD01_B = {DY1,16'h0000};
			3'd6: Y_ADD01_B = {X1F,16'h0000};
			3'd7: Y_ADD01_B = 32'h00000000;
			default: Y_ADD01_B = '0;
		endcase
		Y_ADD01_RES = CTL.Y_ADD01_SUB ? Y_ADD01_A - Y_ADD01_B : Y_ADD01_A + Y_ADD01_B;
		
		case (CTL.Y_ADD23_ASEL)
			3'd0: Y_ADD23_A = {Ya0[31:16],16'h0000};
			3'd1: Y_ADD23_A = {Ya1[31:16],16'h0000};
			3'd2: Y_ADD23_A = {Ya2[31:16],16'h0000};
			3'd3: Y_ADD23_A = {Ya3[31:16],16'h0000};
			3'd4: Y_ADD23_A = {X2F,16'h0000};
			default: Y_ADD23_A = '0;
		endcase
		case (CTL.Y_ADD23_BSEL)
			2'd0: Y_ADD23_B = {Ya0[31:16],16'h0000};
			2'd1: Y_ADD23_B = {Ya1[31:16],16'h0000};
			2'd2: Y_ADD23_B = {Ya2[31:16],16'h0000};
			2'd3: Y_ADD23_B = {Ya3[31:16],16'h0000};
			3'd4: Y_ADD23_B = {DX2,16'h0000};
			3'd5: Y_ADD23_B = {DY2,16'h0000};
			3'd6: Y_ADD23_B = {X2F,16'h0000};
			3'd7: Y_ADD23_B = 32'h00000000;
			default: Y_ADD23_B = '0;
		endcase
		Y_ADD23_RES = CTL.Y_ADD23_SUB ? Y_ADD23_A - Y_ADD23_B : Y_ADD23_A + Y_ADD23_B;
		
		case (CTL.X1_MUNK_SEL)
			2'd0: MUNK_X1 = Xa0[31:16];
			2'd1: MUNK_X1 = Xa1[31:16];
			2'd2: MUNK_X1 = Xa2[31:16];
			2'd3: MUNK_X1 = Xa3[31:16];
		endcase
		case (CTL.X2_MUNK_SEL)
			2'd0: MUNK_X2 = Xa0[31:16];
			2'd1: MUNK_X2 = Xa1[31:16];
			2'd2: MUNK_X2 = Xa2[31:16];
			2'd3: MUNK_X2 = Xa3[31:16];
		endcase
		MUNK_DY12_RES = Ya2[31:16] - Ya1[31:16];
		
			
		case (CTL.Y_T1_SEL)
			2'd0: TEMP_Y_T1 = Ya0[31:16];
			2'd1: TEMP_Y_T1 = Ya1[31:16];
			2'd2: TEMP_Y_T1 = Ya2[31:16];
			2'd3: TEMP_Y_T1 = Ya3[31:16];
		endcase
		case (CTL.T2_SEL)
			2'd0: TEMP_T2 = Ya0[31:16];
			2'd1: TEMP_T2 = Ya1[31:16];
			2'd2: TEMP_T2 = Ya2[31:16];
			2'd3: TEMP_T2 = Ya3[31:16];
		endcase
	end
	
	wire MUNK_FUNC = DDX_Z & DDY_Z & ((DX_Z & DY_ONE & LDY_Z & LDX_ONE) | (DX_ONE & DY_Z & LDX_Z & LDY_ONE));
	wire LINE_CLIP = (CX_N    & (DX_Z |  DX_N) & (DDX_Z |  DDX_N) & (LDX_Z |  LDX_N /*| LSC*/)) | (CY_N    & (DY_Z |  DY_N) & (DDY_Z |  DDY_N) & (LDY_Z |  LDY_N /*| LSC*/)) | 
	                 (CX_CLIP & (DX_Z | ~DX_N) & (DDX_Z | ~DDX_N) & (LDX_Z | ~LDX_N /*| LSC*/)) | (CY_CLIP & (DY_Z | ~DY_N) & (DDY_Z | ~DDY_N) & (LDY_Z | ~LDY_N /*| LSC*/));
	wire REGION_CLIP = (Xa0[31] & Xa1[31] & Xa2[31] & Xa3[31]) | (Ya0[31] & Ya1[31] & Ya2[31] & Ya3[31]) |
	                   ((~Xa0[31] & Xa0[30:16] > {3'b000,CLIPX}) & (~Xa1[31] & Xa1[30:16] > {3'b000,CLIPX}) & (~Xa2[31] & Xa2[30:16] > {3'b000,CLIPX}) & (~Xa3[31] & Xa3[30:16] > {3'b000,CLIPX})) | 
	                   (~MUNK_X1[15] & (MUNK_X1[14:0] > {3'b000,CLIPX}) & LINE_CLIP) | 
							 (~TEMP_Y_T1[15] & (TEMP_Y_T1[14:0] > {4'b0000,CLIPY}) & LINE_CLIP);
	
	always @(posedge CLK) begin
		bit  [15: 0] Xtemp,Ytemp;
		
		if (RST) begin
			
		end
		else if (EN) begin
			if (CTL.A0CH_INIT || CTL.A3CH_INIT || CTL.A0DH_INIT || CTL.A3DH_INIT) begin
				Xtemp <= XS0;
				Ytemp <= YS0;
			end
			if (CTL.A0CL_INIT) begin	//CX->Xa0,CY->Ya0
				Xa0 <= {Xtemp,XS0};
				Ya0 <= {Ytemp,YS0};
				CX_N <= Xtemp[15]; CX_CLIP <= ~Xtemp[15] & Xtemp[14:0] > {3'b000,CLIPX}; 
				CY_N <= Ytemp[15]; CY_CLIP <= ~Ytemp[15] & Ytemp[14:0] > {4'b0000,CLIPY}; 
			end
			if (CTL.A3CL_INIT) begin	//Xa0+LDX->Xa3,Ya0+LDY->Ya3
				Xa3 <= Xa0 + {Xtemp,XS0};
				Ya3 <= Ya0 + {Ytemp,YS0};
				LDX_Z <= ~|{Xtemp,XS0}; LDX_N <= Xtemp[15]; LDX_ONE <= (Xtemp == 16'h0001 | Xtemp == 16'hFFFF) & ~|XS0;
				LDY_Z <= ~|{Ytemp,YS0}; LDY_N <= Ytemp[15]; LDY_ONE <= (Ytemp == 16'h0001 | Ytemp == 16'hFFFF) & ~|YS0;
			end
			if (CTL.A0DL_INIT) begin	//DX->DXa0,DY->DYa0
				DXa0 <= {Xtemp,XS0};
				DYa0 <= {Ytemp,YS0};
				DX_Z <= ~|{Xtemp,XS0[15:4]}; DX_N <= Xtemp[15]; DX_ONE <= (Xtemp[15:4] == 12'h001 | Xtemp[15:4] == 12'hFFF) & ~|{Xtemp[3:0],XS0[15:4]};
				DY_Z <= ~|{Ytemp,YS0[15:4]}; DY_N <= Ytemp[15]; DY_ONE <= (Ytemp[15:4] == 12'h001 | Ytemp[15:4] == 12'hFFF) & ~|{Ytemp[3:0],YS0[15:4]};
			end
			if (CTL.A3DL_INIT) begin	//DXa0+DDX->DXa3,DYa0+DDY->DYa3
				DXa3 <= DXa0 + {Xtemp,XS0};
				DYa3 <= DYa0 + {Ytemp,YS0};
				DDX_Z <= ~|{Xtemp,XS0[15:4]}; DDX_N <= Xtemp[15];
				DDY_Z <= ~|{Ytemp,YS0[15:4]}; DDY_N <= Ytemp[15];
			end
			
			if (CTL.A12C_PRECALC) begin	//Xa0+DXa0->Xa1,Ya0+DYa0->Ya1,Xa3+DXa3->Xa2,Ya3+DYa3->Ya2
				Xa1 <= Xa0 + {{4{DXa0[31]}},DXa0[31:4]};
				Ya1 <= Ya0 + {{4{DYa0[31]}},DYa0[31:4]};
				Xa2 <= Xa3 + {{4{DXa3[31]}},DXa3[31:4]};
				Ya2 <= Ya3 + {{4{DYa3[31]}},DYa3[31:4]};
				DX1 <= Xa3[31:16] - Xa0[31:16];
				DY1 <= Ya3[31:16] - Ya0[31:16];
			end
			if (CTL.A12C_CALC) begin	//
				Xa0 <= Xa1;
				Ya0 <= Ya1;
				Xa3 <= Xa2;
				Ya3 <= Ya2;
				Xa1 <= Xa1 + {{4{DXa0[31]}},DXa0[31:4]};
				Ya1 <= Ya1 + {{4{DYa0[31]}},DYa0[31:4]};
				Xa2 <= Xa2 + {{4{DXa3[31]}},DXa3[31:4]};
				Ya2 <= Ya2 + {{4{DYa3[31]}},DYa3[31:4]};
				DX1 <= Xa2[31:16] - Xa1[31:16];
				DY1 <= Ya2[31:16] - Ya1[31:16];
				
			end
			
			if (CTL.X1_UPD) begin
				X1 <= CTL.X1_MUNK ? MUNK_X1 : X_ADD01_RES[31:16];
			end
			if (CTL.X1F_UPD) begin
				X1F <= Y_ADD01_RES[31:16];
			end
			if (CTL.DX1_UPD) begin
				DX1 <= X_ADD01_RES[31:16];
			end
			if (CTL.DX2_UPD) begin
				DX2 <= X_ADD23_RES[31:16];
			end
			
			if (CTL.X2_UPD) begin
				X2 <= CTL.X2_MUNK ? MUNK_X2 : X_ADD23_RES[31:16];
			end
			if (CTL.X2F_UPD) begin
				X2F <= Y_ADD23_RES[31:16];
			end
			if (CTL.DY1_UPD) begin
				DY1 <= Y_ADD01_RES[31:16];
			end
			if (CTL.DY2_UPD) begin
				DY2 <= Y_ADD23_RES[31:16];
			end

			if (CTL.Y_UPD) begin
				Y <= TEMP_Y_T1;
			end
			if (CTL.Y_INC) begin
				Y <= Y + 16'd1;
			end
		end
	end
	
	assign {XA,YA} = CTL.A3CH_SAVE ? {Xa3[31:16],Ya3[31:16]} : 
	                 CTL.A3CL_SAVE ? {Xa3[15: 0],Ya3[15: 0]} : 
						  CTL.A3DH_SAVE ? {DXa3[31:16],DYa3[31:16]} : 
						  CTL.A3DL_SAVE ? {DXa3[15: 0],DYa3[15: 0]} : '0;
	assign STAT.MF = MUNK_FUNC;
	// 1:1 path winding: HD along x (HDX +-1, VDY +-1): clockwise when HDX and
	// VDY have the same sign; HD along y (HDY +-1, VDX +-1): when HDY and VDX
	// have opposite signs (HDX * VDY - HDY * VDX > 0)
	assign STAT.MCW = (DX_ONE & DY_Z & LDX_Z & LDY_ONE) ? (DX_N == LDY_N) : (DY_N != LDX_N);
	assign STAT.LC = LINE_CLIP;
	assign STAT.RC = REGION_CLIP;
	assign STAT.CW = ($signed(Xa1[31:16]) >= $signed(Xa0[31:16]) && $signed(Xa2[31:16]) >= $signed(Xa3[31:16]));
	assign STAT.CCW = ($signed(Xa1[31:16]) < $signed(Xa0[31:16]) && $signed(Xa2[31:16]) < $signed(Xa3[31:16]) && $signed(Ya0[31:16]) <= $signed(Ya3[31:16])) ||
	                  ($signed(Xa1[31:16]) > $signed(Xa0[31:16]) && $signed(Xa2[31:16]) > $signed(Xa3[31:16]) && $signed(Ya0[31:16]) >= $signed(Ya3[31:16]));
	assign STAT.COMPT1 = (Y == TEMP_Y_T1);
	assign STAT.COMPT2 = (Y == TEMP_T2);
	assign STAT.YADD01N = Y_ADD01_RES[31];
	assign STAT.YADD23N = Y_ADD23_RES[31];
	assign {STAT.DXA10N,STAT.DXA10E} = {~($signed(Xa1[31:16]) >= $signed(Xa0[31:16]))/*DXa0[31]*/,Xa1[31:16] == Xa0[31:16]/*~|DXa0[31:19]*/};
	assign {STAT.DXA23N,STAT.DXA23E} = {~($signed(Xa2[31:16]) >= $signed(Xa3[31:16]))/*DXa3[31]*/,Xa2[31:16] == Xa3[31:16]/*~|DXa3[31:19]*/};
	assign {STAT.DXA30N,STAT.DXA30E}   = {~($signed(Xa3[31:16]) >= $signed(Xa0[31:16]))/*DX1[15]*/,Xa3[31:16] == Xa0[31:16]/*~|{DX1,DX1F[15]}*/};
	assign {STAT.DYA10N,STAT.DYA10E} = {~($signed(Ya1[31:16]) >= $signed(Ya0[31:16]))/*DYa0[31]*/,Ya1[31:16] == Ya0[31:16]/*~|DYa0[31:19]*/};
	assign {STAT.DYA23N,STAT.DYA23E} = {~($signed(Ya2[31:16]) >= $signed(Ya3[31:16]))/*DYa3[31]*/,Ya2[31:16] == Ya3[31:16]/*~|DYa3[31:19]*/};
	assign {STAT.DYA30N,STAT.DYA30E}   = {~($signed(Ya3[31:16]) >= $signed(Ya0[31:16]))/*DY1[15]*/,Ya3[31:16] == Ya0[31:16]/*~|{DY1,DY1F[15]}*/};
	assign {STAT.DX1N,STAT.DX1E}   = {DX1[15],~|DX1};
	assign {STAT.DX2N,STAT.DX2E}   = {DX2[15],~|DX2};
	assign {STAT.DY1N,STAT.DY1E}   = {DY1[15],~|DY1};
	assign {STAT.DY2N,STAT.DY2E}   = {DY2[15],~|DY2};
	assign {STAT.DY12ONEP,STAT.DY12ONEM,STAT.DY12ZERO} = {MUNK_DY12_RES==16'h0001,MUNK_DY12_RES==16'hFFFF,MUNK_DY12_RES==16'h0000};
	assign STAT.NP = ($signed(Ya0[31:16]) == $signed(Ya3[31:16]) && $signed(Ya1[31:16]) == $signed(Ya2[31:16]) && $signed(Ya0[31:16]) == $signed(Ya1[31:16])) ||
	                 ($signed(Xa0[31:16]) == $signed(Xa1[31:16]) && $signed(Xa3[31:16]) == $signed(Xa2[31:16]) && $signed(Xa0[31:16]) == $signed(Xa3[31:16])) /*|| 
						  ($signed(Ya0[31:16]) == $signed(Ya2[31:16])) || ($signed(Ya1[31:16]) == $signed(Ya3[31:16]))*/;
//						  ($signed(Ya0[31:16]) == $signed(Ya2[31:16]) && $signed(Ya1[31:16]) == $signed(Ya3[31:16])) || ($signed(Xa0[31:16]) == $signed(Xa2[31:16]) && $signed(Xa1[31:16]) == $signed(Xa3[31:16]));
	assign STAT.VC = ($signed(Ya0[31:16]) > $signed(Ya3[31:16]) && $signed(Ya1[31:16]) < $signed(Ya2[31:16])) ||//vertically crossed
						  ($signed(Ya0[31:16]) < $signed(Ya3[31:16]) && $signed(Ya1[31:16]) > $signed(Ya2[31:16]));
	assign STAT.YTOP =                                               $signed(Ya0[31:16]) <= $signed(Ya1[31:16]) && $signed(Ya0[31:16]) <= $signed(Ya2[31:16]) && $signed(Ya0[31:16]) <= $signed(Ya3[31:16]) ? 2'h0 :
							 $signed(Ya1[31:16]) <= $signed(Ya0[31:16]) &&                                               $signed(Ya1[31:16]) <= $signed(Ya2[31:16]) && $signed(Ya1[31:16]) <= $signed(Ya3[31:16]) ? 2'h1 : 
							 $signed(Ya2[31:16]) <= $signed(Ya0[31:16]) && $signed(Ya2[31:16]) <= $signed(Ya1[31:16]) &&                                               $signed(Ya2[31:16]) <= $signed(Ya3[31:16]) ? 2'h2 : 2'h3;
						
	assign YO = MathClipCoord(Y);
	assign XLO = MathClipCoord(X1);
	assign XRO = MathClipCoord(X2);
	
`ifdef DEBUG
	assign DBG_Xa0_OVER = (Xa0[31:26] != 6'b000000 && Xa0[31:26] != 6'b111111);
	assign DBG_Xa1_OVER = (Xa1[31:26] != 6'b000000 && Xa1[31:26] != 6'b111111);
	assign DBG_Xa2_OVER = (Xa2[31:26] != 6'b000000 && Xa2[31:26] != 6'b111111);
	assign DBG_Xa3_OVER = (Xa3[31:26] != 6'b000000 && Xa3[31:26] != 6'b111111);
	assign DBG_DY1_BIG = $signed(DY1) >= 150 || $signed(DY1) < -150;
	assign DBG_DY2_BIG = $signed(DY2) >= 150 || $signed(DY2) < -150;
`endif
						  
endmodule

module MADAM_REGIS (
	input             CLK,
	input             RST,
	input             EN,
	
	input             CE,
	
	input             START,
	input             TERMINATE,
	input             PAUSE,
	input MathStat_t  STAT,
	input             LF_AVAIL,
	output            LF_REQ,
	
	output MathCtl_t  CTL,
	output            DONE
);

	typedef enum bit [1:0] {
		R,S,E,W
	} RegisState_t;
	RegisState_t BW1,BW2;
	
	bit  [ 1: 0] T1,T2;
	bit  [ 1: 0] CC1,CC2;
	bit          X1SLOP;
	bit          TWD;
	wire [ 1: 0] F1 = T1 + 2'd1;
	wire [ 1: 0] F2 = T2 - 2'd1;
	wire [ 1: 0] CS = CC1 + CC2;
	
	wire         COMMON_WAIT = (BW1 != W || BW2 != W || !LF_AVAIL);
	bit          BW1_PREV_S,BW2_PREV_S;
	bit          RUN;
	always @(posedge CLK or posedge RST) begin		
		bit           BW1_NEXT_CONER,BW2_NEXT_CONER;
		
		if (RST) begin
			BW1 <= R;
			BW2 <= R;
			RUN <= 0;
			// synopsys translate_off
			// synopsys translate_on
		end
		else if (EN /*&& CE*/) begin
			BW1_NEXT_CONER = 0;
			BW2_NEXT_CONER = 0;
			if (START) begin
				{T1,T2} <= {STAT.YTOP-2'd1,STAT.YTOP+2'd1};
				{CC1,CC2} <= '0;
				BW1 <= S;
				BW2 <= S;
				BW1_PREV_S <= 0;
				BW2_PREV_S <= 0;
				RUN <= 1;
			end
			else if (TERMINATE) begin
				RUN <= 0;
			end
			else if (RUN) begin
				if (!PAUSE) begin
				case (BW1)
					R: if (CE) begin
						if (STAT.COMPT1) begin
							if (CS >= 2'd2) begin
								BW1 <= R;
								RUN <= 0;
							end else begin
								BW1_NEXT_CONER = 1;
								BW1 <= S;
							end
						end else begin
							if (STAT.YADD01N) begin
								BW1 <= W;
							end else begin
								BW1 <= E;
								if (STAT.DY1N) begin
									BW1 <= R;
								end;
							end
						end
					end
					S: begin
						if (STAT.COMPT1) begin
							if (CS >= 2'd2) begin
								BW1 <= R;
								RUN <= 0;
							end else begin
								BW1_NEXT_CONER = 1;
								BW1 <= S;
							end
						end else begin
							BW1_PREV_S <= 1;
							BW1 <= W;
						end
					end
					E: begin
						BW1 <= STAT.YADD01N ? W : E;
					end
					W: if (CE) if (!COMMON_WAIT) begin
						BW1_PREV_S <= 0;
						BW1 <= R;
					end
				endcase
				if (BW1_NEXT_CONER) begin
					T1 <= T1 - 2'd1;
					CC1 <= CC1 + 2'd1;
				end

				case (BW2)
					R: if (CE) begin
						if (STAT.COMPT2) begin
							if (CS >= 2'd2)  begin
								BW2 <= R;
								RUN <= 0;
							end else begin
								BW2_NEXT_CONER = 1;
								BW2 <= S;
							end
						end else begin
							if (STAT.YADD23N) begin
								BW2 <= W;
							end else begin
								BW2 <= E;
								if (STAT.DY2N) begin
									BW2 <= R;
								end;
							end
						end
					end
					S: begin
						if (STAT.COMPT2) begin
							if (CS >= 2'd2) begin
								BW2 <= R;
								RUN <= 0;
							end else begin
								BW2_NEXT_CONER = 1;
								BW2 <= S;
							end
						end else begin
							BW2_PREV_S <= 1;
							BW2 <= W;
						end
					end
					E: begin
						BW2 <= STAT.YADD23N ? W : E;
					end
					W: if (CE) if (!COMMON_WAIT) begin
						BW2_PREV_S <= 0;
						BW2 <= R;
					end
				endcase
				if (BW2_NEXT_CONER) begin
					T2 <= T2 + 2'd1;
					CC2 <= CC2 + 2'd1;
				end
				end
				
				
				case (BW1)
					R: if (CE) begin
						if (STAT.COMPT1) begin
							if (CS >= 2'd2) begin
								RUN <= 0;
							end
						end else if (!STAT.YADD01N) begin
							if (STAT.DY1N) begin
								RUN <= 0;
							end;
						end
					end
					S: begin
						if (STAT.COMPT1) begin
							if (CS >= 2'd2) begin
								RUN <= 0;
							end
						end
					end
				endcase
				
				case (BW2)
					R: if (CE) begin
						if (STAT.COMPT2) begin
							if (CS >= 2'd2) begin
								RUN <= 0;
							end
						end else if (!STAT.YADD23N) begin
							if (STAT.DY2N) begin
								RUN <= 0;
							end;
						end
					end
					S: begin
						if (STAT.COMPT2) begin
							if (CS >= 2'd2) begin
								RUN <= 0;
							end
						end
					end
				endcase
			end
			
		end
	end 
	assign LF_REQ = (BW1 == W && BW2 == W && LF_AVAIL);
	
	always_comb begin	
		CTL = '0;
		case (BW1)
			R: if (CE) begin
				CTL.Y_ADD01_ASEL = 3'd4;//X1F
				CTL.Y_ADD01_BSEL = 3'd4;//DX1
				CTL.Y_ADD01_SUB = STAT.DX1N;//X1SLOP;
				CTL.X1F_UPD = 1;
				CTL.Y_T1_SEL = T1;//Ya(T1)
			end
			S: begin
				CTL.X_ADD01_ASEL = {1'b0,F1};//Xa(F1)
				CTL.X_ADD01_BSEL = 3'd4;//0
				CTL.X_ADD01_SUB = 0;
				CTL.X1_UPD = 1;
				//X1F=Ya(F1)-Ya(T1)
				CTL.Y_ADD01_ASEL = {1'b0,F1};
				CTL.Y_ADD01_BSEL = {1'b0,T1};
				CTL.Y_ADD01_SUB = 1;
				CTL.X1F_UPD = 1;
				CTL.Y_T1_SEL = T1;//Ya(T1)
			end
			E: begin
				CTL.Y_ADD01_ASEL = 3'd4;//X1F
				CTL.Y_ADD01_BSEL = 3'd5;//DY1
				CTL.Y_ADD01_SUB = 1;
				CTL.X1F_UPD = 1;
				CTL.X_ADD01_ASEL = 3'd4;//X1
				CTL.X_ADD01_BSEL = 3'd5;//1
				CTL.X_ADD01_SUB = STAT.DX1N;//X1SLOP;
				CTL.X1_UPD = 1;
			end
			W: if (CE) if (!COMMON_WAIT) begin
				CTL.Y_INC = 1;
				CTL.X_ADD01_ASEL = {1'b0,T1};//Xa(T1)
				CTL.X_ADD01_BSEL = {1'b0,F1};//Xa(F1)
				CTL.X_ADD01_SUB = 1;
				CTL.DX1_UPD = 1;
				//DY1=0+X1F
				CTL.Y_ADD01_ASEL = 3'd7;//0
				CTL.Y_ADD01_BSEL = 3'd6;//X1F
				CTL.Y_ADD01_SUB = 1;
				CTL.DY1_UPD = BW1_PREV_S;
			end
		endcase
		
		case (BW2)
			R: if (CE) begin
				CTL.Y_ADD23_ASEL = 3'd4;//X2F
				CTL.Y_ADD23_BSEL = 3'd4;//DX2
				CTL.Y_ADD23_SUB = STAT.DX2N;//X2SLOP;
				CTL.X2F_UPD = 1;
				CTL.T2_SEL = T2;//Ya(T2)
			end
			S: begin
				CTL.X_ADD23_ASEL = {1'b0,F2};//Xa(F2)
				CTL.X_ADD23_BSEL = 3'd4;//0
				CTL.X_ADD23_SUB = 0;
				CTL.X2_UPD = 1;
				//X2F=Ya(F2)-Ya(T2)
				CTL.Y_ADD23_ASEL = {1'b0,F2};
				CTL.Y_ADD23_BSEL = {1'b0,T2};
				CTL.Y_ADD23_SUB = 1;
				CTL.X2F_UPD = 1;
				CTL.T2_SEL = T2;//Ya(T2)
			end
			E: begin
				CTL.Y_ADD23_ASEL = 3'd4;//X2F
				CTL.Y_ADD23_BSEL = 3'd5;//DY2
				CTL.Y_ADD23_SUB = 1;
				CTL.X2F_UPD = 1;
				CTL.X_ADD23_ASEL = 3'd4;//X2
				CTL.X_ADD23_BSEL = 3'd5;//1
				CTL.X_ADD23_SUB = STAT.DX2N;//X2SLOP;
				CTL.X2_UPD = 1;
			end
			W: if (CE) if (!COMMON_WAIT) begin
				//DX2=Xa(T2)-Xa(F2)
				CTL.X_ADD23_ASEL = {1'b0,T2};//Xa(T2)
				CTL.X_ADD23_BSEL = {1'b0,F2};//Xa(F2)
				CTL.X_ADD23_SUB = 1;
				CTL.DX2_UPD = 1;
				//DY2=0+X2F
				CTL.Y_ADD23_ASEL = 3'd7;//0
				CTL.Y_ADD23_BSEL = 3'd6;//X2F
				CTL.Y_ADD23_SUB = 1;
				CTL.DY2_UPD = BW2_PREV_S;
			end
		endcase
	end
	
	assign DONE = ~RUN & LF_AVAIL;

endmodule
