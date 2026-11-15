import P3DO_PKG::*;

module MADAM_SPORT
(
	input              CLK,
	input              RST_N,
	input              EN,
	
	input              CE_R,
	input              CE_F,
	
	input      [31: 0] MDTI,
	input BusState_t   BUS_STATE,
	input              GRANT,
	output AddrGenCtl_t AG_CTL,
	output reg             LINE0,
	input              LMIDLINE_REQ,
	input              RMIDLINE_REQ,
	
	input              CLUTXEN,
	input              VSCTXEN,
	
	output reg         CLUTWR_REQ,
	input              CLUTWR_ACK,
	input              CLUTWR_FORCE,
	output reg         VIDOUT_REQ,
	input              VIDOUT_PFL,
	output reg         VIDMID_REQ,
	output reg         VIDMID_CURR,
	output reg         VIDMID_FIRST,
	input              VIDOUT_ACK,
	input              VIDMID_ACK,   // Game Bub port: see MADAM_ARB
	
	input              VCE,
	input              PCSC,
	output             LSC,
	output             RSC,
	
	output             FIELD,
	output             V480
	
`ifdef DEBUG
	                   ,
	output reg [ 7: 0] VIDOUT_WAIT_CNT,VIDMID_WAIT_CNT
`endif
	
);

	CLUTCtrl_t  CLUT_DMACTL;
	
	BusState_t BUS_STATE_FF;
	always @(posedge CLK or negedge RST_N) begin		
		if (!RST_N) begin
			BUS_STATE_FF <= BUS_IDLE;
		end
		else if (EN && CE_R) begin
			BUS_STATE_FF <= BUS_STATE;
		end
	end 
	
	wire CTRL_RD = (BUS_STATE_FF == CLUT_CTRL1);
	bit          CLUT_DMACTL_UPDATED;
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) begin
			CLUT_DMACTL <= '0;
			CLUT_DMACTL_UPDATED <= 0;
		end
		else if (EN) begin
			if (VCE) begin
				CLUT_DMACTL_UPDATED <= 0;
			end
			
			if (CE_R) begin
				if (CTRL_RD) begin
					CLUT_DMACTL <= MDTI;
					CLUT_DMACTL_UPDATED <= 1;
				end
			end
		end
	end 

	bit  [10: 0] HCOUNT;
	bit  [ 9: 0] VCOUNT;
	bit          VZ/*,VN*/,FN,FC/*,VR,VD*/,VL;
	always @(posedge CLK or negedge RST_N) begin
		bit  [ 3: 0] PCSC_OLD;
		
		if (!RST_N) begin
			HCOUNT <= '0;
			VCOUNT <= '0;
			{VZ/*,VN*/,FN,FC/*,VR,VD*/,VL} <= '0;
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
				end
			end
			
			case (HCOUNT)
				11'd0: VZ <= PCSC;
//				11'd1: VN <= PCSC;
				11'd2: FN <= PCSC;
				11'd3: FC <= PCSC;
