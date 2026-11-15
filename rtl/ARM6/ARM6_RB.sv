// synopsys translate_off
`define SIM
// synopsys translate_on

module ARM6_RB (
	input             CLK,
	input             RST_N,
	input             CE,
	input             EN,
	
	input       [3:0] MODE,
	
	input       [3:0] W_A,
	input      [31:0] W_D,
	input             W_WE,
	
	input       [3:0] RA_A,
	output     [31:0] RA_Q,
	input       [3:0] RB_A,
	output     [31:0] RB_Q,
	
	
	input      [31:0] PC_D,
	input             PC_WE,
	output     [31:0] PC_Q
	
`ifdef DEBUG
	,
	output     [31:0] DBG_RA_Q,
	output     [31:0] DBG_RB_Q															 
`endif
);
	
	
	wire USR_SEL = (MODE == 4'b0000) || (MODE == 4'b0001 && W_A <= 4'd7) || (MODE >= 4'b0010 && W_A <= 4'd12);
	wire FIQ_SEL = (MODE == 4'b0001 && W_A >= 4'd8);
	wire SVC_SEL = (MODE == 4'b0011 && W_A >= 4'd13);
	wire ABT_SEL = (MODE == 4'b0111 && W_A >= 4'd13);
	wire IRQ_SEL = (MODE == 4'b0010 && W_A >= 4'd13);
	wire UND_SEL = (MODE == 4'b1011 && W_A >= 4'd13);
	
	reg [31:0]  GR_R15; 
	
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) begin
			GR_R15 <= '0;
		end
		else if (EN) begin
			if (PC_WE && CE) begin
				GR_R15 <= PC_D;
			end
		end
	end

`ifdef SIM
	reg [31:0]  GR_USR[16];
	reg [31:0]  GR_FIQ[16];
	reg [31:0]  GR_SVC[16];
	reg [31:0]  GR_ABT[16];
	reg [31:0]  GR_IRQ[16];
	reg [31:0]  GR_UND[16]; 
	reg [31:0]  GR_R15; 
	
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) begin
			GR_USR <= '{16{'0}};
			GR_FIQ <= '{16{'0}};
			GR_SVC <= '{16{'0}};
			GR_ABT <= '{16{'0}};
			GR_IRQ <= '{16{'0}};
			GR_UND <= '{16{'0}};
		end
		else if (EN) begin
			if (USR_SEL && W_WE && CE) begin
				GR_USR[W_A] <= W_D;
			end
			if (FIQ_SEL && W_WE && CE) begin
				GR_FIQ[W_A] <= W_D;
			end
			if (SVC_SEL && W_WE && CE) begin
				GR_SVC[W_A] <= W_D;
			end
			if (ABT_SEL && W_WE && CE) begin
				GR_ABT[W_A] <= W_D;
			end
			if (IRQ_SEL && W_WE && CE) begin
				GR_IRQ[W_A] <= W_D;
			end
			if (UND_SEL && W_WE && CE) begin
				GR_UND[W_A] <= W_D;
			end
		end
	end
	
	assign RA_Q = RA_A == 4'd15                    ? GR_R15 : 
	              MODE == 4'b1011 && RA_A >= 4'd13 ? GR_UND[RA_A] :
					  MODE == 4'b0010 && RA_A >= 4'd13 ? GR_IRQ[RA_A] :
					  MODE == 4'b0111 && RA_A >= 4'd13 ? GR_ABT[RA_A] :
					  MODE == 4'b0011 && RA_A >= 4'd13 ? GR_SVC[RA_A] :
					  MODE == 4'b0001 && RA_A >= 4'd8  ? GR_FIQ[RA_A] :
					                                     GR_USR[RA_A];
	assign RB_Q = RB_A == 4'd15                    ? GR_R15 : 
	              MODE == 4'b1011 && RB_A >= 4'd13 ? GR_UND[RB_A] :
					  MODE == 4'b0010 && RB_A >= 4'd13 ? GR_IRQ[RB_A] :
					  MODE == 4'b0111 && RB_A >= 4'd13 ? GR_ABT[RB_A] :
					  MODE == 4'b0011 && RB_A >= 4'd13 ? GR_SVC[RB_A] :
					  MODE == 4'b0001 && RB_A >= 4'd8  ? GR_FIQ[RB_A] :
					                                     GR_USR[RB_A];
	
