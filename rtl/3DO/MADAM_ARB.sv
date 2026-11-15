import P3DO_PKG::*; 

module MADAM_ARB
(
	input              CLK,
	input              RST_N,
	input              EN,
	
	input              CE_R,
	input              CE_F,
	
	output reg         PHASE1,
	output reg         PHASE2,
	
	//CPU
	output reg         CPU_GRANT,
	input              CPU_READY,
	input AddrGenCtl_t CPU_AG_CTL,
	
	//AG
	input              PBI,
	
	//EXTP
	input              CLIO_REQ,
	input              EXTP_REQ,
	output reg         EXTP_ACK,
	output reg         EXTP_GRANT,
	input AddrGenCtl_t EXTP_AG_CTL,
	input      [ 2: 0] EXTP_NEXT,
	
	//SE
	input      [ 2: 0] SCOBLD_REQ,
	input      [ 2: 0] SCOB_SEL,
	input      [ 1: 0] SPRDATA_REQ,
	input      [ 1: 0] SPR_SEL,
	input              SPRDRAW_REQ,
	input      [ 2: 0] CFB_SEL,
	output reg         CFB_SUSPEND,
	input              SPRPAUS_REQ,
	input              SPREND_REQ,
	output reg         SE_ACK,
	output reg         SE_GRANT,
	input AddrGenCtl_t SE_AG_CTL,
	
	//SPORT
	input              CLUTWR_REQ,
	output reg         CLUTWR_ACK,
	input              VIDOUT_REQ,
	input              VIDMID_REQ,
	input              VIDMID_CURR,
	input              VIDMID_FIRST,
	output reg         VIDOUT_ACK,
	output reg         VIDMID_ACK,   // Game Bub port: the mid-line request's own acknowledge
	output reg         SPORT_GRANT,
	input AddrGenCtl_t SPORT_AG_CTL,
	
	//PLAYER
	input              PLAYER_REQ,
	input              REFRESH_REQ,
	output reg         PLAYER_GRANT,
	input AddrGenCtl_t PLAYER_AG_CTL,
		
	output BusState_t  BUS_STATE,
	output reg         BUS_PB,
	output AddrGenCtl_t DMA_CTL,
	input      [ 3: 0] DBG_EXT
	
`ifdef DEBUG
	                  
`endif
);
	
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) begin
			PHASE1 <= 0;
			PHASE2 <= 0;
		end
		else if (EN && CE_R) begin
			if (BUS_ST == EXTP_PREINIT1 || BUS_ST == EXTP_PREINIT3 || 
			    BUS_ST == PLAY_PREINIT1 || BUS_ST == PLAY_PREINIT3 || BUS_ST == REF_PREINIT1 || 
			    BUS_ST == CLUT_PREINIT1 || BUS_ST == VID_PREINIT1 || BUS_ST == VID_MIDPREINIT1 ||
				 BUS_ST == SCOB_PREINIT1 || BUS_ST == SCOB_PREINIT3 || BUS_ST == SCOB_PREINIT5 || BUS_ST == SCOB_PREINIT7 ||
				 BUS_ST == SPR_PREINIT1 || BUS_ST == SPR_PREINIT3) begin
				PHASE1 <= 0;
				PHASE2 <= 1;
			end else begin
				PHASE1 <= ~PHASE1;
				PHASE2 <= PHASE1;
			end
		end
	end 
	
	wire HI_PRIO_REQ = VIDMID_REQ | CLUTWR_REQ | VIDOUT_REQ | REFRESH_REQ | PLAYER_REQ | EXTP_REQ | SPRPAUS_REQ;
	BusState_t  BUS_ST;
	always @(posedge CLK or negedge RST_N) begin
		bit         CPU_GRANT_INT,EXTP_GRANT_INT,SE_GRANT_INT,SPORT_GRANT_INT,PLAYER_GRANT_INT;
		bit         BUS_PB_INT;
		BusState_t  PB_NEXT_ST;
		bit         SE_RUN;
		bit         SPRDRAW_RESTART;
		bit         VIDMID_PREV_CURR;
		
		if (!RST_N) begin
			BUS_ST <= BUS_IDLE;
			CPU_GRANT_INT <= 1;
			EXTP_GRANT_INT <= 0;
			SE_GRANT_INT <= 0;
			SPORT_GRANT_INT <= 0;
			PLAYER_GRANT_INT <= 0;
			BUS_PB_INT <= 0;
			
			CPU_GRANT <= 1;
			EXTP_GRANT <= 0;
			SE_GRANT <= 0;
			SPORT_GRANT <= 0;
			PLAYER_GRANT <= 0;
			SE_RUN <= 0;
			SPRDRAW_RESTART <= 0;
			CFB_SUSPEND <= 0;
			// synopsys translate_off
			VIDMID_PREV_CURR <= 0;
			// synopsys translate_on
		end
		else if (EN) begin
			if (CE_F) begin
			if (PHASE2) begin
				CPU_GRANT_INT <= 0;
			end
			
			if (CLUTWR_ACK && !CLUTWR_REQ) CLUTWR_ACK <= 0;
			// Game Bub port: the line-start and mid-line requests have an
			// acknowledge each. With the original shared one, a mid-line grant
			// while the line-start request was also pending acknowledged both:
			// MADAM_SPORT dropped the line-start request and the line got no
			// transfers (the rest of the frame a line behind).
			if (VIDOUT_ACK && !VIDOUT_REQ) VIDOUT_ACK <= 0;
			if (VIDMID_ACK && !VIDMID_REQ) VIDMID_ACK <= 0;
			if (SE_ACK && !SCOBLD_REQ) SE_ACK <= 0;
			if (SE_ACK && !SPRDATA_REQ) SE_ACK <= 0;
			if (EXTP_ACK && !EXTP_REQ) EXTP_ACK <= 0;
			
			case (BUS_ST)
				BUS_IDLE: if (PHASE2) begin
					if (CLIO_REQ) begin
						CPU_GRANT_INT <= 1;
					end
					else if (!CPU_READY && !SE_RUN && !HI_PRIO_REQ) begin
						CPU_GRANT_INT <= 1;
					end
					else if (VIDMID_REQ) begin	//priority 2
						VIDMID_ACK <= 1;
						VIDMID_PREV_CURR <= VIDMID_CURR;
						SPORT_GRANT_INT <= 1;
						SE_GRANT_INT <= 0;
						EXTP_GRANT_INT <= 0;
						BUS_ST <= VID_MIDPREINIT1;
					end
					else if (CLUTWR_REQ) begin	//priority 3
						CLUTWR_ACK <= 1;
						SPORT_GRANT_INT <= 1;
						SE_GRANT_INT <= 0;
						EXTP_GRANT_INT <= 0;
						BUS_ST <= CLUT_PREINIT1;
					end
					else if (VIDOUT_REQ) begin	//priority 3
						VIDOUT_ACK <= 1;
						SPORT_GRANT_INT <= 1;
						SE_GRANT_INT <= 0;
						EXTP_GRANT_INT <= 0;
						BUS_ST <= VID_PREINIT1;
					end
					else if (REFRESH_REQ) begin	//priority 4
						PLAYER_GRANT_INT <= 1;
						SE_GRANT_INT <= 0;
						EXTP_GRANT_INT <= 0;
						BUS_ST <= REF_PREINIT1;
					end
					else if (PLAYER_REQ) begin	//priority 5
						PLAYER_GRANT_INT <= 1;
						SE_GRANT_INT <= 0;
						EXTP_GRANT_INT <= 0;
						BUS_ST <= PLAY_PREINIT1;
					end
					else if (EXTP_REQ) begin	//priority 6
						EXTP_ACK <= 1;
						EXTP_GRANT_INT <= 1;
						SE_GRANT_INT <= 0;
						BUS_ST <= !EXTP_NEXT[0] ? EXTP_PREINIT1 : EXTP_PREINIT3;
					end
					else if ((SPRDRAW_REQ || SPRDRAW_RESTART || CFB_SUSPEND) && !SPRPAUS_REQ) begin	
						SE_GRANT_INT <= 1;
						CFB_SUSPEND <= 0;
						SPRDRAW_RESTART <= 0;
						BUS_ST <= CFB_INIT0;
					end
					else if (SPRDATA_REQ && !SPRPAUS_REQ) begin	//priority 7
						SE_GRANT_INT <= 1;
						BUS_ST <= SPRDATA_REQ == 2'd1 ? SPR_PREINIT1 : SPR_PREINIT3;
					end
					else if (SCOBLD_REQ && !SPRPAUS_REQ) begin	//priority 8
						SE_ACK <= 1;
						SE_GRANT_INT <= 1;
						SE_RUN <= 1;
						BUS_ST <= SCOBLD_REQ == 3'd1 ? SCOB_PREINIT1 : SCOBLD_REQ == 3'd2 ? SCOB_PREINIT3 : SCOBLD_REQ == 3'd3 ? SCOB_PREINIT5 : SCOB_PREINIT7;
					end
					else begin	//priority 9
						if (SE_RUN) begin
							if (SPREND_REQ) begin	
								SE_RUN <= 0;
								CPU_GRANT_INT <= 1;
							end else if (SPRPAUS_REQ) begin
								SE_GRANT_INT <= 0;
								CPU_GRANT_INT <= 1;
							end
						end else begin
							CPU_GRANT_INT <= 1;
						end
					end
				end
				
				//CLIO
				EXTP_PREINIT1: BUS_ST <= EXTP_INIT0;
				EXTP_INIT0: BUS_ST <= EXTP_INIT1;				
				EXTP_INIT1: BUS_ST <= EXTP_READ0;				
				EXTP_READ0: BUS_ST <= EXTP_READ1;				
				EXTP_READ1: begin
					if (EXTP_NEXT[1]) begin
						if (PBI) begin
							BUS_PB_INT <= 1;
							BUS_ST <= EXTP_PREINIT1;
						end
						else begin
							BUS_ST <= EXTP_READ0;
						end
					end 
					else begin
						BUS_ST <= EXTP_LOOP0;
					end
				end
				
				EXTP_PREINIT3: BUS_ST <= EXTP_INIT2;
				EXTP_INIT2: BUS_ST <= EXTP_INIT3;				
				EXTP_INIT3: BUS_ST <= EXTP_WRITE0;	
				EXTP_WRITE0: BUS_ST <= EXTP_WRITE1;				
				EXTP_WRITE1: begin
					if (EXTP_NEXT[1]) begin
						if (PBI) begin
							BUS_PB_INT <= 1;
							BUS_ST <= EXTP_PREINIT3;
						end
						else begin
							BUS_ST <= EXTP_WRITE0;
						end
					end 
					else begin
						BUS_ST <= EXTP_LOOP0;
					end
				end
				
				EXTP_LOOP0: BUS_ST <= EXTP_LOOP1;	
				EXTP_LOOP1: BUS_ST <= EXTP_LOOP2;
				EXTP_LOOP2: begin
					if (EXTP_NEXT[2]) begin
						BUS_ST <= EXTP_REINIT1;
					end 
					else begin
						BUS_ST <= EXTP_LOOP3;
					end
				end	
				EXTP_LOOP3: begin
					begin
						EXTP_GRANT_INT <= 0;
						if (!SE_RUN && !HI_PRIO_REQ) CPU_GRANT_INT <= 1;
						BUS_ST <= BUS_IDLE;
					end
				end
				EXTP_REINIT1: begin
					BUS_ST <= !EXTP_NEXT[0] ? EXTP_INIT0 : EXTP_INIT2;
				end
				
				//PLAYER
				PLAY_PREINIT1: BUS_ST <= PLAY_INIT0;	
				PLAY_INIT0: BUS_ST <= PLAY_INIT1;
				PLAY_INIT1: BUS_ST <= PLAY_READ0;
				PLAY_READ0: BUS_ST <= PLAY_READ1;
				PLAY_READ1: BUS_ST <= PLAY_PREINIT3;
				PLAY_PREINIT3: BUS_ST <= PLAY_INIT2;	
				PLAY_INIT2: BUS_ST <= PLAY_INIT3;				
				PLAY_INIT3: BUS_ST <= PLAY_WRITE0;
				PLAY_WRITE0: BUS_ST <= PLAY_WRITE1;
				PLAY_WRITE1: begin
					PLAYER_GRANT_INT <= 0;
					if (!SE_RUN && !HI_PRIO_REQ) CPU_GRANT_INT <= 1;
					BUS_ST <= BUS_IDLE;
				end
				
				REF_PREINIT1: BUS_ST <= REF_INIT0;	
				REF_INIT0: BUS_ST <= REF_INIT1;
				REF_INIT1: BUS_ST <= REF_WRITE0;
				REF_WRITE0: BUS_ST <= REF_WRITE1;
				REF_WRITE1: BUS_ST <= REF_WRITE2;
				REF_WRITE2: BUS_ST <= REF_WRITE3;
				REF_WRITE3: begin
					PLAYER_GRANT_INT <= 0;
					if (!SE_RUN && !HI_PRIO_REQ) CPU_GRANT_INT <= 1;
					BUS_ST <= BUS_IDLE;
				end
				
				//SCOB
				SCOB_PREINIT1: BUS_ST <= SCOB_INIT0;
				SCOB_INIT0: BUS_ST <= SCOB_INIT1;
				SCOB_INIT1: begin
					if (BUS_PB_INT) begin
						BUS_ST <= PB_NEXT_ST;
					end
					else begin
						BUS_ST <= SCOB_FLAG0;
					end
				end
				SCOB_FLAG0: BUS_ST <= SCOB_FLAG1;
				SCOB_FLAG1: begin
					if (PBI) begin
						BUS_PB_INT <= 1;
						PB_NEXT_ST <= SCOB_NEXT0;
						BUS_ST <= SCOB_PREINIT1;
					end
					else begin
						BUS_ST <= SCOB_NEXT0;
					end
				end
				SCOB_NEXT0: BUS_ST <= SCOB_NEXT1;
				SCOB_NEXT1: begin
					if (SCOB_SEL[0]) begin
						BUS_ST <= SCOB_NEXT_REL0;
					end 
					else if (PBI) begin
						BUS_PB_INT <= 1;
						PB_NEXT_ST <= SCOB_SOURCE0;
						BUS_ST <= SCOB_PREINIT1;
					end
					else begin
						BUS_ST <= SCOB_SOURCE0;
					end
				end
				SCOB_NEXT_REL0: BUS_ST <= SCOB_NEXT_REL1;
				SCOB_NEXT_REL1: begin
