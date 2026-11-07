module P3DO_CDROM
(
	input              CLK,
	input              RST_N,
	input              EN,
	
	input              CE,
	
	input      [ 7: 0] CDDI,
	output reg [ 7: 0] CDDO,
	input              CDEN_N,
	input              CDCMD_N,
	input              CDHWR_N,
	input              CDHRD_N,
	input              CDRST_N,
	output reg         CDSTEN_N,
	output reg         CDDTEN_N,
	output reg         CDMDCHG,
	
	input      [15: 0] CDD_DATA,
	input              CDD_WR,
	input              CDD_DTEN,
	input              CDD_DIEN,
	
	inout      [35: 0] EXT_BUS,
	
	input              TRAY_OPEN
	
`ifdef DEBUG
	                  ,
	output reg [15: 0] DBG_CRC,
	output reg [ 7: 0] DBG_CMD[4],
	output reg [11: 0] DBG_WAIT_CNT
`endif
);

	parameter bit [ 7: 0] ID_STAT[12] = '{8'h83,8'h00,8'h10,8'h00,8'h01,8'h00,8'h00,8'h00,8'h00,8'h00,8'h00,8'h00};
	
	parameter bit [ 7: 0]  ERROR_NO_ERR = 8'h00;
	parameter bit [ 7: 0]  ERROR_DISC_OUT = 8'h15;
	parameter bit [ 7: 0]  ERROR_ILLEGAL_REQ = 8'h17;
	
	bit [64: 0] cd_in;
	bit [64: 0] cd_out;
	hps_ext hps_ext
	(
		.clk_sys(CLK),
		.EXT_BUS(EXT_BUS),
		.cd_in(cd_in),
		.cd_out(cd_out)
	);
	
	bit [ 7: 0] HOST_COMM[8];
//	bit [ 7: 0] CDD_STAT[8];
//	bit         CDD_STAT_RECEIV;
	bit         CDD_COMM_SEND;
	bit         CD_IN_MSB = 0;
	always @(posedge CLK) begin
		bit         cd_out64_last = 1;
		bit [ 3: 0] WAIT_CNT = '0;
	
//		CDD_STAT_RECEIV <= 0;
		if (!RST_N) begin
//			cd_out64_last = 1;
		end else if (cd_out[64] != cd_out64_last)  begin
			cd_out64_last <= cd_out[64];
//			{CDD_STAT[7],CDD_STAT[6],CDD_STAT[5],CDD_STAT[4],CDD_STAT[3],CDD_STAT[2],CDD_STAT[1],CDD_STAT[0]} <= cd_out[63:0];
			WAIT_CNT <= '1;
		end else if (WAIT_CNT) begin
			WAIT_CNT <= WAIT_CNT - 4'd1;
//			CDD_STAT_RECEIV <= (WAIT_CNT == 4'd1);
		end
		
		if (CDD_COMM_SEND) begin
			CD_IN_MSB <= ~CD_IN_MSB;
		end
	end
	assign cd_in = {CD_IN_MSB,HOST_COMM[7],HOST_COMM[6],HOST_COMM[5],HOST_COMM[4],HOST_COMM[3],HOST_COMM[2],HOST_COMM[1],HOST_COMM[0]};
	
	//Sectors from Main_MiSTer: 2048 bytes (data), or 2352/2336/2340 bytes (raw, CD-DA), then a 16-bit byte sum.
	//A sector is complete when its transfer ends, whatever its length.
	bit  [11: 0] CDD_DATA_ADDR;
	bit          CDD_BLOCK_READY;
	bit          CDD_IS_LOADED;
	always @(posedge CLK) begin
		bit         RST_N_OLD;
		bit         CDD_DTEN_OLD,CDD_DIEN_OLD;
		
		RST_N_OLD <= RST_N;
		CDD_DTEN_OLD <= CDD_DTEN;
		CDD_DIEN_OLD <= CDD_DIEN;
		if ((!RST_N && RST_N_OLD) || (CDD_DIEN && !CDD_DIEN_OLD)) begin
			CDD_IS_LOADED <= 0;
		end
		
		CDD_BLOCK_READY <= 0;
		if (CDD_WR) begin
			CDD_DATA_ADDR <= CDD_DATA_ADDR + 12'd1;
