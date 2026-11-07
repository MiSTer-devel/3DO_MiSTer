// synopsys translate_off
`define SIM
// synopsys translate_on

module CLIO
`ifdef SIM
#(
	parameter dsp_nram_file = ""
)
`endif
(
	input              CLK,
	input              RST_N,
	input              EN,
	
	input              PAL,
	
	input              CE_R,
	input              CE_F,
	input              IO_EN,
	input              DSP_EN,
	
	input              PON,
	output reg         RESET_N,
	
	input              MCLK_PH1,
	input              MCLK_PH2,
	input      [15: 2] A,
	input      [31: 0] CPU_DI,
	output reg [31: 0] CPU_DO,
	
	input      [31: 0] DI,
	output reg [31: 0] DO,
	input      [ 2: 0] CLC,
	output             CREADY_N,
	output reg         DMAREQ,
	output reg [ 4: 0] DMACH,
	input              PB_INT,

	output             FIRQ_N,
	
	input      [ 7: 0] EDI,
	output reg [ 7: 0] EDO,
	output             ESTR_N,
	output             EWRT_N,
	output             ERST_N,
	output             ECMD_N,
	output             ESEL_N,
	input              ERDY_N,
	input              EINT_N,
	
	input      [ 3: 0] ADBIO_I,
	output reg [ 3: 0] ADBIO_O,
	output reg [ 3: 0] ADBIO_D,
	
	input              VCE,
	input              HSYNC_N,
	input              VSYNC_N,
	
	input      [31: 0] S,
	input              LPSC_N,
	input              RPSC_N,
	output             PCSC,
	
	output     [23: 0] AD,
	output             DE,
	
	input              ACLK_CE,
	output     [15: 0] AUDIOL,
	output     [15: 0] AUDIOR,
	
	input              HINTREPOL_DISABLE,
	input              VINTREPOL_DISABLE,
	input      [ 7: 0] DBG_EXT
`ifdef DEBUG
	                  ,
	output reg [ 7: 0] DBG_VINT1_CNT,
	output reg [ 9: 0] DBG_WAIT_CNT,
	output reg [10: 0] DBG_DMA_WAIT_CNT,
	output             DBG_FIFO_CHANGE,
	output reg [15: 0] DBG_TIMER0,DBG_TIMER1,
	output reg         DBG_HOOK