`else 

	// Game Bub port: the write enables include EN, as GR_R15's and the simulation
	// bank's do (registers were written while the core was paused, EN low)
	bit [31:0]  RB_USR_A_Q,RB_USR_B_Q; 
	ARM6_RB_RAM RB_USR (CLK,W_A,W_D,USR_SEL & W_WE & CE & EN,RA_A,RB_USR_A_Q,RB_A,RB_USR_B_Q);
	bit [31:0]  RB_FIQ_A_Q,RB_FIQ_B_Q; 
	ARM6_RB_RAM RB_FIQ (CLK,W_A,W_D,FIQ_SEL & W_WE & CE & EN,RA_A,RB_FIQ_A_Q,RB_A,RB_FIQ_B_Q);
	bit [31:0]  RB_SVC_A_Q,RB_SVC_B_Q; 
	ARM6_RB_RAM RB_SVC (CLK,W_A,W_D,SVC_SEL & W_WE & CE & EN,RA_A,RB_SVC_A_Q,RB_A,RB_SVC_B_Q);
	bit [31:0]  RB_ABT_A_Q,RB_ABT_B_Q; 
	ARM6_RB_RAM RB_ABT (CLK,W_A,W_D,ABT_SEL & W_WE & CE & EN,RA_A,RB_ABT_A_Q,RB_A,RB_ABT_B_Q);
	bit [31:0]  RB_IRQ_A_Q,RB_IRQ_B_Q; 
	ARM6_RB_RAM RB_IRQ (CLK,W_A,W_D,IRQ_SEL & W_WE & CE & EN,RA_A,RB_IRQ_A_Q,RB_A,RB_IRQ_B_Q);
	bit [31:0]  RB_UND_A_Q,RB_UND_B_Q; 
	ARM6_RB_RAM RB_UND (CLK,W_A,W_D,UND_SEL & W_WE & CE & EN,RA_A,RB_UND_A_Q,RB_A,RB_UND_B_Q);

	
	assign RA_Q = RA_A == 4'd15                    ? GR_R15 : 
	              MODE == 4'b1011 && RA_A >= 4'd13 ? RB_UND_A_Q :
					  MODE == 4'b0010 && RA_A >= 4'd13 ? RB_IRQ_A_Q :
					  MODE == 4'b0111 && RA_A >= 4'd13 ? RB_ABT_A_Q :
					  MODE == 4'b0011 && RA_A >= 4'd13 ? RB_SVC_A_Q :
					  MODE == 4'b0001 && RA_A >= 4'd8  ? RB_FIQ_A_Q :
					                                     RB_USR_A_Q;
	assign RB_Q = RB_A == 4'd15                    ? GR_R15 : 
	              MODE == 4'b1011 && RB_A >= 4'd13 ? RB_UND_B_Q :
					  MODE == 4'b0010 && RB_A >= 4'd13 ? RB_IRQ_B_Q :
					  MODE == 4'b0111 && RB_A >= 4'd13 ? RB_ABT_B_Q :
					  MODE == 4'b0011 && RB_A >= 4'd13 ? RB_SVC_B_Q :
					  MODE == 4'b0001 && RB_A >= 4'd8  ? RB_FIQ_B_Q :
					                                     RB_USR_B_Q;
`ifdef DEBUG
	reg [31:0]  GR_USR[16];
	reg [31:0]  GR_FIQ[16];
	reg [31:0]  GR_SVC[16];
	reg [31:0]  GR_ABT[16];
	reg [31:0]  GR_IRQ[16];
	reg [31:0]  GR_UND[16]; 
	
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) begin
			GR_USR <= '{16{'0}};
			GR_FIQ <= '{16{'0}};
			GR_SVC <= '{16{'0}};
			GR_ABT <= '{16{'0}};
			GR_IRQ <= '{16{'0}};
			GR_UND <= '{16{'0}};
		end
		else if (EN) begin
			if (USR_SEL && W_WE && CE) begin
				GR_USR[W_A] <= W_D;
			end
			if (FIQ_SEL && W_WE && CE) begin
				GR_FIQ[W_A] <= W_D;
			end
			if (SVC_SEL && W_WE && CE) begin
				GR_SVC[W_A] <= W_D;
			end
			if (ABT_SEL && W_WE && CE) begin
				GR_ABT[W_A] <= W_D;
			end
			if (IRQ_SEL && W_WE && CE) begin
				GR_IRQ[W_A] <= W_D;
			end
			if (UND_SEL && W_WE && CE) begin
				GR_UND[W_A] <= W_D;
			end
		end
	end

	assign DBG_RA_Q = RA_A == 4'd15                    ? GR_R15 : 
	              MODE == 4'b1011 && RA_A >= 4'd13 ? GR_UND[RA_A] :
					  MODE == 4'b0010 && RA_A >= 4'd13 ? GR_IRQ[RA_A] :
					  MODE == 4'b0111 && RA_A >= 4'd13 ? GR_ABT[RA_A] :
					  MODE == 4'b0011 && RA_A >= 4'd13 ? GR_SVC[RA_A] :
					  MODE == 4'b0001 && RA_A >= 4'd8  ? GR_FIQ[RA_A] :
					                                     GR_USR[RA_A];
	assign DBG_RB_Q = RB_A == 4'd15                    ? GR_R15 : 
	              MODE == 4'b1011 && RB_A >= 4'd13 ? GR_UND[RB_A] :
					  MODE == 4'b0010 && RB_A >= 4'd13 ? GR_IRQ[RB_A] :
					  MODE == 4'b0111 && RB_A >= 4'd13 ? GR_ABT[RB_A] :
					  MODE == 4'b0011 && RB_A >= 4'd13 ? GR_SVC[RB_A] :
					  MODE == 4'b0001 && RB_A >= 4'd8  ? GR_FIQ[RB_A] :
					                                     GR_USR[RB_A];
																	 