//					if (PBI) begin
//						BUS_PB_INT <= 1;
//						PB_NEXT_ST <= SCOB_SOURCE0;
//						BUS_ST <= SCOB_PREINIT1;
//					end
//					else begin
						BUS_ST <= SCOB_SOURCE0;
//					end
				end
				SCOB_SOURCE0: BUS_ST <= SCOB_SOURCE1;
				SCOB_SOURCE1: begin
					if (SCOB_SEL[0]) begin
						BUS_ST <= SCOB_SOURCE_REL0;
					end 
					else if (PBI) begin
						BUS_PB_INT <= 1;
						PB_NEXT_ST <= SCOB_PIPPTR0;
						BUS_ST <= SCOB_PREINIT1;
					end
					else begin
						BUS_ST <= SCOB_PIPPTR0;
					end
				end
				SCOB_SOURCE_REL0: BUS_ST <= SCOB_SOURCE_REL1;
				SCOB_SOURCE_REL1: begin
//					if (PBI) begin
//						BUS_PB_INT <= 1;
//						PB_NEXT_ST <= SCOB_PIPPTR0;
//						BUS_ST <= SCOB_PREINIT1;
//					end
//					else begin
						BUS_ST <= SCOB_PIPPTR0;
//					end
				end
				SCOB_PIPPTR0: BUS_ST <= SCOB_PIPPTR1;
				SCOB_PIPPTR1: begin
					if (SCOB_SEL[0]) begin
						BUS_ST <= SCOB_PIPPTR_REL0;
					end 
					else if (PBI) begin
						BUS_PB_INT <= 1;
						PB_NEXT_ST <= SCOB_XPOS0;
						BUS_ST <= SCOB_PREINIT1;
					end
					else begin
						BUS_ST <= SCOB_XPOS0;
					end
				end 
				SCOB_PIPPTR_REL0: BUS_ST <= SCOB_PIPPTR_REL1;
				SCOB_PIPPTR_REL1: begin
