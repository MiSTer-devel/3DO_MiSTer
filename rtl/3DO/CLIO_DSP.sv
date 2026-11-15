// synopsys translate_off
`define SIM
// synopsys translate_on

import P3DO_PKG::*; 

module CLIO_DSP
(
	input              CLK,
	input              RST_N,
	input              EN,
	
	input              CE_R,
	input              CE_F,
	
	input              GW,
	input              RESET,
	
	output reg [ 9: 0] PC,
	input      [15: 0] NBUS,
	output reg [15: 0] NRC,
	
	output     [ 7: 0] EI_ADDR,
	input      [15: 0] EI_DATA,
	output             EI_OE,
	output     [ 7: 0] EO_ADDR,
	output     [15: 0] EO_DATA,
	output             EO_WE
);

	bit  [19: 0] ACC;
	ALUStat_t    STATUS;
	
	bit  [ 5: 0] RBASE;
	bit  [ 2: 0] RMAP;
	OpMask_t     OPMASK;
	bit          SLEEP;
	bit  [ 9: 0] INDIRECT;
	bit          MULT1_REQ,MULT2_REQ,ALU1_REQ,ALU2_REQ,BS_REQ;
	bit  [ 3: 0] NUM_OPERANDS;
	bit  [ 1: 0] CURR_REG_OPERAND;
	bit          OP_RDY;
	bit  [15: 0] M1[2];
	bit  [15: 0] M2[2];
	bit          M2SEL[2];
	bit  [15: 0] A1[2];
	bit  [15: 0] A2[2];
	bit  [ 3: 0] AMX[2];
	bit  [ 3: 0] ASEL[2];
	bit  [ 3: 0] BSEL[2];
	bit          BT[2];
	bit  [ 3: 0] COMP_WAIT[2];
	bit          ALU_N,ALU_V,ALU_C,ALU_Z,ALU_X;
	bit  [19: 0] BS_RES;
	bit          ARITH_NUM;
	bit          COMP_NUM;
	bit  [15: 0] MOVE;
	bit          /*WRITE_EN,*/MOVE_WRITE_EN;
	bit  [ 9: 0] WRITE[2];
	bit          DO_WRITE[2];
	
	ALUInst_t    ALU_INST;
	CtrlInst_t   CTRL_INST;
	AddrOper_t   ADDR_OPER;
	Reg12Oper_t  REG12_OPER;
	Reg3Oper_t   REG3_OPER;
	ImmOper_t    IMM_OPER;
	
	
	
	bit  [ 9: 0] RDADDR;
	bit  [15: 0] RDDATA;
	bit          RDEN;
	bit  [ 9: 0] WRADDR;
	bit  [15: 0] WRDATA;
	bit          WREN;
	
	typedef enum bit [0:0] {
		FETCH_INST,
		FETCH_OPERAND
	} FetchState_t;
	FetchState_t FETCH_ST;
	
	typedef enum bit [0:0] {
		OPER_LOAD,
		OPER_INDIRECT
	} OpcodeState_t;
	OpcodeState_t OPER_ST;
	
	typedef enum bit [0:0] {
		COMP_IDLE,
		COMP_CALC
	} CompState_t;
	CompState_t COMP_ST;
	
	//Instruction fetch and calculation	
	typedef enum {
		PC_NOP,
		PC_INC,
		PC_ACC,
		PC_BR,
		PC_RET
	} PCUpdate_t;
	PCUpdate_t PC_UPD;
	
	assign ALU_INST = NRC;
	assign CTRL_INST = NRC;
	assign ADDR_OPER = NRC;
	assign REG12_OPER = NRC;
	assign REG3_OPER = NRC;
	assign IMM_OPER = NRC;
	
	
	wire         INST_SPECIAL = CTRL_INST.A_C && CTRL_INST.MODE == 2'b00;
	bit          INST_NOP;
	bit          INST_BAC;
	bit          INST_RTS;
	bit          INST_JUMP;
	bit          INST_JSR;
	bit          INST_SLEEP;
	bit          INST_BRFROM;
	bit          INST_RBASE;
	bit          INST_RMAP;
	bit          INST_OPMASK;
	bit          INST_MOVEREG;
	bit          INST_MOVE;
	always_comb begin
		INST_NOP = 0;
		INST_BAC = 0;
		INST_RTS = 0;
		INST_JUMP = 0;
		INST_JSR = 0;
		INST_SLEEP = 0;
		INST_BRFROM = 0;
		INST_RBASE = 0;
		INST_RMAP = 0;
		INST_OPMASK = 0;
		INST_MOVEREG = 0;
		INST_MOVE = 0;
		
		if (INST_SPECIAL) begin
			casex (NRC[12:10])
				3'b000: case (NRC[9:7]) 
					3'b000: INST_NOP = 1;
					3'b001: INST_BAC = 1;
					3'b010: INST_RBASE = 1;
					3'b011: INST_RMAP = 1;
					3'b100: INST_RTS = 1;
					3'b101: INST_OPMASK = 1;
					3'b110: ;
					3'b111: INST_SLEEP = 1;
				endcase
				3'b001: INST_JUMP = 1;
				3'b010: INST_JSR = 1;
				3'b011: INST_BRFROM = 1;
				3'b100: INST_MOVEREG = 1;
				3'b101: ;
				3'b11x: INST_MOVE = 1;
			endcase
		end
	end 
		
	wire [15: 0] IJL = !IMM_OPER.JSTFY ? { {3{IMM_OPER.IMM_VAL[12]}},IMM_OPER.IMM_VAL } :
	                                     { IMM_OPER.IMM_VAL,3'b000 };

	wire [15: 0] OP_BUS = OPER_ST == OPER_LOAD && NRC[15] && NRC[14] ? IJL : RDDATA;
		
	wire         INST_CONTROL = CTRL_INST.A_C;
	bit          BRANCH_COND;
	always_comb begin
		bit          MODE12_FLAG0,MODE12_FLAG1;
		bit          MODE12_COND;
		bit          MODE3_NVZ,MODE3_CZ,MODE3_X;
		bit          MODE1_ZX;
		
		MODE12_FLAG0 = (CTRL_INST.FLGSEL ? STATUS.C : STATUS.N) ^ CTRL_INST.MODE[1]; 
		MODE12_FLAG1 = (CTRL_INST.FLGSEL ? STATUS.Z : STATUS.V) ^ CTRL_INST.MODE[1]; 
		MODE12_COND = (CTRL_INST.FLAG_MASK[1] ?  MODE12_FLAG0 : 1'b1) & (CTRL_INST.FLAG_MASK[0] ?  MODE12_FLAG1 : 1'b1) & |CTRL_INST.FLAG_MASK;
		
		MODE3_NVZ = (((STATUS.N ^ STATUS.V) | (STATUS.Z & CTRL_INST.FLAG_MASK[0])) ^ CTRL_INST.FLAG_MASK[1]) & ~CTRL_INST.FLGSEL;
		MODE3_CZ = ((STATUS.C & ~STATUS.Z) ^ CTRL_INST.FLAG_MASK[0]) & ~CTRL_INST.FLAG_MASK[1] & CTRL_INST.FLGSEL;
		MODE3_X = (STATUS.X ^ CTRL_INST.FLAG_MASK[0]) & CTRL_INST.FLAG_MASK[1] & CTRL_INST.FLGSEL;
		
		MODE1_ZX = ((STATUS.Z & STATUS.X) ^ CTRL_INST.FLGSEL) & ~|CTRL_INST.FLAG_MASK;
		
		case (CTRL_INST.MODE)
			2'b00: BRANCH_COND = 0;
			2'b01: BRANCH_COND = MODE12_COND | MODE1_ZX;
			2'b10: BRANCH_COND = MODE12_COND;
			2'b11: BRANCH_COND = MODE3_NVZ | MODE3_CZ | MODE3_X;
		endcase
	end
		
	
	wire ARITH_USE_ALU1 = (ALU_INST.AMX_A == 2'b01 || ALU_INST.AMX_B == 2'b01) && !OPMASK.ALU1;
	wire ARITH_USE_ALU2 = (ALU_INST.AMX_A == 2'b10 || ALU_INST.AMX_B == 2'b10) && !OPMASK.ALU2;
	wire ARITH_USE_MULT = (ALU_INST.AMX_A == 2'b11 || ALU_INST.AMX_B == 2'b11);
	wire ARITH_USE_MULT1 = ARITH_USE_MULT && !OPMASK.MULT1;
	wire ARITH_USE_MULT2 = ARITH_USE_MULT && !OPMASK.MULT2;
	wire ARITH_USE_BS = ALU_INST.BS == 4'b1000 && !OPMASK.BS;
	wire ARITH_INSTANT_BS = ALU_INST.BS != 4'b1000 && !OPMASK.BS;
	wire ARITH_ALU_TRANSFER = ALU_INST.ALU[2:0] == 3'b000;
	// clocks an arithmetic instruction computes: one bit, shifted out
	wire [ 3: 0] ARITH_COMP_WAIT = {1'b0, ARITH_USE_MULT & ~ARITH_ALU_TRANSFER, ARITH_USE_MULT ^ ~ARITH_ALU_TRANSFER, ~ARITH_USE_MULT & ARITH_ALU_TRANSFER};
	
	wire [ 4: 0] OPERAND_REQS = {MULT1_REQ,MULT2_REQ,ALU1_REQ,ALU2_REQ,BS_REQ};
	wire EXACTLY_1_REQ = ExactlyOne(OPERAND_REQS);
	
	wire REG3_OPERAND = !REG12_OPER.TYPE[1];
	wire REG12_OPERAND = REG12_OPER.TYPE == 2'b10 && REG12_OPER.R_IM;
	wire REG2_OPERAND = REG12_OPERAND &&  REG12_OPER.NUMRGS;
	wire REG1_OPERAND = REG12_OPERAND && !REG12_OPER.NUMRGS;
	wire IMM_OPERAND = REG12_OPER.TYPE == 2'b11;
	wire ADDR_DIR_OPERAND = ADDR_OPER.TYPE == 2'b10 && !ADDR_OPER.R_IM && !ADDR_OPER.D_I;
	wire ADDR_IND_OPERAND = ADDR_OPER.TYPE == 2'b10 && !ADDR_OPER.R_IM &&  ADDR_OPER.D_I;
	wire NONE_OPERAND = ((ALU_INST.NUM_OPS == 2'b00                                          && !(ARITH_USE_ALU1 || ARITH_USE_ALU2)) || 
	                     (ALU_INST.NUM_OPS == 2'b01 && !(ARITH_USE_MULT1 || ARITH_USE_MULT2) && !(ARITH_USE_ALU1 || ARITH_USE_ALU2))) && !ARITH_USE_BS && !ALU_INST.A_C && FETCH_ST == FETCH_INST;
	wire ANY_IND_OPERAND = ADDR_IND_OPERAND || (((REG3_OPERAND && CURR_REG_OPERAND == 2'd0)                            ) && REG3_OPER.R3D_I) || 
	                                           (((REG2_OPERAND && CURR_REG_OPERAND == 2'd0) || CURR_REG_OPERAND == 2'd2) && REG12_OPER.R2D_I) ||
															 (((REG1_OPERAND && CURR_REG_OPERAND == 2'd0) || CURR_REG_OPERAND == 2'd1) && REG12_OPER.R1D_I);
	
	wire MOVE_WAIT = DO_WRITE[~ARITH_NUM];
	
	wire COMP_RDY = EXACTLY_1_REQ || OP_RDY || NONE_OPERAND;
	
	wire COMPUTING = |COMP_WAIT[1];
	
	bit  [ 9: 0] REG_ADDR;
	always_comb begin
		bit  [ 3: 0] R;
		bit          X,Y;
		bit          TWIDDLE;
		
		if ((!REG12_OPER.TYPE[1] && CURR_REG_OPERAND == 2'd0) || CURR_REG_OPERAND == 2'd3)
			R = REG3_OPER.R3;
		else if ((REG12_OPER.TYPE[1] && REG12_OPER.NUMRGS && CURR_REG_OPERAND == 2'd0) || CURR_REG_OPERAND == 2'd2)
			R = REG12_OPER.R2;
		else if ((REG12_OPER.TYPE[1] && !REG12_OPER.NUMRGS) || CURR_REG_OPERAND == 2'd1)
			R = REG12_OPER.R1;
		else
			R = '0;

		{Y,X} = R[3:2];
		casex (RMAP)
			3'b0xx: TWIDDLE = X;
			3'b100: TWIDDLE = Y;
			3'b101: TWIDDLE = ~Y;
			3'b110: TWIDDLE = X & Y;
			3'b111: TWIDDLE = X | Y;
		endcase
		
		REG_ADDR = {R[3],TWIDDLE,RBASE[5:1],RBASE[0]^R[2],R[1:0]};
	end
	assign RDADDR = OPER_ST == OPER_INDIRECT                                                                                   ? INDIRECT : 
	                (FETCH_ST == FETCH_INST && INST_MOVEREG) || (FETCH_ST == FETCH_OPERAND && (REG3_OPERAND || REG12_OPERAND)) ? REG_ADDR :
						                                                                                                              ADDR_OPER.OP_ADDR;
	
//		bit          READ_CYCLE;
		bit          MOVE_CYCLE;
	always @(posedge CLK or negedge RST_N) begin
		bit  [ 9: 0] SUBR;
		
		bit          RESET_DELAY;
		bit          BRANCH_DELAY;
		bit          FETCH_OP_RDY_SET;
		bit          HIGH_PRIORITY;
		bit          WRITE_ACT;
		bit  [ 9: 0] WRITE_BUS;
		
		bit          BUF_UPDATE;
		
		if (!RST_N) begin
			RESET_DELAY <= 1;
			FETCH_ST <= FETCH_INST;
			NRC <= '0;
			PC <= '0;
			SUBR <= '0;
			BRANCH_DELAY <= 0;
			RBASE <= '0;
			RMAP <= '0;
			OPMASK <= '0;
			SLEEP <= 0;
			INDIRECT <= '0;
			
			OPER_ST <= OPER_LOAD;
			NUM_OPERANDS <= '0;
			COMP_ST <= COMP_IDLE;
			{MULT1_REQ,MULT2_REQ,ALU1_REQ,ALU2_REQ,BS_REQ} <= '0;
			M1 <= '{2{'0}};
			M2 <= '{2{'0}};
			A1 <= '{2{'0}};
			A2 <= '{2{'0}};
			BSEL <= '{2{'0}};
			BT <= '{2{0}};
			COMP_WAIT <= '{2{'0}};
			ARITH_NUM <= 0;
			MOVE <= '0;
			WRITE <= '{2{'0}};
			DO_WRITE <= '{2{0}};
			CURR_REG_OPERAND <= '0;
			OP_RDY <= 0;
			ACC <= '0;
			STATUS <= '0;
		end
		else if (RESET && CE_R) begin
			RESET_DELAY <= 1;
			FETCH_ST <= FETCH_INST;
			NRC <= '0;
			PC <= '0;
			SUBR <= '0;
			BRANCH_DELAY <= 0;
			RBASE <= '0;
			RMAP <= '0;
			OPMASK <= '0;
			SLEEP <= 0;
			INDIRECT <= '0;
			
			OPER_ST <= OPER_LOAD;
			NUM_OPERANDS <= '0;
			COMP_ST <= COMP_IDLE;
			{MULT1_REQ,MULT2_REQ,ALU1_REQ,ALU2_REQ,BS_REQ} <= '0;
			M1 <= '{2{'0}};
			M2 <= '{2{'0}};
			A1 <= '{2{'0}};
			A2 <= '{2{'0}};
			BSEL <= '{2{'0}};
			BT <= '{2{0}};
			COMP_WAIT <= '{2{'0}};
			ARITH_NUM <= 0;
			COMP_NUM <= 0;
			MOVE <= '0;
			WRITE <= '{2{'0}};
			DO_WRITE <= '{2{0}};
			CURR_REG_OPERAND <= '0;
			OP_RDY <= 0;
			// every frame starts with the accumulator and the flags clear (Opera
			// opera_dsp_loop: Y = 0, flags = 0 before the first instruction)
			ACC <= '0;
			STATUS <= '0;
		end
		else if (EN && GW && CE_R) begin
			RESET_DELAY <= 0;
			BRANCH_DELAY <= 0;
			
			PC_UPD = PC_NOP;
			FETCH_OP_RDY_SET = 0;
			HIGH_PRIORITY = 0;
			
			case (FETCH_ST)
				FETCH_INST: if (RESET_DELAY) begin
					PC_UPD = PC_INC;
					FETCH_ST <= FETCH_INST;
				end
				else if (!SLEEP) begin
					if (INST_NOP) begin
						PC_UPD = PC_INC;
					end
					else if (INST_CONTROL && BRANCH_COND && !BRANCH_DELAY) begin
						if (COMPUTING) begin
							FETCH_ST <= FETCH_INST;
						end else begin
							PC_UPD = PC_BR;
							BRANCH_DELAY <= 1;
							FETCH_ST <= FETCH_INST;
						end
					end
					else if (INST_BAC && !BRANCH_DELAY) begin
						PC_UPD = PC_ACC;
						BRANCH_DELAY <= 1;
					end
					else if ((INST_JUMP || INST_JSR) && !BRANCH_DELAY) begin
						PC_UPD = PC_BR;
						BRANCH_DELAY <= 1;;
						if (INST_JSR) begin
							SUBR <= PC;
						end
					end
					else if (INST_RTS /*&& !BRANCH_DELAY*/) begin
						PC_UPD = PC_RET;
						BRANCH_DELAY <= 1;
					end
					else if (INST_BRFROM && BRANCH_DELAY) begin
						PC_UPD = PC_BR;
						BRANCH_DELAY <= 1;
					end
					else if (INST_MOVE || INST_MOVEREG) begin
						if (BRANCH_DELAY) begin
							PC_UPD = PC_INC;
							FETCH_ST <= FETCH_INST;
						end
						else if (MOVE_WAIT || OPER_ST == OPER_INDIRECT) begin
							FETCH_ST <= FETCH_INST;
						end
						else begin
							PC_UPD = PC_INC;
							FETCH_ST <= FETCH_OPERAND;
						end
					end
					else if (INST_RBASE) begin
						RBASE <= NRC[5:0];
						PC_UPD = PC_INC;
					end
					else if (INST_RMAP) begin
						RMAP <= NRC[2:0];
						PC_UPD = PC_INC;
					end
					else if (INST_OPMASK) begin
						OPMASK <= NRC[4:0];
						PC_UPD = PC_INC;
					end
					else if (INST_SLEEP) begin
						if (BRANCH_DELAY) begin
							PC_UPD = PC_INC;
						end
						else begin
							SLEEP <= 1;
						end
					end
					else if (!ALU_INST.A_C) begin	//arithmetic instruction
						if (BRANCH_DELAY) begin
							PC_UPD = PC_INC;
							FETCH_ST <= FETCH_INST;
						end
						else if (OP_RDY || OPER_ST == OPER_INDIRECT) begin
							FETCH_ST <= FETCH_INST;
						end
						else begin
							if (ARITH_USE_MULT1                  ) MULT1_REQ <= 1;
							if (ARITH_USE_MULT2 && ALU_INST.M2SEL) MULT2_REQ <= 1;
							if (ARITH_USE_ALU1                   ) ALU1_REQ <= 1;
							if (ARITH_USE_ALU2                   ) ALU2_REQ <= 1;
							if (ARITH_USE_BS                     ) BS_REQ <= 1;
							
							case (ALU_INST.NUM_OPS)
								2'b01: NUM_OPERANDS <= 4'b0001;
								2'b10: NUM_OPERANDS <= 4'b0010;
								2'b11: NUM_OPERANDS <= 4'b0100;
								2'b00: NUM_OPERANDS <= ARITH_USE_ALU1 || ARITH_USE_ALU2 ? 4'b1000 : 4'b0000;
							endcase
							
							COMP_WAIT[0] <= ARITH_COMP_WAIT;
							
							if (NONE_OPERAND) FETCH_OP_RDY_SET = 1;
							
							PC_UPD = PC_INC;
							if (ALU_INST.NUM_OPS == 2'b00 && !(ARITH_USE_ALU1 || ARITH_USE_ALU2) && !ARITH_USE_BS)
								FETCH_ST <= FETCH_INST;
							else
								FETCH_ST <= FETCH_OPERAND;
						end
					end
					else begin
						if (!COMPUTING) begin
							PC_UPD = PC_INC;
						end
						FETCH_ST <= FETCH_INST;
					end
				end
				
				FETCH_OPERAND: if (!SLEEP) begin
					if ((REG3_OPERAND || REG2_OPERAND) && CURR_REG_OPERAND != 2'd1) begin
						FETCH_ST <= FETCH_OPERAND;
					end
					else begin
						if (!NUM_OPERANDS[3:1] && (!NUM_OPERANDS[0] || !BS_REQ)) begin
							PC_UPD = PC_INC;
							FETCH_ST <= FETCH_INST;
						end
						else if (OPER_ST == OPER_INDIRECT) begin
							FETCH_ST <= FETCH_OPERAND;
						end
						else begin
							PC_UPD = PC_INC;
							FETCH_ST <= FETCH_OPERAND;
						end
					end
				end
			endcase
			
			if (PC_UPD != PC_NOP)
				NRC <= NBUS;
			
			case (PC_UPD)
				PC_NOP:;
				PC_INC: PC <= PC + 10'd1;
				PC_ACC: PC <= ACC[13:4];
				PC_BR:  PC <= CTRL_INST.BCH_ADDR;
				PC_RET: PC <= SUBR;
			endcase
			
			
			WRITE_ACT = 0;
			WRITE_BUS = '0;
			MOVE_CYCLE <= 0;
//			READ_CYCLE <= 0;
//			DO_WRITE <= '{2{0}};
			MOVE_WRITE_EN <= 0;
			case (OPER_ST)
				OPER_LOAD: if (RESET_DELAY) begin
					OPER_ST <= OPER_LOAD;
				end
				else begin
					if (FETCH_ST == FETCH_INST) begin
						if (!ALU_INST.A_C) begin
							if (BRANCH_DELAY || OP_RDY) begin
							
							end
							else begin
								M2SEL[0] <= ALU_INST.M2SEL;
								AMX[0] <= {ALU_INST.AMX_A,ALU_INST.AMX_B};
								ASEL[0] <= ALU_INST.ALU;
								if (ARITH_INSTANT_BS) begin
									BT[0] <= ALU_INST.ALU[3];
									BSEL[0] <= ALU_INST.BS;
								end
								ARITH_NUM <= ~ARITH_NUM;
							end
						end
						else if (INST_MOVE || INST_MOVEREG) begin
							if (BRANCH_DELAY || MOVE_WAIT) begin
								
							end
							else begin
								if ((INST_MOVE && !ADDR_OPER.D_I) || (INST_MOVEREG && !REG12_OPER.R1D_I)) begin
									WRITE_BUS = RDADDR;
								end
								else begin
//									READ_CYCLE <= 1;
									WRITE_BUS = RDDATA[9:0];
								end
								
								WRITE[~ARITH_NUM] <= WRITE_BUS;
								MOVE_CYCLE <= 1;
//								MOVE_READ_EN <= 1;
							end
						end
						OPER_ST <= OPER_LOAD;
					end
					else if (MOVE_CYCLE) begin
						if (IMM_OPERAND) begin
							MOVE <= OP_BUS;
							MOVE_WRITE_EN <= 1;
							OPER_ST <= OPER_LOAD;
						end
						else if (ADDR_DIR_OPERAND) begin
//							READ_CYCLE <= 1;
							MOVE <= OP_BUS;
							MOVE_WRITE_EN <= 1;
							OPER_ST <= OPER_LOAD;
						end
						else if (ADDR_IND_OPERAND) begin
//							READ_CYCLE <= 1;
							INDIRECT <= RDDATA[9:0];
							MOVE_CYCLE <= 1;
							OPER_ST <= OPER_INDIRECT;
						end
						else if (REG1_OPERAND) begin
							if (!REG12_OPER.R1D_I) begin
//								READ_CYCLE <= 1;
								MOVE <= OP_BUS;
								MOVE_WRITE_EN <= 1;
								OPER_ST <= OPER_LOAD;
							end
							else begin
//								READ_CYCLE <= 1;
								INDIRECT <= RDDATA[9:0];
								MOVE_CYCLE <= 1;
								OPER_ST <= OPER_INDIRECT;
							end
						end
					end
					else if (OPERAND_REQS || NUM_OPERANDS) begin
						if (IMM_OPERAND) begin
							HIGH_PRIORITY = 1;
							OPER_ST <= OPER_LOAD;
						end
						else if (ADDR_DIR_OPERAND) begin
							if (OPERAND_REQS) begin
//								READ_CYCLE <= 1;
								HIGH_PRIORITY = 1;
								WRITE_BUS = RDADDR;
								if (ADDR_OPER.WB1) begin
									WRITE_ACT = 1;
								end
								OPER_ST <= OPER_LOAD;
							end
							else begin
								WRITE_BUS = RDADDR;
								WRITE_ACT = 1;
								NUM_OPERANDS <= NUM_OPERANDS >> 1;
								OPER_ST <= OPER_LOAD;
							end
						end
						else if (ADDR_IND_OPERAND) begin
							if (OPERAND_REQS) begin
//								READ_CYCLE <= 1;
								// the pointer: the operand is read through it in
								// OPER_INDIRECT (as the register operands' indirect forms)
								INDIRECT <= RDDATA[9:0];
								WRITE_BUS = RDDATA[9:0];
								if (ADDR_OPER.WB1) begin
									WRITE_ACT = 1;
								end
								OPER_ST <= OPER_INDIRECT;
							end
							else begin
//								READ_CYCLE <= 1;
								WRITE_BUS = RDDATA[9:0];
								WRITE_ACT = 1;
								NUM_OPERANDS <= NUM_OPERANDS >> 1;
								OPER_ST <= OPER_LOAD;
							end
						end
						else if (REG3_OPERAND && CURR_REG_OPERAND == 2'd0) begin
							if (!REG3_OPER.R3D_I) begin
//								READ_CYCLE <= 1;
								HIGH_PRIORITY = 1;
								CURR_REG_OPERAND <= 2'd2;
								OPER_ST <= OPER_LOAD;
							end
							else begin
//								READ_CYCLE <= 1;
								INDIRECT <= RDDATA[9:0];
								CURR_REG_OPERAND <= 2'd2 + 2'd1;
								OPER_ST <= OPER_INDIRECT;
							end
						end
						else if ((REG2_OPERAND && CURR_REG_OPERAND == 2'd0) || CURR_REG_OPERAND == 2'd2) begin
							if (!REG12_OPER.R2D_I) begin
//								READ_CYCLE <= 1;
								HIGH_PRIORITY = 1;
								CURR_REG_OPERAND <= 2'd1;
								WRITE_BUS = RDADDR;
								if (REG12_OPER.WB2 && !REG3_OPERAND) begin
									WRITE_ACT = 1;
								end
								OPER_ST <= OPER_LOAD;
							end
							else begin
//								READ_CYCLE <= 1;
								INDIRECT <= RDDATA[9:0];
								CURR_REG_OPERAND <= 2'd1 + 2'd1;
								WRITE_BUS = RDDATA[9:0];
								if (REG12_OPER.WB2 && !REG3_OPERAND) begin
									WRITE_ACT = 1;
								end
								OPER_ST <= OPER_INDIRECT;
							end
						end
						else if ((REG1_OPERAND && CURR_REG_OPERAND == 2'd0) || CURR_REG_OPERAND == 2'd1) begin
							if (!REG12_OPER.R1D_I) begin
								if (OPERAND_REQS) begin
//									READ_CYCLE <= 1;
									HIGH_PRIORITY = 1;
									WRITE_BUS = RDADDR;
									if (REG12_OPER.WB1 && !REG3_OPERAND) begin
										WRITE_ACT = 1;
									end
								end
								else begin
									WRITE_BUS = RDADDR;
									WRITE_ACT = 1;
									NUM_OPERANDS <= NUM_OPERANDS >> 1;
								end
								CURR_REG_OPERAND <= 2'd0;
								OPER_ST <= OPER_LOAD;
							end
							else begin
								if (OPERAND_REQS) begin
//									READ_CYCLE <= 1;
									INDIRECT <= RDDATA[9:0];
									WRITE_BUS = RDDATA[9:0];
									if (REG12_OPER.WB1 && !REG3_OPERAND) begin
										WRITE_ACT = 1;
									end
									OPER_ST <= OPER_INDIRECT;
								end
								else begin
//									READ_CYCLE <= 1;
									WRITE_BUS = RDDATA[9:0];
									WRITE_ACT = 1;
									NUM_OPERANDS <= NUM_OPERANDS >> 1;
									OPER_ST <= OPER_LOAD;
								end
								CURR_REG_OPERAND <= 2'd0 + 2'd1;
							end
						end
					end
				end
				
				OPER_INDIRECT: begin
//					READ_CYCLE <= 1;
					if (MOVE_CYCLE) begin
						MOVE <= OP_BUS;
						MOVE_WRITE_EN <= 1;
					end
					else begin
						HIGH_PRIORITY = 1;
					end
					if (CURR_REG_OPERAND == 2'd3) CURR_REG_OPERAND <= 2'd2;
					if (CURR_REG_OPERAND == 2'd2) CURR_REG_OPERAND <= 2'd1;
					if (CURR_REG_OPERAND == 2'd1) CURR_REG_OPERAND <= 2'd0;
					OPER_ST <= OPER_LOAD;
				end
			endcase
			
//			OP_RDY <= 0;
			if (HIGH_PRIORITY) begin
				 if (MULT1_REQ) begin
					MULT1_REQ <= 0;
					M1[0] <= OP_BUS;
					NUM_OPERANDS <= NUM_OPERANDS >> 1;
				 end
				 else if (MULT2_REQ) begin
					MULT2_REQ <= 0;
					M2[0] <= OP_BUS;
					NUM_OPERANDS <= NUM_OPERANDS >> 1;
				 end
				 else if (ALU1_REQ) begin
					ALU1_REQ <= 0;
					A1[0] <= OP_BUS;
					NUM_OPERANDS <= NUM_OPERANDS >> 1;
				 end
				 else if (ALU2_REQ) begin
					ALU2_REQ <= 0;
					A2[0] <= OP_BUS;
					NUM_OPERANDS <= NUM_OPERANDS >> 1;
				 end
				 else if (BS_REQ) begin
					// BS = 1000: the operand is the shift control (bits 3-0 the
					// shift, bit 4 logical); it is not one of the instruction's
					// counted operands (WO 94/16383: "It does not include a
					// Barrel Shifter operand; that is handled independently")
					BS_REQ <= 0;
					BSEL[0] <= OP_BUS[3:0];
					BT[0] <= OP_BUS[4];
				 end
				 
				 if (EXACTLY_1_REQ) begin
					OP_RDY <= 1;
				 end
			end
			
			if (FETCH_OP_RDY_SET) begin
				OP_RDY <= 1;
			end
			
			if (WRITE_ACT) begin
				WRITE[ARITH_NUM] <= WRITE_BUS;
				DO_WRITE[ARITH_NUM] <= 1;
			end
			
			BUF_UPDATE = 0;
//			WRITE_EN <= 0;
			case (COMP_ST)
				COMP_IDLE: if (RESET_DELAY) begin
					COMP_ST <= COMP_IDLE;
				end
				else begin
					if (MOVE_WRITE_EN) begin
//						WRITE_EN <= 1;
					end
					else if (DO_WRITE[COMP_NUM]) begin
						DO_WRITE[COMP_NUM] <= 0;
//						WRITE_EN <= 1;
					end
					
					if (COMP_RDY) begin
						if ((EXACTLY_1_REQ && ANY_IND_OPERAND && OPER_ST != OPER_INDIRECT) || (NONE_OPERAND && OPER_ST == OPER_INDIRECT) || BRANCH_DELAY) begin
							COMP_ST <= COMP_IDLE;
						end
						else begin
							BUF_UPDATE = 1;
							COMP_ST <= COMP_CALC;
						end
					end
					else begin
						COMP_ST <= COMP_IDLE;
					end
				end
				
				COMP_CALC: begin
					if (MOVE_WRITE_EN) begin
//						WRITE_EN <= 1;
					end
					else if (DO_WRITE[~COMP_NUM]) begin
						DO_WRITE[~COMP_NUM] <= 0;
//						WRITE_EN <= 1;
					end
					
					if (COMP_WAIT[1][3:1]) begin
						COMP_WAIT[1] <= COMP_WAIT[1] >> 1;
						COMP_ST <= COMP_CALC;
					end
					else if (COMP_WAIT[1][0]) begin
						COMP_WAIT[1] <= COMP_WAIT[1] >> 1;
						ACC <= BS_RES;
						STATUS <= {ALU_N,ALU_V,ALU_C,ALU_Z,ALU_X};
					
						if (COMP_RDY) begin
							if ((EXACTLY_1_REQ && ANY_IND_OPERAND && OPER_ST != OPER_INDIRECT) || (NONE_OPERAND && OPER_ST == OPER_INDIRECT) || BRANCH_DELAY) begin
								COMP_ST <= COMP_IDLE;
							end
							else begin
								BUF_UPDATE = 1;
								COMP_ST <= COMP_CALC;
							end
						end
						else begin
							COMP_ST <= COMP_IDLE;
						end
					end
				end
			endcase
			
			if (BUF_UPDATE) begin
				M1[1]    <= HIGH_PRIORITY && MULT1_REQ ? OP_BUS : M1[0];
				M2[1]    <= HIGH_PRIORITY && MULT2_REQ ? OP_BUS : M2[0];
				A1[1]    <= HIGH_PRIORITY && ALU1_REQ  ? OP_BUS : A1[0];
				A2[1]    <= HIGH_PRIORITY && ALU2_REQ  ? OP_BUS : A2[0];
				M2SEL[1] <= FETCH_ST == FETCH_INST && !OP_RDY && !ALU_INST.A_C && COMP_RDY ? ALU_INST.M2SEL                  : M2SEL[0];
				ASEL[1]  <= FETCH_ST == FETCH_INST && !OP_RDY && !ALU_INST.A_C && COMP_RDY ? ALU_INST.ALU                    : ASEL[0];
				AMX[1]   <= FETCH_ST == FETCH_INST && !OP_RDY && !ALU_INST.A_C && COMP_RDY ? {ALU_INST.AMX_A,ALU_INST.AMX_B} : AMX[0];
				BSEL[1]  <= HIGH_PRIORITY && BS_REQ ? OP_BUS[3:0] : FETCH_ST == FETCH_INST && !OP_RDY && !ALU_INST.A_C && COMP_RDY ? ALU_INST.BS     : BSEL[0];
				BT[1]    <= HIGH_PRIORITY && BS_REQ ? OP_BUS[4]   : FETCH_ST == FETCH_INST && !OP_RDY && !ALU_INST.A_C && COMP_RDY ? ALU_INST.ALU[3] : BT[0];
				// an instruction without operands computes in the clock it is fetched,
				// before COMP_WAIT[0] holds its timing: take it from the decode, as
				// M2SEL / ASEL / AMX / BSEL / BT above
				COMP_WAIT[1] <= FETCH_ST == FETCH_INST && !OP_RDY && !ALU_INST.A_C && COMP_RDY ? ARITH_COMP_WAIT : COMP_WAIT[0];
				COMP_NUM <= ~COMP_NUM;
				OP_RDY <= 0;
			end
		end
	end 
	
	bit  [31: 0] MULT_RES;
	always_comb begin
		bit  [15: 0] M2_TEMP;
		
		M2_TEMP = M2SEL[1] ? M2[1] : ACC[19:4];
		MULT_RES = $signed(M1[1]) * $signed(M2_TEMP) * 2;
	end 
	
	wire [19: 0] ALU_CARRY = {15'h0000,STATUS[2]/*ALU_C*/,4'h0};
	always_comb begin
		bit  [19: 0] ALU_A,ALU_B;
		bit  [19: 0] ALU_ARITH_A,ALU_ARITH_B;
		bit          ALU_ARITH_SUB;
		bit  [19: 0] ARITH_RES;
		bit          ARITH_C;
		bit          ARITH_V;
		bit  [19: 0] LOG_RES;
		bit  [19: 0] ALU_RES;
		
		case (AMX[1][3:2])
			2'b00: ALU_A = ACC;
			2'b01: ALU_A = {A1[1],4'b0000};
			2'b10: ALU_A = {A2[1],4'b0000};
			2'b11: ALU_A = !M2SEL[1] && (ASEL[1] == 4'b0011 || ASEL[1] == 4'b0101) ? {M1[1]&{16{STATUS[2]}},4'b0000} : MULT_RES[31:12];
		endcase
		case (AMX[1][1:0])
			2'b00: ALU_B = ACC;
			2'b01: ALU_B = {A1[1],4'b0000};
			2'b10: ALU_B = {A2[1],4'b0000};
			2'b11: ALU_B = MULT_RES[31:12];
		endcase
		
		case (ASEL[1])
			4'b0001: ALU_ARITH_A = '0;
			default: ALU_ARITH_A = ALU_A;
		endcase
		case (ASEL[1])
			4'b0000: ALU_ARITH_B = '0;
			4'b0011,
			4'b0101: ALU_ARITH_B = ALU_CARRY;
			4'b0110,
			4'b0111: ALU_ARITH_B = 20'h00001;   // INC / DEC: the ALU's LSB (Opera +0x1000 on Y[31:12], MAME alu_a + 1)
			default: ALU_ARITH_B = ALU_B;
		endcase
		case (ASEL[1])
			4'b0001,
			4'b0100,
			4'b0101,
			4'b0111: ALU_ARITH_SUB = 1;
			default: ALU_ARITH_SUB = 0;
		endcase
		{ARITH_C,ARITH_RES} = {1'b0,ALU_ARITH_A} + {1'b0,ALU_ARITH_B^{20{ALU_ARITH_SUB}}} + {20'h00000,ALU_ARITH_SUB};
		ARITH_V = (ALU_ARITH_A[19] & (ALU_ARITH_B[19]^ALU_ARITH_SUB) & ~ARITH_RES[19]) | (~ALU_ARITH_A[19] & ~(ALU_ARITH_B[19]^ALU_ARITH_SUB) & ARITH_RES[19]);
		
		case (ASEL[1][2:0])
			3'b000: LOG_RES = ALU_A;
			3'b001: LOG_RES = ~ALU_A;
			3'b010: LOG_RES = ALU_A & ALU_B;
			3'b011: LOG_RES = ~(ALU_A & ALU_B);
			3'b100: LOG_RES = ALU_A | ALU_B;
			3'b101: LOG_RES = ~(ALU_A | ALU_B);
			3'b110: LOG_RES = ALU_A ^ ALU_B;
			3'b111: LOG_RES = ~(ALU_A ^ ALU_B);
		endcase
		case (ASEL[1][3])
			1'b0: {ALU_N,ALU_V,ALU_C,ALU_RES} = {ARITH_RES[19],ARITH_V,ARITH_C,ARITH_RES[19:0]};
			1'b1: {ALU_N,ALU_V,ALU_C,ALU_RES} = {LOG_RES[19]  ,1'b0   ,1'b0   ,LOG_RES};
		endcase
		if (BSEL[1] == 4'h8)
			ALU_C = ALU_RES[19];
		ALU_Z = ~|ALU_RES[19:4];
		ALU_X = ~|ALU_RES[3:0];
		
		BS_RES = BarrelShifter(ALU_RES,BSEL[1],BT[1],ALU_V);
	end
	
	assign RDEN = (MOVE_CYCLE && (ADDR_DIR_OPERAND || ANY_IND_OPERAND || REG1_OPERAND)) ||
	              ((OPERAND_REQS || NUM_OPERANDS) && !IMM_OPERAND);
	
	assign WRADDR = MOVE_WRITE_EN        ? WRITE[~ARITH_NUM] : 
	                COMP_ST == COMP_IDLE ? WRITE[ COMP_NUM] : 
						                        WRITE[~COMP_NUM];
	assign WRDATA = MOVE_WRITE_EN        ? MOVE :
	                                       ACC[19:4];
	assign WREN = MOVE_WRITE_EN || (DO_WRITE[COMP_NUM] && COMP_ST == COMP_IDLE) || (DO_WRITE[~COMP_NUM] && COMP_ST == COMP_CALC);
	
	//IRAM
	wire IRAM_OE = (RDADDR[9:8] == 2'h1 || RDADDR[9:8] == 2'h2);
	wire IRAM_WE = (WRADDR[9:8] == 2'h1 || WRADDR[9:8] == 2'h2) && WREN;
	bit  [15: 0] IRAM_DATA;
	CLIO_DSP_IRAM IRAM
	(
		.CLK(CLK),
		.EN(EN),
		
		.WA(WRADDR[7:0]),
		.WD(WRDATA),
		.WE(IRAM_WE & EN & CE_R),
		
		.RA(RDADDR[7:0]),
		.RD(IRAM_DATA)
	);
	
	assign EI_ADDR = RDADDR[7:0];
	assign EI_OE = (RDADDR[9:8] == 2'h0) && RDEN;
	assign EO_ADDR = WRADDR[7:0];
	assign EO_DATA = WRDATA;
	assign EO_WE = (WRADDR[9:8] == 2'h3) && WREN;
	
	
	// Game Bub port: a read of the word an instruction is writing in this
	// clock (the MOVE's word, or an ALU result whose write waits for the
	// port behind a MOVE's) gets the new word. The original read the memory
	// (undefined for the same address in hardware, old in simulation): an
	// instruction two after an ALU writeback read the old value when a MOVE
	// between them had delayed the writeback to the clock of its read
	// (Killing Time's DSP interrupt counter).
	// The data memory has 256 words: 0x100-0x1FF and 0x200-0x2FF are the same
	// words (address bits 7-0), so a write to either is forwarded to a read of
	// either, and only data memory writes are (an output word at 0x308 is not
	// the data word 0x108).
	wire         ALU_WRITE_DUE  = (DO_WRITE[COMP_NUM] && COMP_ST == COMP_IDLE) || (DO_WRITE[~COMP_NUM] && COMP_ST == COMP_CALC);
	wire [ 9: 0] ALU_WRITE_ADDR = COMP_ST == COMP_IDLE ? WRITE[COMP_NUM] : WRITE[~COMP_NUM];
	function automatic bit iram_addr(input [9:0] a);
		return a[9:8] == 2'h1 || a[9:8] == 2'h2;
	endfunction
	wire         RD_FWD_MOVE    = MOVE_WRITE_EN && iram_addr(WRITE[~ARITH_NUM]) && RDADDR[7:0] == WRITE[~ARITH_NUM][7:0];
	wire         RD_FWD_ALU     = ALU_WRITE_DUE && iram_addr(ALU_WRITE_ADDR)   && RDADDR[7:0] == ALU_WRITE_ADDR[7:0];
	assign RDDATA = IRAM_OE ? (RD_FWD_MOVE ? MOVE : RD_FWD_ALU ? ACC[19:4] : IRAM_DATA) : EI_DATA;
	
endmodule

