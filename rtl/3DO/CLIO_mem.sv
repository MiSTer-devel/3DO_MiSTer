// synopsys translate_off
`define SIM
// synopsys translate_on

module CLIO_DMA_FIFO (
	input	        CLK,
	input         EN,
	input         RST,
	
	input	 [31:0] DATA,
	input	        WRREQ,
	input	        RDREQ,
	output [31:0] Q,
	
	output	     EMPTY,
	output	     FULL
);

	wire [31: 0] sub_wire0;
	bit  [ 2: 0] RADDR;
	bit  [ 2: 0] WADDR;
	bit  [ 3: 0] AMOUNT;
	
	always @(posedge CLK) begin
		if (RST) begin
			AMOUNT <= '0;
			RADDR <= '0;
			WADDR <= '0;
		end
		else if (EN) begin
			if (WRREQ && !AMOUNT[3]) begin
				WADDR <= WADDR + 3'd1;
			end
			if (RDREQ && AMOUNT) begin
				RADDR <= RADDR + 3'd1;
			end
			
			if (WRREQ && !RDREQ && !AMOUNT[3]) begin
				AMOUNT <= AMOUNT + 4'd1;
			end else if (!WRREQ && RDREQ && AMOUNT) begin
				AMOUNT <= AMOUNT - 4'd1;
			end
		end
	end
	assign EMPTY = ~|AMOUNT;
	assign FULL = AMOUNT[3];

`ifdef SIM

	reg [31:0]  MEM[8];
	initial begin
		MEM <= '{8{'0}};
	end
	
	always @(posedge CLK) begin
		if (EN) begin
			if (WRREQ) begin
				MEM[WADDR] <= DATA;
			end
		end
	end

	assign Q = MEM[RADDR];
											  	
`else 
	
	altdpram	altdpram_component (
				.data (DATA),
				.inclock (CLK),
				.rdaddress (RADDR),
				.wraddress (WADDR),
				.wren (WRREQ && EN),
				.q (sub_wire0),
				.aclr (1'b0),
				.byteena (1'b1),
				.inclocken (1'b1),
				.rdaddressstall (1'b0),
				.rden (1'b1),
//				.sclr (1'b0),
				.wraddressstall (1'b0));
	defparam
		altdpram_component.indata_aclr = "OFF",
		altdpram_component.indata_reg = "INCLOCK",
		altdpram_component.intended_device_family = "Cyclone V",
		altdpram_component.lpm_type = "altdpram",
		altdpram_component.outdata_aclr = "OFF",
		altdpram_component.outdata_reg = "UNREGISTERED",
		altdpram_component.ram_block_type = "MLAB",
		altdpram_component.rdaddress_aclr = "OFF",
		altdpram_component.rdaddress_reg = "UNREGISTERED",
		altdpram_component.rdcontrol_aclr = "OFF",
		altdpram_component.rdcontrol_reg = "UNREGISTERED",
		altdpram_component.read_during_write_mode_mixed_ports = "CONSTRAINED_DONT_CARE",
		altdpram_component.width = 32,
		altdpram_component.widthad = 3,
		altdpram_component.width_byteena = 1,
		altdpram_component.wraddress_aclr = "OFF",
		altdpram_component.wraddress_reg = "INCLOCK",
		altdpram_component.wrcontrol_aclr = "OFF",
		altdpram_component.wrcontrol_reg = "INCLOCK";
		
	assign Q = RADDR == WADDR && WRREQ ? DATA : sub_wire0;

`endif

endmodule
module CLIO_DSP_NRAM 
`ifdef SIM
#(
	parameter mem_file = ""
)
`endif
(
	input             CLK,
	input             EN,
	
	input     [ 8: 0] WA,
	input     [15: 0] WD,
	input             WE,
	
	input     [ 8: 0] RA,
	output    [15: 0] RD
);
	
