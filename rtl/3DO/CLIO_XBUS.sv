import P3DO_PKG::*; 

module CLIO_XBUS
(
	input              CLK,
	input              RST_N,
	input              EN,
	
	input              CE_R,
	input              CE_F,
	
	input      [ 9: 2] A,
	input      [31: 0] DI,
	output reg [31: 0] DO,
	input              WR,
	input              RD,
	output reg         RDY,
	input              DMA_ALLOW,
	output reg         DMA_ACT,
	output reg         DMA_RDY,
	output reg [31: 0] DMA_DO,
	output reg         DMA_RST,         // XB_DMARESET: flush CLIO's expansion DMA FIFO
	
	input      [ 7: 0] EDI,
	output reg [ 7: 0] EDO,
	output reg         ESTR_N,
	output reg         EWRT_N,
	output reg         ECMD_N,
	output reg         ESEL_N,
	output reg         ERST_N,
	input              ERDY_N,
	input              EINT_N
);

	bit          XB_CPUHASXBUS;
	bit          XB_DIR;
	bit          XB_DMAON;
	bit          XB_RESET;
	bit  [31: 0] XFERCNT;
	
	typedef enum bit [3:0] {
		XBUS_IDLE,
		XBUS_SEL,
		XBUS_RDPOLL,
		XBUS_WRPOLL,
		XBUS_RDSTAT,
		XBUS_WRCOM,
		XBUS_WRDATA,
		XBUS_RDDATA,
		XBUS_STROBE,
		XBUS_WAIT,
		XBUS_END
	} XbusState_t;
	XbusState_t XBUS_ST;
	
	bit  [31: 0] DMA_BUF;
//	bit          DMA_PAUSE;
	always @(posedge CLK or negedge RST_N) begin
		bit         IO_WR_PEND,IO_RD_PEND;
		bit         IS_DMA;
		bit         STROBE_DELAY;
		bit [ 1: 0] DMA_BYTE_CNT;
		
		if (!RST_N) begin
			{ESTR_N,EWRT_N,ECMD_N,ESEL_N} <= '1;
			XBUS_ST <= XBUS_IDLE;
			{IO_WR_PEND,IO_RD_PEND} <= '0;
			RDY <= 1;
			DMA_RDY <= 0;
