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
	bit          ALU_SHC;
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
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) begin
			STATE <= '0;
			EX_IC <= '0;
			RESET_PEND <= 1;
			FIQ_PEND <= 0;
			IRQ_PEND <= 0;
		end
		else if (RES_SYNC) begin
			STATE <= '0;
			EX_IC <= 32'hEF000000;
			RESET_PEND <= 1;
		end
		else if (EN && CE_F) begin
			STATE <= STATE_NEXT;
			 
			if (DECI.NST && DECI.LST) begin
				EX_IC <= DI_IC;

				if (FIQ && !CPSR.F) begin
					EX_IC <= 32'hEF000000;
					FIQ_PEND <= 1;
				end
				else if (IRQ && !CPSR.I) begin
					EX_IC <= 32'hEF000000;
					IRQ_PEND <= 1;
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
	bit          SHIFT_C;
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
			1'b0: MD = DIN;
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
			SHFT_NONE:  begin SHIFT_SA = '0;                        SHIFT_TYPE = 3'b000; end
			SHFT_CONST: begin SHIFT_SA = {3'b000,EX_IC[11:7]};      SHIFT_TYPE = {1'b1,EX_IC[6:5]}; end
			SHFT_REG:   begin SHIFT_SA = SHIFT_LATCH;               SHIFT_TYPE = {1'b0,EX_IC[6:5]}; end
			SHFT_ROT:   begin SHIFT_SA = {3'b000,EX_IC[11:8],1'b0}; SHIFT_TYPE = 3'b011; end
			SHFT_LSL2:  begin SHIFT_SA = 8'd2;                      SHIFT_TYPE = 3'b000; end
		endcase
		
		{SHIFT_C,SHIFT_RES} = Shifter(SHIFT_A, SHIFT_SA, SHIFT_TYPE, CPSR.C);
		
		MUL_RES = BoothMul(RB_RBQ, MUL_SHIFT[1:0], MUL_STEP);
	end 
	
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) begin
			ALU_A <= '0;
			ALU_B <= '0;
			ALU_SHC <= 0;
		end
		else if (EN && CE_R) begin
			if (DECI.DPCTL.ALULTCH) begin
				ALU_A <= DECI.DPCTL.SA ? PSR_RES : RB_RAQ; 
				ALU_B <= DECI.DPCTL.MCTL == MUL_EXE ? MUL_RES : SHIFT_RES; 
				ALU_SHC <= SHIFT_C; 
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
		
		{ADD_C,ADD_RES} = Adder(ALU_A, ALU_B, CPSR.C, DECI.ALU.CD); 
		{ADD_A_SIGN,ADD_B_SIGN,ADD_R_SIGN} = !DECI.ALU.CD[1] ? {ALU_A[31],ALU_B[31],ADD_RES[31]} : {ALU_B[31],ALU_A[31],ADD_RES[31]};
		ADD_Z = ~|ADD_RES;
		ADD_C = (ADD_A_SIGN & (ADD_B_SIGN ^ DECI.ALU.CD[0])) | ((ADD_A_SIGN | (ADD_B_SIGN ^ DECI.ALU.CD[0])) & ~ADD_R_SIGN); 
		ADD_V = (ADD_A_SIGN & ((ADD_B_SIGN ^ DECI.ALU.CD[0]) & ~ADD_R_SIGN)) | (~ADD_A_SIGN & (~ADD_B_SIGN ^ DECI.ALU.CD[0]) & ADD_R_SIGN); 
		
		LOG_RES = Log(ALU_A, ALU_B, DECI.ALU.CD); 
		LOG_Z = ~|LOG_RES;
		LOG_V = CPSR.V;
		
		case (DECI.ALU.OP)
			ALUT_ADD: {ALU_N,ALU_Z,ALU_C,ALU_V,ALU_R} = {ADD_RES[31],ADD_Z ,ADD_C  ,ADD_V ,ADD_RES};
			ALUT_LOG: {ALU_N,ALU_Z,ALU_C,ALU_V,ALU_R} = {LOG_RES[31],LOG_Z ,ALU_SHC,LOG_V ,LOG_RES};
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
	
	assign PC_D = AREG_NEXT;
	assign PC_WE = DECI.PCU;
	
	//PSR
	always_comb begin
		CPSR_NEXT <= CPSR;
		case (DECI.PSRCTL)
			PSRC_ALU: if (!EX_IC[22]) 
				case (CPSR.M)
					5'b10000: CPSR_NEXT[31:28] <= ALU_R[31:28];
					5'b10001,
					5'b10010,
					5'b10011,
					5'b10111,
					5'b11011: begin
						// MSR flags-only must preserve the CPSR control field.
						if (EX_IC[16]) CPSR_NEXT <= ALU_R;
						else CPSR_NEXT[31:28] <= ALU_R[31:28];
					end
					default: ;
				endcase
					
			PSRC_FLG: {CPSR_NEXT.N,CPSR_NEXT.Z,CPSR_NEXT.C,CPSR_NEXT.V} <= {ALU_N,ALU_Z,ALU_C,ALU_V}; 
			
			PSRC_INT: if (FIQ_PEND) {CPSR_NEXT.I,CPSR_NEXT.F,CPSR_NEXT.M} <= {1'b1,1'b1,5'b10001};
						 else if (IRQ_PEND) {CPSR_NEXT.I,CPSR_NEXT.M} <= {1'b1,5'b10010};
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
				PSRC_ALU: if (EX_IC[22])
					case (CPSR.M)
						5'b10001: SPSR[1] <= ALU_R;
						5'b10010: SPSR[2] <= ALU_R;
						5'b10011: SPSR[3] <= ALU_R;
						5'b10111: SPSR[4] <= ALU_R;
						5'b11011: SPSR[5] <= ALU_R;
						default:;
					endcase
				
				PSRC_INT: 
					if (FIQ_PEND) begin SPSR[1] <= CPSR; end
					else if (IRQ_PEND) begin SPSR[2] <= CPSR; end
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
				ADR_VEC: AREG <= RESET_PEND ? 32'h00000000 : FIQ_PEND ? 32'h0000001C : IRQ_PEND ? 32'h00000018 : 32'h00000008;//for SWI
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
	assign nTRANS = ~(CPSR.M[3:0] == 4'b0000) || (EX_IC[27:24] == 4'b1111);
	assign LOCK = DECI.LOCK;
	
`ifdef DEBUG
	assign ILI = DECI.ILI;
`endif
	
endmodule
