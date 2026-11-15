module ARM6_CORE
 (
	input             CLK,
	input             RST_N,
	input             EN,
	
	input             BIGEND,
	
	input             CE_R,
	input             CE_F,
	
	input             nRESET,
	input             nFIQ,
	input             nIRQ,
	
	
	input      [31:0] EDI,
	
	output     [31:0] A,
	input      [31:0] DI,
	output     [31:0] DO,
	output            nRW,
	output            nWB,
	
	output            nMREQ,
	output            SEQ,
	output            nOPC,
	output            nTRANS,
	output            LOCK,
	input             DBE
	
`ifdef DEBUG
	                  ,
	output			   ILI
`endif
);
	
	import ARM6_PKG::*; 
	 
	PSR_t        CPSR; 
	PSR_t        SPSR[6]; 
	PSR_t        CPSR_NEXT;
	bit          FIQ,IRQ;
	
	bit  [31: 0] AREG; 
	bit  [31: 0] DIN; 
	bit  [ 1: 0] BA; 
	bit  [31: 0] AREG_NEXT;
	
	bit  [31: 0] DI_IC;
	bit  [ 4: 0] STATE;
	DecInstr_t   DECI; 
	bit  [31: 0] EX_IC;
	bit  [ 7: 0] SHIFT_LATCH;
	bit          COND_NEXT;
	bit          COND;
	bit  [ 3: 0] BLOCK_RD,BLOCK_WN;
	bit          BLOCK_WE;
	bit          BLOCK_LAST;
	bit  [31: 0] MUL_SHIFT;
	bit  [ 3: 0] MUL_STEP;
	bit          MUL_LAST;
		
	bit  [31: 0] ALU_A;
	bit  [31: 0] ALU_B;
	bit          ALU_SHC,ALU_SHZ;
	bit  [31: 0] ALU_R;
	bit          ALU_N;
	bit          ALU_Z;
	bit          ALU_C;
	bit          ALU_V;
	
	bit          RES_SYNC;
	always @(posedge CLK) begin
		if (EN) begin
			RES_SYNC <= ~nRESET;
		end
	end
	
	//Register bank
	bit  [ 3: 0] RB_MODE;
	
	bit  [ 3: 0] RB_RAN;
	bit  [ 3: 0] RB_RBN;
	bit  [31: 0] RB_RAQ;
	bit  [31: 0] RB_RBQ;
	
	bit  [ 3: 0] RB_WN;
	bit  [31: 0] RB_WD;
	bit          RB_WE;
	
	bit  [31: 0] PC_D;
	bit          PC_WE;
	bit  [31: 0] PC_Q;

	ARM6_RB RB (
		.CLK(CLK),
		.RST_N(RST_N),
		.CE(CE_F),
		.EN(EN),
		
		.MODE(RB_MODE),
		
		.W_A(RB_WN),
		.W_D(RB_WD),
		.W_WE(RB_WE),
		
		.RA_A(RB_RAN),
		.RA_Q(RB_RAQ),
		.RB_A(RB_RBN),
		.RB_Q(RB_RBQ),
		
		.PC_D(PC_D),
		.PC_WE(PC_WE),
		.PC_Q(PC_Q)
	);
	
	
	//Fetch
	bit  [31: 0] IF_IC;
	bit  EX_STATE0;
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) begin
			DIN <= '0;
			BA <= '0;
			FIQ <= 0;
			IRQ <= 0;
		end
		else if (EN && CE_F) begin
			DIN <= DI;
			BA <= AREG[1:0];
			FIQ <= ~nFIQ;
			IRQ <= ~nIRQ;
		end
	end 
	
	//Decode
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) begin
			IF_IC <= '0;
			DI_IC <= '0;
		end
		else if (RES_SYNC) begin
			IF_IC <= 32'hE1A00000;
			DI_IC <= 32'hE1A00000;
		end
		else if (EN && CE_F) begin
			if (!DECI.STALL) begin
				IF_IC <= DI;
			end
		end
		else if (EN && CE_R) begin
			if (!STATE) begin
				DI_IC <= IF_IC;
			end else if (!DECI.STALL) begin
				DI_IC <= DIN;
			end
		end
	end 
	
	wire [ 4: 0] STATE_NEXT = !DECI.NST ? STATE : !DECI.LST ? STATE + 5'd1 : 5'd0;
	bit RESET_PEND,FIQ_PEND,IRQ_PEND;
	// Game Bub port: the executing instruction takes the undefined instruction
	// trap. It is put in EX_IC as an SWI with its condition (Decode runs that);
	// mode, SPSR and vector are chosen here. Substituted when EX_IC is loaded, so
	// that UndefTrap is not in front of the decode (the CPU decode to nMREQ to
	// MADAM to SDRAM controller path is the design's critical path).
	bit UND_TRAP;
	// Game Bub port: a word load whose data is rotated by the address (LDR, SWP)
	wire WORD_ROT = (EX_IC[27:26] == 2'b01) || (EX_IC[27:23] == 5'b00010 && EX_IC[7:4] == 4'b1001);
	// Game Bub port: an MSR to the SPSR: the _flg forms (bit 16 clear, every
	// immediate form) keep everything but the condition flags
	wire SPSR_WR_ALL = EX_IC[16] && !EX_IC[25];
	function automatic PSR_t SPSR_WR(input PSR_t old, input [31:0] res, input all);
		return all ? PSR_t'(res) : PSR_t'({res[31:28], old[27:0]});
	endfunction
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) begin
			STATE <= '0;
			EX_IC <= '0;
			RESET_PEND <= 1;
			FIQ_PEND <= 0;
			IRQ_PEND <= 0;
			UND_TRAP <= 0;
		end
		else if (RES_SYNC) begin
			STATE <= '0;
			EX_IC <= 32'hEF000000;
			RESET_PEND <= 1;
			FIQ_PEND <= 0;//Game Bub port: a reset abandons an exception entry in progress
			IRQ_PEND <= 0;
			UND_TRAP <= 0;
		end
		else if (EN && CE_F) begin
			STATE <= STATE_NEXT;

			if (DECI.NST && DECI.LST) begin
				EX_IC <= UndefTrap(DI_IC) ? {DI_IC[31:28], 4'hF, 24'h000000} : DI_IC;
				UND_TRAP <= UndefTrap(DI_IC);

				if (FIQ && !CPSR.F) begin
					EX_IC <= 32'hEF000000;
					FIQ_PEND <= 1;
					UND_TRAP <= 0;
				end
				else if (IRQ && !CPSR.I) begin
					EX_IC <= 32'hEF000000;
					IRQ_PEND <= 1;
					UND_TRAP <= 0;
				end
				else begin
					RESET_PEND <= 0;
					FIQ_PEND <= 0;
					IRQ_PEND <= 0;
				end
			end
		end
	end 
	assign DECI = COND || STATE ? Decode(EX_IC, STATE, CPSR, BLOCK_RD, BLOCK_WN, BLOCK_WE, BLOCK_LAST, MUL_LAST) : DECI_NOP; 
	
	
	//Execute
	assign RB_MODE = DECI.PSRCTL == PSRC_USR ? 4'b0000 : 
		              DECI.PSRCTL == PSRC_INT ? CPSR_NEXT.M[3:0] : 
				                                  CPSR.M[3:0];
	assign RB_RAN = DECI.RCTL.RAN; 
	assign RB_RBN = DECI.RCTL.RBN;
	
	bit  [31: 0] PSR_RES;
	bit  [31: 0] SHIFT_RES;
	bit          SHIFT_C,SHIFT_ZERO;
	bit  [31: 0] MUL_RES;
	always_comb begin
		bit [31: 0] MD;
		bit [31: 0] IMM;
		bit [31: 0] SHIFT_A;
		bit [ 7: 0] SHIFT_SA;
		bit [ 2: 0] SHIFT_TYPE;
		
		if (!EX_IC[22]) PSR_RES = CPSR;
		else
			case (CPSR.M)
				5'b10001: PSR_RES = SPSR[1];
				5'b10010: PSR_RES = SPSR[2];
				5'b10011: PSR_RES = SPSR[3];
				5'b10111: PSR_RES = SPSR[4];
				5'b11011: PSR_RES = SPSR[5];
				default:  PSR_RES = CPSR;
			endcase
		
		case (DECI.MCTL.SZ)
			// Game Bub port: a word load (LDR, SWP) from an address that is not word aligned
			// is rotated right by 8 times A[1:0], in either endianness (ARM60 datasheet
			// 4.7.6: the addressed byte ends up in bits 7:0 little endian, 31:24 or 15:8 big
			// endian). LDM does not rotate.
			1'b0: MD = WORD_ROT ? ((DIN >> {BA,3'b000}) | (DIN << (6'd32 - {1'b0,BA,3'b000}))) : DIN;
			1'b1: case (BA^{2{BIGEND}})
				2'b11: MD = {24'h000000,DIN[31:24]};
				2'b10: MD = {24'h000000,DIN[23:16]};
				2'b01: MD = {24'h000000,DIN[15: 8]};
				2'b00: MD = {24'h000000,DIN[ 7: 0]};
			endcase
		endcase
		
		case (DECI.DPCTL.IMMT)
			IMM_U8:   IMM = {24'h000000,EX_IC[7:0]};
			IMM_U12:  IMM = {20'h00000,EX_IC[11:0]};
			IMM_S24:  IMM = {{8{EX_IC[23]}},EX_IC[23:0]};
			IMM_OFFS: IMM = {27'h0000000,BlockOffset(EX_IC[15:0])};
			IMM_ZERO: IMM = 32'h00000000;
			IMM_ONE:  IMM = 32'h00000001;
			default:  IMM = MD;
		endcase
		
		SHIFT_A = DECI.DPCTL.SB ? IMM : RB_RBQ;
		case (DECI.DPCTL.SHCTL)
			SHFT_NONE:  begin SHIFT_SA = '0;                                             SHIFT_TYPE = 3'b000;            SHIFT_ZERO = 1; end
			// LSR #0 and ASR #0 encode LSR #32 and ASR #32 (Game Bub port: LSR as well)
			SHFT_CONST: begin SHIFT_SA = {2'b00,(EX_IC[11:7]==5'd0 && (EX_IC[6:5]==2'b01 || EX_IC[6:5]==2'b10)),EX_IC[11:7]}; SHIFT_TYPE = {1'b1,EX_IC[6:5]}; SHIFT_ZERO = ~|EX_IC[11:7] & ~|EX_IC[6:5]; end
			SHFT_REG:   begin SHIFT_SA = SHIFT_LATCH;                                    SHIFT_TYPE = {1'b0,EX_IC[6:5]}; SHIFT_ZERO = ~|SHIFT_LATCH; end
			SHFT_ROT:   begin SHIFT_SA = {3'b000,EX_IC[11:8],1'b0};                      SHIFT_TYPE = 3'b011;            SHIFT_ZERO = ~|EX_IC[11:8]; end
			SHFT_LSL2:  begin SHIFT_SA = 8'd2;                                           SHIFT_TYPE = 3'b000;            SHIFT_ZERO = 0; end
			default:    begin SHIFT_SA = '0;                                             SHIFT_TYPE = 3'b000;            SHIFT_ZERO = 1; end	//not used: no latches
		endcase
		
		{SHIFT_C,SHIFT_RES} = Shifter(SHIFT_A, SHIFT_SA, SHIFT_TYPE, CPSR.C);
		
		MUL_RES = BoothMul(RB_RBQ, MUL_SHIFT[1:0], MUL_STEP);
	end 
	
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) begin
			ALU_A <= '0;
			ALU_B <= '0;
			ALU_SHC <= 0;
			ALU_SHZ <= 0;
		end
		else if (EN && CE_R) begin
			if (DECI.DPCTL.ALULTCH) begin
				ALU_A <= DECI.DPCTL.SA ? PSR_RES : RB_RAQ; 
				ALU_B <= DECI.DPCTL.MCTL == MUL_EXE ? MUL_RES : SHIFT_RES; 
				ALU_SHC <= SHIFT_C; 
				ALU_SHZ <= SHIFT_ZERO; 
			end
		end
	end 
	
	always_comb begin
		bit [31:0] ADD_RES;
		bit        ADD_A_SIGN,ADD_B_SIGN,ADD_R_SIGN;
		bit        ADD_C;
		bit        ADD_Z;
		bit        ADD_V; 		
		bit [31:0] LOG_RES; 
		bit        LOG_Z;
		bit        LOG_V;
		bit        LOG_C;
		
		{ADD_C,ADD_RES} = Adder(ALU_A, ALU_B, CPSR.C, DECI.ALU.CD); 
		{ADD_A_SIGN,ADD_B_SIGN,ADD_R_SIGN} = !DECI.ALU.CD[1] ? {ALU_A[31],ALU_B[31],ADD_RES[31]} : {ALU_B[31],ALU_A[31],ADD_RES[31]};
		ADD_Z = ~|ADD_RES;
		ADD_C = (ADD_A_SIGN & (ADD_B_SIGN ^ DECI.ALU.CD[0])) | ((ADD_A_SIGN | (ADD_B_SIGN ^ DECI.ALU.CD[0])) & ~ADD_R_SIGN); 
		ADD_V = (ADD_A_SIGN & ((ADD_B_SIGN ^ DECI.ALU.CD[0]) & ~ADD_R_SIGN)) | (~ADD_A_SIGN & (~ADD_B_SIGN ^ DECI.ALU.CD[0]) & ADD_R_SIGN); 
		
		LOG_RES = Log(ALU_A, ALU_B, DECI.ALU.CD); 
		LOG_Z = ~|LOG_RES;
		LOG_V = CPSR.V;
		LOG_C = ALU_SHZ ? CPSR.C : ALU_SHC;
		
		case (DECI.ALU.OP)
			ALUT_ADD: {ALU_N,ALU_Z,ALU_C,ALU_V,ALU_R} = {ADD_RES[31],ADD_Z ,ADD_C  ,ADD_V ,ADD_RES};
			ALUT_LOG: {ALU_N,ALU_Z,ALU_C,ALU_V,ALU_R} = {LOG_RES[31],LOG_Z ,LOG_C  ,LOG_V ,LOG_RES};
			ALUT_MUL: {ALU_N,ALU_Z,ALU_C,ALU_V,ALU_R} = {ADD_RES[31],ADD_Z ,CPSR.C ,CPSR.V,ADD_RES};
			ALUT_A:   {ALU_N,ALU_Z,ALU_C,ALU_V,ALU_R} = {CPSR.N     ,CPSR.Z,CPSR.C ,CPSR.V,ALU_A};
			default:  {ALU_N,ALU_Z,ALU_C,ALU_V,ALU_R} = {CPSR.N     ,CPSR.Z,CPSR.C ,CPSR.V,ALU_B};
		endcase 
	end 
	
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) begin
			SHIFT_LATCH <= '0;
		end
		else if (EN && CE_F) begin
			if (DECI.DPCTL.SHLTCH) begin
				SHIFT_LATCH <= ALU_B[7:0]; 
			end
		end
	end 
	
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) begin
			MUL_SHIFT <= '0;
			MUL_STEP <= '0;
		end
		else if (EN && CE_F) begin
			if (DECI.DPCTL.MCTL == MUL_SET) begin
				MUL_SHIFT <= ALU_A;
				MUL_STEP <= '0;
			end
			if (DECI.DPCTL.MCTL == MUL_EXE) begin
				MUL_SHIFT <= {2'b00,MUL_SHIFT[31:2]};
				MUL_STEP <= MUL_STEP + 4'd1;
			end
			
		end
	end 
	assign MUL_LAST = ~|MUL_SHIFT[31:2];
	
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) begin
			BLOCK_RD <= '0;
		end
		else if (EN && CE_F) begin
			if (DECI.RCTL.BINI)
				BLOCK_RD <= RegFromList(EX_IC[15:0], 4'd0);
			else if (DECI.RCTL.BRE)
				BLOCK_RD <= RegFromList(EX_IC[15:0], BLOCK_RD + 4'd1);
				
			BLOCK_WN <= BLOCK_RD;
			BLOCK_WE <= DECI.RCTL.BRE;
		end
	end 
	assign BLOCK_LAST = LastInList(EX_IC[15:0], BLOCK_RD + 4'd0);
	
	assign RB_WN = DECI.RCTL.WN;
	assign RB_WD = ALU_R;
	assign RB_WE = DECI.RCTL.RWE;
	
	// Game Bub port: R15 holds a word address (ARM60 datasheet 3.3: when R15 is
	// read, bits [1:0] are zero). A write to R15 with bits [1:0] set (MOV PC,
	// LDR PC, LDM {PC}) kept them, and every PC read and PC-relative address
	// after it was off by them. The fetches still put them on A[1:0], as the
	// address register is loaded from the ALU.
	assign PC_D = {AREG_NEXT[31:2], 2'b00};
	assign PC_WE = DECI.PCU;
	
	//PSR
	always_comb begin
		CPSR_NEXT <= CPSR;
		case (DECI.PSRCTL)
			// Game Bub port: ARM60 (ARMv3) MSR (datasheet 4.5): the _flg forms (bit 16
			// clear, and every immediate form) write the condition flags only; the
			// register form writes the whole PSR, in User mode the flags only.
			PSRC_ALU: if (!EX_IC[22]) 
				case (CPSR.M)
					5'b10000: CPSR_NEXT[31:28] <= ALU_R[31:28];
					5'b10001,
					5'b10010,
					5'b10011,
					5'b10111,
					5'b11011: begin
						if (EX_IC[16] && !EX_IC[25]) CPSR_NEXT <= ALU_R;
						else CPSR_NEXT[31:28] <= ALU_R[31:28];
					end
					default: ;
				endcase
					
			PSRC_FLG: {CPSR_NEXT.N,CPSR_NEXT.Z,CPSR_NEXT.C,CPSR_NEXT.V} <= {ALU_N,ALU_Z,ALU_C,ALU_V}; 
			
			PSRC_INT: if (FIQ_PEND) {CPSR_NEXT.I,CPSR_NEXT.F,CPSR_NEXT.M} <= {1'b1,1'b1,5'b10001};
						 else if (IRQ_PEND) {CPSR_NEXT.I,CPSR_NEXT.M} <= {1'b1,5'b10010};
						 else if (RESET_PEND) {CPSR_NEXT.I,CPSR_NEXT.F,CPSR_NEXT.M} <= {1'b1,1'b1,5'b10011};//Reset: IRQ and FIQ disabled (ARM60 datasheet; Game Bub port fix)
						 else if (UND_TRAP) {CPSR_NEXT.I,CPSR_NEXT.M} <= {1'b1,5'b11011};//Undefined instruction trap (Game Bub port)
						 else {CPSR_NEXT.I,CPSR_NEXT.M} <= {1'b1,5'b10011};//for SWI
			
			PSRC_RET: 
				case (CPSR.M)
					5'b10001: CPSR_NEXT <= SPSR[1];
					5'b10010: CPSR_NEXT <= SPSR[2];
					5'b10011: CPSR_NEXT <= SPSR[3];
					5'b10111: CPSR_NEXT <= SPSR[4];
					5'b11011: CPSR_NEXT <= SPSR[5];
					default:;
				endcase
				
			default:;
		endcase
	end
	
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) begin
			CPSR <= 32'h000000D3;
			SPSR <= '{6{'0}};
		end
		else if (EN && CE_F) begin
			CPSR <= CPSR_NEXT;
			case (DECI.PSRCTL)
				// Game Bub port: the _flg forms write the condition flags only (they wrote
				// the whole SPSR: the saved mode and interrupt masks were lost)
				PSRC_ALU: if (EX_IC[22])
					case (CPSR.M)
						5'b10001: SPSR[1] <= SPSR_WR(SPSR[1], ALU_R, SPSR_WR_ALL);
						5'b10010: SPSR[2] <= SPSR_WR(SPSR[2], ALU_R, SPSR_WR_ALL);
						5'b10011: SPSR[3] <= SPSR_WR(SPSR[3], ALU_R, SPSR_WR_ALL);
						5'b10111: SPSR[4] <= SPSR_WR(SPSR[4], ALU_R, SPSR_WR_ALL);
						5'b11011: SPSR[5] <= SPSR_WR(SPSR[5], ALU_R, SPSR_WR_ALL);
						default:;
					endcase
				
				PSRC_INT: 
					if (FIQ_PEND) begin SPSR[1] <= CPSR; end
					else if (IRQ_PEND) begin SPSR[2] <= CPSR; end
					else if (UND_TRAP && !RESET_PEND) begin SPSR[5] <= CPSR; end//Undefined instruction trap (Game Bub port)
					else SPSR[3] <= CPSR;//for Reset/SWI
				
				default:;
			endcase
		end
	end
	
	always_comb begin
		COND <= 0;
		case (EX_IC[31:28])
			4'h0: COND <=  CPSR.Z							; //EQ
			4'h1: COND <= ~CPSR.Z							; //NE
			4'h2: COND <=  CPSR.C							; //CS,HS
			4'h3: COND <= ~CPSR.C							; //CC,LO
			4'h4: COND <=  CPSR.N							; //MI
			4'h5: COND <= ~CPSR.N							; //PL
			4'h6: COND <=  CPSR.V							; //VS
			4'h7: COND <= ~CPSR.V							; //VC
			4'h8: COND <=  CPSR.C            & ~CPSR.Z; //HI
			4'h9: COND <= ~CPSR.C            |  CPSR.Z; //LS
			4'hA: COND <= ~(CPSR.N ^ CPSR.V)				; //GE
			4'hB: COND <=  (CPSR.N ^ CPSR.V)				; //LT
			4'hC: COND <= ~(CPSR.N ^ CPSR.V) & ~CPSR.Z; //GT
			4'hD: COND <=  (CPSR.N ^ CPSR.V) |  CPSR.Z; //LE
			4'hE: COND <= 1; //AL
			4'hF: COND <= 0; //
		endcase
	end
	
	//AREG
	assign AREG_NEXT = AREG + 32'd4;
	
	AddrType_t MCTL_ADR_PREV;
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) begin
			AREG <= '0;
			MCTL_ADR_PREV <= ADR_INC;
		end
		else if (EN && CE_F) begin
			case (DECI.MCTL.ADR)
				ADR_INC: AREG <= AREG_NEXT;
				ADR_PC:  AREG <= PC_Q;
				ADR_ALU: AREG <= ALU_R;
				ADR_ALUI:AREG <= ALU_R + 32'd4;
				ADR_VEC: AREG <= RESET_PEND ? 32'h00000000 : FIQ_PEND ? 32'h0000001C : IRQ_PEND ? 32'h00000018 : UND_TRAP ? 32'h00000004 : 32'h00000008;//for SWI; Game Bub port: undefined instruction trap
				default: AREG <= '0;
			endcase
			MCTL_ADR_PREV <= DECI.MCTL.ADR;
		end
	end 
	
	assign A = AREG;
	assign DO = !DBE ? EDI : DECI.MCTL.SZ ? {4{RB_RBQ[7:0]}} : RB_RBQ;
	assign nWB = ~DECI.MCTL.SZ;
	assign nRW = DECI.MCTL.WR;
	
	assign nMREQ = DECI.ICYC || DECI.CCYC;
	assign SEQ = DECI.ICYC ? 1'b0 : DECI.CCYC ? 1'b1 : (DECI.MCTL.ADR == ADR_INC || (DECI.MCTL.ADR == ADR_PC && MCTL_ADR_PREV == ADR_PC));
	assign nOPC = DECI.STALL;
	// Game Bub port: LDRT/STRT/LDRBT/STRBT (post-indexed, W set) make their transfer
	// cycle (state 1, with its nRW) a User mode access in any mode (ARM60 datasheet
	// 4.7.1); they were privileged.
	wire TRANS_T = (EX_IC[27:26] == 2'b01) && !EX_IC[24] && EX_IC[21] && STATE == 5'd1;
	assign nTRANS = (~(CPSR.M[3:0] == 4'b0000) || (EX_IC[27:24] == 4'b1111)) && !TRANS_T;
	assign LOCK = DECI.LOCK;
	
`ifdef DEBUG
	assign ILI = DECI.ILI;
`endif
	
endmodule
