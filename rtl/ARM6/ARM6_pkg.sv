package ARM6_PKG;
	
	typedef struct packed
	{
		bit         N;
		bit         Z;
		bit         C;
		bit         V;
		bit [19: 0] UNUSED;
		bit         I;
		bit         F;
		bit         UNUSED2;
		bit [ 4: 0] M;
	} PSR_t; 
	

	typedef enum bit[2:0] {
		ALUT_NOP = 3'b000, 
		ALUT_ADD = 3'b001, 
		ALUT_LOG = 3'b010,
		ALUT_MUL = 3'b011,
		ALUT_A   = 3'b100,
		ALUT_B   = 3'b101
	} ALUType_t; 

	typedef enum bit[2:0] {
		IMM_DAT  = 3'b000, 
		IMM_U8   = 3'b001, 
		IMM_U12  = 3'b010, 
		IMM_S24  = 3'b011,
		IMM_OFFS = 3'b100,
		IMM_ZERO = 3'b101,
		IMM_ONE  = 3'b110
	} ImmType_t; 

	typedef enum bit[2:0] {
		SHFT_NONE  = 3'b000, 
		SHFT_CONST = 3'b001, 
		SHFT_REG   = 3'b010, 
		SHFT_ROT   = 3'b011,
		SHFT_LSL2  = 3'b100 
	} ShiftCtrl_t;

	typedef enum bit[1:0] {
		MUL_NOP = 2'b00, 
		MUL_SET = 2'b01, 
		MUL_EXE = 2'b10
	} MulCtrl_t;

	typedef enum bit[2:0] {
		PSRC_NOP = 3'b000, 
		PSRC_ALU = 3'b001, 
		PSRC_FLG = 3'b010, 
		PSRC_RET = 3'b011,
		PSRC_INT = 3'b100,
		PSRC_USR = 3'b101
	} PSRCtrl_t;
	
	typedef enum bit[2:0] {
		ADR_INC = 3'b000, 
		ADR_PC  = 3'b001, 
		ADR_ALU = 3'b010, 
		ADR_ALUI = 3'b011, 
		ADR_VEC = 3'b100
	} AddrType_t; 
	
	typedef struct packed
	{
		bit          SA;
		bit          SB;
		ImmType_t    IMMT;
		ShiftCtrl_t  SHCTL;
		MulCtrl_t    MCTL;
		bit          SHLTCH;
		bit          ALULTCH;
	} DPCtrl_t;
	
	typedef struct packed
	{
		ALUType_t    OP;		//ALU operation type
		bit [3:0]    CD;		//ALU operation code
	} ALUCtrl_t;  
	
	typedef struct packed
	{
		bit [3:0]    RAN;		//Register A read
		bit [3:0]    RBN;		//Register B read
		bit [3:0]    WN;		//Register write
		bit          RRE;		//Register read
		bit          RWE;		//Register write
		bit          BINI;	//Register block init
		bit          BRE;		//Register block read
		bit          BWE;		//Register block write
	} RegCtrl_t; 
	
	typedef struct packed
	{
		AddrType_t   ADR;
		bit          RD;
		bit          WR;
		bit          SZ;
	} MemCtrl_t;
	
	typedef struct packed
	{
		DPCtrl_t     DPCTL;
		ALUCtrl_t    ALU;
		RegCtrl_t    RCTL;
		PSRCtrl_t    PSRCTL;
		MemCtrl_t    MCTL;
		bit          PCU;		//Register 15 update
		bit          STALL;
		bit          NST;		//Next state
		bit          LST;		//Last state
		bit          ILI;		//Illegal instruction
		bit          ICYC;
		bit          CCYC;
		bit          LOCK;
	} DecInstr_t; 
	
	parameter DecInstr_t DECI_NOP = '{'{1'b0, 1'b0, IMM_DAT, SHFT_NONE, MUL_NOP, 1'b0, 1'b0},
												 '{ALUT_NOP, 4'b0000},
												 '{4'h0, 4'h0, 4'h0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0},
												 PSRC_NOP,
												 '{ADR_INC, 1'b0, 1'b0, 1'b0},
												 1'b1,
												 1'b0,
												 1'b1,
												 1'b1,
												 1'b0,
												 1'b0,
												 1'b0,
												 1'b0}; 

	
	typedef enum {
		CYC_NO_OP, 
		CYC_SHIFT_READ,
		CYC_DATA_OP, 
		CYC_MUL_INIT, 
		CYC_MUL_EXEC, 
		CYC_PSR_READ,
		CYC_PSR_WRITE,
		CYC_SWAP_ADDR, 
		CYC_SWAP_READ, 
		CYC_SWAP_WRITE, 
		CYC_SWAP_END,
		CYC_TRANS_ADDR,
		CYC_TRANS_STORE,
		CYC_TRANS_LOAD,
		CYC_TRANS_WB,
		CYC_BLOCK_ADDR,
		CYC_BLOCK_STORE,
		CYC_BLOCK_LOAD,
		CYC_BLOCK_LOAD_WB,
		CYC_BLOCK_WB,
		CYC_BRANCH_OFFS,
		CYC_BRANCH_RETURN,
		CYC_RETURN_ADJUST,
		CYC_INT_ADDR
	} CycleOp_t; 

	function DecInstr_t Decode(input [31:0] IC, input [4:0] STATE, PSR_t PSR, input [3:0] BLOCK_RD, input [3:0] BLOCK_WN, input BLOCK_WE, input BLOCK_LAST, input MUL_LAST);
		CycleOp_t CYC;
		DecInstr_t DECI; 
		bit [3:0] Rn, Rm, Rs, Rd; 

		CYC = CYC_NO_OP;
		
		Rn = IC[19:16];
		Rm = IC[3:0];
		Rs = IC[11:8];
		Rd = IC[15:12];
		
		DECI.PCU = 1;
		DECI.STALL = 0;
		DECI.NST = 1;
		DECI.LST = 1;
		DECI.ILI = 0;
		DECI.ICYC = 0;
		DECI.CCYC = 0;
		DECI.LOCK = 0;
		casex ({IC[27:20],IC[7:4]})
			12'b0000xxxx_xxx0,
			12'b00010xx1_xxx0,
			12'b00011xxx_xxx0,
			12'b0010xxxx_xxxx,
			12'b00110xx1_xxxx,
			12'b00111xxx_xxxx: begin
				case (STATE)
				5'd0: begin
					CYC = CYC_DATA_OP;
					DECI.PCU = 1;
					DECI.LST = (Rd != 4'd15);
				end
				5'd1: begin
					CYC = CYC_NO_OP;
					DECI.PCU = 1;
					DECI.LST = 0;
				end
				default: begin
					CYC = CYC_NO_OP;
					DECI.PCU = 1;
					DECI.LST = 1;
				end
				endcase
			end
			12'b0000xxxx_0xx1,
			12'b00010xx1_0xx1,
			12'b00011xxx_0xx1: begin
				case (STATE)
				5'd0: begin
					CYC = CYC_SHIFT_READ;
					DECI.PCU = 1;
					DECI.LST = 0;
					DECI.ICYC = 1;
				end
				5'd1: begin
					CYC = CYC_DATA_OP;
					DECI.PCU = 0;
					DECI.STALL = 1;
					DECI.LST = (Rd != 4'd15);
				end
				5'd2: begin
					CYC = CYC_NO_OP;
					DECI.PCU = 1;
					DECI.LST = 0;
				end
				default: begin
					CYC = CYC_NO_OP;
					DECI.PCU = 1;
					DECI.LST = 1;
				end
				endcase
			end
			
			12'b000000xx_1001: begin //MUL Rd,Rm,Rs; MLA Rd,Rm,Rs,Rn
				case (STATE)
				5'd0: begin
					CYC = CYC_MUL_INIT;
					DECI.PCU = 1;
					DECI.LST = 0;
					DECI.ICYC = 1;
				end
				default: begin
					CYC = CYC_MUL_EXEC;
					DECI.PCU = 0;
					DECI.STALL = 1;
					DECI.NST = MUL_LAST;
					DECI.LST = 1;
					DECI.ICYC = ~MUL_LAST;
				end
				endcase
			end
			
			12'b00010x00_xxx0: begin 	//MRS Rd,PSR
				CYC = CYC_PSR_READ;
				DECI.PCU = 1;
				DECI.LST = 1;
			end
			
			12'b00010x10_xxx0: begin 	//MSR PSR,Rm
				CYC = CYC_PSR_WRITE;
				DECI.PCU = 1;
				DECI.LST = 1;
			end
			
			12'b00010xxx_1001: begin //SWP{B} Rd,Rm,[Rn]
				case (STATE)
				5'd0: begin
					CYC = CYC_SWAP_ADDR;
					DECI.PCU = 1;
					DECI.LST = 0;
				end
				5'd1: begin
					CYC = CYC_SWAP_READ;
					DECI.PCU = 0;
					DECI.STALL = 1;
					DECI.LST = 0;
					DECI.LOCK = 1;
				end
				5'd2: begin
					CYC = CYC_SWAP_WRITE;
					DECI.PCU = 0;
					DECI.STALL = 1;
					DECI.LST = 0;
					DECI.ICYC = 1;
					DECI.LOCK = 1;
				end
				default: begin
					CYC = CYC_SWAP_END;
					DECI.PCU = 0;
					DECI.STALL = 1;
					DECI.LST = 1;
				end
				endcase
			end
			
			12'b010xxxx0_xxxx, 			//STR{B} Rd,Rn,#imm
			12'b011xxxx0_xxx0: begin 	//STR{B} Rd,Rn,Rm shift#
				case (STATE)
				5'd0: begin
					CYC = CYC_TRANS_ADDR;
					DECI.PCU = 1;
					DECI.LST = 0;
				end
				default: begin
					CYC = CYC_TRANS_STORE;
					DECI.PCU = 0;
					DECI.STALL = 1;
					DECI.LST = 1;
				end
				endcase
			end
			12'b010xxxx1_xxxx,			//LDR{B} Rd,Rn,#imm
			12'b011xxxx1_xxx0: begin 	//LDR{B} Rd,Rn,Rm shift#
				case (STATE)
				5'd0: begin
					CYC = CYC_TRANS_ADDR;
					DECI.PCU = 1;
					DECI.LST = 0;
				end
				5'd1: begin
					CYC = CYC_TRANS_LOAD;
					DECI.PCU = 0;
					DECI.STALL = 1;
					DECI.LST = 0;
					DECI.ICYC = 1;
				end
				5'd2: begin
					CYC = CYC_TRANS_WB;
					DECI.PCU = 0;
					DECI.STALL = 1;
					DECI.LST = (Rd != 4'd15);
				end
				5'd3: begin
					CYC = CYC_NO_OP;
					DECI.PCU = 1;
					DECI.LST = 0;
				end
				default: begin
					CYC = CYC_NO_OP;
					DECI.PCU = 1;
					DECI.LST = 1;
				end
				endcase
			end
			
			12'b100xxxx0_xxxx: begin //STM Rn, list
				case (STATE)
				5'd0: begin
					CYC = CYC_BLOCK_ADDR;
					DECI.PCU = 1;
					DECI.LST = 0;
				end
				default: begin
					CYC = CYC_BLOCK_STORE;
					DECI.PCU = 0;
					DECI.STALL = 1;
					DECI.NST = BLOCK_LAST;
					DECI.LST = 1;
				end
				endcase
			end
			12'b100xxxx1_xxxx: begin //LDM Rn, list
				case (STATE)
				5'd0: begin
					CYC = CYC_BLOCK_ADDR;
					DECI.PCU = 1;
					DECI.LST = 0;
				end
				5'd1: begin
					CYC = BLOCK_WE ? CYC_BLOCK_LOAD_WB : CYC_BLOCK_LOAD;
					DECI.PCU = 0;
					DECI.STALL = 1;
					DECI.NST = BLOCK_LAST;
					DECI.LST = 0;
					DECI.ICYC = BLOCK_LAST;
				end
				5'd2: begin
					CYC = CYC_BLOCK_WB;
					DECI.PCU = 0;
					DECI.STALL = 1;
					DECI.NST = 1;
					DECI.LST = (BLOCK_WN != 4'd15);
					DECI.ICYC = 0;
				end
				5'd3: begin
					CYC = CYC_NO_OP;
					DECI.PCU = 1;
					DECI.LST = 0;
				end
				default: begin
					CYC = CYC_NO_OP;
					DECI.PCU = 1;
					DECI.LST = 1;
				end
				endcase
			end
			
			12'b101xxxxx_xxxx: begin //B{L} #offset
				case (STATE)
				5'd0: begin
					CYC = CYC_BRANCH_OFFS;
					DECI.PCU = 0;
					DECI.LST = 0;
				end
				5'd1: begin
					CYC = CYC_BRANCH_RETURN;
					DECI.PCU = 0;
					DECI.LST = 0;
				end
				default: begin
					CYC = CYC_RETURN_ADJUST;
					DECI.PCU = 1;
					DECI.LST = 1;
				end
				endcase
			end
			
			12'b1110xxxx_xxx0: begin //CDP 
				CYC = CYC_NO_OP;
				DECI.PCU = 1;
				DECI.LST = 1;
			end
			
			12'b1111xxxx_xxxx: begin //SWI #offset
				case (STATE)
				5'd0: begin
					CYC = CYC_INT_ADDR;
					DECI.PCU = 0;
					DECI.LST = 0;
				end
				5'd1: begin
					CYC = CYC_RETURN_ADJUST;
					DECI.PCU = 0;
					DECI.LST = 0;
				end
				default: begin
					CYC = CYC_NO_OP;
					DECI.PCU = 1;
					DECI.LST = 1;
				end
				endcase
			end
			
			default: DECI.ILI = 1;
		endcase 
		
		DECI.DPCTL = {1'b0, 1'b0, IMM_DAT, SHFT_NONE, MUL_NOP, 1'b0, 1'b0};
		DECI.ALU = {ALUT_NOP, 4'b0000};
		DECI.RCTL = {4'd0, 4'd0, 4'd0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0};
		DECI.PSRCTL = PSRC_NOP;
		DECI.MCTL = {ADR_INC, 1'b0, 1'b0, 1'b0};
		case (CYC)
			CYC_NO_OP: begin
			end
			
			CYC_SHIFT_READ: begin
				DECI.DPCTL = {1'b0, 1'b0, IMM_DAT, SHFT_NONE, MUL_NOP, 1'b1, 1'b1};
				DECI.ALU = {ALUT_B, 4'b0000};
				DECI.RCTL = {4'd0, Rs, 4'd0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0};
			end
			
			CYC_DATA_OP: begin
				DECI.DPCTL = {1'b0, IC[25], IMM_U8, IC[25] ? SHFT_ROT : IC[4] ? SHFT_REG : SHFT_CONST, MUL_NOP, 1'b0, 1'b1};
				case (IC[24:21])
					4'b0000: DECI.ALU = {ALUT_LOG, 4'b0000}; //AND
					4'b0001: DECI.ALU = {ALUT_LOG, 4'b0001}; //EOR
					4'b0010: DECI.ALU = {ALUT_ADD, 4'b0001}; //SUB
					4'b0011: DECI.ALU = {ALUT_ADD, 4'b0011}; //RSB
					4'b0100: DECI.ALU = {ALUT_ADD, 4'b0000}; //ADD
					4'b0101: DECI.ALU = {ALUT_ADD, 4'b0100}; //ADC
					4'b0110: DECI.ALU = {ALUT_ADD, 4'b0101}; //SBC
					4'b0111: DECI.ALU = {ALUT_ADD, 4'b0111}; //RSC
					4'b1000: DECI.ALU = {ALUT_LOG, 4'b0000}; //TST
					4'b1001: DECI.ALU = {ALUT_LOG, 4'b0001}; //TEQ
					4'b1010: DECI.ALU = {ALUT_ADD, 4'b0001}; //CMP
					4'b1011: DECI.ALU = {ALUT_ADD, 4'b0000}; //CMN
					4'b1100: DECI.ALU = {ALUT_LOG, 4'b0010}; //ORR
					4'b1101: DECI.ALU = {ALUT_LOG, 4'b0011}; //MOV
					4'b1110: DECI.ALU = {ALUT_LOG, 4'b0100}; //BIC
					4'b1111: DECI.ALU = {ALUT_LOG, 4'b0111}; //MVN
				endcase
				DECI.RCTL = {Rn, Rm, Rd, 1'b1, ~IC[24]|IC[23], 1'b0, 1'b0, 1'b0};
				DECI.PSRCTL = Rd == 4'd15 && IC[20] ? PSRC_RET : IC[20] ? PSRC_FLG : PSRC_NOP;
				DECI.MCTL = {Rd != 4'd15 ? (DECI.PCU ? ADR_INC : ADR_PC) : ADR_ALU, 1'b0, 1'b0, 1'b0};
			end
			
			CYC_MUL_INIT: begin
				DECI.DPCTL = {1'b0, ~IC[21], IMM_ZERO, SHFT_NONE, MUL_SET, 1'b0, 1'b1};
				DECI.ALU = {ALUT_B, 4'b0000};
				DECI.RCTL = {Rs, IC[15:12], IC[19:16], 1'b1, 1'b1, 1'b0, 1'b0, 1'b0};
				DECI.MCTL = {ADR_INC, 1'b0, 1'b0, 1'b0};
			end
				
			CYC_MUL_EXEC: begin
				DECI.DPCTL = {1'b0, 1'b0, IMM_ZERO, SHFT_NONE, MUL_EXE, 1'b0, 1'b1};
				DECI.ALU = {ALUT_MUL, 4'b0000};
				DECI.RCTL = {IC[19:16], Rm, IC[19:16], 1'b1, 1'b1, 1'b0, 1'b0, 1'b0};
				DECI.PSRCTL = IC[20] ? PSRC_FLG : PSRC_NOP;
				DECI.MCTL = {ADR_PC, 1'b0, 1'b0, 1'b0};
			end
				
			CYC_PSR_READ: begin
				DECI.DPCTL = {1'b1, 1'b0, IMM_DAT, SHFT_NONE, MUL_NOP, 1'b0, 1'b1};
				DECI.ALU = {ALUT_A, 4'b0000};
				DECI.RCTL = {4'd0, 4'd0, Rd, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0};
			end
				
			CYC_PSR_WRITE: begin
				DECI.DPCTL = {1'b0, 1'b0, IMM_DAT, IC[25] ? SHFT_ROT : IC[4] ? SHFT_REG : SHFT_CONST, MUL_NOP, 1'b0, 1'b1};
				DECI.ALU = {ALUT_B, 4'b0000};
				DECI.RCTL = {4'd0, Rm, Rd, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0};
				DECI.PSRCTL = PSRC_ALU;
			end
			
			CYC_SWAP_ADDR: begin
				DECI.DPCTL = {1'b0, 1'b0, IMM_DAT, SHFT_NONE, MUL_NOP, 1'b0, 1'b1};
				DECI.ALU = {ALUT_A, 4'b0000};
				DECI.RCTL = {Rn, 4'd0, 4'd0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0};
				DECI.MCTL = {ADR_ALU, 1'b0, 1'b0, 1'b0};
			end
			
			CYC_SWAP_READ: begin
				DECI.ALU = {ALUT_A, 4'b0000};
				DECI.RCTL = {4'd0, 4'd0, 4'd0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0};
				DECI.MCTL = {ADR_ALU, 1'b1, 1'b0, IC[22]};
			end
			
			CYC_SWAP_WRITE: begin
				DECI.DPCTL = {1'b0, 1'b1, IMM_DAT, SHFT_NONE, MUL_NOP, 1'b0, 1'b1};
				DECI.ALU = {ALUT_B, 4'b0000};
				DECI.RCTL = {4'd0, Rm, Rd, 1'b1, 1'b1, 1'b0, 1'b0, 1'b0};
				DECI.MCTL = {ADR_PC, 1'b0, 1'b1, IC[22]};
			end
			
			CYC_SWAP_END: begin
				DECI.MCTL = {ADR_PC, 1'b0, 1'b0, 1'b0};
			end
			
			CYC_TRANS_ADDR: begin
				DECI.DPCTL = {1'b0, ~IC[25], IMM_U12, IC[25] ? SHFT_CONST : SHFT_NONE, MUL_NOP, 1'b0, 1'b1};
				DECI.ALU = {IC[24] ? ALUT_ADD : ALUT_A, {3'b000,~IC[23]}};
				DECI.RCTL = {Rn, Rm, Rd, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0};
				DECI.MCTL = {ADR_ALU, 1'b0, 1'b0, 1'b0};
			end
			
			CYC_TRANS_STORE: begin
				DECI.ALU = {ALUT_ADD, {3'b000,~IC[23]}};
				DECI.RCTL = {4'd0, Rd, Rn, 1'b0, IC[21]|~IC[24], 1'b0, 1'b0, 1'b0};
				DECI.MCTL = {ADR_PC, 1'b0, 1'b1, IC[22]};
			end
				
			CYC_TRANS_LOAD: begin
				DECI.ALU = {ALUT_ADD, {3'b000,~IC[23]}};
				DECI.RCTL = {4'd0, 4'd0, Rn, 1'b0, IC[21]|~IC[24], 1'b0, 1'b0, 1'b0};
				DECI.MCTL = {ADR_PC, 1'b1, 1'b0, IC[22]};
			end
			
			CYC_TRANS_WB: begin
				DECI.DPCTL = {1'b0, 1'b1, IMM_DAT, SHFT_NONE, MUL_NOP, 1'b0, 1'b1};
				DECI.ALU = {ALUT_B, 4'b0000};
				DECI.RCTL = {4'd0, 4'd0, Rd, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0};
				DECI.MCTL = {Rd != 4'd15 ? ADR_PC : ADR_ALU, 1'b0, 1'b0, IC[22]};
			end
				
			CYC_BLOCK_ADDR: begin
				DECI.DPCTL = {1'b0, 1'b1, IMM_OFFS, SHFT_LSL2, MUL_NOP, 1'b0, 1'b1};
				DECI.ALU = {IC[23] ? ALUT_A : ALUT_ADD, {3'b000,~IC[23]}};
				DECI.RCTL = {Rn, 4'd0, Rd, 1'b1, 1'b0, 1'b1, 1'b0, 1'b0};
				DECI.MCTL = {IC[24]^IC[23] ? ADR_ALU : ADR_ALUI, 1'b0, 1'b0, 1'b0};
			end
			
			CYC_BLOCK_STORE: begin
				DECI.ALU = {ALUT_ADD, {3'b000,~IC[23]}};
				DECI.RCTL = {4'd0, BLOCK_RD, Rn, 1'b0, IC[21], 1'b0, 1'b1, 1'b0};
				DECI.MCTL = {!BLOCK_LAST ? ADR_INC : ADR_PC, 1'b0, 1'b1, 1'b0};
				DECI.PSRCTL = IC[22] && !IC[15] ? PSRC_USR : PSRC_NOP;
			end
			
			CYC_BLOCK_LOAD: begin
				DECI.ALU = {ALUT_ADD, {3'b000,~IC[23]}};
				DECI.RCTL = {4'd0, 4'd0, Rn, 1'b0, IC[21], 1'b0, 1'b1, 1'b0};
				DECI.MCTL = {!BLOCK_LAST ? ADR_INC : ADR_PC, 1'b1, 1'b0, 1'b0};
				DECI.PSRCTL = IC[22] && !IC[15] ? PSRC_USR: PSRC_NOP;
			end
			
			CYC_BLOCK_LOAD_WB: begin
				DECI.DPCTL = {1'b0, 1'b1, IMM_DAT, SHFT_NONE, MUL_NOP, 1'b0, 1'b1};
				DECI.ALU = {ALUT_B, 4'b0000};
				DECI.RCTL = {4'd0, 4'd0, BLOCK_WN, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0};
				DECI.MCTL = {!BLOCK_LAST ? ADR_INC : ADR_PC, 1'b0, 1'b0, 1'b0};
				DECI.PSRCTL = IC[22] && !IC[15] ? PSRC_USR :
				              IC[22] &&  IC[15] && BLOCK_WN == 4'd15 ? PSRC_RET : PSRC_NOP;
			end
			
			CYC_BLOCK_WB: begin
				DECI.DPCTL = {1'b0, 1'b1, IMM_DAT, SHFT_NONE, MUL_NOP, 1'b0, 1'b1};
				DECI.ALU = {ALUT_B, 4'b0000};
				DECI.RCTL = {4'd0, 4'd0, BLOCK_WN, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0};
				DECI.MCTL = {BLOCK_WN != 4'd15 ? ADR_PC : ADR_ALU, 1'b0, 1'b0, 1'b0};
				DECI.PSRCTL = IC[22] && !IC[15] ? PSRC_USR :
				              IC[22] &&  IC[15] && BLOCK_WN == 4'd15 ? PSRC_RET : PSRC_NOP;
			end
			
			CYC_BRANCH_OFFS: begin
				DECI.DPCTL = {1'b0, 1'b1, IMM_S24, SHFT_LSL2, MUL_NOP, 1'b0, 1'b1};
				DECI.ALU = {ALUT_ADD, 4'b0000};
				DECI.RCTL = {4'd15, 4'd0, 4'd0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0};
				DECI.MCTL = {ADR_ALU, 1'b0, 1'b0, 1'b0};
			end
			
			CYC_BRANCH_RETURN: begin
				DECI.DPCTL = {1'b0, 1'b0, IMM_ZERO, SHFT_NONE, MUL_NOP, 1'b0, 1'b1};
				DECI.ALU = {ALUT_A, 4'b0000};
				DECI.RCTL = {4'd15, 4'd0, 4'd14, 1'b1, IC[24], 1'b0, 1'b0, 1'b0};
			end
			
			CYC_RETURN_ADJUST: begin
				DECI.DPCTL = {1'b0, 1'b1, IMM_ONE, SHFT_LSL2, MUL_NOP, 1'b0, 1'b1};
				DECI.ALU = {ALUT_ADD, 4'b0001};
				DECI.RCTL = {4'd14, 4'd0, 4'd14, 1'b1, IC[24], 1'b0, 1'b0, 1'b0};
			end
			
			CYC_INT_ADDR: begin
				DECI.DPCTL = {1'b0, 1'b0, IMM_ZERO, SHFT_NONE, MUL_NOP, 1'b0, 1'b1};
				DECI.ALU = {ALUT_A, 4'b0000};
				DECI.RCTL = {4'd15, 4'd0, 4'd14, 1'b1, 1'b1, 1'b0, 1'b0, 1'b0};
				DECI.MCTL = {ADR_VEC, 1'b0, 1'b0, 1'b0};
				DECI.PSRCTL = PSRC_INT;
			end
			
			default: begin
				
			end
		endcase
		
		return DECI; 
	endfunction	
	
	function bit [32:0] Shifter(input bit [31:0] val, input bit [7:0] sa, input bit [2:0] t, input bit ci);
		bit [31: 0] tmp0, tmp1, tmp2, tmp3, tmp4, tmp5;
		bit         cl0, cl1, cl2, cl3, cl4, cl5;
		bit         cr0, cr1, cr2, cr3, cr4, cr5;
		bit         rot,arith,dir,rrx;
		
		{rot,arith,dir} = {&t[1:0],t[1]&~t[0],|t[1:0]};
		rrx = (t == 3'b111 && sa == 8'h00);
		
		{cl0,tmp0,cr0} = !sa[0]   ? {1'b0,  val, 1'b0} : (dir ? { 1'b0,  val[ 0: 0]&{ 1{rot}}|{ 1{ val[31]}}&{ 1{arith}},  val[31: 1],  val[ 0]} : { val[31],  val[30:0], { 1{1'b0}}, 1'b0 });
		{cl1,tmp1,cr1} = !sa[1]   ? { cl0, tmp0,  cr0} : (dir ? { 1'b0, tmp0[ 1: 0]&{ 2{rot}}|{ 2{tmp0[31]}}&{ 2{arith}}, tmp0[31: 2], tmp0[ 1]} : {tmp0[30], tmp0[29:0], { 2{1'b0}}, 1'b0 });
		{cl2,tmp2,cr2} = !sa[2]   ? { cl1, tmp1,  cr1} : (dir ? { 1'b0, tmp1[ 3: 0]&{ 4{rot}}|{ 4{tmp1[31]}}&{ 4{arith}}, tmp1[31: 4], tmp1[ 3]} : {tmp1[28], tmp1[27:0], { 4{1'b0}}, 1'b0 });
		{cl3,tmp3,cr3} = !sa[3]   ? { cl2, tmp2,  cr2} : (dir ? { 1'b0, tmp2[ 7: 0]&{ 8{rot}}|{ 8{tmp2[31]}}&{ 8{arith}}, tmp2[31: 8], tmp2[ 7]} : {tmp2[24], tmp2[23:0], { 8{1'b0}}, 1'b0 });
		{cl4,tmp4,cr4} = !sa[4]   ? { cl3, tmp3,  cr3} : (dir ? { 1'b0, tmp3[15: 0]&{16{rot}}|{16{tmp3[31]}}&{16{arith}}, tmp3[31:16], tmp3[15]} : {tmp3[16], tmp3[15:0], {16{1'b0}}, 1'b0 });
		{cl5,tmp5,cr5} = !sa[7:5] ? { cl4, tmp4,  cr4} : (dir ? { 1'b0, tmp4[31: 0]&{32{rot}}|{32{tmp4[31]}}&{32{arith}},              tmp4[31]} : {tmp4[ 0],             {32{1'b0}}, 1'b0 });
		// Zero register shifts, immediate rotates and immediate LSL preserve carry.
		// Immediate LSR/ASR encoded zero and RRX are not zero-count operations.
		if (sa == 8'h00 && (!t[2] || t[1:0] == 2'b00))
			return {ci,val};
		return rrx ? {val[0],ci,val[31:1]} : {dir?cr5:cl5,tmp5};
	endfunction
	
	function bit [32:0] Adder(input bit [31:0] a, input bit [31:0] b, input bit ci, input bit [3:0] code);
		bit [31:0] a2,b2;
		bit        ci2;
		bit [32:0] sum;
		
		a2 = a ^ {32{ code[1]&code[0]}};
		b2 = b ^ {32{~code[1]&code[0]}};
		ci2 = code[2] ? ci : code[3] ^ code[0];
		sum = {1'b0,a2} + {1'b0,b2} + {{32{1'b0}},ci2};
		
		return {sum[32],sum[31:0]};
	endfunction 

	
	function bit [31:0] Log(input bit [31:0] a, input bit [31:0] b, input bit [3:0] code);
		bit [31:0] b2;
		bit [31:0] res;
		
		b2 = b ^ {32{code[2]}};
		case (code[1:0])
			2'b00: res = a & b2;
			2'b01: res = a ^ b2;
			2'b10: res = a | b2;
			2'b11: res = b2;
		endcase
	
		return res;
	endfunction 
	
	function bit [31:0] BoothMul(input bit [31:0] a, input bit [1:0] b, input bit [3:0] step);
		bit [31:0] t0;
		bit [31:0] t1;
		
		t0 = (a & {32{b[0]}}) << {step,1'b0};
		t1 = (a & {32{b[1]}}) << {step,1'b1};
	
		return t0 + t1;
	endfunction 
	
	function bit [4:0] BlockOffset(input bit [15:0] list);
		bit [ 1: 0] sum0[8];
		bit [ 2: 0] sum1[4];
		bit [ 3: 0] sum2[2];
		bit [ 4: 0] sum3;
		
		sum0[0] = {1'b0,list[ 0]} + {1'b0,list[ 1]};
		sum0[1] = {1'b0,list[ 2]} + {1'b0,list[ 3]};
		sum0[2] = {1'b0,list[ 4]} + {1'b0,list[ 5]};
		sum0[3] = {1'b0,list[ 6]} + {1'b0,list[ 7]};
		sum0[4] = {1'b0,list[ 8]} + {1'b0,list[ 9]};
		sum0[5] = {1'b0,list[10]} + {1'b0,list[11]};
		sum0[6] = {1'b0,list[12]} + {1'b0,list[13]};
		sum0[7] = {1'b0,list[14]} + {1'b0,list[15]};
		
		sum1[0] = {1'b0,sum0[ 0]} + {1'b0,sum0[ 1]};
		sum1[1] = {1'b0,sum0[ 2]} + {1'b0,sum0[ 3]};
		sum1[2] = {1'b0,sum0[ 4]} + {1'b0,sum0[ 5]};
		sum1[3] = {1'b0,sum0[ 6]} + {1'b0,sum0[ 7]};
		
		sum2[0] = {1'b0,sum1[ 0]} + {1'b0,sum1[ 1]};
		sum2[1] = {1'b0,sum1[ 2]} + {1'b0,sum1[ 3]};
		
		sum3    = {1'b0,sum2[ 0]} + {1'b0,sum2[ 1]};
	
		return sum3;
	endfunction 
	
	function bit [3:0] RegFromList(input bit [15:0] list, input bit [3:0] from);
		bit [15:0] mask;
		bit [15:0] temp;
		bit [3:0] r;
		
		mask = 16'hFFFF << from;
		temp = list & mask;
		
		r = 4'd0;
		if (temp[15]) r = 4'd15;
		if (temp[14]) r = 4'd14;
		if (temp[13]) r = 4'd13;
		if (temp[12]) r = 4'd12;
		if (temp[11]) r = 4'd11;
		if (temp[10]) r = 4'd10;
		if (temp[ 9]) r = 4'd9;
		if (temp[ 8]) r = 4'd8;
		if (temp[ 7]) r = 4'd7;
		if (temp[ 6]) r = 4'd6;
		if (temp[ 5]) r = 4'd5;
		if (temp[ 4]) r = 4'd4;
		if (temp[ 3]) r = 4'd3;
		if (temp[ 2]) r = 4'd2;
		if (temp[ 1]) r = 4'd1;
		if (temp[ 0]) r = 4'd0;
	
		return r;
	endfunction 
	
	function bit LastInList(input bit [15:0] list, input bit [3:0] curr);
		bit [15:0] mask;
		bit        res;
		
		mask = 16'hFFFE << curr;
		res = ~|(list & mask);
		
		return res;
	endfunction 

endpackage