`ifdef DEBUG
			if (CDD_DTEN) DBG_CRC <= CDD_DATA;
`endif
			if (CDD_DIEN && CDD_DATA_ADDR == 12'h3FF) CDD_IS_LOADED <= 1;
		end
		if (!CDD_DTEN && CDD_DTEN_OLD) begin
			CDD_BLOCK_READY <= 1;
			RX_BYTES <= CDD_DATA_ADDR != 12'd0 ? {CDD_DATA_ADDR[10:0],1'b0} - 12'd2 : 12'd0;
		end
		
		if ((CDD_DTEN && !CDD_DTEN_OLD) || (CDD_DIEN && !CDD_DIEN_OLD)) begin
			CDD_DATA_ADDR <= '0;
		end
	end
		
	bit  [10: 0] DISC_TOC_RPOS;
	bit  [ 7: 0] DISC_TOC_Q;
	dpram_dif #(10,16,11,8) disc_toc 
	(
		.clock(CLK),
		
		.address_a(CDD_DATA_ADDR[9:0]),
		.data_a(CDD_DATA),
		.wren_a(CDD_DIEN & CDD_WR),
		
		.address_b(DISC_TOC_RPOS),
		.q_b(DISC_TOC_Q)
	);
	
	bit  [11: 0] DISC_DATA_RPOS;
	bit  [ 7: 0] DISC_DATA_Q;
	dpram_dif #(11,16,12,8) disc_data
	(
		.clock(CLK),
		
		.address_a(CDD_DATA_ADDR[10:0]),
		.data_a(CDD_DATA),
		.wren_a(CDD_DTEN & ~CDD_DATA_ADDR[11] & CDD_WR),
		
		.address_b(DISC_DATA_RPOS),
		.q_b(DISC_DATA_Q)
	);
	
	typedef enum bit [2:0] {
		IO_IDLE,
		IO_CMD_READ,
		IO_CMD_WRITE,
		IO_DAT_READ
	} IOState_t;
	IOState_t IO_ST;
	
	
	typedef enum bit [2:0] {
		CMD_IDLE,
		CMD_EXEC
	} CommandState_t;
	CommandState_t CMD_ST;
	
	bit  [ 7: 0] STATUS;
	bit  [ 7: 0] ERROR;
//	bit  [ 7: 0] SPEED;
	
	bit  [ 7: 0] COMMAND[8];
	wire [ 7: 0] CMD_CODE = COMMAND[0];
	bit  [ 7: 0] STAT_DATA[12];
	bit  [ 7: 0] DOUT;
	
	bit          ST_EN,DT_EN;
	
	bit  [ 3: 0] STAT_FIFO_WPOS,STAT_FIFO_RPOS;
	
	//Block parameters (MODE SET page 0): density, block length (0 = 2048), flags (0x80 error byte, 0x40 subcode)
	bit  [ 7: 0] BLK_DENSITY;
	bit  [11: 0] BLK_LEN;
	bit          BLK_ERRB,BLK_SUBC;
	wire [11: 0] BLK_BASE = BLK_LEN == 12'd0 ? 12'd2048 : BLK_LEN;
	//What Main_MiSTer sends per sector (HOST_COMM[7] of READ): 0 = 2048 bytes of user data, 1 = 2352 raw bytes
	//(CD-DA samples big-endian), 2 = 2336 (raw minus sync+header), 3 = 2340 (raw minus sync)
	wire [ 1: 0] BLK_FMT  = BLK_BASE == 12'd2352 ? 2'd1 : BLK_BASE == 12'd2336 ? 2'd2 : BLK_BASE == 12'd2340 ? 2'd3 : 2'd0;
	wire [11: 0] BLK_DATA = BLK_FMT != 2'd0 || BLK_BASE < 12'd2048 ? BLK_BASE : 12'd2048;
	wire [11: 0] BLK_XFER = BLK_BASE + (BLK_SUBC ? 12'd96 : 12'd0) + (BLK_ERRB ? 12'd1 : 12'd0);

	//Current read: bytes per block from Main_MiSTer (data, then subcode when asked), bytes per block to the host
	//(what Main_MiSTer did not send, and the error byte, read as 0)
	bit  [ 1: 0] RD_FMT;
	bit          RD_SUBC;
	bit  [11: 0] RD_DATA_LEN,RD_XFER_LEN;
	bit  [11: 0] RX_BYTES;
	bit  [23: 0] RD_COUNT;
	bit          READING;

	//Absolute position (binary MSF) of the next block to transfer, for READ SUBQ
	bit  [ 7: 0] POS_M,POS_S,POS_F;

	//READ SUBQ: TOC scan
	bit  [ 2: 0] SQ_STEP;
	bit  [ 6: 0] SQ_T,SQ_LAST;
	bit  [ 7: 0] SQ_CTL,SQ_M,SQ_S;
	bit  [ 6: 0] SQ_TRK;
	bit  [ 7: 0] SQ_TCTL,SQ_TM,SQ_TS,SQ_TF;
	bit          SQ_FOUND,SQ_IDX;
	bit          REPLY_ERR;

	function bit [7:0] ToBCD(input bit [6:0] v);
		bit [3:0] tens;
		bit [6:0] units;
		tens = v >= 7'd90 ? 4'd9 : v >= 7'd80 ? 4'd8 : v >= 7'd70 ? 4'd7 : v >= 7'd60 ? 4'd6 : v >= 7'd50 ? 4'd5 :
		       v >= 7'd40 ? 4'd4 : v >= 7'd30 ? 4'd3 : v >= 7'd20 ? 4'd2 : v >= 7'd10 ? 4'd1 : 4'd0;
		units = v - {3'd0,tens} * 7'd10;
		return {tens,units[3:0]};
	endfunction

	//a - b in binary MSF (a >= b)
	function bit [23:0] MSFSub(input bit [23:0] a, input bit [23:0] b);
		bit [7:0] m,s,f;
		bit       bf,bs;
		f = a[7:0] - b[7:0];   bf = a[7:0] < b[7:0];
		if (bf) f = f + 8'd75;
		s = a[15:8] - b[15:8] - {7'd0,bf};   bs = {1'b0,a[15:8]} < {1'b0,b[15:8]} + {8'd0,bf};
		if (bs) s = s + 8'd60;
		m = a[23:16] - b[23:16] - {7'd0,bs};
		return {m,s,f};
	endfunction

	always @(posedge CLK or negedge RST_N) begin
		bit         CDHRD_N_OLD,CDHWR_N_OLD;
		bit [ 2: 0] CMD_DATA_CNT,COM_DATA_LEN;
		bit [ 3: 0] COM_STAT_CNT,COM_STAT_LEN;
		bit [15: 0] CMD_EXEC_WAIT;
		bit [11: 0] DATA_CNT;
		bit [23: 0] FRAME_CNT,NEXT_FRAME_CNT;
		bit [23: 0] SQ_REL;
		bit [ 7: 0] ST_DELAY_CNT;
		bit         CMD_REC;
		bit         CDD_IS_LOADED_OLD,TRAY_OPEN_OLD;
		
		if (!RST_N) begin
			IO_ST <= IO_IDLE;
			COMMAND <= '{8{'0}};
			STATUS <= 8'h81;
			ERROR <= ERROR_NO_ERR;
			
			CMD_DATA_CNT <= '0;
			COM_STAT_CNT <= '0;
			DATA_CNT <= '0;
			ST_EN <= 0;
			DT_EN <= 0;
			CDMDCHG <= 0;
			ST_DELAY_CNT <= '1;
			{CDD_IS_LOADED_OLD,TRAY_OPEN_OLD} <= '0;
			
			CMD_ST <= CMD_IDLE;
			CMD_REC <= 0;
			
			{BLK_DENSITY,BLK_LEN,BLK_ERRB,BLK_SUBC} <= '0;
			READING <= 0;
			{POS_M,POS_S,POS_F} <= {8'd0,8'd2,8'd0};
			HOST_COMM[7] <= '0;

`ifdef DEBUG
			DBG_CMD <= '{4{'0}};
`endif
		end
		else if (!CDRST_N) begin
			IO_ST <= IO_IDLE;
			COMMAND <= '{8{'0}};
