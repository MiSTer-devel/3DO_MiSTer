import P3DO_PKG::*;

module MADAM_PLAYER
(
	input              CLK,
	input              RST_N,
	input              EN,
	
	input              CE_R,
	input              CE_F,
	
	input      [31: 0] MDTI,
	output     [31: 0] MDTO,
	input BusState_t   BUS_STATE,
	input              GRANT,
	input              DMA_REG_OVF,
	output AddrGenCtl_t AG_CTL,
	
	input              PLAYXEN,
	
	input              VCE,
	input      [10: 0] H_CNT,
	input      [ 9: 0] V_CNT,
	
	output reg         PLAY_REQ,
	output reg         PLAY_INT,
	
	output reg         REF_REQ,
	
	input              PBDI,
	output reg             PBDO,
	output reg             PBCLK,
	
	output reg [ 9: 0] DBG_WAIT_CNT
);

	BusState_t BUS_STATE_FF;
	always @(posedge CLK or negedge RST_N) begin		
		if (!RST_N) begin
			BUS_STATE_FF <= BUS_IDLE;
		end
		else if (EN && CE_R) begin
			BUS_STATE_FF <= BUS_STATE;
		end
	end 
	
	wire PLAY_ACK = (BUS_STATE_FF == PLAY_INIT0);
	
	bit          SHIFT_STROBE,SHIFT_LAST;
	bit  [ 4: 0] SHIFT_CNT;
	// GameBub: the data bit of each falling PBCLK edge is taken on the video
	// clock, CAP_DLY VCE clocks after the edge (the pad presents it right after
	// the edge and keeps it until the next one, at least 100 clocks later),
	// into a queue that the bus-clock side shifts in when it runs. MiSTer took
	// it on the bus clock (SHIFT_PEND), which the core's PAUSE stops: a pause
	// longer than a PBCLK period (8 us) lost a bit, and the pad words after it
	// arrived misaligned (phantom buttons: the "no more devices" 1s slid into
	// the pad word). Pauses are that long here: a VRAM page copy through the
	// SDRAM takes about 30 us.
	localparam bit [5:0] CAP_DLY = 6'd50;
	bit  [ 5: 0] CAP_CNT;
	bit  [31: 0] BITQ;
	bit  [ 5: 0] BITQ_WP, BITQ_RP;   // 32 entries
	bit          SHIFT_BIT;
	always @(posedge CLK or negedge RST_N) begin
		bit          ENABLE;
		bit          START_PEND,END_PEND;
		
		if (!RST_N) begin
			PBCLK <= 0;
			PLAY_REQ <= 0;
			PLAY_INT <= 0;
			ENABLE <= 0;
			START_PEND <= 0;
			END_PEND <= 0;
			CAP_CNT <= '0;
			BITQ_WP <= '0;
			BITQ_RP <= '0;
			// synopsys translate_off
			PEND <= 0;
			// synopsys translate_on
		end else begin
			if (EN && VCE) begin
				DBG_WAIT_CNT <= DBG_WAIT_CNT + 1'd1;
				
				if (CAP_CNT != 6'd0) begin
					CAP_CNT <= CAP_CNT - 6'd1;
					if (CAP_CNT == 6'd1) begin
						BITQ[BITQ_WP[4:0]] <= PBDI;
						BITQ_WP <= BITQ_WP + 6'd1;
					end
				end
				
				if (V_CNT <= 10'd7) begin
					PBCLK <= 1;
					DBG_WAIT_CNT <= '0;
				end else if (V_CNT <= 10'd15) begin
					PBCLK <= 0;
					ENABLE <= PLAYXEN;
					DBG_WAIT_CNT <= '0;
					BITQ_WP <= BITQ_RP;   // a frame's bits still queued by now are dropped
					CAP_CNT <= '0;
				end else if (V_CNT == 10'd16 && H_CNT == 11'd0 && ENABLE) begin
					START_PEND <= 1;
				end else if (V_CNT <= 10'd239 && ENABLE) begin
					if (H_CNT == 11'd100 - 1 || H_CNT == 11'd300 - 1 || H_CNT == 11'd500 - 1 || H_CNT == 11'd700 - 1 || H_CNT == 11'd0900 - 1 || H_CNT == 11'd1100 - 1 || H_CNT == 11'd1300 - 1 || H_CNT == 11'd1500 - 1) begin
						PBCLK <= 1;
					end
					if (H_CNT == 11'd200 - 1 || H_CNT == 11'd400 - 1 || H_CNT == 11'd600 - 1 || H_CNT == 11'd800 - 1 || H_CNT == 11'd1000 - 1 || H_CNT == 11'd1200 - 1 || H_CNT == 11'd1400 - 1 || H_CNT == 11'd1559 - 1) begin
						PBCLK <= 0;
						CAP_CNT <= CAP_DLY;
						
					end
				end else begin
					PBCLK <= 0;
					DBG_WAIT_CNT <= '0;
				end
				
				if (END_PEND) begin
					END_PEND <= 0;
					ENABLE <= 0;
				end
			end
			
			if (EN && CE_R) begin
				SHIFT_STROBE <= 0;
				if (START_PEND) begin
					SHIFT_CNT <= '0;
					SHIFT_LAST <= 0;
					PLAY_REQ <= 1;
					START_PEND <= 0;
				end
				else if (BITQ_RP != BITQ_WP) begin
					SHIFT_BIT <= BITQ[BITQ_RP[4:0]];
					BITQ_RP <= BITQ_RP + 6'd1;
					SHIFT_STROBE <= 1;
					SHIFT_CNT <= SHIFT_CNT + 5'd1;
					if (SHIFT_CNT == 5'd31) begin
						SHIFT_LAST <= 1;
						PLAY_REQ <= 1;
					end else begin
						SHIFT_LAST <= 0;
					end 
					DBG_WAIT_CNT <= '0;
				end
				
				if (PLAY_REQ && PLAY_ACK) begin
					PLAY_REQ <= 0;
				end
			
				PLAY_INT <= 0;
				if (DATA_WR && DMA_REG_OVF) begin
					PLAY_INT <= 1;
					END_PEND <= 1;
				end
			end
		end
	end 
	
	wire DATA_WR = (BUS_STATE_FF == PLAY_WRITE1);
	bit  [31: 0] SHF_REG;
	bit  [31: 0] BUF_OUT;
	always @(posedge CLK or negedge RST_N) begin
		bit          OUT;
		
		if (!RST_N) begin
			PBDO <= 0;
			SHF_REG <= '0;
		end
		else if (EN && CE_R) begin
			OUT <= 0;
			if (SHIFT_STROBE) begin
				{PBDO,SHF_REG} <= {SHF_REG,SHIFT_BIT};   // GameBub: the queued bit (was PBDI)
				OUT <= SHIFT_LAST;
			end
			if (OUT) begin
				BUF_OUT <= SHF_REG;
			end
		end
	end 
	
	wire REF_ACK = (BUS_STATE_FF == REF_INIT0);
	always @(posedge CLK or negedge RST_N) begin
		bit          REFRESH_PEND;
		
		if (!RST_N) begin
			REF_REQ <= 0;
			REFRESH_PEND <= 0;
		end else begin
			if (EN && VCE) begin
				if (H_CNT == 11'd0 || H_CNT == 11'd400 - 1 || H_CNT == 11'd1200 - 1) begin
					REFRESH_PEND <= 1;
				end
			end
			
			if (EN && CE_R) begin
				if (REFRESH_PEND) begin
					REF_REQ <= 1;
					REFRESH_PEND <= 0;
				end
				
				if (REF_REQ && REF_ACK) begin
					REF_REQ <= 0;
				end
			end
		end
	end 
	
	assign MDTO = BUF_OUT;
	
	always_comb begin
		AG_CTL = '0;
		
		case (BUS_STATE)
			PLAY_PREINIT1: begin
				AG_CTL.DMA_GROUP_ADDR = 7'h5C;
				AG_CTL.DMA_GROUP_ADDR_SEL = 1;
				AG_CTL.DMA_GROUP_HOLD = 1;
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = 2'h2;
				AG_CTL.DMA_ADDR_SEL = 1;
				AG_CTL.DMA_ADDER_CTL = 4'b0000;
			end
			
			PLAY_INIT0: begin
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = 2'h2;
				AG_CTL.DMA_ADDR_SEL = 1;
				AG_CTL.DMA_ADDER_CTL = 4'b0000;
			end
			
			PLAY_INIT1: begin
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = 2'h2;
				AG_CTL.DMA_ADDR_SEL = 1;
				AG_CTL.DMA_ADDER_CTL = 4'b0000;
			end
			
			PLAY_READ0: begin
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = 2'h2;
				AG_CTL.DMA_ADDR_SEL = 1;
				AG_CTL.DMA_ADDER_CTL = 4'b0000;
			end
			
			PLAY_READ1: begin
				AG_CTL.DMA_OWN_SEL = 1;
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = 2'h2;
				AG_CTL.DMA_REG_WRITE_SEL = 0;
				AG_CTL.DMA_REG_WRITE_CTL = 3'h6;
				AG_CTL.DMA_REG_WRITE_EN = 1;
				AG_CTL.DMA_ADDR_SEL = 1;
				AG_CTL.DMA_ADDER_CTL = 4'b0001;
			end
			
			PLAY_PREINIT3: begin
				AG_CTL.DMA_GROUP_ADDR = 7'h5C;
				AG_CTL.DMA_GROUP_ADDR_SEL = 1;
				AG_CTL.DMA_GROUP_HOLD = 1;
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = 2'h0;
				AG_CTL.DMA_ADDR_SEL = 1;
				AG_CTL.DMA_ADDER_CTL = 4'b0000;
			end
			
			PLAY_INIT2: begin
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = 2'h0;
				AG_CTL.DMA_ADDR_SEL = 1;
				AG_CTL.DMA_ADDER_CTL = 4'b0000;
			end
			
			PLAY_INIT3: begin
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = 2'h1;
				AG_CTL.DMA_ADDR_SEL = 1;
				AG_CTL.DMA_ADDER_CTL = 4'b0000;
			end
			
			PLAY_WRITE0: begin
				AG_CTL.DMA_OWN_SEL = 1;
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = 2'h0;
				AG_CTL.DMA_REG_WRITE_SEL = 0;
				AG_CTL.DMA_REG_WRITE_CTL = 3'h5;
				AG_CTL.DMA_REG_WRITE_EN = 1;
				AG_CTL.DMA_ADDR_SEL = 1;
				AG_CTL.DMA_ADDER_CTL = 4'b0010;
			end
			
			PLAY_WRITE1: begin
				AG_CTL.DMA_OWN_SEL = 1;
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = 2'h1;
				AG_CTL.DMA_REG_WRITE_SEL = 0;
				AG_CTL.DMA_REG_WRITE_CTL = 3'h4;
				AG_CTL.DMA_REG_WRITE_EN = 1;
				AG_CTL.DMA_ADDR_SEL = 1;
				AG_CTL.DMA_ADDER_CTL = 4'b0001;
			end
			
			REF_PREINIT1: begin
				AG_CTL.DMA_GROUP_ADDR = 7'h5C;
				AG_CTL.DMA_GROUP_ADDR_SEL = 1;
				AG_CTL.DMA_GROUP_HOLD = 1;
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = 2'h3;
				AG_CTL.DMA_ADDR_SEL = 1;
				AG_CTL.DMA_ADDER_CTL = 4'b0000;
			end
			
			REF_INIT0: begin
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = 2'h3;
				AG_CTL.DMA_ADDR_SEL = 1;
				AG_CTL.DMA_ADDER_CTL = 4'b0000;
			end
			
			REF_INIT1: begin
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = 2'h3;
				AG_CTL.DMA_ADDR_SEL = 1;
				AG_CTL.DMA_ADDER_CTL = 4'b0000;
			end
			
			REF_WRITE0,
			REF_WRITE1,
			REF_WRITE2: begin
				AG_CTL.DMA_OWN_SEL = 1;
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = 2'h3;
				AG_CTL.DMA_ADDR_SEL = 1;
				AG_CTL.DMA_ADDER_CTL = 4'b0000;
			end
			
			REF_WRITE3: begin
				AG_CTL.DMA_OWN_SEL = 1;
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = 2'h3;
				AG_CTL.DMA_REG_WRITE_SEL = 0;
				AG_CTL.DMA_REG_WRITE_CTL = 3'h7;
				AG_CTL.DMA_REG_WRITE_EN = 1;
				AG_CTL.DMA_ADDR_SEL = 1;
				AG_CTL.DMA_ADDER_CTL = 4'b0111;
			end
			
			default:;
		endcase
	end

endmodule
