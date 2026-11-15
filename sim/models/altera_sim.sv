// Simulation models of the Altera megafunctions used by the
// 3DO core modules that the module testbenches compile (Verilator has
// no Altera library). altdpram is from the 3DO_GameBub port (rtl/compat).
//
// Only the configurations that the 3DO RTL actually uses are supported:
//   altdpram : registered write (INCLOCK), unregistered (asynchronous) read.
//              This maps 1:1 onto Xilinx distributed RAM (RAM32M/RAM64M...).
//
// Copyright (c) 2026 Adam Polkosnik
// SPDX-License-Identifier: GPL-3.0-or-later

`default_nettype none

module altdpram #(
	parameter integer width                 = 1,
	parameter integer widthad               = 1,
	parameter integer numwords              = 0,
	parameter integer width_byteena         = 1,
	parameter integer byte_size             = 8,
	// The following parameters are accepted for source compatibility only.
	parameter         indata_aclr           = "OFF",
	parameter         indata_reg            = "INCLOCK",
	parameter         intended_device_family = "Cyclone V",
	parameter         lpm_type              = "altdpram",
	parameter         lpm_hint              = "UNUSED",
	parameter         outdata_aclr          = "OFF",
	parameter         outdata_reg           = "UNREGISTERED",
	parameter         ram_block_type        = "MLAB",
	parameter         rdaddress_aclr        = "OFF",
	parameter         rdaddress_reg         = "UNREGISTERED",
	parameter         rdcontrol_aclr        = "OFF",
	parameter         rdcontrol_reg         = "UNREGISTERED",
	parameter         read_during_write_mode_mixed_ports = "CONSTRAINED_DONT_CARE",
	parameter         wraddress_aclr        = "OFF",
	parameter         wraddress_reg         = "INCLOCK",
	parameter         wrcontrol_aclr        = "OFF",
	parameter         wrcontrol_reg         = "INCLOCK",
	parameter         use_eab               = "ON",
	parameter         power_up_uninitialized = "FALSE"
) (
	input  wire [width-1:0]         data,
	input  wire                     inclock,
	input  wire                     outclock,
	input  wire [widthad-1:0]       rdaddress,
	input  wire [widthad-1:0]       wraddress,
	input  wire                     wren,
	output wire [width-1:0]         q,
	input  wire                     aclr,
	input  wire [width_byteena-1:0] byteena,
	input  wire                     inclocken,
	input  wire                     outclocken,
	input  wire                     rdaddressstall,
	input  wire                     rden,
	input  wire                     wraddressstall
);
	localparam integer DEPTH     = (numwords != 0) ? numwords : (1 << widthad);
	localparam integer LANE_BITS = width / width_byteena;

	(* ram_style = "distributed" *) reg [width-1:0] mem [0:DEPTH-1];

	integer i;
	initial begin
		for (i = 0; i < DEPTH; i = i + 1) mem[i] = {width{1'b0}};
	end

	// inclocken is tied high by every 3DO instance; it is still honoured.
	genvar b;
	generate
		for (b = 0; b < width_byteena; b = b + 1) begin : g_lane
			always @(posedge inclock) begin
				if (wren && inclocken && byteena[b])
					mem[wraddress][b*LANE_BITS +: LANE_BITS] <= data[b*LANE_BITS +: LANE_BITS];
			end
		end
	endgenerate

	assign q = mem[rdaddress];
endmodule

// lpm_divide, combinational, as MADAM's matrix engine uses it: signed
// numerator and denominator, LPM_REMAINDERPOSITIVE=TRUE:
//   numer = quotient * denom + remain, 0 <= remain < |denom|
module lpm_divide #(
	parameter integer lpm_widthn = 64,
	parameter integer lpm_widthd = 32,
	parameter         lpm_nrepresentation = "SIGNED",
	parameter         lpm_drepresentation = "SIGNED",
	parameter         lpm_hint = "LPM_REMAINDERPOSITIVE=TRUE",
	parameter         lpm_type = "LPM_DIVIDE",
	parameter integer lpm_pipeline = 0
) (
	input  wire [lpm_widthn-1:0] numer,
	input  wire [lpm_widthd-1:0] denom,
	output reg  [lpm_widthn-1:0] quotient,
	output reg  [lpm_widthd-1:0] remain,
	input  wire                  aclr,
	input  wire                  clken,
	input  wire                  clock
);
	always_comb begin
		logic signed [lpm_widthn-1:0] n, d, q, r;
		n = $signed(numer);
		d = lpm_widthn'($signed(denom));
		if (d == 0) begin
			q = n[lpm_widthn-1] ? 1 : '1;
			r = n;
		end else begin
			q = n / d;
			r = n % d;
			if (r < 0) begin
				if (d > 0) begin r = r + d; q = q - 1; end
				else       begin r = r - d; q = q + 1; end
			end
		end
		quotient = q;
		remain = r[lpm_widthd-1:0];
	end
endmodule

// altsyncram as the core uses it: BIDIR_DUAL_PORT or DUAL_PORT, registered
// addresses, unregistered outputs, port B as wide as port A or a power of
// two times wider (word i of port A in a port B word at bits [i*width_a +:
// width_a], the Altera mixed-width order), byte enables on port A, a read
// of a word written in the same clock on the same port gives the new data.
module altsyncram #(
	parameter         operation_mode = "BIDIR_DUAL_PORT",
	parameter integer width_a = 1,
	parameter integer widthad_a = 1,
	parameter integer numwords_a = 0,
	parameter integer width_b = 1,
	parameter integer widthad_b = 1,
	parameter integer numwords_b = 0,
	parameter integer width_byteena_a = 1,
	parameter integer width_byteena_b = 1,
	parameter integer byte_size = 8,
	parameter         address_reg_b = "CLOCK1",
	parameter         address_aclr_a = "NONE",
	parameter         address_aclr_b = "NONE",
	parameter         indata_reg_b = "CLOCK1",
	parameter         wrcontrol_wraddress_reg_b = "CLOCK1",
	parameter         outdata_reg_a = "UNREGISTERED",
	parameter         outdata_reg_b = "UNREGISTERED",
	parameter         outdata_aclr_a = "NONE",
	parameter         outdata_aclr_b = "NONE",
	parameter         clock_enable_input_a = "BYPASS",
	parameter         clock_enable_input_b = "BYPASS",
	parameter         clock_enable_output_a = "BYPASS",
	parameter         clock_enable_output_b = "BYPASS",
	parameter         read_during_write_mode_port_a = "NEW_DATA_NO_NBE_READ",
	parameter         read_during_write_mode_port_b = "NEW_DATA_NO_NBE_READ",
	parameter         read_during_write_mode_mixed_ports = "DONT_CARE",
	parameter         power_up_uninitialized = "FALSE",
	parameter         intended_device_family = "Cyclone V",
	parameter         lpm_type = "altsyncram",
	parameter         lpm_hint = "UNUSED",
	parameter         ram_block_type = "AUTO",
	parameter         init_file = ""
) (
	input  wire [widthad_a-1:0]       address_a,
	input  wire [widthad_b-1:0]       address_b,
	input  wire                       clock0,
	input  wire                       clock1,
	input  wire [width_a-1:0]         data_a,
	input  wire [width_b-1:0]         data_b,
	input  wire                       wren_a,
	input  wire                       wren_b,
	output wire [width_a-1:0]         q_a,
	output wire [width_b-1:0]         q_b,
	input  wire                       aclr0,
	input  wire                       aclr1,
	input  wire                       addressstall_a,
	input  wire                       addressstall_b,
	input  wire [width_byteena_a-1:0] byteena_a,
	input  wire [width_byteena_b-1:0] byteena_b,
	input  wire                       clocken0,
	input  wire                       clocken1,
	input  wire                       clocken2,
	input  wire                       clocken3,
	output wire [2:0]                 eccstatus,
	input  wire                       rden_a,
	input  wire                       rden_b
);
	localparam integer RATIO = width_b / width_a;
	localparam integer DEPTH = 1 << widthad_a;
	localparam integer LANE  = width_a / width_byteena_a;
	localparam integer SH    = widthad_a - widthad_b;

	reg [width_a-1:0] mem [0:DEPTH-1];
	reg [widthad_a-1:0] ra;
	reg [widthad_b-1:0] rb;

	integer k;
	initial begin
		for (k = 0; k < DEPTH; k = k + 1) mem[k] = {width_a{1'b0}};
		if (RATIO * width_a != width_b || (1 << SH) != RATIO) begin
			$display("altsyncram model: unsupported widths %0d / %0d", width_a, width_b);
			$fatal;
		end
	end

	always @(posedge clock0) begin
		if (wren_a)
			for (int b = 0; b < width_byteena_a; b++)
				if (byteena_a[b]) mem[address_a][b*LANE +: LANE] <= data_a[b*LANE +: LANE];
		ra <= address_a;
	end
	assign q_a = mem[ra];

	wire clkb = (address_reg_b == "CLOCK0") ? clock0 : clock1;
	always @(posedge clkb) begin
		if (wren_b && operation_mode == "BIDIR_DUAL_PORT")
			for (int i = 0; i < RATIO; i++)
				mem[widthad_a'({address_b, {SH{1'b0}}}) + widthad_a'(i)] <= data_b[i*width_a +: width_a];
		rb <= address_b;
	end
	genvar g;
	generate
		for (g = 0; g < RATIO; g = g + 1) begin : g_qb
			assign q_b[g*width_a +: width_a] = mem[widthad_a'({rb, {SH{1'b0}}}) + widthad_a'(g)];
		end
	endgenerate
	assign eccstatus = 3'b000;
endmodule

`default_nettype wire