`endif
);

	parameter bit [31: 0] REV = 32'h02020000;
	
	bit  [31: 0] CSTAT;
	bit  [10: 0] VINT0,VINT1;
	bit  [31: 0] DMAEN;
	bit  [31: 0] FIFOINIT;
	bit  [10: 0] HCNT;
	bit  [ 8: 0] VCNT;
	bit          FLD;
	
	bit  [31: 0] INT0_PEND,INT1_PEND;
	bit  [31: 0] INT0_EN,INT1_EN;
	bit  [31: 0] INT_MODE;
	
	bit  [31: 0] HDELAY;
	
	bit  [15: 0] TM_CNT[16];
	bit  [15: 0] TM_RELOAD[16];
	bit  [ 3: 0] TM_CTRL[16];
	
	bit  [31: 0] UNCLE_BITS;
	
	bit  [16: 0] NOISE;
	
	bit  [11: 0] RESET_DELAY;
	
	bit  [ 2: 0] CLC1,CLC2;
	
	typedef enum bit [2:0] {
		IO_IDLE,
		IO_WAIT,
		IO_END,
		IO_DSP_WRITE,
		IO_DSP_READ,
		IO_DMA
	} IOState_t;
	IOState_t IO_ST;
	bit          IO_READY;
	
	typedef enum bit [3:0] {
		DMA_IDLE,
		DMA_REQUEST,
		DMA_DSP_WRITE,
		DMA_DSP_READ,
		DMA_DSP_END,
		DMA_EXP_READ,
		DMA_EXP_WAIT,
		DMA_EXP_END,
		DMA_END
	} DMAState_t;
	DMAState_t DMA_ST;
	bit  [ 4: 0] DMA_CHAN;
	
	bit  [12: 0] DMA_TO_DSP_PEND;
	bit  [ 3: 0] DMA_FROM_DSP_PEND;
	bit  [31: 0] DMA_BUF;
	bit  [15: 0] DMA_BUF2;//for EOFIFO
	bit          DMA_TO_DSP_WRITE[2];
	bit          DMA_FROM_DSP_READ[2];
	bit  [ 1: 0] DMA_EXP_PEND;
	bit          DMA_EXP_FIFO_WRITE,DMA_EXP_FIFO_READ;
	
	
	bit  [ 1: 0] DSP_RST;
	bit          DSP_GW;
	bit  [ 9: 0] DSP_PC;
	bit  [15: 0] DSP_NRC;
	bit  [15: 0] DSP_NOISE;
	bit  [15: 0] DSP_SEMAPHORE;
	bit  [ 3: 0] DSP_SEMAPHORE_STAT;
	
	bit  [15: 2] IO_A_LATCH;
	bit  [31: 0] IO_DI_LATCH;
	bit          IO_XBUS_WR;
	bit          IO_XBUS_RD;
	bit          XBUS_DMA_READY,DMA_XBUS_ACT;
	bit  [31: 0] XBUS_DMA_DO;
	bit  [31: 0] XBUS_DO;
	bit          XBUS_READY;
//	bit  [ 8: 0] DSP_ADDR;
	bit  [15: 0] DSP_DO;
	bit  [15: 0] DSP_DO_LATCH;
	
	bit          DSP_ACCESS_32;
	bit          DSP_NRAM32_WE;
	bit          DSP_EIRAM32_WE;
	bit          DSP_SEMA_WE;
	bit          DSP_SEMA_ACK;
	bit          DSP_NOISE_RD;
	
	bit          EIFIFO_EMPTY_LATCH[13];
	
	bit          VINT0_REQ,VINT1_REQ;
	bit          VINT0_ACK,VINT1_ACK;
	bit          TMINT_REQ[8];
	
	wire CONTROL_SEL = (A >= (16'h0000>>2) && A <= (16'h003F>>2));
	wire INTERRUPT_SEL = (A >= (16'h0040>>2) && A <= (16'h00FF>>2));
	wire TIMER_SEL = (A >= (16'h0100>>2) && A <= (16'h017F>>2));
	wire TIMER_CTRL_SEL = (A >= (16'h0200>>2) && A <= (16'h02FF>>2));
	wire FIFO_SEL = (A >= (16'h0300>>2) && A <= (16'h03FF>>2));
	wire XBUS_SEL = (A >= (16'h0400>>2) && A <= (16'h0BFF>>2));
	wire DSP_DIRECT_SEL = (A >= (16'h1700>>2) && A <= (16'h17FF>>2));
	wire DSP_NRAM32_SEL = (A >= (16'h1800>>2) && A <= (16'h1FFF>>2));
	wire DSP_NRAM16_SEL = (A >= (16'h2000>>2) && A <= (16'h2FFF>>2));
	wire DSP_EIRAM32_SEL = (A >= (16'h3000>>2) && A <= (16'h31FF>>2));
	wire DSP_EIRAM16_SEL = (A >= (16'h3400>>2) && A <= (16'h37FF>>2));
	wire DSP_EORAM32_SEL = (A >= (16'h3800>>2) && A <= (16'h39FF>>2));
	wire DSP_EORAM16_SEL = (A >= (16'h3C00>>2) && A <= (16'h3FFF>>2));
	wire UNCLE_SEL = (A >= (16'hC000>>2) && A <= (16'hC00F>>2));
	bit          INFO_CODE;
	always @(posedge CLK or negedge RST_N) begin
		bit          EINT_N_OLD;
		bit  [31: 0] DMAEN_OLD;
		bit  [ 9: 0] TM_CLKDIV;
		bit          TM_CLK;
		bit          TM_CASCADE[16];
		bit          TM_ZERO[16];
		bit  [ 1: 0] DMA_EXP_WORD_CNT;
		bit          DMA_EXP_PEND_INC,DMA_EXP_PEND_DEC;
		bit  [ 2: 0] DMA_DSP_WORD_CNT;
		bit          DMA_INT_REQ;
		
		if (!RST_N) begin
			CSTAT <= 32'h00000011;//CSTAT_PON
			VINT0 <= '0;
			VINT1 <= '0;
			DMAEN <= '0;
			FIFOINIT <= '0;
			INT0_PEND <= '0;
			INT1_PEND <= '0;
			INT0_EN <= '0;
			INT1_EN <= '0;
			HDELAY <= '0;
			UNCLE_BITS <= '0;
			{ADBIO_D,ADBIO_O} <= '0;
			
			IO_ST <= IO_IDLE;
			IO_XBUS_RD <= 0;
			IO_XBUS_WR <= 0;
			IO_READY <= 1;
			DSP_RST <= '0;
			DSP_GW <= 0;
			DSP_NRAM32_WE <= 0;
			DSP_EIRAM32_WE <= 0;
			DSP_SEMA_WE <= 0;
			DSP_SEMA_ACK <= 0;
			DSP_NOISE_RD <= 0;
			
			DMA_ST <= DMA_IDLE;
			DMA_CHAN <= '0;
			DMA_TO_DSP_PEND <= '0;
			DMA_FROM_DSP_PEND <= '0;
			DMA_EXP_PEND <= '0;
			DMA_EXP_WORD_CNT <= '0;
			{DMA_EXP_FIFO_WRITE,DMA_EXP_FIFO_READ} <= '0;
			DMA_INT_REQ <= 0;
			DMACH <= '0;
			DMAREQ <= 0;
			
			VINT0_ACK <= 0;
			VINT1_ACK <= 0;
		end
		else if (PON) begin
			CSTAT <= 32'h00000011;//CSTAT_PON
			VINT0 <= '0;
			VINT1 <= '0;
			DMAEN <= '0;
			FIFOINIT <= '0;
			INT0_PEND <= '0;
			INT1_PEND <= '0;
			INT0_EN <= '0;
			INT1_EN <= '0;
			HDELAY <= '0;
			UNCLE_BITS <= '0;
			{ADBIO_D,ADBIO_O} <= '0;
			
			IO_ST <= IO_IDLE;
			IO_XBUS_RD <= 0;
			IO_XBUS_WR <= 0;
			IO_READY <= 1;
			DSP_RST <= '0;
			DSP_GW <= 0;
			DSP_NRAM32_WE <= 0;
			DSP_EIRAM32_WE <= 0;
			DSP_SEMA_WE <= 0;
			DSP_SEMA_ACK <= 0;
			DSP_NOISE_RD <= 0;
			
			DMA_ST <= DMA_IDLE;
			DMA_CHAN <= '0;
			DMA_TO_DSP_PEND <= '0;
			DMA_FROM_DSP_PEND <= '0;
			DMA_EXP_PEND <= '0;
			DMA_EXP_WORD_CNT <= '0;
			{DMA_EXP_FIFO_WRITE,DMA_EXP_FIFO_READ} <= '0;
			DMA_INT_REQ <= 0;
			DMACH <= '0;
			DMAREQ <= 0;
			
			VINT0_ACK <= 0;
			VINT1_ACK <= 0;
		end
		else if (EN && CE_R) begin
			if (IO_EN) TM_CLK <= 0;
			TM_CLKDIV <= TM_CLKDIV + 10'd1;
			if (TM_CLKDIV == 10'd399) begin//TODO: use TimerSlack register
				TM_CLKDIV <= '0;
				TM_CLK <= 1;
			end
			
			if (DSP_EN) begin	
				if (EIFIFO_OE_LATCH[ 0] && EIFIFO_COUNT[ 0] < 4'd2 && !DMA_TO_DSP_PEND[ 0]) DMA_TO_DSP_PEND[ 0] <= 1;
				if (EIFIFO_OE_LATCH[ 1] && EIFIFO_COUNT[ 1] < 4'd2 && !DMA_TO_DSP_PEND[ 1]) DMA_TO_DSP_PEND[ 1] <= 1;
				if (EIFIFO_OE_LATCH[ 2] && EIFIFO_COUNT[ 2] < 4'd2 && !DMA_TO_DSP_PEND[ 2]) DMA_TO_DSP_PEND[ 2] <= 1;
				if (EIFIFO_OE_LATCH[ 3] && EIFIFO_COUNT[ 3] < 4'd2 && !DMA_TO_DSP_PEND[ 3]) DMA_TO_DSP_PEND[ 3] <= 1;
				if (EIFIFO_OE_LATCH[ 4] && EIFIFO_COUNT[ 4] < 4'd2 && !DMA_TO_DSP_PEND[ 4]) DMA_TO_DSP_PEND[ 4] <= 1;
				if (EIFIFO_OE_LATCH[ 5] && EIFIFO_COUNT[ 5] < 4'd2 && !DMA_TO_DSP_PEND[ 5]) DMA_TO_DSP_PEND[ 5] <= 1;
				if (EIFIFO_OE_LATCH[ 6] && EIFIFO_COUNT[ 6] < 4'd2 && !DMA_TO_DSP_PEND[ 6]) DMA_TO_DSP_PEND[ 6] <= 1;
				if (EIFIFO_OE_LATCH[ 7] && EIFIFO_COUNT[ 7] < 4'd2 && !DMA_TO_DSP_PEND[ 7]) DMA_TO_DSP_PEND[ 7] <= 1;
				if (EIFIFO_OE_LATCH[ 8] && EIFIFO_COUNT[ 8] < 4'd2 && !DMA_TO_DSP_PEND[ 8]) DMA_TO_DSP_PEND[ 8] <= 1;
				if (EIFIFO_OE_LATCH[ 9] && EIFIFO_COUNT[ 9] < 4'd2 && !DMA_TO_DSP_PEND[ 9]) DMA_TO_DSP_PEND[ 9] <= 1;
				if (EIFIFO_OE_LATCH[10] && EIFIFO_COUNT[10] < 4'd2 && !DMA_TO_DSP_PEND[10]) DMA_TO_DSP_PEND[10] <= 1;
				if (EIFIFO_OE_LATCH[11] && EIFIFO_COUNT[11] < 4'd2 && !DMA_TO_DSP_PEND[11]) DMA_TO_DSP_PEND[11] <= 1;
				if (EIFIFO_OE_LATCH[12] && EIFIFO_COUNT[12] < 4'd2 && !DMA_TO_DSP_PEND[12]) DMA_TO_DSP_PEND[12] <= 1;
				
				if (EOFIFO_WE_LATCH[0] && EOFIFO_COUNT[0] >= 4'd6 && !DMA_FROM_DSP_PEND[0]) DMA_FROM_DSP_PEND[0] <= 1;
				if (EOFIFO_WE_LATCH[1] && EOFIFO_COUNT[1] >= 4'd6 && !DMA_FROM_DSP_PEND[1]) DMA_FROM_DSP_PEND[1] <= 1;
				if (EOFIFO_WE_LATCH[2] && EOFIFO_COUNT[2] >= 4'd6 && !DMA_FROM_DSP_PEND[2]) DMA_FROM_DSP_PEND[2] <= 1;
				if (EOFIFO_WE_LATCH[3] && EOFIFO_COUNT[3] >= 4'd6 && !DMA_FROM_DSP_PEND[3]) DMA_FROM_DSP_PEND[3] <= 1;
				
				if (EOFIFO_FLUSH[0] && EOFIFO_COUNT[0] && !DMA_FROM_DSP_PEND[0]) DMA_FROM_DSP_PEND[0] <= 1;
				if (EOFIFO_FLUSH[1] && EOFIFO_COUNT[1] && !DMA_FROM_DSP_PEND[1]) DMA_FROM_DSP_PEND[1] <= 1;
				if (EOFIFO_FLUSH[2] && EOFIFO_COUNT[2] && !DMA_FROM_DSP_PEND[2]) DMA_FROM_DSP_PEND[2] <= 1;
				if (EOFIFO_FLUSH[3] && EOFIFO_COUNT[3] && !DMA_FROM_DSP_PEND[3]) DMA_FROM_DSP_PEND[3] <= 1;
			end
			
			if (IO_EN) begin			
				INFO_CODE <= 0;
				if (CLC == 3'h7) begin
					INFO_CODE <= 1;
				end
				CLC2 <= CLC1;
				CLC1 <= CLC;
				
				RESET_DELAY <= {RESET_DELAY[10:0],CSTAT[4]};
				if (CSTAT[4]) begin
					if (PAL) begin
						INT0_PEND <= '0;
						INT1_PEND <= '0;
						INT0_EN <= '0;
						INT1_EN <= '0;
					end
					ADBIO_O <= '0;
				end
				CSTAT[4] <= 0;
				FIFOINIT <= '0;
				DSP_RST <= {1'b0,DSP_RST[1]};
				DSP_EIRAM32_WE <= 0;
				DSP_NRAM32_WE <= 0;
				DSP_SEMA_WE <= 0;
				DSP_SEMA_ACK <= 0;
				DSP_NOISE_RD <= 0;
				case (IO_ST)
					IO_IDLE: begin
						
						if (CLC == 3'h1 && !INFO_CODE) begin
							if (XBUS_SEL) begin
								IO_XBUS_WR <= 1;
								IO_READY <= 0;
								IO_ST <= IO_WAIT;
							end
						end
						else if (CLC == 3'h3 && !INFO_CODE) begin
							if (XBUS_SEL) begin
								IO_XBUS_RD <= 1;
								IO_READY <= 0;
								IO_ST <= IO_WAIT;
							end
						end
						
						if (CLC == 3'h1 && !INFO_CODE /*&& MCLK_PH1*/) begin	//CPU write
							if (CONTROL_SEL) begin
								case ({A[5:2],2'b00})
									6'h08: VINT0 <= CPU_DI[10:0];
									6'h0C: VINT1 <= CPU_DI[10:0];
									6'h28: begin CSTAT <= CPU_DI; CSTAT[6] <= &CPU_DI[5:4]; end
									default:;
								endcase
								IO_ST <= IO_IDLE;
								
`ifdef DEBUG
								if ({A[5:2],2'b00} == 6'h0C && CPU_DI[10:0] == 11'h7FF) DBG_VINT1_CNT <= DBG_VINT1_CNT + 1'd1;
								if ({A[5:2],2'b00} == 6'h28 && CPU_DI[5]) DBG_VINT1_CNT <= '0;
`endif
							end
							else if (INTERRUPT_SEL) begin
								case ({A[7:2],2'b00})
									8'h40: INT0_PEND <= INT0_PEND | CPU_DI;
									8'h44: INT0_PEND <= INT0_PEND & ~CPU_DI;
									8'h48: INT0_EN <= INT0_EN | CPU_DI;
									8'h4C: INT0_EN <= INT0_EN & ~CPU_DI;
									8'h50: INT_MODE <= INT_MODE | CPU_DI;
									8'h54: INT_MODE <= INT_MODE & ~CPU_DI;
									8'h60: INT1_PEND <= INT1_PEND | CPU_DI;
									8'h64: INT1_PEND <= INT1_PEND & ~CPU_DI;
									8'h68: INT1_EN <= INT1_EN | CPU_DI;
									8'h6C: INT1_EN <= INT1_EN & ~CPU_DI;
									8'h80: HDELAY <= CPU_DI;
									8'h84: {ADBIO_D,ADBIO_O} <= CPU_DI[7:0];
									default:;
								endcase
								IO_ST <= IO_IDLE;
							end
							else if (TIMER_SEL) begin
								if (!A[2]) TM_CNT[A[6:3]] <= CPU_DI[15:0];
								else       TM_RELOAD[A[6:3]] <= CPU_DI[15:0];
								IO_ST <= IO_IDLE;
							end
							else if (TIMER_CTRL_SEL) begin
								case ({A[7:2],2'b00})
									8'h00: {TM_CTRL[ 7],TM_CTRL[ 6],TM_CTRL[ 5],TM_CTRL[ 4],TM_CTRL[ 3],TM_CTRL[ 2],TM_CTRL[ 1],TM_CTRL[ 0]} <= {TM_CTRL[ 7],TM_CTRL[ 6],TM_CTRL[ 5],TM_CTRL[ 4],TM_CTRL[ 3],TM_CTRL[ 2],TM_CTRL[ 1],TM_CTRL[ 0]} |  CPU_DI;
									8'h04: {TM_CTRL[ 7],TM_CTRL[ 6],TM_CTRL[ 5],TM_CTRL[ 4],TM_CTRL[ 3],TM_CTRL[ 2],TM_CTRL[ 1],TM_CTRL[ 0]} <= {TM_CTRL[ 7],TM_CTRL[ 6],TM_CTRL[ 5],TM_CTRL[ 4],TM_CTRL[ 3],TM_CTRL[ 2],TM_CTRL[ 1],TM_CTRL[ 0]} & ~CPU_DI;
									8'h08: {TM_CTRL[15],TM_CTRL[14],TM_CTRL[13],TM_CTRL[12],TM_CTRL[11],TM_CTRL[10],TM_CTRL[ 9],TM_CTRL[ 8]} <= {TM_CTRL[15],TM_CTRL[14],TM_CTRL[13],TM_CTRL[12],TM_CTRL[11],TM_CTRL[10],TM_CTRL[ 9],TM_CTRL[ 8]} |  CPU_DI;
									8'h0C: {TM_CTRL[15],TM_CTRL[14],TM_CTRL[13],TM_CTRL[12],TM_CTRL[11],TM_CTRL[10],TM_CTRL[ 9],TM_CTRL[ 8]} <= {TM_CTRL[15],TM_CTRL[14],TM_CTRL[13],TM_CTRL[12],TM_CTRL[11],TM_CTRL[10],TM_CTRL[ 9],TM_CTRL[ 8]} & ~CPU_DI;
									default:;
								endcase
								IO_ST <= IO_IDLE;
							end
							else if (FIFO_SEL) begin
								case ({A[7:2],2'b00})
									8'h00: begin FIFOINIT <= CPU_DI; DMAEN <= DMAEN & ~CPU_DI; end
									8'h04: DMAEN <= DMAEN | CPU_DI;
									8'h08: DMAEN <= DMAEN & ~CPU_DI;
									default:;
								endcase
								IO_ST <= IO_IDLE;
							end
							else if (XBUS_SEL) begin
								IO_XBUS_WR <= 1;
	//							IO_READY <= 0;
								IO_ST <= IO_WAIT;
							end
							else if (DSP_DIRECT_SEL) begin
								case ({A[7:2],2'b00})
									8'hD0: DSP_SEMA_WE <= 1;
									8'hD4: DSP_SEMA_ACK <= 1;
									8'hE4: DSP_RST <= 2'b01;
									8'hE8: DSP_RST <= 2'b11;
									8'hFC: DSP_GW <= CPU_DI[0];
									default:;
								endcase
								IO_ST <= IO_IDLE;
							end
							else if (DSP_NRAM32_SEL) begin
								DSP_ACCESS_32 <= 1;
								IO_ST <= IO_DSP_WRITE;
							end
							else if (DSP_NRAM16_SEL) begin
								DSP_ACCESS_32 <= 0;
								IO_ST <= IO_DSP_WRITE;
							end
							else if (DSP_EIRAM32_SEL) begin
								DSP_ACCESS_32 <= 1;
								IO_ST <= IO_DSP_WRITE;
							end
							else if (DSP_EIRAM16_SEL) begin
								DSP_ACCESS_32 <= 0;
								IO_ST <= IO_DSP_WRITE;
							end
							else if (UNCLE_SEL) begin
								case ({A[3:2],2'b00})
									4'h4: UNCLE_BITS <= CPU_DI;
									4'h8: ;
									4'hC: ;
									default:;
								endcase
								IO_ST <= IO_IDLE;
							end
						end
						else if (CLC == 3'h3 && !INFO_CODE /*&& MCLK_PH1*/) begin	//CPU read
							if (A == (16'h0000>>2)) begin
								IO_ST <= IO_IDLE;
							end
							else if (DSP_DIRECT_SEL) begin
								case ({A[7:2],2'b00})
									8'hF0: DSP_NOISE_RD <= 1;
									default:;
								endcase
								IO_ST <= IO_DSP_READ;
							end
							else if (DSP_EORAM32_SEL) begin
								DSP_ACCESS_32 <= 1;
								IO_ST <= IO_DSP_READ;
							end
							else if (DSP_EORAM16_SEL) begin
								DSP_ACCESS_32 <= 0;
								IO_ST <= IO_DSP_READ;
							end
				
`ifdef DEBUG
							if (TIMER_SEL && A[6:2] == 5'b00000) begin
								DBG_TIMER0 <= TM_CNT[0];
							end
							if (TIMER_SEL && A[6:2] == 5'b00010) begin
								DBG_TIMER1 <= TM_CNT[1];
							end
`endif
						end
`ifdef DEBUG
						DBG_WAIT_CNT <= '0;
`endif
					end
					
					IO_WAIT: begin
`ifdef DEBUG
						DBG_WAIT_CNT <= DBG_WAIT_CNT + 1'd1;
`endif
						
						IO_XBUS_WR <= 0;
						IO_XBUS_RD <= 0;
						if (!IO_XBUS_WR && !IO_XBUS_RD && XBUS_READY) begin
							IO_READY <= 1;
							IO_ST <= IO_IDLE;
							
`ifdef DEBUG
							DBG_WAIT_CNT <= '0;
`endif
						end
					end
					
					IO_END: begin
						if (CLC == 3'h0) begin
							IO_ST <= IO_IDLE;
						end
					end
					
					IO_DSP_WRITE: begin
						if (DSP_NRAM32_SEL) DSP_NRAM32_WE <= 1;
						if (DSP_EIRAM32_SEL) DSP_EIRAM32_WE <= 1;
						IO_ST <= IO_IDLE;
					end
					
					IO_DSP_READ: begin					
						IO_ST <= IO_IDLE;
					end
				
				endcase
				IO_A_LATCH <= A[10:2];
				IO_DI_LATCH <= CPU_DI;
				DSP_DO_LATCH <= DSP_DO;
				
				//Interrupts
				
				//Vint0 int
				if (VINT0_REQ && !VINT0_ACK) begin
					INT0_PEND[0] <= 1;
					VINT0_ACK <= 1;
				end
				if (!VINT0_REQ && VINT0_ACK) VINT0_ACK <= 0;
				
				//Vint1 int
				if (VINT1_REQ && !VINT1_ACK) begin
					INT0_PEND[1] <= 1;
					VINT1_ACK <= 1;
				end
				if (!VINT1_REQ && VINT1_ACK) VINT1_ACK <= 0;
				
				//Xbus int
				EINT_N_OLD <= EINT_N;
				if (!EINT_N && EINT_N_OLD) begin
					INT0_PEND[2] <= 1;
				end
				
				if (TMINT_REQ[7]) INT0_PEND[ 3] <= 1;//Timer15 int
				if (TMINT_REQ[6]) INT0_PEND[ 4] <= 1;//Timer13 int
				if (TMINT_REQ[5]) INT0_PEND[ 5] <= 1;//Timer11 int
				if (TMINT_REQ[4]) INT0_PEND[ 6] <= 1;//Timer9 int
				if (TMINT_REQ[3]) INT0_PEND[ 7] <= 1;//Timer7 int
				if (TMINT_REQ[2]) INT0_PEND[ 8] <= 1;//Timer5 int
				if (TMINT_REQ[1]) INT0_PEND[ 9] <= 1;//Timer3 int
				if (TMINT_REQ[0]) INT0_PEND[10] <= 1;//Timer1 int
				
				//Timers
				TMINT_REQ <= '{8{0}};
				for (int i=0; i<16; i++) begin
					if (TM_CLK) begin
						TM_CASCADE[i] = (i == 0 ? 1'b0 : TM_ZERO[i-1]);
						TM_ZERO[i] <= 0;
						if (TM_CTRL[i][0] && (!TM_CTRL[i][2] || TM_CASCADE[i])) begin
							TM_CNT[i] <= TM_CNT[i] - 16'd1;
							if (TM_CNT[i] == 16'h0000) begin
								if (TM_CTRL[i][1]) begin
									TM_CNT[i] <= TM_RELOAD[i];
								end
								else begin
									TM_CTRL[i][0] <= 0;
								end
								TM_ZERO[i] <= 1;
								if (i & 1) TMINT_REQ[i/2] <= 1;
							end
						end
					end
				end
				
				if (DSP_CPUINT_REQ) begin
					INT0_PEND[11] <= 1;
				end
				
//				if (DMA_INT_REQ && DMA_CHAN == 5'h0F) begin
//					INT0_PEND[11] <= 1;
//				end
				if (DMA_INT_REQ && DMA_CHAN == 5'h10) begin
					INT0_PEND[12] <= 1;
				end
				if (DMA_INT_REQ && DMA_CHAN == 5'h11) begin
					INT0_PEND[13] <= 1;
				end
				if (DMA_INT_REQ && DMA_CHAN == 5'h12) begin
					INT0_PEND[14] <= 1;
				end
				if (DMA_INT_REQ && DMA_CHAN == 5'h13) begin
					INT0_PEND[15] <= 1;
				end
				if (DMA_INT_REQ && DMA_CHAN == 5'h00) begin
					INT0_PEND[16] <= 1;
				end
				if (DMA_INT_REQ && DMA_CHAN == 5'h01) begin
					INT0_PEND[17] <= 1;
				end
				if (DMA_INT_REQ && DMA_CHAN == 5'h02) begin
					INT0_PEND[18] <= 1;
				end
				if (DMA_INT_REQ && DMA_CHAN == 5'h03) begin
					INT0_PEND[19] <= 1;
				end
				if (DMA_INT_REQ && DMA_CHAN == 5'h04) begin
					INT0_PEND[20] <= 1;
				end
				if (DMA_INT_REQ && DMA_CHAN == 5'h05) begin
					INT0_PEND[21] <= 1;
				end
				if (DMA_INT_REQ && DMA_CHAN == 5'h06) begin
					INT0_PEND[22] <= 1;
				end
				if (DMA_INT_REQ && DMA_CHAN == 5'h07) begin
					INT0_PEND[23] <= 1;
				end
				if (DMA_INT_REQ && DMA_CHAN == 5'h08) begin
					INT0_PEND[24] <= 1;
				end
				if (DMA_INT_REQ && DMA_CHAN == 5'h09) begin
					INT0_PEND[25] <= 1;
				end
				if (DMA_INT_REQ && DMA_CHAN == 5'h0A) begin
					INT0_PEND[26] <= 1;
				end
				if (DMA_INT_REQ && DMA_CHAN == 5'h0B) begin
					INT0_PEND[27] <= 1;
				end
				if (DMA_INT_REQ && DMA_CHAN == 5'h0C) begin
					INT0_PEND[28] <= 1;
				end
				if (DMA_INT_REQ && DMA_CHAN == 5'h14) begin
					INT0_PEND[29] <= 1;
				end
				
				if (PB_INT) begin
					INT1_PEND[0] <= 1;
					INT0_PEND[31] <= 1;
				end
				
				//DMA
				DMAEN_OLD <= DMAEN;
				if (DMAEN[ 0] && !DMAEN_OLD[ 0] && !EIFIFO_COUNT[ 0]) DMA_TO_DSP_PEND[ 0] <= 1;
				if (DMAEN[ 1] && !DMAEN_OLD[ 1] && !EIFIFO_COUNT[ 1]) DMA_TO_DSP_PEND[ 1] <= 1;
				if (DMAEN[ 2] && !DMAEN_OLD[ 2] && !EIFIFO_COUNT[ 2]) DMA_TO_DSP_PEND[ 2] <= 1;
				if (DMAEN[ 3] && !DMAEN_OLD[ 3] && !EIFIFO_COUNT[ 3]) DMA_TO_DSP_PEND[ 3] <= 1;
				if (DMAEN[ 4] && !DMAEN_OLD[ 4] && !EIFIFO_COUNT[ 4]) DMA_TO_DSP_PEND[ 4] <= 1;
				if (DMAEN[ 5] && !DMAEN_OLD[ 5] && !EIFIFO_COUNT[ 5]) DMA_TO_DSP_PEND[ 5] <= 1;
				if (DMAEN[ 6] && !DMAEN_OLD[ 6] && !EIFIFO_COUNT[ 6]) DMA_TO_DSP_PEND[ 6] <= 1;
				if (DMAEN[ 7] && !DMAEN_OLD[ 7] && !EIFIFO_COUNT[ 7]) DMA_TO_DSP_PEND[ 7] <= 1;
				if (DMAEN[ 8] && !DMAEN_OLD[ 8] && !EIFIFO_COUNT[ 8]) DMA_TO_DSP_PEND[ 8] <= 1;
				if (DMAEN[ 9] && !DMAEN_OLD[ 9] && !EIFIFO_COUNT[ 9]) DMA_TO_DSP_PEND[ 9] <= 1;
				if (DMAEN[10] && !DMAEN_OLD[10] && !EIFIFO_COUNT[10]) DMA_TO_DSP_PEND[10] <= 1;
				if (DMAEN[11] && !DMAEN_OLD[11] && !EIFIFO_COUNT[11]) DMA_TO_DSP_PEND[11] <= 1;
				if (DMAEN[12] && !DMAEN_OLD[12] && !EIFIFO_COUNT[12]) DMA_TO_DSP_PEND[12] <= 1;
				
				if (FIFOINIT[ 0]) DMA_TO_DSP_PEND[ 0] <= 0;
				if (FIFOINIT[ 1]) DMA_TO_DSP_PEND[ 1] <= 0;
				if (FIFOINIT[ 2]) DMA_TO_DSP_PEND[ 2] <= 0;
				if (FIFOINIT[ 3]) DMA_TO_DSP_PEND[ 3] <= 0;
				if (FIFOINIT[ 4]) DMA_TO_DSP_PEND[ 4] <= 0;
				if (FIFOINIT[ 5]) DMA_TO_DSP_PEND[ 5] <= 0;
				if (FIFOINIT[ 6]) DMA_TO_DSP_PEND[ 6] <= 0;
				if (FIFOINIT[ 7]) DMA_TO_DSP_PEND[ 7] <= 0;
				if (FIFOINIT[ 8]) DMA_TO_DSP_PEND[ 8] <= 0;
				if (FIFOINIT[ 9]) DMA_TO_DSP_PEND[ 9] <= 0;
				if (FIFOINIT[10]) DMA_TO_DSP_PEND[10] <= 0;
				if (FIFOINIT[11]) DMA_TO_DSP_PEND[11] <= 0;
				if (FIFOINIT[12]) DMA_TO_DSP_PEND[12] <= 0;
				if (FIFOINIT[16]) DMA_FROM_DSP_PEND[0] <= 0;
				if (FIFOINIT[17]) DMA_FROM_DSP_PEND[1] <= 0;
				if (FIFOINIT[18]) DMA_FROM_DSP_PEND[2] <= 0;
				if (FIFOINIT[19]) DMA_FROM_DSP_PEND[3] <= 0;
				
				DMAREQ <= 0;
				DMA_INT_REQ <= 0;
				DMA_EXP_FIFO_WRITE <= 0;
				DMA_EXP_FIFO_READ <= 0;
				DMA_EXP_PEND_INC = 0;
				DMA_EXP_PEND_DEC = 0;
				DMA_TO_DSP_WRITE[1] <= DMA_TO_DSP_WRITE[0]; 
				DMA_TO_DSP_WRITE[0] <= 0;
				DMA_FROM_DSP_READ[1] <= DMA_FROM_DSP_READ[0]; 
				DMA_FROM_DSP_READ[0] <= 0;
				case (DMA_ST)
					DMA_IDLE: begin
						if (DMA_TO_DSP_PEND[0] && DMAEN[0]) begin			//DMA to DSP0
							DMA_CHAN <= 5'h00;
							DMA_ST <= DMA_REQUEST;
						end
						else if (DMA_TO_DSP_PEND[1] && DMAEN[1]) begin	//DMA to DSP1
							DMA_CHAN <= 5'h01;
							DMA_ST <= DMA_REQUEST;
						end
						else if (DMA_TO_DSP_PEND[2] && DMAEN[2]) begin	//DMA to DSP2
							DMA_CHAN <= 5'h02;
							DMA_ST <= DMA_REQUEST;
						end
						else if (DMA_TO_DSP_PEND[3] && DMAEN[3]) begin	//DMA to DSP3
							DMA_CHAN <= 5'h03;
							DMA_ST <= DMA_REQUEST;
						end
						else if (DMA_TO_DSP_PEND[4] && DMAEN[4]) begin	//DMA to DSP4
							DMA_CHAN <= 5'h04;
							DMA_ST <= DMA_REQUEST;
						end
						else if (DMA_TO_DSP_PEND[5] && DMAEN[5]) begin	//DMA to DSP5
							DMA_CHAN <= 5'h05;
							DMA_ST <= DMA_REQUEST;
						end
						else if (DMA_TO_DSP_PEND[6] && DMAEN[6]) begin	//DMA to DSP6
							DMA_CHAN <= 5'h06;
							DMA_ST <= DMA_REQUEST;
						end
						else if (DMA_TO_DSP_PEND[7] && DMAEN[7]) begin	//DMA to DSP7
							DMA_CHAN <= 5'h07;
							DMA_ST <= DMA_REQUEST;
						end
						else if (DMA_TO_DSP_PEND[8] && DMAEN[8]) begin	//DMA to DSP8
							DMA_CHAN <= 5'h08;
							DMA_ST <= DMA_REQUEST;
						end
						else if (DMA_TO_DSP_PEND[9] && DMAEN[9]) begin	//DMA to DSP9
							DMA_CHAN <= 5'h09;
							DMA_ST <= DMA_REQUEST;
						end
						else if (DMA_TO_DSP_PEND[10] && DMAEN[10]) begin	//DMA to DSP10
							DMA_CHAN <= 5'h0A;
							DMA_ST <= DMA_REQUEST;
						end
						else if (DMA_TO_DSP_PEND[11] && DMAEN[11]) begin	//DMA to DSP11
							DMA_CHAN <= 5'h0B;
							DMA_ST <= DMA_REQUEST;
						end
						else if (DMA_TO_DSP_PEND[12] && DMAEN[12]) begin	//DMA to DSP12
							DMA_CHAN <= 5'h0C;
							DMA_ST <= DMA_REQUEST;
						end
	//					else if (DMA_PEND[13] && DMAEN[13]) begin	//DMA to UNCLE
	//						DMA_CHAN <= 5'h0D;
	//						DMA_ST <= DMA_REQUEST;
	//					end
	//					else if (DMA_PEND[14] && DMAEN[14]) begin	//DMA to EXT
	//						DMA_CHAN <= 5'h0E;
	//						DMA_ST <= DMA_REQUEST;
	//					end
	//					else if (DMA_PEND[15] && DMAEN[15]) begin	//DMA to DSPN
	//						DMA_CHAN <= 5'h0F;
	//						DMA_ST <= DMA_REQUEST;
	//					end
						else if (DMA_FROM_DSP_PEND[0] && DMAEN[16]) begin	//DSP0 to DMA
							DMA_CHAN <= 5'h10;
							DMA_ST <= DMA_REQUEST;
						end
						else if (DMA_FROM_DSP_PEND[1] && DMAEN[17]) begin	//DSP1 to DMA
							DMA_CHAN <= 5'h11;
							DMA_ST <= DMA_REQUEST;
						end
						else if (DMA_FROM_DSP_PEND[2] && DMAEN[18]) begin	//DSP2 to DMA
							DMA_CHAN <= 5'h12;
							DMA_ST <= DMA_REQUEST;
						end
						else if (DMA_FROM_DSP_PEND[3] && DMAEN[19]) begin	//DSP3 to DMA
							DMA_CHAN <= 5'h13;
							DMA_ST <= DMA_REQUEST;
						end
						else if (DMA_EXP_PEND && DMAEN[20]) begin	//DMA to/from EXP
							DMA_CHAN <= 5'h14;
							DMA_ST <= DMA_REQUEST;
						end
					end
					
					DMA_REQUEST: begin
						DMACH <= DMA_CHAN;
						DMAREQ <= 1;
						if (DMA_CHAN <= 5'h0C)
							DMA_ST <= DMA_DSP_WRITE;
						else if (DMA_CHAN >= 5'h10 && DMA_CHAN <= 5'h13)
							DMA_ST <= DMA_DSP_READ;
						else if (DMA_CHAN == 5'h14)
							DMA_ST <= DMA_EXP_READ;
						else
							DMA_ST <= DMA_END;
					end
					
					DMA_DSP_WRITE: begin
						if (CLC2 == 3'h2 && CLC1 == 3'h0) begin
							DMA_BUF <= DI;
							DMA_TO_DSP_WRITE[0] <= 1;
						end
						if (CLC == 3'h7) begin
							DMA_TO_DSP_PEND[DMA_CHAN[3:0]] <= 0;
							DMA_ST <= DMA_DSP_END;
						end
					end
					
					DMA_DSP_READ: begin
						if (CLC == 3'h2) begin
							DMA_FROM_DSP_READ[0] <= 1;
						end
						if (CLC == 3'h7) begin
							DMA_FROM_DSP_PEND[DMA_CHAN[1:0]] <= 0;
							DMA_ST <= DMA_DSP_END;
						end
					end
					
					DMA_DSP_END: begin
						if (CLC == 3'h2) begin
							
						end
						if (CLC == 3'h3) begin
							DMA_INT_REQ <= 1;
						end
						DMA_ST <= DMA_END;
					end
					
					DMA_EXP_READ: begin
						if (CLC2 == 3'h2 && CLC1 == 3'h0) begin
							DMA_EXP_FIFO_READ <= 1;
						end
						if (CLC == 3'h7) begin
							DMA_EXP_PEND_DEC = 1;
							DMA_ST <= DMA_EXP_END;
						end
					end
					
					DMA_EXP_END: begin
						if (CLC == 3'h2) begin
	//						DMA_INT_REQ <= 1;
						end
						if (CLC == 3'h3) begin
							DMA_INT_REQ <= 1;
						end
						DMA_ST <= DMA_END;
					end
					
					DMA_END: begin
						DMA_ST <= DMA_IDLE;
					end
				
				endcase
				
`ifdef DEBUG
				if (DMA_XBUS_ACT) DBG_DMA_WAIT_CNT <= DBG_DMA_WAIT_CNT + 1'd1;
`endif
				
				if (DMA_FROM_DSP_READ[0]) begin
					DMA_BUF2 <= EOFIFO_Q[DMA_CHAN[1:0]];
				end
				
				if (XBUS_DMA_READY) begin
					DMA_EXP_FIFO_WRITE <= 1;
					DMA_EXP_WORD_CNT <= DMA_EXP_WORD_CNT + 2'd1;
					if (DMA_EXP_WORD_CNT == 2'd3 || !DMA_XBUS_ACT) begin
						DMA_EXP_PEND_INC = 1;
						DMA_EXP_WORD_CNT <= '0;
					end
					
`ifdef DEBUG
					DBG_DMA_WAIT_CNT <= '0;
`endif
				end
				if ( DMA_EXP_PEND_INC && !DMA_EXP_PEND_DEC) DMA_EXP_PEND <= DMA_EXP_PEND + 2'd1;
				if (!DMA_EXP_PEND_INC &&  DMA_EXP_PEND_DEC) DMA_EXP_PEND <= DMA_EXP_PEND - 2'd1;
			end
		end
	end
	wire [ 8: 0] DSP_ADDR = DSP_NRAM32_WE || DSP_EIRAM32_WE ? {IO_A_LATCH[9:2],1'b1} : (DSP_ACCESS_32 ? {A[9:2],1'b0} : A[10:2]);
	wire [15: 0] DSP_DI   = DSP_NRAM32_WE || DSP_EIRAM32_WE ? IO_DI_LATCH[15:0]      : (DSP_ACCESS_32 ? CPU_DI[31:16]  : CPU_DI[15:0]);
	wire         DSP_NRAM_WE = DSP_NRAM32_WE || (DSP_NRAM32_SEL && IO_ST == IO_DSP_WRITE) || (DSP_NRAM16_SEL && IO_ST == IO_DSP_WRITE);
	wire         DSP_EIRAM_WE = DSP_EIRAM32_WE || (DSP_EIRAM32_SEL && IO_ST == IO_DSP_WRITE) || (DSP_EIRAM16_SEL && IO_ST == IO_DSP_WRITE);
	
	always @(posedge CLK) begin
		if (CONTROL_SEL)
			case ({A[5:2],2'b00})
				6'h00: CPU_DO <= REV;
				6'h08: CPU_DO <= {16'h0000,5'b00000,VINT0};
				6'h0C: CPU_DO <= {16'h0000,5'b00000,VINT1};
				6'h28: CPU_DO <= CSTAT;
				6'h30: CPU_DO <= {16'h0000,5'b00000,HCNT};
				6'h34: CPU_DO <= {16'h0000,4'b0000,FLD,2'b00,VCNT};
				default: CPU_DO <= '0;
			endcase
		else if (INTERRUPT_SEL)
			case ({A[7:2],2'b00})
				8'h40,
				8'h44: CPU_DO <= INT0_PEND;
				8'h48,
				8'h4C: CPU_DO <= {1'b1,INT0_EN[30:0]};
				8'h50,
				8'h54: CPU_DO <= INT_MODE;
				8'h60,
				8'h64: CPU_DO <= INT1_PEND;
				8'h68,
				8'h6C: CPU_DO <= INT1_EN;
				8'h80: CPU_DO <= HDELAY;
				8'h84: CPU_DO <= {16'h0000,12'h000,ADBIO_I};
				default: CPU_DO <= '0;
			endcase
		else if (TIMER_SEL)
			if (!A[2]) CPU_DO <= {16'h0000,TM_CNT[A[6:3]]};
			else       CPU_DO <= {16'h0000,TM_RELOAD[A[6:3]]};
		else if (FIFO_SEL)
			case ({A[7:2],2'b00})
				8'h04: CPU_DO <= DMAEN;
				8'h08: CPU_DO <= DMAEN;
				8'h80: CPU_DO <= {28'h0000000,EIFIFO_COUNT[ 0]};
				8'h84: CPU_DO <= {28'h0000000,EIFIFO_COUNT[ 1]};
				8'h88: CPU_DO <= {28'h0000000,EIFIFO_COUNT[ 2]};
				8'h8C: CPU_DO <= {28'h0000000,EIFIFO_COUNT[ 3]};
				8'h90: CPU_DO <= {28'h0000000,EIFIFO_COUNT[ 4]};
				8'h94: CPU_DO <= {28'h0000000,EIFIFO_COUNT[ 5]};
				8'h98: CPU_DO <= {28'h0000000,EIFIFO_COUNT[ 6]};
				8'h9C: CPU_DO <= {28'h0000000,EIFIFO_COUNT[ 7]};
				8'hA0: CPU_DO <= {28'h0000000,EIFIFO_COUNT[ 8]};
				8'hA4: CPU_DO <= {28'h0000000,EIFIFO_COUNT[ 9]};
				8'hA8: CPU_DO <= {28'h0000000,EIFIFO_COUNT[10]};
				8'hAC: CPU_DO <= {28'h0000000,EIFIFO_COUNT[11]};
				8'hB0: CPU_DO <= {28'h0000000,EIFIFO_COUNT[12]};
//				8'hB4: CPU_DO <= {28'h0000000,EIFIFO_COUNT[ 0]};
//				8'hB8: CPU_DO <= {28'h0000000,EIFIFO_COUNT[ 0]};
				8'hC0: CPU_DO <= {28'h0000000,EIFIFO_COUNT[ 0]};
				8'hC4: CPU_DO <= {28'h0000000,EIFIFO_COUNT[ 1]};
				8'hC8: CPU_DO <= {28'h0000000,EIFIFO_COUNT[ 2]};
				8'hCC: CPU_DO <= {28'h0000000,EIFIFO_COUNT[ 3]};
				default: CPU_DO <= '0;
			endcase
		else if (XBUS_SEL)
			CPU_DO <= XBUS_DO;
		else if (DSP_DIRECT_SEL)
			case ({A[7:2],2'b00})
				8'hD0: CPU_DO <= {12'b0000_0000_0000,DSP_SEMAPHORE_STAT,DSP_SEMAPHORE};
				8'hF0: CPU_DO <= {16'h0000,DSP_NOISE};
				8'hF4: CPU_DO <= {16'h0000,6'b000000,DSP_PC};
				8'hF8: CPU_DO <= {16'h0000,DSP_NRC};
				8'hFC: CPU_DO <= {31'h00000000,DSP_GW};
				default: CPU_DO <= '0;
			endcase
		else if (DSP_EORAM32_SEL)
			CPU_DO <= {DSP_DO,DSP_DO_LATCH};
		else if (DSP_EORAM16_SEL)
			CPU_DO <= {16'h0000,DSP_DO};
		else if (UNCLE_SEL)
			case ({A[3:2],2'b00})
//				4'h0: CPU_DO <= 32'h03000001;
				4'h4: CPU_DO <= UNCLE_BITS;
				default: CPU_DO <= '0;
			endcase
		else
			CPU_DO <= '0;
	end
	
	always_comb begin
		if (CLC2 == 3'h2 && CLC1 == 3'h0) 
			case (DMA_CHAN)
				5'h10: DO = {DMA_BUF2,EOFIFO_Q[0]};
				5'h11: DO = {DMA_BUF2,EOFIFO_Q[1]};
				5'h12: DO = {DMA_BUF2,EOFIFO_Q[2]};
				5'h13: DO = {DMA_BUF2,EOFIFO_Q[3]};
				5'h14: DO = XBUS_FIFO_Q;
				default: DO = '0;
			endcase
		else 
			DO = '0;
	end
	assign CREADY_N = ~IO_READY;
	
	assign FIRQ_N = ~(|(INT0_PEND[30:0] & INT0_EN[30:0]) | |(INT1_PEND & INT1_EN));
	
	assign RESET_N = ~|RESET_DELAY[11:8];
	
	//XBUS
	CLIO_XBUS XBUS
	(
		.CLK(CLK),
		.RST_N(RST_N),
		.EN(EN),
		
		.CE_R(CE_R && IO_EN),
		.CE_F(CE_F && IO_EN),
		
		.A(IO_A_LATCH[9:2]),
		.DI(IO_DI_LATCH),
		.DO(XBUS_DO),
		.WR(IO_XBUS_WR),
		.RD(IO_XBUS_RD),
		.RDY(XBUS_READY),
		
		.DMA_ALLOW(~XBUS_FIFO_FULL),
		.DMA_ACT(DMA_XBUS_ACT),
		.DMA_RDY(XBUS_DMA_READY),
		.DMA_DO(XBUS_DMA_DO),
		
		.EDI(EDI),
		.EDO(EDO),
		.ESTR_N(ESTR_N),
		.EWRT_N(EWRT_N),
		.ECMD_N(ECMD_N),
		.ESEL_N(ESEL_N),
		.ERST_N(ERST_N),
		.ERDY_N(ERDY_N),
		.EINT_N(EINT_N)
	);
	
	bit  [31: 0] XBUS_FIFO_Q;
	bit          XBUS_FIFO_FULL;
	bit          XBUS_FIFO_EMPTY;
	CLIO_DMA_FIFO XBUS_FIFO (.CLK(CLK), .EN(EN), .RST(~RST_N), .DATA(XBUS_DMA_DO), .WRREQ(DMA_EXP_FIFO_WRITE & IO_EN & CE_R), .RDREQ(DMA_EXP_FIFO_READ & IO_EN & CE_R), .Q(XBUS_FIFO_Q), .FULL(XBUS_FIFO_FULL), .EMPTY(XBUS_FIFO_EMPTY));
	
	//DSP
	bit          DSP_RESET;
	
	bit  [15: 0] DSP_NBUS;
	bit  [ 7: 0] DSP_EI_ADDR;
	bit  [15: 0] DSP_EI_DATA;
	bit          DSP_EI_OE;
	bit  [ 7: 0] DSP_EO_ADDR;
	bit  [15: 0] DSP_EO_DATA;
	bit          DSP_EO_WE;
	CLIO_DSP	DSP
	(
		.CLK(CLK),
		.RST_N(RST_N),
		.EN(DSP_EN),
		
		.CE_R(CE_R),
		.CE_F(CE_F),
		
		.GW(DSP_GW),
		.RESET(DSP_RESET),
		
		.PC(DSP_PC),
		.NBUS(DSP_NBUS),
		
		.NRC(DSP_NRC),
		
		.EI_ADDR(DSP_EI_ADDR),
		.EI_DATA(DSP_EI_DATA),
		.EI_OE(DSP_EI_OE),
		.EO_ADDR(DSP_EO_ADDR),
		.EO_DATA(DSP_EO_DATA),
		.EO_WE(DSP_EO_WE)
	);
	
	CLIO_DSP_NRAM 
`ifdef SIM
	#(dsp_nram_file)
`endif
	NRAM
	(
		.CLK(CLK),
		.EN(EN),
		
		.WA(DSP_ADDR),
		.WD(DSP_DI),
		.WE(DSP_NRAM_WE & IO_EN & CE_R),
		
		.RA(DSP_PC[8:0]),
		.RD(DSP_NBUS)
	);
	
	//EIRAM
	wire EIRAM_WE = (DSP_ADDR[7:0] <= 8'h6F && DSP_EIRAM_WE);//0x000-0x06F
	wire EIRAM_OE = (DSP_EI_ADDR <= 8'h6F);//0x000-0x06F
	bit  [15: 0] EIRAM_DATA;
	CLIO_DSP_EIRAM EIRAM
	(
		.CLK(CLK),
		.EN(EN),
		
		.WA(DSP_ADDR[6:0]),
		.WD(DSP_DI),
		.WE(EIRAM_WE & IO_EN & CE_R),
		
		.RA(DSP_EI_ADDR[6:0]),
		.RD(EIRAM_DATA)
	);
	
	//EORAM
	wire DSP_EORAM_WE = (DSP_EO_ADDR[7:4] == 4'h0) && DSP_EO_WE;//0x300-0x30F
	bit  [15: 0] DSP_EORAM_DO;
	CLIO_DSP_EORAM EORAM
	(
		.CLK(CLK),
		.EN(EN),
		
		.WA(DSP_EO_ADDR[3:0]),
		.WD(DSP_EO_DATA),
		.WE(DSP_EORAM_WE & DSP_EN & CE_R),
		
		.RA(DSP_ADDR[3:0]),
		.RD(DSP_EORAM_DO)
	);
	
	wire NOISE_OE = (DSP_EI_ADDR == 8'hEA);					//0x0EA
	always @(posedge CLK or negedge RST_N) begin
		bit  [16: 0] NOISE_NEW;
		
		if (!RST_N) begin
			NOISE <= 17'h00001;
		end
		else if (EN && CE_R) begin
			NOISE_NEW = {NOISE[5]^NOISE[0],NOISE[16:1]};
			
			if (DSP_EN) begin
				if (NOISE_OE) begin
					NOISE <= NOISE_NEW;
				end
			end
			
			if (IO_EN) begin
				if (DSP_NOISE_RD) begin
					DSP_NOISE <= NOISE[15:0];
					NOISE <= NOISE_NEW;
				end
			end
		end
	end
	
	bit          AUDLOCK;
	bit          AUDWS;
	wire AUDLOCK_OE = DSP_EI_ADDR == 8'hEB;				//0x0EB
	wire AUDLOCK_WE = DSP_EO_ADDR == 8'hEB && DSP_EO_WE;		//0x3EB
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) begin
			AUDLOCK <= 0;
		end
		else if (EN && DSP_EN && CE_R) begin
			if (AUDLOCK_WE) begin
				AUDLOCK <= DSP_EO_DATA[15];
			end
		end
	end
	
	wire SEMASTAT_OE = DSP_EI_ADDR == 8'hEC;				//0x0EC
	wire SEMAACK_WE = DSP_EO_ADDR == 8'hEC && DSP_EO_WE;		//0x3EC
	wire SEMAPHORE_OE = DSP_EI_ADDR == 8'hED;				//0x0ED
	wire SEMAPHORE_WE = DSP_EO_ADDR == 8'hED && DSP_EO_WE;	//0x3ED
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) begin
			DSP_SEMAPHORE <= '0;
			DSP_SEMAPHORE_STAT <= '0;
		end
		else if (EN && CE_R) begin
			if (DSP_EN) begin
				if (SEMAACK_WE) begin
					DSP_SEMAPHORE_STAT[0] <= 1;
				end
				else if (SEMAPHORE_WE) begin
					DSP_SEMAPHORE <= DSP_EO_DATA;
					DSP_SEMAPHORE_STAT <= '0;
					DSP_SEMAPHORE_STAT[2] <= 1;
				end
			end
			
			if (IO_EN) begin
				if (DSP_SEMA_ACK) begin
					DSP_SEMAPHORE_STAT[1] <= 1;
				end
				else if (DSP_SEMA_WE) begin
					DSP_SEMAPHORE <= CPU_DI[15:0];
					DSP_SEMAPHORE_STAT <= '0;
					DSP_SEMAPHORE_STAT[3] <= 1;
				end
			end
		end
	end
	
	wire PC_OE = (DSP_EI_ADDR == 8'hEE);					//0x0EE
	
	bit  [15: 0] DSP_CPUINT;
	bit          DSP_CPUINT_REQ;
	wire CPUINT_WE = DSP_EO_ADDR == 8'hEE && DSP_EO_WE;		//0x3EE
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) begin
			DSP_CPUINT <= '0;
			DSP_CPUINT_REQ <= 0;
		end
		else if (EN && CE_R) begin
			if (IO_EN) begin
				DSP_CPUINT_REQ <= 0;
			end
			
			if (DSP_EN) begin
				if (CPUINT_WE) begin
					DSP_CPUINT <= DSP_EO_DATA;
					DSP_CPUINT_REQ <= 1;
				end
			end
		end
	end
	
	bit  [15: 0] CNTR,RELOAD;
	wire CNTR_OE   = DSP_EI_ADDR == 8'hEF;				//0x0EF
	wire RELOAD_WE = DSP_EO_ADDR == 8'hEF && DSP_EO_WE;	//0x3EF
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) begin
			CNTR <= '0;
			RELOAD <= '0;
			DSP_RESET <= 0;
		end
		else if (EN && DSP_EN && CE_R) begin
			DSP_RESET <= 0;
			
			if (DSP_GW) CNTR <= CNTR - 16'd1;
			if ((!CNTR && RELOAD && DSP_GW) || DSP_RST || (AUDWS && AUDLOCK)) begin
				CNTR <= RELOAD;
				RELOAD <= 16'd565;
				DSP_RESET <= 1;
			end
			
			if (RELOAD_WE) begin
				RELOAD <= DSP_EO_DATA;
			end
		end
	end
	
	
	wire EIFIFO_STAT_OE = DSP_EI_ADDR >= 8'hD0 && DSP_EI_ADDR <= 8'hDE;	//0x0D0-0x0DE
	wire EIFIFO_OE2 = DSP_EI_ADDR >= 8'h70 && DSP_EI_ADDR <= 8'h7C;			//0x070-0x07C
	wire EIFIFO_OE = DSP_EI_ADDR >= 8'hF0 && DSP_EI_ADDR <= 8'hFC;			//0x0F0-0x0FC
	wire EIFIFO0_OE  = EIFIFO_OE && DSP_EI_ADDR[3:0] == 4'h0 && DSP_EI_OE;
	wire EIFIFO1_OE  = EIFIFO_OE && DSP_EI_ADDR[3:0] == 4'h1 && DSP_EI_OE;
	wire EIFIFO2_OE  = EIFIFO_OE && DSP_EI_ADDR[3:0] == 4'h2 && DSP_EI_OE;
	wire EIFIFO3_OE  = EIFIFO_OE && DSP_EI_ADDR[3:0] == 4'h3 && DSP_EI_OE;
	wire EIFIFO4_OE  = EIFIFO_OE && DSP_EI_ADDR[3:0] == 4'h4 && DSP_EI_OE;
	wire EIFIFO5_OE  = EIFIFO_OE && DSP_EI_ADDR[3:0] == 4'h5 && DSP_EI_OE;
	wire EIFIFO6_OE  = EIFIFO_OE && DSP_EI_ADDR[3:0] == 4'h6 && DSP_EI_OE;
	wire EIFIFO7_OE  = EIFIFO_OE && DSP_EI_ADDR[3:0] == 4'h7 && DSP_EI_OE;
	wire EIFIFO8_OE  = EIFIFO_OE && DSP_EI_ADDR[3:0] == 4'h8 && DSP_EI_OE;
	wire EIFIFO9_OE  = EIFIFO_OE && DSP_EI_ADDR[3:0] == 4'h9 && DSP_EI_OE;
	wire EIFIFO10_OE = EIFIFO_OE && DSP_EI_ADDR[3:0] == 4'hA && DSP_EI_OE;
	wire EIFIFO11_OE = EIFIFO_OE && DSP_EI_ADDR[3:0] == 4'hB && DSP_EI_OE;
	wire EIFIFO12_OE = EIFIFO_OE && DSP_EI_ADDR[3:0] == 4'hC && DSP_EI_OE;
	wire [15: 0] EIFIFO_DATA = DMA_TO_DSP_WRITE[1] ? DMA_BUF[15:0] : DMA_BUF[31:16];
	wire         EIFIFO_WRREQ[13] = '{(DMA_TO_DSP_WRITE[1] || DMA_TO_DSP_WRITE[0]) && DMA_CHAN[3:0] == 4'h0,
	                                  (DMA_TO_DSP_WRITE[1] || DMA_TO_DSP_WRITE[0]) && DMA_CHAN[3:0] == 4'h1,
												 (DMA_TO_DSP_WRITE[1] || DMA_TO_DSP_WRITE[0]) && DMA_CHAN[3:0] == 4'h2,
												 (DMA_TO_DSP_WRITE[1] || DMA_TO_DSP_WRITE[0]) && DMA_CHAN[3:0] == 4'h3,
												 (DMA_TO_DSP_WRITE[1] || DMA_TO_DSP_WRITE[0]) && DMA_CHAN[3:0] == 4'h4,
												 (DMA_TO_DSP_WRITE[1] || DMA_TO_DSP_WRITE[0]) && DMA_CHAN[3:0] == 4'h5,
												 (DMA_TO_DSP_WRITE[1] || DMA_TO_DSP_WRITE[0]) && DMA_CHAN[3:0] == 4'h6,
												 (DMA_TO_DSP_WRITE[1] || DMA_TO_DSP_WRITE[0]) && DMA_CHAN[3:0] == 4'h7,
												 (DMA_TO_DSP_WRITE[1] || DMA_TO_DSP_WRITE[0]) && DMA_CHAN[3:0] == 4'h8,
												 (DMA_TO_DSP_WRITE[1] || DMA_TO_DSP_WRITE[0]) && DMA_CHAN[3:0] == 4'h9,
												 (DMA_TO_DSP_WRITE[1] || DMA_TO_DSP_WRITE[0]) && DMA_CHAN[3:0] == 4'hA,
												 (DMA_TO_DSP_WRITE[1] || DMA_TO_DSP_WRITE[0]) && DMA_CHAN[3:0] == 4'hB,
											 	 (DMA_TO_DSP_WRITE[1] || DMA_TO_DSP_WRITE[0]) && DMA_CHAN[3:0] == 4'hC};
//	bit          EIFIFO_RDREQ[13];
	bit  [15: 0] EIFIFO_Q[13];
	bit  [ 3: 0] EIFIFO_COUNT[13];
	//A value the CPU wrote to 0x070+n is returned by the next DSP read of channel n instead of the
	//FIFO, which does not move then (Opera: CPUSupply). Popping there dropped the head word: the
	//audio folio supplies a value before starting a stream, and the stream's first word (the header
	//of Psychic Detective's first sound) was lost, so its decoder saturated for a whole block.
	bit          EIFIFO_CPU[13];
	CLIO_DSP_FIFO EIFIFO0  (.CLK(CLK), .EN(EN), .RST(FIFOINIT[ 0]), .DATA(EIFIFO_DATA), .WRREQ(EIFIFO_WRREQ[ 0] & IO_EN & CE_R), .RDREQ(EIFIFO0_OE & DSP_EN & CE_R & !EIFIFO_CPU[0]), .Q(EIFIFO_Q[ 0]), .COUNT(EIFIFO_COUNT[ 0]));
	CLIO_DSP_FIFO EIFIFO1  (.CLK(CLK), .EN(EN), .RST(FIFOINIT[ 1]), .DATA(EIFIFO_DATA), .WRREQ(EIFIFO_WRREQ[ 1] & IO_EN & CE_R), .RDREQ(EIFIFO1_OE & DSP_EN & CE_R & !EIFIFO_CPU[1]), .Q(EIFIFO_Q[ 1]), .COUNT(EIFIFO_COUNT[ 1]));
	CLIO_DSP_FIFO EIFIFO2  (.CLK(CLK), .EN(EN), .RST(FIFOINIT[ 2]), .DATA(EIFIFO_DATA), .WRREQ(EIFIFO_WRREQ[ 2] & IO_EN & CE_R), .RDREQ(EIFIFO2_OE & DSP_EN & CE_R & !EIFIFO_CPU[2]), .Q(EIFIFO_Q[ 2]), .COUNT(EIFIFO_COUNT[ 2]));
	CLIO_DSP_FIFO EIFIFO3  (.CLK(CLK), .EN(EN), .RST(FIFOINIT[ 3]), .DATA(EIFIFO_DATA), .WRREQ(EIFIFO_WRREQ[ 3] & IO_EN & CE_R), .RDREQ(EIFIFO3_OE & DSP_EN & CE_R & !EIFIFO_CPU[3]), .Q(EIFIFO_Q[ 3]), .COUNT(EIFIFO_COUNT[ 3]));
	CLIO_DSP_FIFO EIFIFO4  (.CLK(CLK), .EN(EN), .RST(FIFOINIT[ 4]), .DATA(EIFIFO_DATA), .WRREQ(EIFIFO_WRREQ[ 4] & IO_EN & CE_R), .RDREQ(EIFIFO4_OE & DSP_EN & CE_R & !EIFIFO_CPU[4]), .Q(EIFIFO_Q[ 4]), .COUNT(EIFIFO_COUNT[ 4]));
	CLIO_DSP_FIFO EIFIFO5  (.CLK(CLK), .EN(EN), .RST(FIFOINIT[ 5]), .DATA(EIFIFO_DATA), .WRREQ(EIFIFO_WRREQ[ 5] & IO_EN & CE_R), .RDREQ(EIFIFO5_OE & DSP_EN & CE_R & !EIFIFO_CPU[5]), .Q(EIFIFO_Q[ 5]), .COUNT(EIFIFO_COUNT[ 5]));
	CLIO_DSP_FIFO EIFIFO6  (.CLK(CLK), .EN(EN), .RST(FIFOINIT[ 6]), .DATA(EIFIFO_DATA), .WRREQ(EIFIFO_WRREQ[ 6] & IO_EN & CE_R), .RDREQ(EIFIFO6_OE & DSP_EN & CE_R & !EIFIFO_CPU[6]), .Q(EIFIFO_Q[ 6]), .COUNT(EIFIFO_COUNT[ 6]));
	CLIO_DSP_FIFO EIFIFO7  (.CLK(CLK), .EN(EN), .RST(FIFOINIT[ 7]), .DATA(EIFIFO_DATA), .WRREQ(EIFIFO_WRREQ[ 7] & IO_EN & CE_R), .RDREQ(EIFIFO7_OE & DSP_EN & CE_R & !EIFIFO_CPU[7]), .Q(EIFIFO_Q[ 7]), .COUNT(EIFIFO_COUNT[ 7]));
	CLIO_DSP_FIFO EIFIFO8  (.CLK(CLK), .EN(EN), .RST(FIFOINIT[ 8]), .DATA(EIFIFO_DATA), .WRREQ(EIFIFO_WRREQ[ 8] & IO_EN & CE_R), .RDREQ(EIFIFO8_OE & DSP_EN & CE_R & !EIFIFO_CPU[8]), .Q(EIFIFO_Q[ 8]), .COUNT(EIFIFO_COUNT[ 8]));
	CLIO_DSP_FIFO EIFIFO9  (.CLK(CLK), .EN(EN), .RST(FIFOINIT[ 9]), .DATA(EIFIFO_DATA), .WRREQ(EIFIFO_WRREQ[ 9] & IO_EN & CE_R), .RDREQ(EIFIFO9_OE & DSP_EN & CE_R & !EIFIFO_CPU[9]), .Q(EIFIFO_Q[ 9]), .COUNT(EIFIFO_COUNT[ 9]));
	CLIO_DSP_FIFO EIFIFO10 (.CLK(CLK), .EN(EN), .RST(FIFOINIT[10]), .DATA(EIFIFO_DATA), .WRREQ(EIFIFO_WRREQ[10] & IO_EN & CE_R), .RDREQ(EIFIFO10_OE & DSP_EN & CE_R & !EIFIFO_CPU[10]), .Q(EIFIFO_Q[10]), .COUNT(EIFIFO_COUNT[10]));
	CLIO_DSP_FIFO EIFIFO11 (.CLK(CLK), .EN(EN), .RST(FIFOINIT[11]), .DATA(EIFIFO_DATA), .WRREQ(EIFIFO_WRREQ[11] & IO_EN & CE_R), .RDREQ(EIFIFO11_OE & DSP_EN & CE_R & !EIFIFO_CPU[11]), .Q(EIFIFO_Q[11]), .COUNT(EIFIFO_COUNT[11]));
	CLIO_DSP_FIFO EIFIFO12 (.CLK(CLK), .EN(EN), .RST(FIFOINIT[12]), .DATA(EIFIFO_DATA), .WRREQ(EIFIFO_WRREQ[12] & IO_EN & CE_R), .RDREQ(EIFIFO12_OE & DSP_EN & CE_R & !EIFIFO_CPU[12]), .Q(EIFIFO_Q[12]), .COUNT(EIFIFO_COUNT[12]));
	wire [ 3: 0] EIFIFO_STAT[15] = '{{EIFIFO_COUNT[0]},
	                                 {EIFIFO_COUNT[1]},
												{EIFIFO_COUNT[2]},
												{EIFIFO_COUNT[3]},
											   {EIFIFO_COUNT[4]},
											   {EIFIFO_COUNT[5]},
											   {EIFIFO_COUNT[6]},
											   {EIFIFO_COUNT[7]},
											   {EIFIFO_COUNT[8]},
											   {EIFIFO_COUNT[9]},
	                                 {EIFIFO_COUNT[10]},
											   {EIFIFO_COUNT[11]},
											   {EIFIFO_COUNT[12]},
												{4'b0000},
												{4'b0000}};
	
	wire EOFIFO_STAT_OE = DSP_EI_ADDR >= 8'hE0 && DSP_EI_ADDR <= 8'hE3;	//0x0E0-0x0E3
	wire EOFIFO0_WE = DSP_EO_ADDR == 8'hF0 && DSP_EO_WE;	//0x3F0
	wire EOFIFO1_WE = DSP_EO_ADDR == 8'hF1 && DSP_EO_WE;	//0x3F1
	wire EOFIFO2_WE = DSP_EO_ADDR == 8'hF2 && DSP_EO_WE;	//0x3F2
	wire EOFIFO3_WE = DSP_EO_ADDR == 8'hF3 && DSP_EO_WE;	//0x3F3

	wire         EOFIFO_RDREQ[4] = '{(DMA_FROM_DSP_READ[1] || DMA_FROM_DSP_READ[0]) && DMA_CHAN[3:0] == 4'h0,
	                                 (DMA_FROM_DSP_READ[1] || DMA_FROM_DSP_READ[0]) && DMA_CHAN[3:0] == 4'h1,
												(DMA_FROM_DSP_READ[1] || DMA_FROM_DSP_READ[0]) && DMA_CHAN[3:0] == 4'h2,
												(DMA_FROM_DSP_READ[1] || DMA_FROM_DSP_READ[0]) && DMA_CHAN[3:0] == 4'h3};
	bit  [15: 0] EOFIFO_Q[4];
	bit  [ 3: 0] EOFIFO_COUNT[4];
	CLIO_DSP_FIFO EOFIFO0 (.CLK(CLK), .EN(EN), .RST(FIFOINIT[16]), .DATA(DSP_EO_DATA), .WRREQ(EOFIFO0_WE & DSP_EN & CE_R), .RDREQ(EOFIFO_RDREQ[0] & IO_EN & CE_R), .Q(EOFIFO_Q[0]), .COUNT(EOFIFO_COUNT[0]));
	CLIO_DSP_FIFO EOFIFO1 (.CLK(CLK), .EN(EN), .RST(FIFOINIT[17]), .DATA(DSP_EO_DATA), .WRREQ(EOFIFO1_WE & DSP_EN & CE_R), .RDREQ(EOFIFO_RDREQ[1] & IO_EN & CE_R), .Q(EOFIFO_Q[1]), .COUNT(EOFIFO_COUNT[1]));
	CLIO_DSP_FIFO EOFIFO2 (.CLK(CLK), .EN(EN), .RST(FIFOINIT[18]), .DATA(DSP_EO_DATA), .WRREQ(EOFIFO2_WE & DSP_EN & CE_R), .RDREQ(EOFIFO_RDREQ[2] & IO_EN & CE_R), .Q(EOFIFO_Q[2]), .COUNT(EOFIFO_COUNT[2]));
	CLIO_DSP_FIFO EOFIFO3 (.CLK(CLK), .EN(EN), .RST(FIFOINIT[19]), .DATA(DSP_EO_DATA), .WRREQ(EOFIFO3_WE & DSP_EN & CE_R), .RDREQ(EOFIFO_RDREQ[3] & IO_EN & CE_R), .Q(EOFIFO_Q[3]), .COUNT(EOFIFO_COUNT[3]));
	wire [ 3: 0] EOFIFO_STAT[4] = '{{EOFIFO_COUNT[0]},
	                                {EOFIFO_COUNT[1]},
											  {EOFIFO_COUNT[2]},
											  {EOFIFO_COUNT[3]}};
											  
	bit          EIFIFO_OE_LATCH[13];
	bit          EOFIFO_WE_LATCH[4];
	wire EIFIFO_BUF_WE = (DSP_ADDR[7:0] >= 9'h070 && DSP_ADDR[7:0] <= 9'h07E && DSP_EIRAM_WE);//0x070-0x07E
	//A DSP read of an input FIFO (bump 0x0F0-0x0FC, read 0x070-0x07C) returns the current head,
	//EIFIFO_Q, read in the DSP cycle itself. It used to return EIFIFO_BUF loaded by the previous
	//read, i.e. the sample before the head: instruments that bump the left then the right sample of
	//a stereo frame (the BIOS audio CD player's fixedstereo16swap.dsp) got their channels swapped.
	//The head must not be copied between the DSP cycles: the FIFO is an MLAB written in the cycle
	//after the CE_R edge that registers the write, so a copy taken then can catch the old content of
	//the slot being written when the FIFO was empty (a sample one lap old: a crackle on hardware,
	//invisible in simulation). In the DSP cycle the MLAB is stable.
	//A read of an empty FIFO returns 0 and does not pop: the head slot of an empty FIFO holds a word
	//one lap old. Opera returns 0 for a channel without data.
	bit  [15: 0] EIFIFO_BUF[13];	//the value written by the CPU (EIFIFO_CPU)
//	bit          EIFIFO_BUF_EMPTY[13];
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) begin
			EIFIFO_OE_LATCH <= '{13{0}};
			EOFIFO_WE_LATCH <= '{4{0}};
			EIFIFO_BUF <= '{13{'0}};
			EIFIFO_CPU <= '{13{0}};
//			EIFIFO_BUF_EMPTY <= '{13{0}};
		end
		else if (EN && CE_R) begin
			if (DSP_EN) begin
				EIFIFO_OE_LATCH[ 0] <= EIFIFO0_OE;
				EIFIFO_OE_LATCH[ 1] <= EIFIFO1_OE;
				EIFIFO_OE_LATCH[ 2] <= EIFIFO2_OE;
				EIFIFO_OE_LATCH[ 3] <= EIFIFO3_OE;
				EIFIFO_OE_LATCH[ 4] <= EIFIFO4_OE;
				EIFIFO_OE_LATCH[ 5] <= EIFIFO5_OE;
				EIFIFO_OE_LATCH[ 6] <= EIFIFO6_OE;
				EIFIFO_OE_LATCH[ 7] <= EIFIFO7_OE;
				EIFIFO_OE_LATCH[ 8] <= EIFIFO8_OE;
				EIFIFO_OE_LATCH[ 9] <= EIFIFO9_OE;
				EIFIFO_OE_LATCH[10] <= EIFIFO10_OE;
				EIFIFO_OE_LATCH[11] <= EIFIFO11_OE;
				EIFIFO_OE_LATCH[12] <= EIFIFO12_OE;
				EOFIFO_WE_LATCH[ 0] <= EOFIFO0_WE;
				EOFIFO_WE_LATCH[ 1] <= EOFIFO1_WE;
				EOFIFO_WE_LATCH[ 2] <= EOFIFO2_WE;
				EOFIFO_WE_LATCH[ 3] <= EOFIFO3_WE;
				
				if ((EIFIFO_OE || EIFIFO_OE2) && DSP_EI_OE) begin
					EIFIFO_CPU[DSP_EI_ADDR[3:0]] <= 0;
//					EIFIFO_BUF_EMPTY[DSP_EI_ADDR[3:0]] <= 1;
				end
			end
			if (IO_EN) begin
				if (EIFIFO_BUF_WE) begin
					EIFIFO_BUF[DSP_ADDR[3:0]] <= DSP_DI;
					EIFIFO_CPU[DSP_ADDR[3:0]] <= 1;
//					EIFIFO_BUF_EMPTY[DSP_ADDR[3:0]] <= 0;
				end
			end
		end
	end
	
`ifdef DEBUG
	assign DBG_FIFO_CHANGE = (EIFIFO0_OE|EIFIFO1_OE|EIFIFO2_OE|EIFIFO3_OE|EIFIFO4_OE|EIFIFO5_OE|EIFIFO6_OE|EIFIFO7_OE|EIFIFO8_OE|EIFIFO9_OE|EIFIFO10_OE|EIFIFO11_OE|EIFIFO12_OE
	                          |EIFIFO_WRREQ[0]|EIFIFO_WRREQ[1]|EIFIFO_WRREQ[2]|EIFIFO_WRREQ[3]|EIFIFO_WRREQ[4]|EIFIFO_WRREQ[5]|EIFIFO_WRREQ[6]|EIFIFO_WRREQ[7]|EIFIFO_WRREQ[8]|EIFIFO_WRREQ[9]|EIFIFO_WRREQ[10]|EIFIFO_WRREQ[1]|EIFIFO_WRREQ[12]
									  //|EOFIFO0_WE|EOFIFO1_WE|EOFIFO2_WE|EOFIFO3_WE|EOFIFO_RDREQ[0]|EOFIFO_RDREQ[1]|EOFIFO_RDREQ[2]|EOFIFO_RDREQ[3]
									  ) & CE_R;
`endif
	
	bit  [ 3: 0] EOFIFO_FLUSH;
	wire EOFIFO_FLUSH_WE = (DSP_EO_ADDR == 8'hFD) && DSP_EO_WE;	//0x3FD
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) begin
			EOFIFO_FLUSH <= '0;
		end
		else begin
			if (EN && DSP_EN && CE_R) begin
				EOFIFO_FLUSH <= '0;
				if (EOFIFO_FLUSH_WE) begin
					EOFIFO_FLUSH <= DSP_EO_DATA[3:0];
				end
			end
		end
	end
	
	bit  [15: 0] AUDIO[2];
	wire AUDIO_WE = (DSP_EO_ADDR == 8'hFE || DSP_EO_ADDR == 8'hFF) && DSP_EO_WE;	//0x3FE-0x3FF
	always @(posedge CLK or negedge RST_N) begin
		bit  [8: 0] CLK_DIV;
		bit  [15: 0] TEMP;
		
		if (!RST_N) begin
			AUDIO <= '{2{'0}};
			AUDWS <= 0;
		end
		else begin
			if (EN && DSP_EN && CE_R) begin
				if (AUDIO_WE) begin
					AUDIO[DSP_EO_ADDR[0]] <= DSP_EO_DATA;
					
`ifdef DEBUG
					TEMP = $signed(DSP_EO_DATA) >= $signed(AUDIO[0]) ? $signed(DSP_EO_DATA) - $signed(AUDIO[0]) : $signed(AUDIO[0]) - $signed(DSP_EO_DATA);
					if (!DSP_EO_ADDR[0]) DBG_HOOK <= (TEMP >= 16'h4000);
`endif
				end
				AUDWS <= 0;
			end
			
			if (ACLK_CE) begin
				CLK_DIV <= CLK_DIV + 9'd1;
				if (CLK_DIV == 9'h17F) begin
					CLK_DIV <= '0;
					AUDWS <= 1;
				end
			end
		end
	end
	assign AUDIOL = AUDIO[0];
	assign AUDIOR = AUDIO[1];
	
	assign DSP_EI_DATA = EIRAM_OE ? EIRAM_DATA : 
						      EIFIFO_STAT_OE ? {12'b0000_0000_0000,EIFIFO_STAT[DSP_EI_ADDR[3:0]]} :
						      EOFIFO_STAT_OE ? {12'b0000_0000_0000,EOFIFO_STAT[DSP_EI_ADDR[1:0]]} :
						      EIFIFO_OE || EIFIFO_OE2 ? (EIFIFO_CPU[DSP_EI_ADDR[3:0]] ? EIFIFO_BUF[DSP_EI_ADDR[3:0]] : EIFIFO_COUNT[DSP_EI_ADDR[3:0]] == 4'd0 ? 16'h0000 : EIFIFO_Q[DSP_EI_ADDR[3:0]]) :
								NOISE_OE ? NOISE[15:0] :
						      AUDLOCK_OE ? {AUDLOCK,15'b000_0000_0000_0000} :
						      SEMASTAT_OE ? {12'b0000_0000_0000,DSP_SEMAPHORE_STAT} :
						      SEMAPHORE_OE ? DSP_SEMAPHORE :
						      PC_OE ? DSP_PC :
						      CNTR_OE ? CNTR : '0;
								
	assign DSP_DO = DSP_ADDR[7:0] >= 8'h00 && DSP_ADDR[7:0] <= 8'h0F ? DSP_EORAM_DO :
	                DSP_ADDR[7:0] == 8'hEB ? {AUDLOCK,15'b000_0000_0000_0000} : 
	                DSP_ADDR[7:0] == 8'hEC ? {12'b0000_0000_0000,DSP_SEMAPHORE_STAT} :
	                DSP_ADDR[7:0] == 8'hED ? DSP_SEMAPHORE :
	                DSP_ADDR[7:0] == 8'hEE ? DSP_CPUINT :
	                DSP_ADDR[7:0] == 8'hEF ? RELOAD :
						 '0;
	
	CLIO_VIDEO VIDEO
	(
		.CLK(CLK),
		.RST_N(RST_N),
		.EN(EN),
		
		.PAL(PAL),
		
		.VCE(VCE),
		.HSYNC_N(HSYNC_N),
		.VSYNC_N(VSYNC_N),
		
		.HCNT(HCNT),
		.VCNT(VCNT),
		.FLD(FLD),
		
		.S(S),
		.LSC_N(LPSC_N),
		.RSC_N(RPSC_N),
		.PCSC(PCSC),
		
		.AD(AD),
		.DE(DE),
		
		.HINTREPOL_DISABLE(HINTREPOL_DISABLE),
		.VINTREPOL_DISABLE(VINTREPOL_DISABLE),
		.DBG_EXT(DBG_EXT)
	);
	
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) begin
			VINT0_REQ <= 0;
			VINT1_REQ <= 0;
		end
		else if (VCE) begin
			if (HCNT == 0) begin
				if (VCNT == VINT0[8:0]) VINT0_REQ <= 1; 
				if (VCNT == VINT1[8:0]) VINT1_REQ <= 1;
			end
			
			if (VINT0_ACK && VINT0_REQ) VINT0_REQ <= 0; 
			if (VINT1_ACK && VINT1_REQ) VINT1_REQ <= 0; 
		end
	end

endmodule