//					if (PBI) begin
//						BUS_PB_INT <= 1;
//						PB_NEXT_ST <= SCOB_XPOS0;
//						BUS_ST <= SCOB_PREINIT1;
//					end
//					else begin
						BUS_ST <= SCOB_XPOS0;
//					end
				end
				SCOB_XPOS0: BUS_ST <= SCOB_XPOS1;
				SCOB_XPOS1: begin
					if (PBI) begin
						BUS_PB_INT <= 1;
						PB_NEXT_ST <= SCOB_YPOS0;
						BUS_ST <= SCOB_PREINIT1;
					end
					else begin
						BUS_ST <= SCOB_YPOS0;
					end
				end
				SCOB_YPOS0: BUS_ST <= SCOB_YPOS1;
				SCOB_YPOS1: begin
					if (!SCOB_SEL[0] && !HI_PRIO_REQ) begin
						BUS_ST <= SCOBLD_REQ == 3'd2 ? SCOB_PREINIT3 : SCOBLD_REQ == 3'd3 ? SCOB_PREINIT5 : BUS_IDLE;
					end
					else begin
						SE_GRANT_INT <= 0;
						BUS_ST <= BUS_IDLE;
					end
				end
				
				SCOB_PREINIT3: BUS_ST <= SCOB_INIT2;
				SCOB_INIT2: BUS_ST <= SCOB_INIT3;
				SCOB_INIT3: begin
					if (BUS_PB_INT) begin
						BUS_ST <= PB_NEXT_ST;
					end
					else if (SCOB_SEL[0]) begin
						BUS_ST <= SCOB_DX0;
					end
					else if (SCOB_SEL[1]) begin
						BUS_ST <= SCOB_DDX0;
					end
					else if (SCOB_SEL[2]) begin
						BUS_ST <= SCOB_PPMP0;
					end
					else begin
						SE_GRANT_INT <= 0;
						BUS_ST <= BUS_IDLE;
					end
				end
				SCOB_DX0: BUS_ST <= SCOB_DX1;
				SCOB_DX1: begin
					if (PBI) begin
						BUS_PB_INT <= 1;
						PB_NEXT_ST <= SCOB_DY0;
						BUS_ST <= SCOB_PREINIT3;
					end
					else begin
						BUS_ST <= SCOB_DY0;
					end
				end
				SCOB_DY0: BUS_ST <= SCOB_DY1;
				SCOB_DY1: begin
					if (PBI) begin
						BUS_PB_INT <= 1;
						PB_NEXT_ST <= SCOB_LINEDX0;
						BUS_ST <= SCOB_PREINIT3;
					end
					else begin
						BUS_ST <= SCOB_LINEDX0;
					end
				end
				SCOB_LINEDX0: BUS_ST <= SCOB_LINEDX1;
				SCOB_LINEDX1: begin
					if (PBI) begin
						BUS_PB_INT <= 1;
						PB_NEXT_ST <= SCOB_LINEDY0;
						BUS_ST <= SCOB_PREINIT3;
					end
					else begin
						BUS_ST <= SCOB_LINEDY0;
					end
				end
				SCOB_LINEDY0: BUS_ST <= SCOB_LINEDY1;
				SCOB_LINEDY1: begin
					if (SCOB_SEL[1]) begin
						if (PBI) begin
							BUS_PB_INT <= 1;
							PB_NEXT_ST <= SCOB_DDX0;
							BUS_ST <= SCOB_PREINIT3;
						end
						else begin
							BUS_ST <= SCOB_DDX0;
						end
					end
					else if (SCOB_SEL[2]) begin
						if (PBI) begin
							BUS_PB_INT <= 1;
							PB_NEXT_ST <= SCOB_PPMP0;
							BUS_ST <= SCOB_PREINIT3;
						end
						else begin
							BUS_ST <= SCOB_PPMP0;
						end
					end
					else if (SCOBLD_REQ == 3'd3 && !HI_PRIO_REQ) begin
						BUS_ST <= SCOB_PREINIT5;
					end
					else begin
						SE_GRANT_INT <= 0;
						BUS_ST <= BUS_IDLE;
					end
				end
				SCOB_DDX0: BUS_ST <= SCOB_DDX1;
				SCOB_DDX1: begin
					if (PBI) begin
						BUS_PB_INT <= 1;
						PB_NEXT_ST <= SCOB_DDY0;
						BUS_ST <= SCOB_PREINIT3;
					end
					else begin
						BUS_ST <= SCOB_DDY0;
					end
				end
				SCOB_DDY0: BUS_ST <= SCOB_DDY1;
				SCOB_DDY1: begin
					if (SCOB_SEL[2]) begin
						if (PBI) begin
							BUS_PB_INT <= 1;
							PB_NEXT_ST <= SCOB_PPMP0;
							BUS_ST <= SCOB_PREINIT3;
						end
						else begin
							BUS_ST <= SCOB_PPMP0;
						end
					end
					else if (SCOBLD_REQ == 3'd3 && !HI_PRIO_REQ) begin
						BUS_ST <= SCOB_PREINIT5;
					end
					else begin
						SE_GRANT_INT <= 0;
						BUS_ST <= BUS_IDLE;
					end
				end
				SCOB_PPMP0: BUS_ST <= SCOB_PPMP1;
				SCOB_PPMP1: begin
					if (SCOBLD_REQ == 3'd3 && !HI_PRIO_REQ) begin
						BUS_ST <= SCOB_PREINIT5;
					end
					else begin
						SE_GRANT_INT <= 0;
						BUS_ST <= BUS_IDLE;
					end
				end
				
				SCOB_PREINIT5: BUS_ST <= SCOB_INIT4;
				SCOB_INIT4: BUS_ST <= SCOB_INIT5;
				SCOB_INIT5: begin
					if (BUS_PB_INT) begin
						BUS_ST <= PB_NEXT_ST;
					end
					else begin
						BUS_ST <= SCOB_PRE00;
					end
				end
				SCOB_PRE00: BUS_ST <= SCOB_PRE01;
				SCOB_PRE01: begin
					if (SCOB_SEL[0]) begin
						if (PBI) begin
							BUS_PB_INT <= 1;
							PB_NEXT_ST <= SCOB_PRE10;
							BUS_ST <= SCOB_PREINIT5;
						end
						else begin
							BUS_ST <= SCOB_PRE10;
						end
					end
					else if (SCOBLD_REQ == 3'd4 && !HI_PRIO_REQ) begin
						BUS_ST <= SCOB_PREINIT7;
					end
					else if (SPRDATA_REQ && !HI_PRIO_REQ) begin
						BUS_ST <= SPRDATA_REQ == 2'd1 ? SPR_PREINIT1 : SPR_PREINIT3;
					end
					else begin
						SE_GRANT_INT <= 0;
						BUS_ST <= BUS_IDLE;
					end
				end
				SCOB_PRE10: BUS_ST <= SCOB_PRE11;
				SCOB_PRE11: begin
					if (SCOBLD_REQ == 3'd4 && !HI_PRIO_REQ) begin
						BUS_ST <= SCOB_PREINIT7;
					end
					else if (SPRDATA_REQ && !HI_PRIO_REQ) begin
						BUS_ST <= SPRDATA_REQ == 2'd1 ? SPR_PREINIT1 : SPR_PREINIT3;
					end
					else begin
						SE_GRANT_INT <= 0;
						BUS_ST <= BUS_IDLE;
					end
				end
				
				SCOB_PREINIT7: BUS_ST <= SCOB_INIT6;
				SCOB_INIT6: BUS_ST <= SCOB_INIT7;
				SCOB_INIT7: BUS_ST <= SCOB_PIP0;
				SCOB_PIP0: BUS_ST <= SCOB_PIP1;
				SCOB_PIP1: begin
					if (!SCOB_SEL[0]) begin
						if (PBI) begin
							BUS_PB_INT <= 1;
							BUS_ST <= SCOB_PREINIT7;
						end
						else begin
							BUS_ST <= SCOB_PIP0;
						end
					end
					else if (SCOBLD_REQ == 3'd4 && !HI_PRIO_REQ) begin
						BUS_ST <= SCOB_PREINIT7;
					end
					else if (SPRDATA_REQ && !HI_PRIO_REQ) begin
						BUS_ST <= SPRDATA_REQ == 2'd1 ? SPR_PREINIT1 : SPR_PREINIT3;
					end
					else begin
						SE_GRANT_INT <= 0;
						BUS_ST <= BUS_IDLE;
					end
				end
				
				SPR_PREINIT1: BUS_ST <= SPR_INIT0;
				SPR_INIT0: BUS_ST <= SPR_INIT1;
				SPR_INIT1: begin
					if (BUS_PB_INT) begin
						BUS_ST <= PB_NEXT_ST;
					end
					else begin
						BUS_ST <= SPR_OFFS0;
					end
				end
				SPR_OFFS0: BUS_ST <= SPR_OFFS1;
				SPR_OFFS1: begin
					if (PBI) begin
						BUS_PB_INT <= 1;
						PB_NEXT_ST <= SPR_OFFS2;
						BUS_ST <= SPR_PREINIT1;
					end
					else begin
						BUS_ST <= SPR_OFFS2;
					end
				end
				SPR_OFFS2: BUS_ST <= SPR_OFFS3;
				SPR_OFFS3: BUS_ST <= SPR_CALC0;
				SPR_CALC0: BUS_ST <= SPR_CALC1;
				SPR_CALC1:
					if (SPRDATA_REQ && !HI_PRIO_REQ) begin
						BUS_ST <= SPRDATA_REQ == 2'd1 ? SPR_PREINIT1 : SPR_PREINIT3;
					end
					else begin
						SE_GRANT_INT <= 0;
						BUS_ST <= BUS_IDLE;
					end
				
				SPR_PREINIT3: BUS_ST <= SPR_INIT2;
				SPR_INIT2: BUS_ST <= SPR_INIT3;
				SPR_INIT3: BUS_ST <= SPR_DATA0;
				SPR_DATA0: BUS_ST <= SPR_DATA1;
				SPR_DATA1: 
					if (SPR_SEL[0]) begin
						if (SPRDATA_REQ && !HI_PRIO_REQ) begin
							BUS_ST <= SPRDATA_REQ == 2'd1 ? SPR_PREINIT1 : SPR_PREINIT3;
						end else begin
							SE_GRANT_INT <= 0;
							BUS_ST <= BUS_IDLE;
						end
					end
					else if (PBI) begin
						BUS_PB_INT <= 1;
						BUS_ST <= SPR_PREINIT3;
					end
					else begin
						BUS_ST <= SPR_DATA0;
					end
					
				CFB_INIT0: BUS_ST <= CFB_INIT1;
				CFB_INIT1: begin
					if (CFB_SEL[2]) begin
						BUS_ST <= CFB_READ0;
					end
					else begin
						BUS_ST <= CFB_WRITE0;
					end
				end
				CFB_READ0: BUS_ST <= CFB_READ1;
				CFB_READ1: begin
					if (HI_PRIO_REQ && !CFB_SUSPEND && DBG_EXT[0]) CFB_SUSPEND <= 1;
					BUS_ST <= CFB_WRITE0;
				end
				CFB_WRITE0: BUS_ST <= CFB_WRITE1;
				CFB_WRITE1: begin
					if (CFB_SEL[0]) begin
						CFB_SUSPEND <= 0;
						SE_GRANT_INT <= 0;
						BUS_ST <= BUS_IDLE;
					end
					else if (CFB_SEL[1]) begin
						SE_GRANT_INT <= 0;
						BUS_ST <= BUS_IDLE;
					end
					else if (CFB_SEL[2]) begin
						BUS_ST <= CFB_READ0;
					end
					else begin
						if (HI_PRIO_REQ && !CFB_SUSPEND && DBG_EXT[0]) CFB_SUSPEND <= 1;
						BUS_ST <= CFB_WRITE0;
					end
				end
				
				//CLUT
				CLUT_PREINIT1: BUS_ST <= CLUT_INIT0;
				CLUT_INIT0: BUS_ST <= CLUT_INIT1;
				CLUT_INIT1: BUS_ST <= CLUT_CTRL0;
				CLUT_CTRL0: BUS_ST <= CLUT_CTRL1;
				CLUT_CTRL1: BUS_ST <= CLUT_CURR0;
				CLUT_CURR0: BUS_ST <= CLUT_CURR1;
				CLUT_CURR1: BUS_ST <= CLUT_PREV0;
				CLUT_PREV0: BUS_ST <= CLUT_PREV1;
				CLUT_PREV1: BUS_ST <= CLUT_NEXT0;
				CLUT_NEXT0: BUS_ST <= CLUT_NEXT1;
				CLUT_NEXT1: BUS_ST <= CLUT_NEXT_REL0;
				CLUT_NEXT_REL0: BUS_ST <= CLUT_NEXT_REL1;
				CLUT_NEXT_REL1: BUS_ST <= CLUT_TRANSFER0;
				CLUT_TRANSFER0: BUS_ST <= CLUT_TRANSFER1;
				CLUT_TRANSFER1: BUS_ST <= CLUT_MIDINIT0;
				CLUT_MIDINIT0: BUS_ST <= CLUT_MIDINIT1;
				CLUT_MIDINIT1: BUS_ST <= CLUT_MIDTRANS0;
				CLUT_MIDTRANS0: BUS_ST <= CLUT_MIDTRANS1;
				CLUT_MIDTRANS1: begin
					SPORT_GRANT_INT <= 0;
					if (!SE_RUN && !HI_PRIO_REQ) CPU_GRANT_INT <= 1;
					BUS_ST <= BUS_IDLE;
				end
				
				VID_PREINIT1: BUS_ST <= VID_INIT0;
				VID_INIT0: BUS_ST <= VID_INIT1;
				VID_INIT1: BUS_ST <= VID_PREV0;
				VID_PREV0: BUS_ST <= VID_PREV1;
				VID_PREV1: BUS_ST <= VID_CALC0;
				VID_CALC0: BUS_ST <= VID_CALC1;
				VID_CALC1: BUS_ST <= VID_CURR0;
				VID_CURR0: BUS_ST <= VID_CURR1;
				VID_CURR1: begin
					if (VIDMID_FIRST) begin
						VIDMID_PREV_CURR <= VIDMID_CURR;
						BUS_ST <= VID_MIDPREINIT1;
					end
					else begin
						SPORT_GRANT_INT <= 0;
						if (!SE_RUN && !HI_PRIO_REQ) CPU_GRANT_INT <= 1;
						BUS_ST <= BUS_IDLE;
					end
				end
				
				VID_MIDPREINIT1: BUS_ST <= VID_MIDINIT0;
				VID_MIDINIT0: BUS_ST <= VID_MIDINIT1;
				VID_MIDINIT1: BUS_ST <= VIDMID_PREV_CURR ? VID_MIDCURR0 : VID_MIDPREV0;
				VID_MIDPREV0: BUS_ST <= VID_MIDPREV1;
				VID_MIDPREV1: begin
					if (VIDMID_FIRST) begin
						VIDMID_PREV_CURR <= ~VIDMID_PREV_CURR;
						BUS_ST <= VID_MIDCURR0;
					end
					else begin
						SPORT_GRANT_INT <= 0;
						if (!SE_RUN && !HI_PRIO_REQ) CPU_GRANT_INT <= 1;
						BUS_ST <= BUS_IDLE;
					end
				end
				
				VID_MIDCURR0: BUS_ST <= VID_MIDCURR1;
				VID_MIDCURR1: begin
					if (VIDMID_FIRST) begin
						VIDMID_PREV_CURR <= ~VIDMID_PREV_CURR;
						BUS_ST <= VID_MIDPREV0;
					end
					else begin
						SPORT_GRANT_INT <= 0;
						if (!SE_RUN && !HI_PRIO_REQ) CPU_GRANT_INT <= 1;
						BUS_ST <= BUS_IDLE;
					end
				end
				
				default:;
			endcase
			
			if (BUS_ST == EXTP_INIT1 || BUS_ST == EXTP_INIT3 ||
			    BUS_ST == SCOB_INIT1 || BUS_ST == SCOB_INIT3 || BUS_ST == SCOB_INIT5 || BUS_ST == SCOB_INIT7 ||
			    BUS_ST == SPR_INIT1  || BUS_ST == SPR_INIT3) begin
				BUS_PB_INT <= 0;
			end
			end
			
			if (CE_R) begin
				CPU_GRANT <= CPU_GRANT_INT;
				EXTP_GRANT <= EXTP_GRANT_INT;
				SE_GRANT <= SE_GRANT_INT;
				SPORT_GRANT <= SPORT_GRANT_INT;
				PLAYER_GRANT <= PLAYER_GRANT_INT;
				BUS_PB <= BUS_PB_INT;
			end
		end
	end 
	assign BUS_STATE = BUS_ST;

	AddrGenCtl_t DMA_CTL2;
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) begin
			DMA_CTL2 <= '0;
		end
		else if (EN && CE_R) begin
			DMA_CTL2 <= '0;
			
			if (BUS_ST == EXTP_PREINIT1 || BUS_ST == EXTP_INIT0 || BUS_ST == EXTP_INIT1 ||			
				 BUS_ST == EXTP_READ0 || BUS_ST == EXTP_READ1 ||		
				 BUS_ST == EXTP_PREINIT3 || BUS_ST == EXTP_INIT2 || BUS_ST == EXTP_INIT3 ||
				 BUS_ST == EXTP_WRITE0 || BUS_ST == EXTP_WRITE1 ||			
				 BUS_ST == EXTP_LOOP0 || BUS_ST == EXTP_LOOP1 ||
				 BUS_ST == EXTP_LOOP2 || BUS_ST == EXTP_LOOP3) begin
				DMA_CTL2 <= EXTP_AG_CTL;
			end
			else if (BUS_ST == SCOB_PREINIT1 || BUS_ST == SCOB_INIT0 || BUS_ST == SCOB_INIT1 ||
				BUS_ST == SCOB_FLAG0 || BUS_ST == SCOB_FLAG1 ||
				BUS_ST == SCOB_NEXT0 || BUS_ST == SCOB_NEXT1 ||
				BUS_ST == SCOB_NEXT_REL0 || BUS_ST == SCOB_NEXT_REL1 ||
				BUS_ST == SCOB_SOURCE0 || BUS_ST == SCOB_SOURCE1 ||
				BUS_ST == SCOB_SOURCE_REL0 || BUS_ST == SCOB_SOURCE_REL1 ||
				BUS_ST == SCOB_PIPPTR0 || BUS_ST == SCOB_PIPPTR1 ||
				BUS_ST == SCOB_PIPPTR_REL0 || BUS_ST == SCOB_PIPPTR_REL1 ||
				BUS_ST == SCOB_XPOS0 || BUS_ST == SCOB_XPOS1 ||
				BUS_ST == SCOB_YPOS0 || BUS_ST == SCOB_YPOS1 ||
				
				BUS_ST == SCOB_PREINIT3 || BUS_ST == SCOB_INIT2 || BUS_ST == SCOB_INIT3 ||
				BUS_ST == SCOB_DX0 || BUS_ST == SCOB_DX1 ||
				BUS_ST == SCOB_DY0 || BUS_ST == SCOB_DY1 ||
				BUS_ST == SCOB_LINEDX0 || BUS_ST == SCOB_LINEDX1 ||
				BUS_ST == SCOB_LINEDY0 || BUS_ST == SCOB_LINEDY1 ||
				BUS_ST == SCOB_DDX0 || BUS_ST == SCOB_DDX1 ||
				BUS_ST == SCOB_DDY0 || BUS_ST == SCOB_DDY1 ||
				BUS_ST == SCOB_PPMP0 || BUS_ST == SCOB_PPMP1 ||
				
				BUS_ST == SCOB_PREINIT5 || BUS_ST == SCOB_INIT4 || BUS_ST == SCOB_INIT5 ||
				BUS_ST == SCOB_PRE00 || BUS_ST == SCOB_PRE01 ||
				BUS_ST == SCOB_PRE10 || BUS_ST == SCOB_PRE11 ||
				
				BUS_ST == SCOB_PREINIT7 || BUS_ST == SCOB_INIT6 || BUS_ST == SCOB_INIT7 ||
				BUS_ST == SCOB_PIP0 || BUS_ST == SCOB_PIP1 ||
				
				BUS_ST == SPR_PREINIT1 || BUS_ST == SPR_INIT0 || BUS_ST == SPR_INIT1 ||
				BUS_ST == SPR_OFFS0 || BUS_ST == SPR_OFFS1 ||
				BUS_ST == SPR_OFFS2 || BUS_ST == SPR_OFFS3 ||
				BUS_ST == SPR_CALC0 || BUS_ST == SPR_CALC1 ||
				BUS_ST == SPR_PREINIT3 || BUS_ST == SPR_INIT2 || BUS_ST == SPR_INIT3 ||
				BUS_ST == SPR_DATA0 || BUS_ST == SPR_DATA1 ||
				
				BUS_ST == CFB_INIT0 || BUS_ST == CFB_INIT1 ||
				BUS_ST == CFB_READ0 || BUS_ST == CFB_READ1 ||
				BUS_ST == CFB_WRITE0 || BUS_ST == CFB_WRITE1) begin
				DMA_CTL2 <= SE_AG_CTL;
			end
			else if (BUS_ST == CLUT_PREINIT1 || BUS_ST == CLUT_INIT0 || BUS_ST == CLUT_INIT1 || 
				BUS_ST == CLUT_CTRL0 || BUS_ST == CLUT_CTRL1 ||
				BUS_ST == CLUT_CURR0 || BUS_ST == CLUT_CURR1 ||
				BUS_ST == CLUT_PREV0 || BUS_ST == CLUT_PREV1 ||
				BUS_ST == CLUT_NEXT0 || BUS_ST == CLUT_NEXT1 ||
				BUS_ST == CLUT_NEXT_REL0 || BUS_ST == CLUT_NEXT_REL1 ||
				BUS_ST == CLUT_TRANSFER0 || BUS_ST == CLUT_TRANSFER1 ||
				BUS_ST == CLUT_MIDINIT0 || BUS_ST == CLUT_MIDINIT1 ||
				BUS_ST == CLUT_MIDTRANS0 || BUS_ST == CLUT_MIDTRANS1 ||
				
				BUS_ST == VID_PREINIT1 || BUS_ST == VID_INIT0 || BUS_ST == VID_INIT1 ||
				BUS_ST == VID_PREV0 || BUS_ST == VID_PREV1 ||
				BUS_ST == VID_CALC0 || BUS_ST == VID_CALC1 ||
				BUS_ST == VID_CURR0 || BUS_ST == VID_CURR1 ||
				BUS_ST == VID_MIDPREINIT1 ||BUS_ST == VID_MIDINIT0 || BUS_ST == VID_MIDINIT1 ||
				BUS_ST == VID_MIDPREV0 || BUS_ST == VID_MIDPREV1 ||
				BUS_ST == VID_MIDCURR0 || BUS_ST == VID_MIDCURR1) begin
				DMA_CTL2 <= SPORT_AG_CTL;
			end
			else if (BUS_ST == PLAY_PREINIT1 || BUS_ST == PLAY_INIT0 || BUS_ST == PLAY_INIT1 ||
				BUS_ST == PLAY_READ0 || BUS_ST == PLAY_READ1 ||
				BUS_ST == PLAY_PREINIT3 || BUS_ST == PLAY_INIT2 || BUS_ST == PLAY_INIT3 ||
				BUS_ST == PLAY_WRITE0 || BUS_ST == PLAY_WRITE1 ||
				BUS_ST == REF_PREINIT1 || BUS_ST == REF_INIT0 || BUS_ST == REF_INIT1 ||
				BUS_ST == REF_WRITE0 || BUS_ST == REF_WRITE1 || BUS_ST == REF_WRITE2 || BUS_ST == REF_WRITE3) begin
				DMA_CTL2 <= PLAYER_AG_CTL;
			end
		end
	end
	
	assign DMA_CTL = CPU_GRANT ? CPU_AG_CTL : DMA_CTL2;
	
endmodule