//			DMA_PAUSE <= 0;
			DMA_BYTE_CNT <= '0;
			DMA_RST <= 0;
			
			XB_DIR <= 0;
			XB_RESET <= 0;
			XB_DMAON <= 0;
			XB_CPUHASXBUS <= 0;
		end
		else if (EN & CE_R) begin			
			if (WR) begin IO_WR_PEND <= 1; RDY <= 0; end
			if (RD) begin IO_RD_PEND <= 1; RDY <= 0; end
			
			DMA_RDY <= 0;
			DMA_RST <= 0;
			ESTR_N <= 1;
			case (XBUS_ST)
				XBUS_IDLE: begin
					if (IO_WR_PEND) begin
						casex ({A[9:2],2'b00})
							10'h000: begin XB_DIR <= XB_DIR | DI[9];
						                  XB_DMAON <= XB_DMAON | DI[11];
												XB_RESET <= XB_RESET | DI[15];
												// XB_DMARESET (bit 14, "also does a flush", Portfolio
												// clio.h): the DMA stops and its partial word and
												// CLIO's FIFO are dropped
												if (DI[14]) begin XB_DMAON <= 0; DMA_BYTE_CNT <= '0; DMA_DO <= '0; DMA_RST <= 1; end end
							10'h004: begin XB_CPUHASXBUS <= XB_CPUHASXBUS & ~DI[7]; 
												XB_DIR <= XB_DIR & ~DI[9];
						                  XB_DMAON <= XB_DMAON & ~DI[11];
						                  XB_RESET <= XB_RESET & ~DI[15]; end
							10'h00C: begin XFERCNT <= DI; end
							10'h10x,
							10'h11x,
							10'h12x,
							10'h13x: begin XB_CPUHASXBUS <= 1; XBUS_ST <= XBUS_SEL; end
							10'h14x,
							10'h15x,
							10'h16x,
							10'h17x: begin XBUS_ST <= XBUS_WRPOLL; end
							10'h18x,
							10'h19x,
							10'h1Ax,
							10'h1Bx: begin XBUS_ST <= XBUS_WRCOM; end
							default:;
						endcase
						IO_WR_PEND <= 0;
						if (A[9:8] != 2'b01) RDY <= 1;
						IS_DMA <= 0;
					end
					else if (IO_RD_PEND) begin
						casex ({A[9:2],2'b00})
							10'h000,
							10'h004: DO <= {16'h0000,XB_RESET,3'b000,XB_DMAON,1'b0,XB_DIR,1'b0,XB_CPUHASXBUS,7'b000_0000};
							10'h014: DO <= 32'h00004000;
							10'h14x,
							10'h15x,
							10'h16x,
							10'h17x: begin XBUS_ST <= XBUS_RDPOLL; end
							10'h18x,
							10'h19x,
							10'h1Ax,
							10'h1Bx: begin XBUS_ST <= XBUS_RDSTAT; end
							10'h1Cx,
							10'h1Dx,
							10'h1Ex,
							10'h1Fx: begin XBUS_ST <= XBUS_RDDATA; end
							default: DO <= '0;
						endcase
						IO_RD_PEND <= 0;
						if (A[9:8] != 2'b01) RDY <= 1;
						IS_DMA <= 0;
					end
					else if (XB_DMAON && !XB_CPUHASXBUS && DMA_ALLOW) begin
						XFERCNT <= XFERCNT - 1'd1;
						IS_DMA <= 1;
						XBUS_ST <= XB_DIR ? XBUS_WRDATA : XBUS_RDDATA;
					end
//					if (DMA_RD && DMA_PAUSE) DMA_PAUSE <= 0;
				end
				
				XBUS_SEL: begin
					EDO <= DI[7:0];
					ESEL_N <= 0;
					ECMD_N <= 1;
					EWRT_N <= 0;
					XBUS_ST <= XBUS_STROBE;
				end
				
				XBUS_RDPOLL: begin
					ESEL_N <= 0;
					ECMD_N <= 0;
					EWRT_N <= 1;
					XBUS_ST <= XBUS_STROBE;
				end
				
				XBUS_WRPOLL: begin
					EDO <= DI[7:0];
					ESEL_N <= 0;
					ECMD_N <= 0;
					EWRT_N <= 0;
					XBUS_ST <= XBUS_STROBE;
				end
				
				XBUS_RDSTAT: begin
					ESEL_N <= 1;
					ECMD_N <= 0;
					EWRT_N <= 1;
					XBUS_ST <= XBUS_STROBE;
				end
				
				XBUS_WRCOM: begin
					EDO <= DI[7:0];
					ESEL_N <= 1;
					ECMD_N <= 0;
					EWRT_N <= 0;
					XBUS_ST <= XBUS_STROBE;
				end
				
				XBUS_WRDATA: begin
					EDO <= DI[7:0];
					ESEL_N <= 1;
					ECMD_N <= 1;
					EWRT_N <= 0;
					XBUS_ST <= XBUS_STROBE;
				end
				
				XBUS_RDDATA: begin
					ESEL_N <= 1;
					ECMD_N <= 1;
					EWRT_N <= 1;
					XBUS_ST <= XBUS_STROBE;
				end
				
				XBUS_STROBE: begin
					ESTR_N <= 0;
					STROBE_DELAY <= ~STROBE_DELAY;
					if (STROBE_DELAY) begin
						XBUS_ST <= XBUS_WAIT;
					end
				end
				
				XBUS_WAIT: begin
					XBUS_ST <= XBUS_END;
				end
				
				XBUS_END: begin
					DO <= {24'h000000,EDI};
					if (!IS_DMA) RDY <= 1;
					else begin
						DMA_DO <= {DMA_DO[23:0],EDI};
						DMA_BYTE_CNT <= DMA_BYTE_CNT + 2'd1;
						if (DMA_BYTE_CNT == 2'd3) begin
							DMA_RDY <= 1;
						end
						if (XFERCNT == '0) begin
							XB_DMAON <= 0;
							DMA_BYTE_CNT <= '0;
							DMA_RDY <= 1;
						end
					end
					ESEL_N <= 1;
					ECMD_N <= 1;
					EWRT_N <= 1;
					XBUS_ST <= XBUS_IDLE;
				end
				
			endcase
		end
	end
	assign ERST_N = ~XB_RESET;
	
	assign DMA_ACT = (XB_DMAON /*&& !XB_CPUHASXBUS && XFERCNT != '0*/);
	
endmodule