`endif
`endif

	assign PC_Q = GR_R15;

endmodule

module ARM6_RB_RAM (
	input             CLK,
	
	input       [3:0] W_A,
	input      [31:0] W_D,
	input             W_WE,
	
	input       [3:0] RA_A,
	output     [31:0] RA_Q,
	input       [3:0] RB_A,
	output     [31:0] RB_Q
);
		
	altdpram	altdpram_component_a (
				.data (W_D),
				.inclock (CLK),
				.outclock (CLK),
				.rdaddress (RA_A),
				.wraddress (W_A),
				.wren (W_WE),
				.q (RA_Q),
				.aclr (1'b0),
				.byteena (1'b1),
				.inclocken (1'b1),
				.outclocken (1'b1),
				.rdaddressstall (1'b0),
				.rden (1'b1),
//				.sclr (1'b0),
				.wraddressstall (1'b0));
	defparam
		altdpram_component_a.indata_aclr = "OFF",
		altdpram_component_a.indata_reg = "INCLOCK",
		altdpram_component_a.intended_device_family = "Cyclone V",
		altdpram_component_a.lpm_type = "altdpram",
		altdpram_component_a.outdata_aclr = "OFF",
		altdpram_component_a.outdata_reg = "UNREGISTERED",
		altdpram_component_a.ram_block_type = "MLAB",
		altdpram_component_a.rdaddress_aclr = "OFF",
		altdpram_component_a.rdaddress_reg = "UNREGISTERED",
		altdpram_component_a.rdcontrol_aclr = "OFF",
		altdpram_component_a.rdcontrol_reg = "UNREGISTERED",
		altdpram_component_a.read_during_write_mode_mixed_ports = "CONSTRAINED_DONT_CARE",
		altdpram_component_a.width = 32,
		altdpram_component_a.widthad = 4,
		altdpram_component_a.width_byteena = 1,
		altdpram_component_a.wraddress_aclr = "OFF",
		altdpram_component_a.wraddress_reg = "INCLOCK",
		altdpram_component_a.wrcontrol_aclr = "OFF",
		altdpram_component_a.wrcontrol_reg = "INCLOCK";
		
	altdpram	altdpram_component_b (
				.data (W_D),
				.inclock (CLK),
				.outclock (CLK),
				.rdaddress (RB_A),
				.wraddress (W_A),
				.wren (W_WE),
				.q (RB_Q),
				.aclr (1'b0),
				.byteena (1'b1),
				.inclocken (1'b1),
				.outclocken (1'b1),
				.rdaddressstall (1'b0),
				.rden (1'b1),
//				.sclr (1'b0),
				.wraddressstall (1'b0));
	defparam
		altdpram_component_b.indata_aclr = "OFF",
		altdpram_component_b.indata_reg = "INCLOCK",
		altdpram_component_b.intended_device_family = "Cyclone V",
		altdpram_component_b.lpm_type = "altdpram",
		altdpram_component_b.outdata_aclr = "OFF",
		altdpram_component_b.outdata_reg = "UNREGISTERED",
		altdpram_component_b.ram_block_type = "MLAB",
		altdpram_component_b.rdaddress_aclr = "OFF",
		altdpram_component_b.rdaddress_reg = "UNREGISTERED",
		altdpram_component_b.rdcontrol_aclr = "OFF",
		altdpram_component_b.rdcontrol_reg = "UNREGISTERED",
		altdpram_component_b.read_during_write_mode_mixed_ports = "CONSTRAINED_DONT_CARE",
		altdpram_component_b.width = 32,
		altdpram_component_b.widthad = 4,
		altdpram_component_b.width_byteena = 1,
		altdpram_component_b.wraddress_aclr = "OFF",
		altdpram_component_b.wraddress_reg = "INCLOCK",
		altdpram_component_b.wrcontrol_aclr = "OFF",
		altdpram_component_b.wrcontrol_reg = "INCLOCK";

endmodule