//			STATUS <= CDD_IS_LOADED ? 8'hC1 : 8'h81;
			ERROR <= ERROR_NO_ERR;
			
			CMD_DATA_CNT <= '0;
			COM_STAT_CNT <= '0;
			DATA_CNT <= '0;
			ST_EN <= 0;
			DT_EN <= 0;
			CDMDCHG <= 0;
			{CDD_IS_LOADED_OLD,TRAY_OPEN_OLD} <= '0;
			
			CMD_ST <= CMD_IDLE;
			CMD_REC <= 0;

			{BLK_DENSITY,BLK_LEN,BLK_ERRB,BLK_SUBC} <= '0;
			READING <= 0;
		end
		else begin
`ifdef DEBUG
			if (DT_EN && !ST_EN && CE) DBG_WAIT_CNT <= DBG_WAIT_CNT + 1'd1;
`endif
			
			NEXT_FRAME_CNT = FRAME_CNT + 24'd1;
			
			CDD_COMM_SEND <= 0;
			
			CDHRD_N_OLD <= CDHRD_N;
			CDHWR_N_OLD <= CDHWR_N;
			case (IO_ST)
				IO_IDLE: begin
					if (!CDHRD_N && CDHRD_N_OLD && !CDCMD_N && !CDEN_N) begin
						IO_ST <= IO_CMD_READ;
					end
					if (!CDHWR_N && CDHWR_N_OLD && !CDCMD_N && !CDEN_N) begin
						IO_ST <= IO_CMD_WRITE;
					end
					if (!CDHRD_N && CDHRD_N_OLD && CDCMD_N && !CDEN_N) begin
						IO_ST <= IO_DAT_READ;
					end
				end
				
				IO_CMD_READ: begin
					DOUT <= STAT_DATA[STAT_FIFO_RPOS];
					STAT_FIFO_RPOS <= STAT_FIFO_RPOS + 4'd1;
					
					COM_STAT_CNT <= COM_STAT_CNT + 4'd1;
					if (COM_STAT_CNT == COM_STAT_LEN) begin
						ST_EN <= 0;
					end
					IO_ST <= IO_IDLE;
				end
				
				IO_CMD_WRITE: begin
					CMD_DATA_CNT <= CMD_DATA_CNT + 3'd1;
					if (CMD_DATA_CNT == 0) begin
						COMMAND[0] <= CDDI;
						//The OS sends 7 bytes for every command but ABORT (1 byte)
						COM_DATA_LEN <= CDDI == 8'h08 ? 3'd0 : 3'd6;
						if (CDDI == 8'h08) begin
							CMD_DATA_CNT <= '0;
							COM_STAT_CNT <= '0;
							STAT_FIFO_RPOS <= '0;
							CMD_REC <= 1;
						end
						case (CDDI)
							8'h80: COM_STAT_LEN <= 4'd3;
							8'h82: COM_STAT_LEN <= 4'd9;
							8'h83: COM_STAT_LEN <= 4'd11;
							8'h84: COM_STAT_LEN <= 4'd6;
							8'h85: COM_STAT_LEN <= 4'd6;
							8'h87: COM_STAT_LEN <= 4'd11;
							8'h8A: COM_STAT_LEN <= 4'd11;
							8'h8B: COM_STAT_LEN <= 4'd7;
							8'h8C: COM_STAT_LEN <= 4'd9;
							8'h8D: COM_STAT_LEN <= 4'd7;
							default: COM_STAT_LEN <= 4'd1;
						endcase
`ifdef DEBUG
						DBG_CMD[0] <= COMMAND[0];
						DBG_CMD[1] <= DBG_CMD[0];
						DBG_CMD[2] <= DBG_CMD[1];
						DBG_CMD[3] <= DBG_CMD[2];
`endif
						
					end else begin
						COMMAND[CMD_DATA_CNT] <= CDDI;
						if (CMD_DATA_CNT == COM_DATA_LEN) begin
							CMD_DATA_CNT <= '0;
							COM_STAT_CNT <= '0;
							STAT_FIFO_RPOS <= '0;
							if (CMD_CODE == 8'h10) begin
								DISC_DATA_RPOS <= '0;
								DATA_CNT <= '0;
								FRAME_CNT <= '0;
							end
							CMD_REC <= 1;
						end
					end
					IO_ST <= IO_IDLE;
				end
				
				IO_DAT_READ: begin
					if (DT_EN) begin
						DOUT <= DATA_CNT < RD_DATA_LEN && DATA_CNT < RX_BYTES ? DISC_DATA_Q : 8'h00;
						DISC_DATA_RPOS <= DISC_DATA_RPOS + 12'd1;
					
						DATA_CNT <= DATA_CNT + 12'd1;
						if (DATA_CNT == RD_XFER_LEN - 12'd1) begin
							DISC_DATA_RPOS <= '0;
							DATA_CNT <= '0;
							DT_EN <= 0;
							FRAME_CNT <= NEXT_FRAME_CNT;
							if (POS_F == 8'd74) begin
								POS_F <= '0;
								if (POS_S == 8'd59) begin POS_S <= '0; POS_M <= POS_M + 8'd1; end
								else POS_S <= POS_S + 8'd1;
							end else begin
								POS_F <= POS_F + 8'd1;
							end
							if (NEXT_FRAME_CNT != RD_COUNT) begin
								{HOST_COMM[0],HOST_COMM[1],HOST_COMM[2],HOST_COMM[3],HOST_COMM[4],HOST_COMM[5],HOST_COMM[6]} <= {8'h20,8'h00,8'h00,8'h00,8'h00,8'h00,8'h00};
								HOST_COMM[7] <= {5'b00000,RD_SUBC,RD_FMT};
								CDD_COMM_SEND <= 1;
							end else begin
								READING <= 0;
							end
						end
					end else begin
						DOUT <= 8'h00;
					end
					IO_ST <= IO_IDLE;
					
`ifdef DEBUG
					DBG_WAIT_CNT <= '0;
`endif
				end
				
			endcase
			
			if (CMD_EXEC_WAIT && CE) CMD_EXEC_WAIT <= CMD_EXEC_WAIT - 16'd1;
			case (CMD_ST)
				CMD_IDLE: if (CMD_REC && CE) begin
					case (CMD_CODE)
						8'h02: begin	//Spin up
							if (STATUS[7] && STATUS[6]) begin STATUS[5] <= 1; STATUS[0] <= 1; ERROR <= ERROR_NO_ERR; end
							else begin STATUS[4] <= 1; STATUS[0] <= 0; ERROR <= ERROR_DISC_OUT; end
							CMD_ST <= CMD_EXEC;
						end
						
						8'h01,	//Seek
						8'h03,	//Spin down
						8'h04,	//Diagnostics
						8'h05: begin	//No operation
							if (CMD_CODE == 8'h03) STATUS[5] <= 0;
							REPLY_ERR <= 0;
							CMD_ST <= CMD_EXEC;
						end

						8'h06,	//Eject
						8'h08,	//Abort
						8'h0A,	//Reset (no status)
						8'h0B: begin	//Flush
							//stop the current read here and in Main_MiSTer
							READING <= 0;
							DT_EN <= 0;
							DATA_CNT <= '0;
							DISC_DATA_RPOS <= '0;
							ST_DELAY_CNT <= '1;
							{HOST_COMM[0],HOST_COMM[1],HOST_COMM[2],HOST_COMM[3],HOST_COMM[4],HOST_COMM[5],HOST_COMM[6],HOST_COMM[7]} <= {CMD_CODE,8'h00,8'h00,8'h00,8'h00,8'h00,8'h00,8'h00};
							CDD_COMM_SEND <= 1;
							if (CMD_CODE == 8'h06) begin STATUS <= 8'h01; ERROR <= ERROR_NO_ERR; end
							REPLY_ERR <= 0;
							if (CMD_CODE == 8'h0A) begin
								{BLK_DENSITY,BLK_LEN,BLK_ERRB,BLK_SUBC} <= '0;
								ERROR <= ERROR_NO_ERR;
								CMD_REC <= 0;
							end else begin
								CMD_ST <= CMD_EXEC;
							end
						end

						8'h07: begin	//Inject (close the drawer)
							STATUS <= CDD_IS_LOADED ? 8'hC1 : 8'h81;
							REPLY_ERR <= 0;
							CMD_ST <= CMD_EXEC;
						end

						8'h09: begin	//Mode set
							if (COMMAND[1] == 8'h00) begin //Block parameters
								BLK_DENSITY <= COMMAND[2];
								BLK_LEN <= {COMMAND[3][3:0],COMMAND[4]};
								{BLK_ERRB,BLK_SUBC} <= COMMAND[5][7:6];
							end
							else if (COMMAND[1] == 8'h03) begin //Set speed
//								SPEED <= COMMAND[3];
							end
							else if (COMMAND[1] == 8'h05) begin //Set volume
								
							end
							CMD_ST <= CMD_EXEC;
						end
						
						8'h10: begin //Read data (the 3DO plays audio CDs with it: there is no play command)
							{HOST_COMM[0],HOST_COMM[1],HOST_COMM[2],HOST_COMM[3],HOST_COMM[4],HOST_COMM[5],HOST_COMM[6]} <= {COMMAND[0],COMMAND[1],COMMAND[2],COMMAND[3],COMMAND[4],COMMAND[5],COMMAND[6]};
							HOST_COMM[7] <= {5'b00000,BLK_SUBC,BLK_FMT};
							CDD_COMM_SEND <= 1;
							RD_FMT <= BLK_FMT;
							RD_SUBC <= BLK_SUBC;
							RD_DATA_LEN <= BLK_DATA + (BLK_SUBC ? 12'd96 : 12'd0);
							RD_XFER_LEN <= BLK_XFER;
							RD_COUNT <= {COMMAND[4],COMMAND[5],COMMAND[6]};
							{POS_M,POS_S,POS_F} <= {COMMAND[1],COMMAND[2],COMMAND[3]};
							READING <= 1;
							CMD_ST <= CMD_EXEC;
						end
						
						8'h80: begin	//Data path check
							CMD_ST <= CMD_EXEC;
						end
						
						8'h82: begin	//Read error
							CMD_ST <= CMD_EXEC;
						end
						
						8'h83: begin	//Read ID
							CMD_EXEC_WAIT <= 16'd4120;
							CMD_ST <= CMD_EXEC;
						end
						
						8'h85: begin	//Read capacity
							DISC_TOC_RPOS <= 11'h003;
							CMD_ST <= CMD_EXEC;
						end
						
						8'h8B: begin	//Read disc info
							DISC_TOC_RPOS <= 10'h000;
							CMD_ST <= CMD_EXEC;
						end
						
						8'h8C: begin	//Read TOC
							DISC_TOC_RPOS <= {COMMAND[2][6:0],4'h0};
							CMD_ST <= CMD_EXEC;
						end
						
						8'h8D: begin	//Read session info
							CMD_ST <= CMD_EXEC;
						end
						
						8'h84,	//Mode sense
						8'h8A: begin	//Read disc code
							CMD_ST <= CMD_EXEC;
						end

						8'h87: begin	//Read Sub-Q
							if (STATUS[7] && STATUS[6]) begin
								DISC_TOC_RPOS <= 11'h002;
								SQ_STEP <= '0;
								SQ_FOUND <= 0;
								REPLY_ERR <= 0;
							end else begin
								COM_STAT_LEN <= 4'd1;
								REPLY_ERR <= 1;
								ERROR <= ERROR_DISC_OUT;
							end
							CMD_ST <= CMD_EXEC;
						end

						default: begin //Read header/UPC/ISRC/device driver, play (not on this drive), unknown: illegal request
							COM_STAT_LEN <= 4'd1;
							REPLY_ERR <= 1;
							ERROR <= ERROR_ILLEGAL_REQ;
							CMD_ST <= CMD_EXEC;
						end
					endcase
					STAT_FIFO_WPOS <= '0;
				end
				
				CMD_EXEC: if (!CMD_EXEC_WAIT && CE) begin
					case (COMMAND[0])
						8'h02: begin	//Spin up
							STAT_FIFO_WPOS <= STAT_FIFO_WPOS + 4'd1;
							if (STAT_FIFO_WPOS == 4'd0) begin
								STAT_DATA[0] <= 8'h02;
							end else if (STAT_FIFO_WPOS == 4'd1) begin
								STAT_DATA[1] <= STATUS;
								ERROR <= ERROR_NO_ERR;
								ST_EN <= 1;
								CMD_REC <= 0;
								CMD_ST <= CMD_IDLE;
							end
						end
						
						8'h06: begin	//Eject
							STAT_FIFO_WPOS <= STAT_FIFO_WPOS + 4'd1;
							if (STAT_FIFO_WPOS == 4'd0) begin
								STAT_DATA[0] <= 8'h06;
							end else if (STAT_FIFO_WPOS == 4'd1) begin
								STAT_DATA[1] <= STATUS;
								ERROR <= ERROR_NO_ERR;
								ST_EN <= 1;
								CMD_REC <= 0;
								CMD_ST <= CMD_IDLE;
							end
						end
						
						8'h09: begin
							STAT_FIFO_WPOS <= STAT_FIFO_WPOS + 4'd1;
							if (STAT_FIFO_WPOS == 4'd0) begin
								STAT_DATA[0] <= 8'h09;
							end else if (STAT_FIFO_WPOS == 4'd1) begin
								STAT_DATA[1] <= STATUS;
								ERROR <= ERROR_NO_ERR;
								ST_EN <= 1;
								CMD_REC <= 0;
								CMD_ST <= CMD_IDLE;
							end
						end
						
						8'h10: begin //Read data
							STAT_FIFO_WPOS <= STAT_FIFO_WPOS + 4'd1;
							if (STAT_FIFO_WPOS == 4'd0) begin
								STAT_DATA[0] <= 8'h10;
							end else if (STAT_FIFO_WPOS == 4'd1) begin
								STAT_DATA[1] <= STATUS;
								ERROR <= ERROR_NO_ERR;
//								ST_EN <= 1;
								CMD_REC <= 0;
								CMD_ST <= CMD_IDLE;
							end
						end
						
						8'h80: begin	//Data path check
							STAT_FIFO_WPOS <= STAT_FIFO_WPOS + 4'd1;
							if (STAT_FIFO_WPOS == 4'd0) begin
								STAT_DATA[0] <= 8'h80;
							end else if (STAT_FIFO_WPOS == 4'd1) begin
								STAT_DATA[1] <= 8'hAA;
							end else if (STAT_FIFO_WPOS == 4'd2) begin
								STAT_DATA[2] <= 8'h55;
							end else if (STAT_FIFO_WPOS == 4'd3) begin
								STAT_DATA[3] <= STATUS;
								ERROR <= ERROR_NO_ERR;
								ST_EN <= 1;
								CMD_REC <= 0;
								CMD_ST <= CMD_IDLE;
							end
						end
						
						8'h82: begin	//Read error
							STAT_FIFO_WPOS <= STAT_FIFO_WPOS + 4'd1;
							if (STAT_FIFO_WPOS == 4'd0) begin
								STAT_DATA[0] <= 8'h82;
							end else if (STAT_FIFO_WPOS <= 4'd8) begin
								STAT_DATA[STAT_FIFO_WPOS] <= ERROR;
							end else if (STAT_FIFO_WPOS == 4'd9) begin
								STAT_DATA[9] <= STATUS;
								ERROR <= ERROR_NO_ERR;
								ST_EN <= 1;
								CMD_REC <= 0;
								CMD_ST <= CMD_IDLE;
							end
						end
						
						8'h83: begin	//Read ID
							STAT_FIFO_WPOS <= STAT_FIFO_WPOS + 4'd1;
							STAT_DATA[STAT_FIFO_WPOS] <= ID_STAT[STAT_FIFO_WPOS];
							if (STAT_FIFO_WPOS == 4'd11) begin
								STAT_DATA[11] <= STATUS;
								ERROR <= ERROR_NO_ERR;
								ST_EN <= 1;
								CMD_REC <= 0;
								CMD_ST <= CMD_IDLE;
							end
						end
						
						8'h85: begin	//Read capacity (7 bytes): lead-out MSF, 2 bytes, status (the OS reads the MSF 6 bytes from the end)
							DISC_TOC_RPOS <= DISC_TOC_RPOS + 10'd1;
							STAT_FIFO_WPOS <= STAT_FIFO_WPOS + 4'd1;
							if (STAT_FIFO_WPOS == 4'd0) begin
								STAT_DATA[0] <= 8'h85;
							end else if (STAT_FIFO_WPOS <= 4'd3) begin
								STAT_DATA[STAT_FIFO_WPOS] <= DISC_TOC_Q;
							end else if (STAT_FIFO_WPOS <= 4'd5) begin
								STAT_DATA[STAT_FIFO_WPOS] <= 8'h00;
							end else if (STAT_FIFO_WPOS == 4'd6) begin
								STAT_DATA[6] <= STATUS;
								ERROR <= ERROR_NO_ERR;
								ST_EN <= 1;
								CMD_REC <= 0;
								CMD_ST <= CMD_IDLE;
							end
						end
							
						8'h8B: begin	//Read disc info
							DISC_TOC_RPOS <= DISC_TOC_RPOS + 10'd1;
							STAT_FIFO_WPOS <= STAT_FIFO_WPOS + 4'd1;
							if (STAT_FIFO_WPOS == 4'd0) begin
								STAT_DATA[0] <= 8'h8B;
							end else if (STAT_FIFO_WPOS <= 4'd6) begin
								STAT_DATA[STAT_FIFO_WPOS] <= DISC_TOC_Q;
							end else if (STAT_FIFO_WPOS == 4'd7) begin
								STAT_DATA[7] <= STATUS;
								ERROR <= ERROR_NO_ERR;
								ST_EN <= 1;
								CMD_REC <= 0;
								CMD_ST <= CMD_IDLE;
							end
						end
							
						8'h8C: begin	//Read TOC
							DISC_TOC_RPOS <= DISC_TOC_RPOS + 10'd1;
							STAT_FIFO_WPOS <= STAT_FIFO_WPOS + 4'd1;
							if (STAT_FIFO_WPOS == 4'd0) begin
								STAT_DATA[0] <= 8'h8C;
							end else if (STAT_FIFO_WPOS <= 4'd8) begin
								STAT_DATA[STAT_FIFO_WPOS] <= DISC_TOC_Q;
							end else if (STAT_FIFO_WPOS == 4'd9) begin
								STAT_DATA[9] <= STATUS;
								ERROR <= ERROR_NO_ERR;
								ST_EN <= 1;
								CMD_REC <= 0;
								CMD_ST <= CMD_IDLE;
							end
						end
							
						8'h8D: begin	//Read session info
							STAT_FIFO_WPOS <= STAT_FIFO_WPOS + 4'd1;
							if (STAT_FIFO_WPOS == 4'd0) begin
								STAT_DATA[0] <= 8'h8D;
							end else if (STAT_FIFO_WPOS <= 4'd6) begin
								STAT_DATA[STAT_FIFO_WPOS] <= 8'h00;
							end else if (STAT_FIFO_WPOS == 4'd7) begin
								STAT_DATA[7] <= STATUS;
								ERROR <= ERROR_NO_ERR;
								ST_EN <= 1;
								CMD_REC <= 0;
								CMD_ST <= CMD_IDLE;
							end
						end

						8'h84: begin	//Mode sense (7 bytes): page, then page 0 = density, block length, flags
							STAT_FIFO_WPOS <= STAT_FIFO_WPOS + 4'd1;
							if (STAT_FIFO_WPOS == 4'd0) begin
								STAT_DATA[0] <= 8'h84;
							end else if (STAT_FIFO_WPOS == 4'd1) begin
								STAT_DATA[1] <= COMMAND[1];
							end else if (STAT_FIFO_WPOS == 4'd2) begin
								STAT_DATA[2] <= COMMAND[1] == 8'h00 ? BLK_DENSITY : 8'h00;
							end else if (STAT_FIFO_WPOS == 4'd3) begin
								STAT_DATA[3] <= COMMAND[1] == 8'h00 ? {4'h0,BLK_BASE[11:8]} : 8'h00;
							end else if (STAT_FIFO_WPOS == 4'd4) begin
								STAT_DATA[4] <= COMMAND[1] == 8'h00 ? BLK_BASE[7:0] : 8'h00;
							end else if (STAT_FIFO_WPOS == 4'd5) begin
								STAT_DATA[5] <= COMMAND[1] == 8'h00 ? {BLK_ERRB,BLK_SUBC,6'b000000} : 8'h00;
							end else if (STAT_FIFO_WPOS == 4'd6) begin
								STAT_DATA[6] <= STATUS;
								ERROR <= ERROR_NO_ERR;
								ST_EN <= 1;
								CMD_REC <= 0;
								CMD_ST <= CMD_IDLE;
							end
						end

						8'h87: begin	//Read Sub-Q: find the track holding the current position in the TOC
							if (REPLY_ERR) begin
								STAT_FIFO_WPOS <= STAT_FIFO_WPOS + 4'd1;
								if (STAT_FIFO_WPOS == 4'd0) begin
									STAT_DATA[0] <= 8'h87;
								end else begin
									STAT_DATA[1] <= STATUS | 8'h10;
									ST_EN <= 1;
									CMD_REC <= 0;
									CMD_ST <= CMD_IDLE;
								end
							end else begin
								case (SQ_STEP)
									3'd0: begin SQ_T    <= DISC_TOC_Q[6:0]; DISC_TOC_RPOS <= 11'h003;      SQ_STEP <= 3'd1; end	//first track
									3'd1: begin SQ_LAST <= DISC_TOC_Q[6:0]; DISC_TOC_RPOS <= {SQ_T,4'h2};  SQ_STEP <= 3'd2; end	//last track
									3'd2: begin SQ_CTL  <= DISC_TOC_Q;      DISC_TOC_RPOS <= {SQ_T,4'h5};  SQ_STEP <= 3'd3; end	//track control
									3'd3: begin SQ_M    <= DISC_TOC_Q;      DISC_TOC_RPOS <= {SQ_T,4'h6};  SQ_STEP <= 3'd4; end	//track start
									3'd4: begin SQ_S    <= DISC_TOC_Q;      DISC_TOC_RPOS <= {SQ_T,4'h7};  SQ_STEP <= 3'd5; end
									3'd5: begin
										if ({SQ_M,SQ_S,DISC_TOC_Q} <= {POS_M,POS_S,POS_F}) begin
											{SQ_TRK,SQ_TCTL,SQ_TM,SQ_TS,SQ_TF} <= {SQ_T,SQ_CTL,SQ_M,SQ_S,DISC_TOC_Q};
											SQ_IDX <= 1;
											SQ_FOUND <= 1;
											if (SQ_T < SQ_LAST && SQ_T < 7'd99) begin
												SQ_T <= SQ_T + 7'd1;
												DISC_TOC_RPOS <= {SQ_T + 7'd1,4'h2};
												SQ_STEP <= 3'd2;
											end else begin
												SQ_STEP <= 3'd6;
											end
										end else begin
											if (!SQ_FOUND) begin	//before the first track: its pregap (index 0)
												{SQ_TRK,SQ_TCTL,SQ_TM,SQ_TS,SQ_TF} <= {SQ_T,SQ_CTL,SQ_M,SQ_S,DISC_TOC_Q};
												SQ_IDX <= 0;
											end
											SQ_STEP <= 3'd6;
										end
									end
									default: begin
										SQ_REL = SQ_IDX ? MSFSub({POS_M,POS_S,POS_F},{SQ_TM,SQ_TS,SQ_TF}) : MSFSub({SQ_TM,SQ_TS,SQ_TF},{POS_M,POS_S,POS_F});
										STAT_DATA[0] <= 8'h87;
										STAT_DATA[1] <= 8'h00;
										STAT_DATA[2] <= {SQ_TCTL[3:0],4'h1};	//control, ADR 1 (position)
										STAT_DATA[3] <= ToBCD(SQ_TRK);
										STAT_DATA[4] <= {7'd0,SQ_IDX};
										STAT_DATA[5] <= POS_M;
										STAT_DATA[6] <= POS_S;
										STAT_DATA[7] <= POS_F;
										STAT_DATA[8] <= SQ_REL[23:16];
										STAT_DATA[9] <= SQ_REL[15:8];
										STAT_DATA[10] <= SQ_REL[7:0];
										STAT_DATA[11] <= STATUS;
										ERROR <= ERROR_NO_ERR;
										ST_EN <= 1;
										CMD_REC <= 0;
										CMD_ST <= CMD_IDLE;
									end
								endcase
							end
						end

						8'h8A: begin	//Read disc code
							STAT_FIFO_WPOS <= STAT_FIFO_WPOS + 4'd1;
							if (STAT_FIFO_WPOS == 4'd0) begin
								STAT_DATA[0] <= 8'h8A;
							end else if (STAT_FIFO_WPOS <= 4'd10) begin
								STAT_DATA[STAT_FIFO_WPOS] <= 8'h00;
							end else if (STAT_FIFO_WPOS == 4'd11) begin
								STAT_DATA[11] <= STATUS;
								ERROR <= ERROR_NO_ERR;
								ST_EN <= 1;
								CMD_REC <= 0;
								CMD_ST <= CMD_IDLE;
							end
						end

						default: begin	//the command and the drive status (error bit set for an illegal request)
							STAT_FIFO_WPOS <= STAT_FIFO_WPOS + 4'd1;
							if (STAT_FIFO_WPOS == 4'd0) begin
								STAT_DATA[0] <= COMMAND[0];
							end else begin
								STAT_DATA[1] <= STATUS | {3'b000,REPLY_ERR,4'b0000};
								if (!REPLY_ERR) ERROR <= ERROR_NO_ERR;
								ST_EN <= 1;
								CMD_REC <= 0;
								CMD_ST <= CMD_IDLE;
							end
						end
					endcase
				end
				
			endcase
			
			if (CDD_BLOCK_READY && READING) begin
				DT_EN <= 1;
				if (NEXT_FRAME_CNT == RD_COUNT) begin
					ST_DELAY_CNT <= 8'd192;
				end
			end
			
			if (CE) begin
				if (ST_DELAY_CNT != 8'd255) begin
					ST_DELAY_CNT <= ST_DELAY_CNT - 8'd1;
				end
				if (ST_DELAY_CNT == 8'd0) begin
					ST_EN <= 1;
				end
			end
			
			CDD_IS_LOADED_OLD <= CDD_IS_LOADED;
			if (CDD_IS_LOADED && !CDD_IS_LOADED_OLD) begin
				CDMDCHG <= 1;
				STATUS <= 8'hC1;
			end
			TRAY_OPEN_OLD <= TRAY_OPEN;
			if (TRAY_OPEN && !TRAY_OPEN_OLD) begin
				CDMDCHG <= 1;
				STATUS <= 8'h01;
			end
		end
	end
	
	assign CDDO = DOUT;
	assign CDSTEN_N = ~ST_EN;
	assign CDDTEN_N = ~DT_EN;
//	assign CDMDCHG = 1;
	
endmodule