//				11'd4: VR <= PCSC;
//				11'd5: VD <= PCSC;
				11'd6: VL <= PCSC;
			endcase
		end
	end 
	assign FIELD = FN;
	assign V480 = CLUT_DMACTL.V480;
	
	//CLUT transfer
	bit  [ 8: 0] LINE;
	bit          ENVIDDMA;
	always @(posedge CLK or negedge RST_N) begin
		bit          ALLOW;
		bit          PEND;
		bit          PEND2;
		
		if (!RST_N) begin
			CLUTWR_REQ <= 0;
			LINE0 <= 0;
			ALLOW <= 0;
			// synopsys translate_off
			LINE <= '0;
			ENVIDDMA <= 0;
			// synopsys translate_on
		end
		else begin
			if (EN && VCE) begin
				if (HCOUNT == 11'd7) begin
					if (VZ) begin
						ALLOW <= 0;
						PEND2 <= 1;
					end
					if (FC) begin
						ALLOW <= 1;
						LINE <= '0;
						ENVIDDMA <= 0;
					end
				end
				
				if (HCOUNT == 11'd1290 - 11'd10 - 1 && ALLOW && CLUTXEN) begin
					/*if (VZ) begin
						LINE <= '0;
					end else*/ if (LINE) begin
						LINE <= LINE - 9'd1;
					end
					if (LINE == 9'd1 || FC) begin
						PEND <= 1;
					end
				end
				
				if (CLUT_DMACTL_UPDATED) begin
					LINE <= CLUT_DMACTL.LINE;
					ENVIDDMA <= CLUT_DMACTL.ENVIDDMA;
					ALLOW <= (CLUT_DMACTL.LINE != '0);
				end
			end
			
			if (EN && CE_R) begin
				if (PEND) begin
					PEND <= 0;
					CLUTWR_REQ <= 1;
				end
				
				if (CLUTWR_REQ && CLUTWR_ACK) begin
					CLUTWR_REQ <= 0;
				end
				
				LINE0 <= 0;
				if (PEND2) begin
					PEND2 <= 0;
					LINE0 <= 1;
				end
			end
		end
	end 
	
	wire CLUT_TRANS = (BUS_STATE_FF == CLUT_TRANSFER1);
	bit          CLUT_TRANS_EXEC;
	always @(posedge CLK or negedge RST_N) begin
		bit  [ 5: 0] CNT;
		bit          PEND;
		
		if (!RST_N) begin
			CLUT_TRANS_EXEC <= 0;
			CNT <= '0;
		end
		else begin
			if (EN && CE_R) begin
				if (CLUT_TRANS) begin
					PEND <= 1;
				end
			end
			
			if (EN && VCE) begin
				if (PEND && HCOUNT >= 11'd1340 - 1) begin
					CNT <= '0;
					PEND <= 0;
					// Game Bub port: an entry with no optional words (length 0)
					// shifts none out (Opera; the patent: "a number of optional
					// additional control words ... if any"). The count wrapped
					// to 64 words before, the next entry's header among them.
					CLUT_TRANS_EXEC <= CLUTXEN && CLUT_DMACTL.LEN != '0;
				end
				
				if (CLUT_TRANS_EXEC) begin
					CNT <= CNT + 6'd1;
					if (CNT == CLUT_DMACTL.LEN - 6'd1) 
						CLUT_TRANS_EXEC <= 0;
				end
			end
		end
	end 
	
	//Video transfer
	bit          VIDEO_TRANS_PEND;
	bit          VIDEO_TRANS_EXEC;
	bit  [ 9: 0] VIDEO_CNT;
	always @(posedge CLK or negedge RST_N) begin		
		bit          PEND;
		
		if (!RST_N) begin
			VIDOUT_REQ <= 0;
			VIDEO_TRANS_PEND <= 0;
			VIDEO_TRANS_EXEC <= 0;
			VIDEO_CNT <= '0;
		end else begin
			if (EN && VCE) begin
				if (HCOUNT == 11'd1490 - 11'd20 - 1 && ENVIDDMA && VSCTXEN) begin
					PEND <= 1;
					VIDEO_TRANS_PEND <= 1;
				end
				if (HCOUNT == 11'd10 - 1 && VIDEO_TRANS_PEND) begin
					VIDEO_TRANS_PEND <= 0;
					VIDEO_CNT <= '0;
					VIDEO_TRANS_EXEC <= 1;
				end
				if (VIDEO_TRANS_EXEC && HCOUNT[0]) begin
					VIDEO_CNT <= VIDEO_CNT + 10'd1;
					if (VIDEO_CNT == 10'd640 - 1) 
						VIDEO_TRANS_EXEC <= 0;
				end
			end
			
			if (EN && CE_R) begin
				if (PEND) begin
					PEND <= 0;
					VIDOUT_REQ <= 1;
				end
				if (VIDOUT_REQ && VIDOUT_ACK) begin
					VIDOUT_REQ <= 0;
				end
`ifdef DEBUG
				if (VIDOUT_REQ) VIDOUT_WAIT_CNT <= VIDOUT_WAIT_CNT + 1'd1;
				else VIDOUT_WAIT_CNT <= '0;
`endif
			end
		end
	end 
	
	wire VID_SEQ = (BUS_STATE_FF >= VID_PREINIT1 && BUS_STATE_FF <= VID_MIDCURR1);
	wire VID_PREV_TRANS = (BUS_STATE_FF == VID_PREV1);
	wire VID_CURR_TRANS = (BUS_STATE_FF == VID_CURR1);

	always @(posedge CLK or negedge RST_N) begin
		bit          LMID_PEND,RMID_PEND;
		
		if (!RST_N) begin
			VIDMID_REQ <= 0;
			VIDMID_CURR <= 0;
			VIDMID_FIRST <= 0;
			{LMID_PEND,RMID_PEND} <= '0;
		end
		else if (EN && CE_R) begin
			if (VID_PREV_TRANS || VID_CURR_TRANS) begin
				VIDMID_FIRST <= 1;
				VIDMID_CURR <= VIDOUT_PFL;
			end
			if (BUS_STATE_FF == VID_MIDINIT1 && VIDMID_FIRST) begin
				VIDMID_CURR <= ~VIDMID_CURR;
			end
			if (BUS_STATE_FF == VID_MIDPREV1 || BUS_STATE_FF == VID_MIDCURR1) begin
				VIDMID_FIRST <= 0;
			end
			
			if (LMIDLINE_REQ && VIDEO_TRANS_EXEC) LMID_PEND <= 1;
			if (RMIDLINE_REQ && VIDEO_TRANS_EXEC) RMID_PEND <= 1;
			
			// Game Bub port: a pending mid-line request is posted only when no
			// video sequence is on the bus: posting sets VIDMID_CURR, which a
			// running sequence still reads to pick the DMA register it
			// advances (VID_MIDINIT1), and the original's posting one CE_R
			// after the previous grant advanced the other half's register.
			if (LMID_PEND && !VIDMID_REQ && !VID_SEQ) begin
				LMID_PEND <= 0;
				VIDMID_REQ <= 1;
				VIDMID_CURR <= ~VIDOUT_PFL;
			end
			else if (RMID_PEND && !VIDMID_REQ && !VID_SEQ) begin
				RMID_PEND <= 0;
				VIDMID_REQ <= 1;
				VIDMID_CURR <= VIDOUT_PFL;
			end
			if (VIDMID_REQ && VIDMID_ACK) begin
				VIDMID_REQ <= 0;
			end
`ifdef DEBUG
				if (VIDMID_REQ) VIDMID_WAIT_CNT <= VIDMID_WAIT_CNT + 1'd1;
				else VIDMID_WAIT_CNT <= '0;
`endif
		end
	end
	
	assign LSC = ((CLUT_TRANS_EXEC | (VIDEO_TRANS_EXEC & (VIDEO_CNT[0] ^  VIDOUT_PFL) & HCOUNT[0])) & VCE);
	assign RSC = ((CLUT_TRANS_EXEC | (VIDEO_TRANS_EXEC & (VIDEO_CNT[0] ^ ~VIDOUT_PFL) & HCOUNT[0])) & VCE);
	
	always_comb begin
		AG_CTL = '0;
		
		case (BUS_STATE)
			CLUT_PREINIT1: begin
				AG_CTL.DMA_OWN_SEL = 0;
				AG_CTL.DMA_GROUP_ADDR = 7'h60;
				AG_CTL.DMA_GROUP_ADDR_SEL = 1;
				AG_CTL.DMA_GROUP_HOLD = 1;
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = 2'h0;
				AG_CTL.DMA_ADDR_SEL = 1;
				AG_CTL.DMA_ADDER_CTL = 4'b0000;
			end
			
			CLUT_INIT0: begin
				AG_CTL.DMA_OWN_SEL = 0;
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = {1'b0,~CLUTWR_FORCE};
				AG_CTL.DMA_ADDR_SEL = 1;
				AG_CTL.DMA_ADDER_CTL = 4'b0000;
			end
			
			CLUT_INIT1: begin
				AG_CTL.DMA_OWN_SEL = 0;
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = {1'b0,~CLUTWR_FORCE};
				AG_CTL.DMA_ADDR_SEL = 1;
				AG_CTL.DMA_ADDER_CTL = 4'b0000;
			end
			
			CLUT_CTRL0: begin
				AG_CTL.DMA_OWN_SEL = 1;
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = {1'b0,~CLUTWR_FORCE};
				AG_CTL.DMA_REG_WRITE_SEL = 0;
				AG_CTL.DMA_REG_WRITE_CTL = 3'h0;
				AG_CTL.DMA_REG_WRITE_EN = 1;
				AG_CTL.DMA_ADDR_SEL = 1;
				AG_CTL.DMA_ADDER_CTL = 4'b0000;
			end
			
			CLUT_CTRL1: begin
				AG_CTL.DMA_OWN_SEL = 0;
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = 2'h0;
				AG_CTL.DMA_ADDR_SEL = 1;
				AG_CTL.DMA_ADDER_CTL = 4'b0001;
			end
			
			CLUT_CURR0,CLUT_PREV0,CLUT_NEXT0: begin
				AG_CTL.DMA_OWN_SEL = 1;
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = 2'h0;
				AG_CTL.DMA_REG_WRITE_SEL = 0;
				AG_CTL.DMA_REG_WRITE_CTL = 3'h0;
				AG_CTL.DMA_REG_WRITE_EN = 1;
				AG_CTL.DMA_ADDER_CTL = 4'b0001;
			end
			
			CLUT_CURR1: begin
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = 2'h0;
				AG_CTL.DMA_REG_WRITE_SEL = 0;
				AG_CTL.DMA_REG_WRITE_CTL = 3'h5;
				AG_CTL.DMA_REG_WRITE_EN = CLUT_DMACTL.LDCURR;
				AG_CTL.DMA_ADDER_CTL = 4'b0001;
			end
			
			CLUT_PREV1: begin
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = 2'h0;
				AG_CTL.DMA_REG_WRITE_SEL = 0;
				AG_CTL.DMA_REG_WRITE_CTL = 3'h4;
				AG_CTL.DMA_REG_WRITE_EN = CLUT_DMACTL.LDPREV;
				AG_CTL.DMA_ADDER_CTL = 4'b0001;
			end
			
			CLUT_NEXT1: begin
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = 2'h0;
				AG_CTL.DMA_REG_WRITE_SEL = 0;
				AG_CTL.DMA_REG_WRITE_CTL = 3'h1;
				AG_CTL.DMA_REG_WRITE_EN = 1;
				AG_CTL.DMA_ADDER_CTL = 4'b0001;
			end
			
			// Header bit 18 (VDL_RELSEL, named NPABS here) set: the next
			// VDL address is relative, word 3 + the address after it
			// (entry + 16 bytes; patent: REL = target - PC - 4; Opera
			// next += entry + 16). Clear: word 3 as loaded in CLUT_NEXT1.
			// REL0 (the address bus holds word 3's address, OFFS_FF word
			// 3) writes the next VDL address (1) as address + OFFS + 1 and
			// reads the list pointer (0, word 3's address) back onto the
			// bus; REL1 then writes the pointer as address + 1, the first
			// optional word, for CLUT_TRANSFER.
			CLUT_NEXT_REL0: begin
				AG_CTL.DMA_OWN_SEL = 1;
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = 2'h0;
				AG_CTL.DMA_REG_WRITE_SEL = 0;
				AG_CTL.DMA_REG_WRITE_CTL = 3'h1;
				AG_CTL.DMA_REG_WRITE_EN = CLUT_DMACTL.NPABS;
				AG_CTL.DMA_ADDR_SEL = 1;
				AG_CTL.DMA_ADDER_CTL = 4'b0110;
			end
			
			CLUT_NEXT_REL1: begin
				AG_CTL.DMA_OWN_SEL = 1;
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = 2'h0;
				AG_CTL.DMA_REG_WRITE_SEL = 0;
				AG_CTL.DMA_REG_WRITE_CTL = 3'h0;
				AG_CTL.DMA_REG_WRITE_EN = 1;
				AG_CTL.DMA_ADDR_SEL = 1;
				AG_CTL.DMA_ADDER_CTL = 4'b0001;
			end
			
			CLUT_TRANSFER0: begin
				AG_CTL.DMA_OWN_SEL = 1;
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = 2'h0;
				AG_CTL.DMA_REG_WRITE_SEL = 0;
				AG_CTL.DMA_REG_WRITE_CTL = 3'h2;
				AG_CTL.DMA_REG_WRITE_EN = 1;
				AG_CTL.DMA_ADDR_SEL = 1;
				AG_CTL.DMA_ADDER_CTL = 4'b0111;
			end
			
			CLUT_TRANSFER1: begin
				AG_CTL.DMA_OWN_SEL = 0;
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = 2'h0;
				AG_CTL.DMA_ADDR_SEL = 1;
			end
			
			CLUT_MIDINIT0,CLUT_MIDINIT1: begin
				AG_CTL.DMA_OWN_SEL = 0;
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = 2'h2;
				AG_CTL.DMA_ADDR_SEL = 1;
			end
			
			CLUT_MIDTRANS0,CLUT_MIDTRANS1: begin
				AG_CTL.DMA_OWN_SEL = 0;
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = 2'h2;
				AG_CTL.DMA_ADDR_SEL = 1;
			end
			
			VID_PREINIT1: begin
				AG_CTL.DMA_OWN_SEL = 0;
				AG_CTL.DMA_GROUP_ADDR = 7'h64;
				AG_CTL.DMA_GROUP_ADDR_SEL = 1;
				AG_CTL.DMA_GROUP_HOLD = 1;
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = 2'h0;
				AG_CTL.DMA_ADDR_SEL = 1;
			end
			
			VID_INIT0: begin
				AG_CTL.DMA_OWN_SEL = 0;
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = 2'h0;
				AG_CTL.DMA_ADDR_SEL = 1;
			end
			
			VID_INIT1: begin
				AG_CTL.DMA_OWN_SEL = 0;
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = 2'h0;
				AG_CTL.DMA_ADDR_SEL = 1;
			end
			
			VID_PREV0: begin
				AG_CTL.DMA_OWN_SEL = 1;
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = 2'h0;
				AG_CTL.DMA_REG_WRITE_SEL = 0;
				AG_CTL.DMA_REG_WRITE_CTL = 3'h6;
				AG_CTL.DMA_REG_WRITE_EN = 1;
				AG_CTL.DMA_ADDR_SEL = 1;
				AG_CTL.DMA_ADDER_CTL = 4'b0111;
			end
			
			VID_PREV1: begin
				AG_CTL.DMA_OWN_SEL = 1;
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = 2'h0;
				AG_CTL.DMA_REG_WRITE_SEL = 0;
				AG_CTL.DMA_REG_WRITE_CTL = 3'h4;
				AG_CTL.DMA_REG_WRITE_EN = ~VIDOUT_PFL | CLUT_DMACTL.V480;
				AG_CTL.DMA_ADDR_SEL = 1;
				AG_CTL.DMA_ADDER_CTL = {1'b1,CLUT_DMACTL.DISPMODE};
			end
			
			VID_CALC0: begin
				AG_CTL.DMA_OWN_SEL = 0;
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = 2'h1;
				AG_CTL.DMA_ADDR_SEL = 1;
			end
			
			VID_CALC1: begin
				AG_CTL.DMA_OWN_SEL = 1;
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = 2'h1;
				AG_CTL.DMA_REG_WRITE_SEL = 0;
				AG_CTL.DMA_REG_WRITE_CTL = 3'h4;
				AG_CTL.DMA_REG_WRITE_EN = ~CLUT_DMACTL.PREVSEL;
				AG_CTL.DMA_ADDR_SEL = 1;
				AG_CTL.DMA_ADDER_CTL = 4'b0000;
			end
			
			VID_CURR0: begin
				AG_CTL.DMA_OWN_SEL = 1;
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = 2'h1;
				AG_CTL.DMA_REG_WRITE_SEL = 0;
				AG_CTL.DMA_REG_WRITE_CTL = 3'h7;
				AG_CTL.DMA_REG_WRITE_EN = 1;
				AG_CTL.DMA_ADDR_SEL = 1;
				AG_CTL.DMA_ADDER_CTL = 4'b0111;
			end
			
			VID_CURR1: begin
				AG_CTL.DMA_OWN_SEL = 1;
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = 2'h1;
				AG_CTL.DMA_REG_WRITE_SEL = 0;
				AG_CTL.DMA_REG_WRITE_CTL = 3'h5;
				AG_CTL.DMA_REG_WRITE_EN = VIDOUT_PFL | CLUT_DMACTL.V480;
				AG_CTL.DMA_ADDR_SEL = 1;
				AG_CTL.DMA_ADDER_CTL = {1'b1,CLUT_DMACTL.DISPMODE};
			end
			
			VID_MIDPREINIT1: begin
				AG_CTL.DMA_OWN_SEL = 0;
				AG_CTL.DMA_GROUP_ADDR = 7'h64;
				AG_CTL.DMA_GROUP_ADDR_SEL = 1;
				AG_CTL.DMA_GROUP_HOLD = 1;
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = {1'b1,VIDMID_CURR};
				AG_CTL.DMA_ADDR_SEL = 1;
			end
			
			VID_MIDINIT0: begin
				AG_CTL.DMA_OWN_SEL = 0;
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = {1'b1,VIDMID_CURR};
				AG_CTL.DMA_ADDR_SEL = 1;
			end
			
			VID_MIDINIT1: begin
				AG_CTL.DMA_OWN_SEL = 0;
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = {1'b1,VIDMID_CURR};
				AG_CTL.DMA_ADDR_SEL = 1;
			end
			
			VID_MIDPREV0: begin
				AG_CTL.DMA_OWN_SEL = 1;
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = 2'h2;
				AG_CTL.DMA_REG_WRITE_SEL = 0;
				AG_CTL.DMA_REG_WRITE_CTL = 3'h6;
				AG_CTL.DMA_REG_WRITE_EN = 1;
				AG_CTL.DMA_ADDR_SEL = 1;
				AG_CTL.DMA_ADDER_CTL = 4'b0111;
			end
			
			VID_MIDCURR0: begin
				AG_CTL.DMA_OWN_SEL = 1;
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = 2'h3;
				AG_CTL.DMA_REG_WRITE_SEL = 0;
				AG_CTL.DMA_REG_WRITE_CTL = 3'h7;
				AG_CTL.DMA_REG_WRITE_EN = 1;
				AG_CTL.DMA_ADDR_SEL = 1;
				AG_CTL.DMA_ADDER_CTL = 4'b0111;
			end
			
			VID_MIDPREV1,
			VID_MIDCURR1: begin
				AG_CTL.DMA_OWN_SEL = 0;
				AG_CTL.DMA_REG_READ_SEL = 1;
				AG_CTL.DMA_REG_READ_CTL = {1'b1,VIDMID_CURR};
				AG_CTL.DMA_ADDR_SEL = 1;
			end
			
			default:;
		endcase
	end

endmodule