`ifdef SIM

	reg [15:0]  MEM[512];
	initial begin
		//MEM <= '{512{'0}};
		$readmemh(mem_file, MEM);
	end
	
	always @(posedge CLK) begin
		if (EN) begin
			if (WE) begin
				MEM[WA] <= WD;
			end
		end
	end

	assign RD = MEM[RA];
											  	
`else 

	wire [15: 0] sub_wire0;

	altdpram	altdpram_component (
				.data (WD),
				.inclock (CLK),
				.rdaddress (RA),
				.wraddress (WA),
				.wren (WE && EN),
				.q (sub_wire0),
				.aclr (1'b0),
				.byteena (1'b1),
				.inclocken (1'b1),
				.rdaddressstall (1'b0),
				.rden (1'b1),
//				.sclr (1'b0),
				.wraddressstall (1'b0));
	defparam
		altdpram_component.indata_aclr = "OFF",
		altdpram_component.indata_reg = "INCLOCK",
		altdpram_component.intended_device_family = "Cyclone V",
		altdpram_component.lpm_type = "altdpram",
		altdpram_component.outdata_aclr = "OFF",
		altdpram_component.outdata_reg = "UNREGISTERED",
		altdpram_component.ram_block_type = "MLAB",
		altdpram_component.rdaddress_aclr = "OFF",
		altdpram_component.rdaddress_reg = "UNREGISTERED",
		altdpram_component.rdcontrol_aclr = "OFF",
		altdpram_component.rdcontrol_reg = "UNREGISTERED",
		altdpram_component.read_during_write_mode_mixed_ports = "CONSTRAINED_DONT_CARE",
		altdpram_component.width = 16,
		altdpram_component.widthad = 9,
		altdpram_component.width_byteena = 1,
		altdpram_component.wraddress_aclr = "OFF",
		altdpram_component.wraddress_reg = "INCLOCK",
		altdpram_component.wrcontrol_aclr = "OFF",
		altdpram_component.wrcontrol_reg = "INCLOCK";
		
	assign RD = sub_wire0;

`endif

endmodule

module CLIO_DSP_EIRAM (
	input             CLK,
	input             EN,
	
	input     [ 6: 0] WA,
	input     [15: 0] WD,
	input             WE,
	
	input     [ 6: 0] RA,
	output    [15: 0] RD
);

`ifdef SIM

	reg [15:0]  MEM[128];
	initial begin
		MEM <= '{128{'0}};
	end
	
	always @(posedge CLK) begin
		if (EN) begin
			if (WE) begin
				MEM[WA] <= WD;
			end
		end
	end

	assign RD = MEM[RA];
											  	
`else 

	wire [15: 0] sub_wire0;

	altdpram	altdpram_component (
				.data (WD),
				.inclock (CLK),
				.rdaddress (RA),
				.wraddress (WA),
				.wren (WE && EN),
				.q (sub_wire0),
				.aclr (1'b0),
				.byteena (1'b1),
				.inclocken (1'b1),
				.rdaddressstall (1'b0),
				.rden (1'b1),
//				.sclr (1'b0),
				.wraddressstall (1'b0));
	defparam
		altdpram_component.indata_aclr = "OFF",
		altdpram_component.indata_reg = "INCLOCK",
		altdpram_component.intended_device_family = "Cyclone V",
		altdpram_component.lpm_type = "altdpram",
		altdpram_component.outdata_aclr = "OFF",
		altdpram_component.outdata_reg = "UNREGISTERED",
		altdpram_component.ram_block_type = "MLAB",
		altdpram_component.rdaddress_aclr = "OFF",
		altdpram_component.rdaddress_reg = "UNREGISTERED",
		altdpram_component.rdcontrol_aclr = "OFF",
		altdpram_component.rdcontrol_reg = "UNREGISTERED",
		altdpram_component.read_during_write_mode_mixed_ports = "CONSTRAINED_DONT_CARE",
		altdpram_component.width = 16,
		altdpram_component.widthad = 7,
		altdpram_component.width_byteena = 1,
		altdpram_component.wraddress_aclr = "OFF",
		altdpram_component.wraddress_reg = "INCLOCK",
		altdpram_component.wrcontrol_aclr = "OFF",
		altdpram_component.wrcontrol_reg = "INCLOCK";
		
	assign RD = sub_wire0;

`endif

endmodule


module CLIO_DSP_EORAM (
	input             CLK,
	input             EN,
	
	input     [ 3: 0] WA,
	input     [15: 0] WD,
	input             WE,
	
	input     [ 3: 0] RA,
	output    [15: 0] RD
);

`ifdef SIM

	reg [15:0]  MEM[16];
	initial begin
		MEM <= '{16{'0}};
	end
	
	always @(posedge CLK) begin
		if (EN) begin
			if (WE) begin
				MEM[WA] <= WD;
			end
		end
	end

	assign RD = MEM[RA];
											  	
`else 

	wire [15: 0] sub_wire0;

	altdpram	altdpram_component (
				.data (WD),
				.inclock (CLK),
				.rdaddress (RA),
				.wraddress (WA),
				.wren (WE && EN),
				.q (sub_wire0),
				.aclr (1'b0),
				.byteena (1'b1),
				.inclocken (1'b1),
				.rdaddressstall (1'b0),
				.rden (1'b1),
//				.sclr (1'b0),
				.wraddressstall (1'b0));
	defparam
		altdpram_component.indata_aclr = "OFF",
		altdpram_component.indata_reg = "INCLOCK",
		altdpram_component.intended_device_family = "Cyclone V",
		altdpram_component.lpm_type = "altdpram",
		altdpram_component.outdata_aclr = "OFF",
		altdpram_component.outdata_reg = "UNREGISTERED",
		altdpram_component.ram_block_type = "MLAB",
		altdpram_component.rdaddress_aclr = "OFF",
		altdpram_component.rdaddress_reg = "UNREGISTERED",
		altdpram_component.rdcontrol_aclr = "OFF",
		altdpram_component.rdcontrol_reg = "UNREGISTERED",
		altdpram_component.read_during_write_mode_mixed_ports = "CONSTRAINED_DONT_CARE",
		altdpram_component.width = 16,
		altdpram_component.widthad = 4,
		altdpram_component.width_byteena = 1,
		altdpram_component.wraddress_aclr = "OFF",
		altdpram_component.wraddress_reg = "INCLOCK",
		altdpram_component.wrcontrol_aclr = "OFF",
		altdpram_component.wrcontrol_reg = "INCLOCK";
		
	assign RD = sub_wire0;

`endif

endmodule

module CLIO_DSP_FIFO (
	input	        CLK,
	input         EN,
	input         RST,
	
	input	 [15:0] DATA,
	input	        WRREQ,
	input	        RDREQ,
	output [15:0] Q,
	
	output [ 3:0] COUNT
);

	bit  [ 2: 0] RADDR;
	bit  [ 2: 0] WADDR;
	bit  [ 3: 0] AMOUNT;
	
	always @(posedge CLK) begin
		if (RST) begin
			AMOUNT <= '0;
			RADDR <= '0;
			WADDR <= '0;
		end
		else if (EN) begin
			if (WRREQ && !AMOUNT[3]) begin
				WADDR <= WADDR + 3'd1;
			end
			if (RDREQ && AMOUNT) begin
				RADDR <= RADDR + 3'd1;
			end

			//Count what was actually written and popped: a read of an empty FIFO pops nothing and a
			//write to a full one is dropped, so a write and a read in the same cycle change the count
			//when the FIFO is empty or full (it used to stay the same, one off from the pointers)
			if ((WRREQ && !AMOUNT[3]) && !(RDREQ && AMOUNT)) begin
				AMOUNT <= AMOUNT + 4'd1;
			end else if (!(WRREQ && !AMOUNT[3]) && (RDREQ && AMOUNT)) begin
				AMOUNT <= AMOUNT - 4'd1;
			end
		end
	end
	assign COUNT = AMOUNT;

`ifdef SIM

	reg [15:0]  MEM[8];
	initial begin
		MEM <= '{8{'0}};
	end
	
	always @(posedge CLK) begin
		if (EN) begin
			if (WRREQ) begin
				MEM[WADDR] <= DATA;
			end
		end
	end

	assign Q = MEM[RADDR];
											  	
`else 
	
	wire [15: 0] sub_wire0;
	altdpram	altdpram_component (
				.data (DATA),
				.inclock (CLK),
				.rdaddress (RADDR),
				.wraddress (WADDR),
				.wren (WRREQ && EN),
				.q (sub_wire0),
				.aclr (1'b0),
				.byteena (1'b1),
				.inclocken (1'b1),
				.rdaddressstall (1'b0),
				.rden (1'b1),
//				.sclr (1'b0),
				.wraddressstall (1'b0));
	defparam
		altdpram_component.indata_aclr = "OFF",
		altdpram_component.indata_reg = "INCLOCK",
		altdpram_component.intended_device_family = "Cyclone V",
		altdpram_component.lpm_type = "altdpram",
		altdpram_component.outdata_aclr = "OFF",
		altdpram_component.outdata_reg = "UNREGISTERED",
		altdpram_component.ram_block_type = "MLAB",
		altdpram_component.rdaddress_aclr = "OFF",
		altdpram_component.rdaddress_reg = "UNREGISTERED",
		altdpram_component.rdcontrol_aclr = "OFF",
		altdpram_component.rdcontrol_reg = "UNREGISTERED",
		altdpram_component.read_during_write_mode_mixed_ports = "CONSTRAINED_DONT_CARE",
		altdpram_component.width = 16,
		altdpram_component.widthad = 3,
		altdpram_component.width_byteena = 1,
		altdpram_component.wraddress_aclr = "OFF",
		altdpram_component.wraddress_reg = "INCLOCK",
		altdpram_component.wrcontrol_aclr = "OFF",
		altdpram_component.wrcontrol_reg = "INCLOCK";
		
	assign Q = RADDR == WADDR && WRREQ ? DATA : sub_wire0;

`endif

endmodule

module CLIO_COL_TBL (
	input             CLK,
	input             EN,
	
	input     [ 6: 0] WADDR,
	input     [ 7: 0] DIN,
	input             WE,
	
	input     [ 6: 0] RADDR,
	output    [ 7: 0] DOUT
);
	
// synopsys translate_off
`define SIM
// synopsys translate_on
	
`ifdef SIM

	reg [7:0] BUF[128];
	initial begin
		BUF = '{128{'0}};
	end
	
	always @(posedge CLK) begin
		if (EN) begin
			if (WE) begin
				BUF[WADDR] <= DIN;
			end
		end
	end

	assign DOUT = BUF[RADDR];
											  	
`else 

	wire [ 7: 0] sub_wire0;

	altdpram	altdpram_component (
				.data (DIN),
				.inclock (CLK),
				.rdaddress (RADDR),
				.wraddress (WADDR),
				.wren (WE),
				.q (sub_wire0),
				.aclr (1'b0),
				.byteena (1'b1),
				.inclocken (1'b1),
				.rdaddressstall (1'b0),
				.rden (1'b1),
//				.sclr (1'b0),
				.wraddressstall (1'b0));
	defparam
		altdpram_component.indata_aclr = "OFF",
		altdpram_component.indata_reg = "INCLOCK",
		altdpram_component.intended_device_family = "Cyclone V",
		altdpram_component.lpm_type = "altdpram",
		altdpram_component.outdata_aclr = "OFF",
		altdpram_component.outdata_reg = "UNREGISTERED",
		altdpram_component.ram_block_type = "MLAB",
		altdpram_component.rdaddress_aclr = "OFF",
		altdpram_component.rdaddress_reg = "UNREGISTERED",
		altdpram_component.rdcontrol_aclr = "OFF",
		altdpram_component.rdcontrol_reg = "UNREGISTERED",
		altdpram_component.read_during_write_mode_mixed_ports = "CONSTRAINED_DONT_CARE",
		altdpram_component.width = 8,
		altdpram_component.widthad = 7,
		altdpram_component.width_byteena = 1,
		altdpram_component.wraddress_aclr = "OFF",
		altdpram_component.wraddress_reg = "INCLOCK",
		altdpram_component.wrcontrol_aclr = "OFF",
		altdpram_component.wrcontrol_reg = "INCLOCK";
		
	assign DOUT = sub_wire0;
	
`endif

endmodule

module CLIO_DSP_IRAM (
	input             CLK,
	input             EN,
	
	input     [ 7: 0] WA,
	input     [15: 0] WD,
	input             WE,
	
	input     [ 7: 0] RA,
	output    [15: 0] RD
);

`ifdef SIM

	reg [15:0]  MEM[256];
	initial begin
		MEM <= '{256{'0}};
	end
	
	always @(posedge CLK) begin
		if (EN) begin
			if (WE) begin
				MEM[WA] <= WD;
			end
		end
	end

	assign RD = MEM[RA];
											  	
`else 

	wire [15: 0] sub_wire0;

	altdpram	altdpram_component (
				.data (WD),
				.inclock (CLK),
				.rdaddress (RA),
				.wraddress (WA),
				.wren (WE && EN),
				.q (sub_wire0),
				.aclr (1'b0),
				.byteena (1'b1),
				.inclocken (1'b1),
				.rdaddressstall (1'b0),
				.rden (1'b1),
//				.sclr (1'b0),
				.wraddressstall (1'b0));
	defparam
		altdpram_component.indata_aclr = "OFF",
		altdpram_component.indata_reg = "INCLOCK",
		altdpram_component.intended_device_family = "Cyclone V",
		altdpram_component.lpm_type = "altdpram",
		altdpram_component.outdata_aclr = "OFF",
		altdpram_component.outdata_reg = "UNREGISTERED",
		altdpram_component.ram_block_type = "MLAB",
		altdpram_component.rdaddress_aclr = "OFF",
		altdpram_component.rdaddress_reg = "UNREGISTERED",
		altdpram_component.rdcontrol_aclr = "OFF",
		altdpram_component.rdcontrol_reg = "UNREGISTERED",
		altdpram_component.read_during_write_mode_mixed_ports = "CONSTRAINED_DONT_CARE",
		altdpram_component.width = 16,
		altdpram_component.widthad = 8,
		altdpram_component.width_byteena = 1,
		altdpram_component.wraddress_aclr = "OFF",
		altdpram_component.wraddress_reg = "INCLOCK",
		altdpram_component.wrcontrol_aclr = "OFF",
		altdpram_component.wrcontrol_reg = "INCLOCK";
		
	assign RD = sub_wire0;

`endif

endmodule
