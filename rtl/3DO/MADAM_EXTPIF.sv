import P3DO_PKG::*;

module MADAM_EXTPIF
(
	input              CLK,
	input              RST_N,
	input              EN,
	
	input              CE_R,
	input              CE_F,
	
	input              MCLK_PH1,
	input              MCLK_PH2,
	input              CPU_GRANT,
	input              CPU_RW,
	input              CPU_SEL,
	
	input      [31: 0] MDTI,
	input BusState_t   BUS_STATE,
	input              BUS_PB,
	input              GRANT,
	input              DMA_REG_OVF,
	input              DMA_REG_ZERO,
	input              AG_PBI,
	output AddrGenCtl_t AG_CTL,
	
	output reg         CPU_REQ,
	output reg         DMA_REQ,
	input              DMA_ACK,
	output reg [ 2: 0] NEXT,
	
	input              PLAYER_INT,
	
	output     [10: 0] H_CNT,
	output     [ 9: 0] V_CNT,
	output             FORCE_CLUT,
	
	input              VCE,
	input              DMAREQ,
	input      [ 4: 0] DMACH,//
	output reg [ 2: 0] CCODE,
	input              CREADY_N,
	input              PCSC
	
`ifdef DEBUG
	                   ,
	output reg [ 7: 0] DBG_FRAME_CNT
`endif
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
	
	wire BUS_PREINIT = (BUS_STATE_FF == EXTP_INIT0 || BUS_STATE_FF == EXTP_INIT2);
	wire BUS_INIT = (BUS_STATE_FF == EXTP_INIT1 || BUS_STATE_FF == EXTP_INIT3);
	wire BUS_READ = (BUS_STATE_FF == EXTP_READ1);
	wire BUS_WRITE = (BUS_STATE_FF == EXTP_WRITE1);
	
	bit  [ 2: 0] CPU_CCODE;
	always @(posedge CLK or negedge RST_N) begin		
		if (!RST_N) begin
			CPU_REQ <= 0;
			CPU_CCODE <= '0;
		end
		else if (EN && CE_R) begin
			CPU_CCODE <= '0;
			if (CPU_GRANT) begin
				if (CPU_SEL && !CPU_REQ) begin
					CPU_CCODE <= CPU_RW ? 3'h1 : 3'h3;
					CPU_REQ <= 1;
				end
				else if (CPU_SEL && CPU_REQ && !CREADY_N && MCLK_PH2) begin
					CPU_REQ <= 0;
				end
			end
		end
	end
	
	bit  [ 4: 0] DMA_CHAN;
	always @(posedge CLK or negedge RST_N) begin		
		if (!RST_N) begin
			DMA_REQ <= 0;
		end
		else if (EN && CE_R) begin
			if (DMAREQ) begin
				DMA_CHAN <= DMACH;
				DMA_REQ <= 1;
			end
			if (DMA_REQ && DMA_ACK) begin
				DMA_REQ <= 0;
			end
		end
	end 
	wire DMA_DIR = (DMA_CHAN >= 5'h10);
	
	bit  [ 1: 0] BURST_CNT;
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) begin
			BURST_CNT <= '0;
		end
		else if (EN && CE_R) begin
			if (BUS_PREINIT && !BUS_PB && !BLOCK_END) begin
				BURST_CNT <= 2'd0;
			end
			if (BUS_READ || BUS_WRITE) begin
				BURST_CNT <= BURST_CNT + 2'd1;
			end
		end
	end 
	wire         BURST_LAST = (BURST_CNT == (DMA_CHAN == 5'h14 ? 2'd3 : 2'd2));
	
	bit          BLOCK_END,BLOCK_CONTINUE;
	bit          BLOCK_AND_LEN_END;
	bit          NEXT_ZERO;
	// LOOP2 reads the next starting address (AG_MDTO = the stack value read in
	// LOOP1). Zero means no loop: the transfer is complete (WO 94/10641, loop
	// test; "DMA operation is not allowed to be pointed at ... address zero")
	wire         LOOP_NEXT_ZERO = ~|MDTI[23:2];
	always @(posedge CLK or negedge RST_N) begin		
		
		if (!RST_N) begin
			{BLOCK_END,BLOCK_CONTINUE} <= '0;
			BLOCK_AND_LEN_END <= 0;
			NEXT_ZERO <= 0;
		end
		else if (EN && CE_R) begin
			if (BUS_WRITE || BUS_READ) begin
				BLOCK_END <= DMA_REG_OVF;
				BLOCK_CONTINUE <= DMA_REG_OVF && !BURST_LAST && (DMA_CHAN != 5'h14);
			end
			if (BUS_STATE_FF == EXTP_LOOP0 && BLOCK_END) begin
				BLOCK_AND_LEN_END <= 1;
			end
			if (BUS_STATE_FF == EXTP_LOOP2) begin
				NEXT_ZERO <= LOOP_NEXT_ZERO;
			end
			if (BUS_STATE_FF == EXTP_LOOP3) begin
				BLOCK_END <= 0;
				BLOCK_AND_LEN_END <= 0;
			end
		end
	end
	
	always_comb begin		
		CCODE <= '0;
		if (CPU_GRANT) begin
			CCODE <= CPU_CCODE;
		end
		else if (GRANT) begin
			if (BUS_INIT) begin
				CCODE <= 3'h2;
			end
			if ((BUS_READ || BUS_WRITE) && !AG_PBI && !DMA_REG_OVF && !BURST_LAST) begin
				CCODE <= 3'h2;
			end
			if (BUS_STATE_FF == EXTP_LOOP2 && (!BLOCK_CONTINUE || LOOP_NEXT_ZERO)) begin
				CCODE <= 3'h7;
			end
			// the info code after 7: 2 = burst end, 3 = the length ran out and
			// the channel loops (interrupt), 4 = it ran out with no next buffer:
			// the transfer is complete (interrupt, CLIO stops requesting)
			if (BUS_STATE_FF == EXTP_LOOP3) begin
				CCODE <= !BLOCK_AND_LEN_END ? 3'h2 : NEXT_ZERO ? 3'h4 : 3'h3;
			end
		end
//		else if (PLAYER_INT) begin
//			CCODE <= 3'h7;
//		end
	end
	
	always_comb begin
		AG_CTL = '0;
		NEXT = {2'b00,DMA_DIR};
		
		case (BUS_STATE)
			EXTP_PREINIT1: begin
				AG_CTL.DMA_GROUP_ADDR = {DMA_CHAN,2'h0};
				AG_CTL.DMA_GROUP_ADDR_SEL = 1;
				AG_CTL.DMA_GROUP_HOLD = 1;
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = 2'h0;
				AG_CTL.DMA_ADDR_SEL = 1;
				AG_CTL.DMA_ADDER_CTL = 4'b0000;
			end
			
			EXTP_INIT0: begin
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = 2'h0;
				AG_CTL.DMA_ADDR_SEL = 1;
				AG_CTL.DMA_ADDER_CTL = 4'b0000;
			end
			
			EXTP_INIT1: begin
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = 2'h1;
				AG_CTL.DMA_ADDR_SEL = 1;
				AG_CTL.DMA_ADDER_CTL = 4'b0000;
			end
			
			EXTP_READ0: begin
				AG_CTL.DMA_OWN_SEL = 1;
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = 2'h0;
				AG_CTL.DMA_REG_WRITE_SEL = 0;
				AG_CTL.DMA_REG_WRITE_CTL = {DMA_CHAN[0],2'h1};
				AG_CTL.DMA_REG_WRITE_EN = 1;
				AG_CTL.DMA_ADDR_SEL = 1;
				AG_CTL.DMA_ADDER_CTL = 4'b0010;
			end
			
			EXTP_READ1: begin
				AG_CTL.DMA_OWN_SEL = 1;
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = 2'h1;
				AG_CTL.DMA_REG_WRITE_SEL = 0;
				AG_CTL.DMA_REG_WRITE_CTL = {DMA_CHAN[0],2'h0};
				AG_CTL.DMA_REG_WRITE_EN = 1;
				AG_CTL.DMA_ADDR_SEL = 1;
				AG_CTL.DMA_ADDER_CTL = 4'b0001;
				NEXT = {1'b0,~(BURST_LAST|DMA_REG_OVF),DMA_DIR};
			end
			
			EXTP_PREINIT3: begin
				AG_CTL.DMA_GROUP_ADDR = {DMA_CHAN,2'h0};
				AG_CTL.DMA_GROUP_ADDR_SEL = 1;
				AG_CTL.DMA_GROUP_HOLD = 1;
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = 2'h0;
				AG_CTL.DMA_ADDR_SEL = 1;
				AG_CTL.DMA_ADDER_CTL = 4'b0000;
			end
			
			EXTP_INIT2: begin
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = 2'h0;
				AG_CTL.DMA_ADDR_SEL = 1;
				AG_CTL.DMA_ADDER_CTL = 4'b0000;
			end
			
			EXTP_INIT3: begin
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = 2'h1;
				AG_CTL.DMA_ADDR_SEL = 1;
				AG_CTL.DMA_ADDER_CTL = 4'b0000;
			end
			
			EXTP_WRITE0: begin
				AG_CTL.DMA_OWN_SEL = 1;
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = 2'h0;
				AG_CTL.DMA_REG_WRITE_SEL = 0;
				AG_CTL.DMA_REG_WRITE_CTL = {DMA_CHAN[0],2'h1};
				AG_CTL.DMA_REG_WRITE_EN = 1;
				AG_CTL.DMA_ADDR_SEL = 1;
				AG_CTL.DMA_ADDER_CTL = 4'b0010;
			end
			
			EXTP_WRITE1: begin
				AG_CTL.DMA_OWN_SEL = 1;
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = 2'h1;
				AG_CTL.DMA_REG_WRITE_SEL = 0;
				AG_CTL.DMA_REG_WRITE_CTL = {DMA_CHAN[0],2'h0};
				AG_CTL.DMA_REG_WRITE_EN = 1;
				AG_CTL.DMA_ADDR_SEL = 1;
				AG_CTL.DMA_ADDER_CTL = 4'b0001;
				NEXT = {1'b0,~(BURST_LAST|DMA_REG_OVF),DMA_DIR};
			end
			
			EXTP_LOOP0: begin
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = 2'h3;
				AG_CTL.DMA_ADDR_SEL = 1;
				AG_CTL.DMA_ADDER_CTL = 4'b0000;
			end
			
			EXTP_LOOP1: begin
				AG_CTL.DMA_OWN_SEL = 1;
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = 2'h2;
				AG_CTL.DMA_REG_WRITE_SEL = 0;
				AG_CTL.DMA_REG_WRITE_CTL = {DMA_CHAN[0],2'h1};
				AG_CTL.DMA_REG_WRITE_EN = BLOCK_END;
				AG_CTL.DMA_ADDR_SEL = 1;
				AG_CTL.DMA_ADDER_CTL = 4'b0000;
			end
			
			EXTP_LOOP2: begin
				AG_CTL.DMA_OWN_SEL = 1;
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = 2'h3;
				AG_CTL.DMA_REG_WRITE_SEL = 0;
				AG_CTL.DMA_REG_WRITE_CTL = {DMA_CHAN[0],2'h0};
				AG_CTL.DMA_REG_WRITE_EN = BLOCK_END;
				AG_CTL.DMA_ADDR_SEL = 1;
				AG_CTL.DMA_ADDER_CTL = 4'b0000;
				NEXT = {BLOCK_CONTINUE && !LOOP_NEXT_ZERO,1'b0,DMA_DIR};
			end
			
			EXTP_LOOP3: begin
				AG_CTL.DMA_ZERO_SEL = 1;
				AG_CTL.DMA_REG_WRITE_SEL = 0;
				AG_CTL.DMA_REG_WRITE_CTL = {DMA_CHAN[0],2'h3};
				AG_CTL.DMA_REG_WRITE_EN = 0;
				AG_CTL.DMA_ADDR_SEL = 1;
				AG_CTL.DMA_ADDER_CTL = 4'b0000;
			end
			
			EXTP_REINIT1: begin
				AG_CTL.DMA_ADDR_SEL = 1;
				AG_CTL.DMA_ADDER_CTL = 4'b0000;
			end
		
			default:;
		endcase
	end
	
	bit  [10: 0] HCOUNT;
	bit  [ 9: 0] VCOUNT;
	bit          /*VZ,VN,FN,*/FC/*,VR,VD*/,VL;
	always @(posedge CLK or negedge RST_N) begin
		bit  [ 3: 0] PCSC_OLD;
		
		if (!RST_N) begin
			HCOUNT <= '0;
			VCOUNT <= '0;
			{/*VZ,VN,FN,*/FC/*,VR,VD*/,VL} <= '0;
			PCSC_OLD <= '0;
		end
		else if (EN && VCE) begin
			PCSC_OLD <= {PCSC_OLD[2:0],PCSC};
			
			HCOUNT <= HCOUNT + 11'd1;
			if (PCSC_OLD == 4'b0011) begin
				HCOUNT <= '0;
				VCOUNT <= VCOUNT + 1'd1;
				if (VL) begin
					VCOUNT <= '0;
`ifdef DEBUG
					DBG_FRAME_CNT <= DBG_FRAME_CNT + 1'd1;
`endif
				end
			end
			
			case (HCOUNT)
//				11'd0: VZ <= PCSC;
//				11'd1: VN <= PCSC;
//				11'd2: FN <= PCSC;
				11'd3: FC <= PCSC;
//				11'd4: VR <= PCSC;
//				11'd5: VD <= PCSC;
				11'd6: VL <= PCSC;
			endcase
		end
	end 
	assign H_CNT = HCOUNT;
	assign V_CNT = VCOUNT;
	assign FORCE_CLUT = FC;
	

endmodule
