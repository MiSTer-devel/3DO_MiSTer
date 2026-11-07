//============================================================================
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//============================================================================

module emu
(
	//Master input clock
	input         CLK_50M,

	//Async reset from top-level module.
	//Can be used as initial reset.
	input         RESET,

	//Must be passed to hps_io module
	inout  [45:0] HPS_BUS,

	//Base video clock. Usually equals to CLK_SYS.
	output        CLK_VIDEO,

	//Multiple resolutions are supported using different CE_PIXEL rates.
	//Must be based on CLK_VIDEO
	output        CE_PIXEL,

	//Video aspect ratio for HDMI. Most retro systems have ratio 4:3.
	//if VIDEO_ARX[12] or VIDEO_ARY[12] is set then [11:0] contains scaled size instead of aspect ratio.
	output [12:0] VIDEO_ARX,
	output [12:0] VIDEO_ARY,

	output  [7:0] VGA_R,
	output  [7:0] VGA_G,
	output  [7:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_DE,    // = ~(VBlank | HBlank)
	output        VGA_F1,
	output [1:0]  VGA_SL,
	output        VGA_SCALER, // Force VGA scaler
	output        VGA_DISABLE, // analog out is off

	input  [11:0] HDMI_WIDTH,
	input  [11:0] HDMI_HEIGHT,
	output        HDMI_FREEZE,
	output        HDMI_BLACKOUT,
	output        HDMI_BOB_DEINT,

	input   [5:0] LFB_FMT,
	input  [31:0] LFB_BASE,
	input  [11:0] LFB_WIDTH,
	input  [11:0] LFB_HEIGHT,
	input  [13:0] LFB_STRIDE,

`ifdef MISTER_FB
	// Use framebuffer in DDRAM (USE_FB=1 in qsf)
	// FB_FORMAT:
	//    [2:0] : 011=8bpp(palette) 100=16bpp 101=24bpp 110=32bpp
	//    [3]   : 0=16bits 565 1=16bits 1555
	//    [4]   : 0=RGB  1=BGR (for 16/24/32 modes)
	//
	// FB_STRIDE either 0 (rounded to 256 bytes) or multiple of pixel size (in bytes)
	output        FB_EN,
	output  [4:0] FB_FORMAT,
	output [11:0] FB_WIDTH,
	output [11:0] FB_HEIGHT,
	output [31:0] FB_BASE,
	output [13:0] FB_STRIDE,
	input         FB_VBL,
	input         FB_LL,
	output        FB_FORCE_BLANK,

`ifdef MISTER_FB_PALETTE
	// Palette control for 8bit modes.
	// Ignored for other video modes.
	output        FB_PAL_CLK,
	output  [7:0] FB_PAL_ADDR,
	output [23:0] FB_PAL_DOUT,
	input  [23:0] FB_PAL_DIN,
	output        FB_PAL_WR,
`endif
`endif

	output        LED_USER,  // 1 - ON, 0 - OFF.

	// b[1]: 0 - LED status is system status OR'd with b[0]
	//       1 - LED status is controled solely by b[0]
	// hint: supply 2'b00 to let the system control the LED.
	output  [1:0] LED_POWER,
	output  [1:0] LED_DISK,

	// I/O board button press simulation (active high)
	// b[1]: user button
	// b[0]: osd button
	output  [1:0] BUTTONS,

	input         CLK_AUDIO, // 24.576 MHz
	output [15:0] AUDIO_L,
	output [15:0] AUDIO_R,
	output        AUDIO_S,   // 1 - signed audio samples, 0 - unsigned
	output  [1:0] AUDIO_MIX, // 0 - no mix, 1 - 25%, 2 - 50%, 3 - 100% (mono)

	//ADC
	inout   [3:0] ADC_BUS,

	//SD-SPI
	output        SD_SCK,
	output        SD_MOSI,
	input         SD_MISO,
	output        SD_CS,
	input         SD_CD,

	//High latency DDR3 RAM interface
	//Use for non-critical time purposes
	output        DDRAM_CLK,
	input         DDRAM_BUSY,
	output  [7:0] DDRAM_BURSTCNT,
	output [28:0] DDRAM_ADDR,
	input  [63:0] DDRAM_DOUT,
	input         DDRAM_DOUT_READY,
	output        DDRAM_RD,
	output [63:0] DDRAM_DIN,
	output  [7:0] DDRAM_BE,
	output        DDRAM_WE,

	//SDRAM interface with lower latency
	output        SDRAM_CLK,
	output        SDRAM_CKE,
	output [12:0] SDRAM_A,
	output  [1:0] SDRAM_BA,
	inout  [15:0] SDRAM_DQ,
	output        SDRAM_DQML,
	output        SDRAM_DQMH,
	output        SDRAM_nCS,
	output        SDRAM_nCAS,
	output        SDRAM_nRAS,
	output        SDRAM_nWE,

`ifdef MISTER_DUAL_SDRAM
	//Secondary SDRAM
	//Set all output SDRAM_* signals to Z ASAP if SDRAM2_EN is 0
	input         SDRAM2_EN,
	output        SDRAM2_CLK,
	output [12:0] SDRAM2_A,
	output  [1:0] SDRAM2_BA,
	inout  [15:0] SDRAM2_DQ,
	output        SDRAM2_nCS,
	output        SDRAM2_nCAS,
	output        SDRAM2_nRAS,
	output        SDRAM2_nWE,
`endif

	input         UART_CTS,
	output        UART_RTS,
	input         UART_RXD,
	output        UART_TXD,
	output        UART_DTR,
	input         UART_DSR,

	// Open-drain User port.
	// 0 - D+/RX
	// 1 - D-/TX
	// 2..6 - USR2..USR6
	// Set USER_OUT to 1 to read from USER_IN.
	input   [6:0] USER_IN,
	output  [6:0] USER_OUT,

	input         OSD_STATUS
);

	assign ADC_BUS  = 'Z;
	assign {UART_RTS, UART_TXD, UART_DTR} = 0;
	assign BUTTONS   = {1'b0,osd_btn};
	assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
	assign USER_OUT = '0;
	
	assign AUDIO_S = 1;
	assign AUDIO_MIX = 0;
	assign HDMI_FREEZE = 0;
	assign HDMI_BLACKOUT = 0;
	assign HDMI_BOB_DEINT = 0;
	
	assign LED_DISK  = 0;
	assign LED_POWER = 0;
	assign LED_USER  = bios_download;
	assign VGA_SCALER= 0;
	assign VGA_DISABLE = 0;
	
//	assign {SDRAM2_DQ, SDRAM2_CLK,SDRAM2_A,SDRAM2_BA,SDRAM2_nCS,SDRAM2_nCAS,SDRAM2_nRAS,SDRAM2_nWE} = 'Z;
	
	///////////////////////  CLOCK/RESET  ///////////////////////////////////
	wire clk_sys, clk_mem, locked;

	pll pll
	(
		.refclk(CLK_50M),
		.rst(0),
		.outclk_0(clk_sys),
		.outclk_1(clk_mem),
		.outclk_2(),
		.locked(locked)
	);

	wire clk_vid;
	pll2 pll2
	(
		.refclk(CLK_50M),
		.rst(0),
		.outclk_0(clk_vid),
		.reconfig_to_pll(reconfig_to_pll),
		.reconfig_from_pll(reconfig_from_pll), 
		.locked()
	);
	
	wire [63:0] reconfig_to_pll;
	wire [63:0] reconfig_from_pll;
	wire        cfg_waitrequest;
	reg         cfg_write;
	reg   [5:0] cfg_address;
	reg  [31:0] cfg_data;
	
	pll_cfg pll_cfg
	(
		.mgmt_clk(CLK_50M),
		.mgmt_reset(0),
		.mgmt_waitrequest(cfg_waitrequest),
		.mgmt_read(0),
		.mgmt_readdata(),
		.mgmt_write(cfg_write),
		.mgmt_address(cfg_address),
		.mgmt_writedata(cfg_data),
		.reconfig_to_pll(reconfig_to_pll),
		.reconfig_from_pll(reconfig_from_pll)
	);

	always @(posedge CLK_50M) begin
		reg pald = 0, pald2 = 0;
		reg resd = 0, resd2 = 0;
		reg [2:0] state = 0;

		pald  <= 0;//PAL;
		pald2 <= pald;
		
		resd  <= reset;
		resd2 <= resd;
	
		if (pald2 != pald || (resd && !resd2)) state <= 1;
	
		cfg_write <= 0;
		if (!cfg_waitrequest) begin
			if (state) state <= state + 1'd1;
			case (state)
				1: begin
						cfg_address <= 0;
						cfg_data <= 0;
						cfg_write <= 1;
					end
				3: begin
						cfg_address <= 5;
						cfg_data <= !pald2 ? 32'h00020504 : 32'h00020403;
						cfg_write <= 1;
					end
				5: begin
						cfg_address <= 7;
						cfg_data <= !pald2 ? 32'hD61AA39A : 32'h428F5C29;
						cfg_write <= 1;
					end
				7: begin
						cfg_address <= 2;
						cfg_data <= 0;
						cfg_write <= 1;
					end
			endcase
		end
	end 

	
	///////////////////////////////////////////////////
	
	// Status Bit Map:
	//             Upper                             Lower              
	// 0         1         2         3          4         5         6   
	// 01234567890123456789012345678901 23456789012345678901234567890123
	// 0123456789ABCDEFGHIJKLMNOPQRSTUV 0123456789ABCDEFGHIJKLMNOPQRSTUV
	// X     XXXX  XXXXXXXX             XXXXXXXX                        
	
	`include "build_id.v"
	localparam CONF_STR = {
		"3DO;;",
		"S0,CUEISO,Insert Disk;",
		"FS2,BIN,Load bios;",
		"-;",
		"OFG,Region,BIOS,NTSC,PAL;",

		"-;",
		"D0RC,Load Backup RAM;",
		"D0RD,Save Backup RAM;",
		"D0OE,Autosave,Off,On;",
		
		"-;",
		"P1,Audio & Video;",
		"P1O67,Scale,Normal,V-Integer,Narrower HV-Integer,Wider HV-Integer;",
		"P1O89,Vertical Crop,Disabled,216p(5x),224p;",
	
		"P2,Input;",
		"P2O[34:32],Pad,1,2,3,4,Off;",
		"D1P2O[35],Flightstick,Off,On;",
		"D2P2O[36],Mouse,Off,On;",
		"P2O[38:37],Arcade control,Off,Trackball;",/*,LightGun*/
		"P2O[39],Arcade service,Off,On;",
		"P2-;",

		"P3,Hardware;",
		"P3OJ,Video mode,240p,480i(original);",

		"P4,Debug;",
		"P4OH,H Interpolation,Off,On;",
		"P4OI,V Interpolation,Off,On;",
		
		"-;",
		"R0,Reset;",
		"J1,A,B,C,P,X,R,L,T/Start,Coin;",
		"jn,A,B,X,Start,Select,R,L,L2,R2;",
		"jp,A,B,X,Start,Select,R,L,L2,R2;",
		"V,v",`BUILD_DATE
	};

	wire [63:0] status;
	wire [15:0] status_menumask = {13'd0,mouse_mask,stick_mask,~bk_ena};
	
	wire  [1:0] buttons;
	wire [15:0] joystick_0,joystick_1,joystick_2,joystick_3,joystick_4;
	wire  [7:0] joy0_x0,joy0_y0,joy0_x1,joy0_y1,joy1_x0,joy1_y0,joy1_x1,joy1_y1;
	wire        ioctl_download;
	wire        ioctl_wr;
	wire [24:0] ioctl_addr;
	wire [15:0] ioctl_data;
	wire  [7:0] ioctl_index;
	reg         ioctl_wait = 0;
	
	reg  [31:0] sd_lba = '0;
	reg         sd_rd = 0;
	reg         sd_wr = 0;
	wire        sd_ack;
	wire  [7:0] sd_buff_addr;
	wire [15:0] sd_buff_dout;
	wire [15:0] sd_buff_din;
	wire        sd_buff_wr;
	wire        img_mounted;
	wire        img_readonly;
	wire [63:0] img_size;
	
	wire        forced_scandoubler;
	wire [10:0] ps2_key;
	wire [24:0] ps2_mouse;
	
	wire [35:0] EXT_BUS;
	
	wire [21:0] gamma_bus;
	wire [15:0] sdram_sz;
	
	hps_io #(.CONF_STR(CONF_STR), .WIDE(1)) hps_io
	(
		.clk_sys(clk_sys),
		.HPS_BUS(HPS_BUS),
	
		.joystick_0(joystick_0),
		.joystick_1(joystick_1),
		.joystick_2(joystick_2),
		.joystick_3(joystick_3),
		.joystick_4(joystick_4),
		.joystick_l_analog_0({joy0_y0, joy0_x0}),
		.joystick_l_analog_1({joy1_y0, joy1_x0}),
		.joystick_r_analog_0({joy0_y1, joy0_x1}),
		.joystick_r_analog_1({joy1_y1, joy1_x1}),
	
		.buttons(buttons),
		.forced_scandoubler(forced_scandoubler),
		.new_vmode(new_vmode),
	
		.status(status),
		.status_in(status),
		.status_set(0),
		.status_menumask(status_menumask),
	
		.ioctl_download(ioctl_download),
		.ioctl_index(ioctl_index),
		.ioctl_wr(ioctl_wr),
		.ioctl_addr(ioctl_addr),
		.ioctl_dout(ioctl_data),
		.ioctl_wait(ioctl_wait),
	
		.sd_lba('{sd_lba}),
		.sd_rd(sd_rd),
		.sd_wr(sd_wr),
		.sd_ack(sd_ack),
		.sd_buff_addr(sd_buff_addr),
		.sd_buff_dout(sd_buff_dout),
		.sd_buff_din('{sd_buff_din}),
		.sd_buff_wr(sd_buff_wr),
		.img_mounted(img_mounted),
		.img_readonly(img_readonly),
		.img_size(img_size),
	
		.gamma_bus(gamma_bus),
		.sdram_sz(sdram_sz),
	
		.ps2_key(ps2_key),
		.ps2_mouse(ps2_mouse),
	
		.EXT_BUS(EXT_BUS)
	);
	
	wire bios_download = ioctl_download & (ioctl_index[5:2] == 4'b0000 && ioctl_index[1:0] != 2'h3);
	wire kanji_download = ioctl_download & (ioctl_index[5:2] == 4'b0000 && ioctl_index[1:0] == 2'h3);
	wire cdd_data_download = ioctl_download & (ioctl_index[5:2] == 4'b0010);
	wire cdd_info_download = ioctl_download & (ioctl_index[5:2] == 4'b0011);
	wire save_download = ioctl_download & (ioctl_index[5:2] == 4'b0001);
	
	reg osd_btn = 0;
//	always @(posedge clk_sys) begin
//		integer timeout = 0;
//		reg     has_bootrom = 0;
//		reg     last_rst = 0;
//	
//		if (RESET) last_rst = 0;
//		if (status[0]) last_rst = 1;
//	
//		if (bios_download & ioctl_wr & status[0]) has_bootrom <= 1;
//	
//		if(last_rst & ~status[0]) begin
//			osd_btn <= 0;
//			if(timeout < 24000000) begin
//				timeout <= timeout + 1;
//				osd_btn <= ~has_bootrom;
//			end
//		end
//	end
	
	reg reset = 1, mem_rst = 1;
	always @(posedge clk_sys) begin
		reg        reset_cond,reset_cond_old;
		reg [12:0] reset_delay = '0;
		
		reset_cond = RESET | status[0] | buttons[1];
		reset_cond_old <= reset_cond;
		if (reset_cond && !reset_cond_old) reset_delay <= '1;
		else if (reset_delay) reset_delay <= reset_delay - 13'd1;
		
		reset   <= reset_cond | |reset_delay | bios_download | kanji_download;
		mem_rst <= reset_cond | |reset_delay;
	end	
	

`ifdef DEBUG
`define USE_BRAM_BLOCKS_FOR_VRAM 0
`else
`define USE_BRAM_BLOCKS_FOR_VRAM 1
`endif

	reg          PAL = 0;
	always @(posedge clk_sys) begin
		reg  [31: 0] cs;
		reg bios_download_old;
		reg bios_pal = 0;
	
		bios_download_old <= bios_download;
		
		if (bios_download && !bios_download_old) begin
			cs <= '0;
		end 
		
		if (bios_download && ioctl_wr) begin
			cs <= cs + {16'h0000,ioctl_data};
		end
		if (!bios_download && bios_download_old) begin
			bios_pal <= (cs == 32'hD63EC5E9 || //Panasonic FZ-1 (E)
			             cs == 32'hD5CFD1C5);  //Panasonic FZ-1 (E) (unencrypted)
		end 
		
		case (status[16:15])
			2'h0: PAL <= bios_pal;
			2'h1: PAL <= 0;
			default: PAL <= 1;
		endcase
	end
	
	reg new_vmode;
	always @(posedge clk_sys) begin
		reg old_pal;
		int to;
		
		if(!reset) begin
			old_pal <= PAL;
			if(old_pal != PAL) to <= 5000000;
		end
		else to <= 5000000;
		
		if(to) begin
			to <= to - 1;
			if(to == 1) new_vmode <= ~new_vmode;
		end
	end

	/*Frambuffer position in games:
	3D Atlas (US): 0x2CC000
	Alone in the Dark (US): 0x248800
	Blade Force (US): 0x200000/0x225800/0x24B000
	Cannon Fodder (US): 0x2AE800/0x2D2800
	Casper (US): 0x200000/0x225800/0x24B000
	DeathKeep (US): 0x250000/0x278000 (FMV only)
	FIFA International Soccer (US, Korea): 0x2AC000/0x2D2000
	Gex (US, EU): 0x25C800/0x282000/0x2A7800/0x2CD000 (FMV only)
	Psychic Detective (US) (Disc 1): 0x28B800/0x2B1000
	Quarantine (US): 0x274BA4
	Road & Track Presents - The Need for Speed (US, EU): 0x2AD000/0x2D3000
	Seal of the Pharaoh (US): 0x270800/0x296000
	Bodyconscious Digital Rave! Part 1 - Shinjuku & Takasaki (Japan): 0x24B000
	Live! 3DO Magazine CD-ROM 1 (Japan): 0x280000/0x2A5800
	Pretty Soldier SailorMoon S (Japan): 0x24C000 (FMV only)
	Most others: 0x200000/0x225800
	*/
	
	//FPGA has enough BRAM to replace 0x70000 bytes (out of 0x100000 bytes) of VRAM.  
	//Of these, 0x6C000 bytes start at BRAM_OFFS*0x10000, while the remaining 0x4000 bytes always start at offset 0xFC000 (VDL). 
	reg  [ 3: 0] BRAM4_OFFS;//Block 0x40000
	reg  [ 3: 0] BRAM2_OFFS;//Block 0x20000
	reg  [ 3: 0] BRAM1_OFFS;//Block 0x10000
	reg          NEED_DSP_PAUSE;
	always @(posedge clk_sys) begin
		reg [31: 0] msf,id;
	
		if (cdd_info_download && ioctl_wr) begin
			if (ioctl_addr == 25'h004) begin
				msf[31:16] <= {ioctl_data[7:0],ioctl_data[15:8]};
			end 
			if (ioctl_addr == 25'h006) begin
				msf[15:0] <= {ioctl_data[7:0],ioctl_data[15:8]};
			end 
			
			if (ioctl_addr == 25'h458) begin
				id[31:16] <= {ioctl_data[7:0],ioctl_data[15:8]};
			end 
			if (ioctl_addr == 25'h45A) begin
				id[15:0] <= {ioctl_data[7:0],ioctl_data[15:8]};
			end 
			if (ioctl_addr == 25'h480) begin
				{BRAM4_OFFS,BRAM2_OFFS,BRAM1_OFFS} <= {4'h0,4'h4,4'h6};
				NEED_DSP_PAUSE <= 0;
				if (id == 32'h29E4D882) {BRAM4_OFFS,BRAM2_OFFS,BRAM1_OFFS} <= {4'hC,4'hA,4'h9};//3D Atlas (US)
				if (id == 32'h274E924C) {BRAM4_OFFS,BRAM2_OFFS,BRAM1_OFFS} <= {4'h4,4'h2,4'h8};//Alone in the Dark (US)
				if (id == 32'h0340842C) {BRAM4_OFFS,BRAM2_OFFS,BRAM1_OFFS} <= {4'hC,4'hA,4'h9};//Cannon Fodder (US)
				if (id == 32'h2D731C98) {BRAM4_OFFS,BRAM2_OFFS,BRAM1_OFFS} <= {4'hC,4'hA,4'h9};//FIFA International Soccer (US, Korea)
				if (id == 32'h2584F855) {BRAM4_OFFS,BRAM2_OFFS,BRAM1_OFFS} <= {4'h8,4'hC,4'hE};//Psychic Detective (US) (Disc 1)
				if (id == 32'h031BED09) {BRAM4_OFFS,BRAM2_OFFS,BRAM1_OFFS} <= {4'h8,4'h6,4'hC};//Quarantine (US)
				if (id == 32'h06DE0DC2) {BRAM4_OFFS,BRAM2_OFFS,BRAM1_OFFS} <= {4'hC,4'hA,4'h9};//Road & Track Presents - The Need for Speed (US, EU)
				if (id == 32'h2D95DCB6) {BRAM4_OFFS,BRAM2_OFFS,BRAM1_OFFS} <= {4'h8,4'h6,4'hC};//Seal of the Pharaoh (US)
				if (id == 32'h07732394) {BRAM4_OFFS,BRAM2_OFFS,BRAM1_OFFS} <= {4'h0,4'h6,4'h4};//Space Hulk - Vengeance of the Blood Angels (US)
				if (id == 32'h0387DF78) {BRAM4_OFFS,BRAM2_OFFS,BRAM1_OFFS} <= {4'h4,4'h8,4'hA};//Bodyconscious Digital Rave! Part 1 - Shinjuku & Takasaki (Japan)
				if (id == 32'h213128DD) {BRAM4_OFFS,BRAM2_OFFS,BRAM1_OFFS} <= {4'h8,4'hC,4'hE};//Live! 3DO Magazine CD-ROM 1 (Japan)
				
				if (id == 32'h25609184                       ) NEED_DSP_PAUSE <= 1;//Blade Force (US)
				if (id == 32'h043DCD69 && msf == 32'h69026900) NEED_DSP_PAUSE <= 1;//Decathlon (US) (Unl)
				if (id == 32'h0A9B739E                       ) NEED_DSP_PAUSE <= 1;//Killing Time (US) (RE1)
				if (id == 32'h06065D10                       ) NEED_DSP_PAUSE <= 1;//Snow Job Starring Tracy Scoggins (US)
				if (id == 32'h3AC732DE                       ) NEED_DSP_PAUSE <= 1;//BattleSport (USA) (Beta) (1995-09-22)
			end
		end
	end
	
	wire [23: 2] LA;
	wire         LRAS0_N;
	wire         LRAS2_N;
	wire         LRAS3_N;
	wire         LCAS_N;
	wire [ 1: 0] LWE_N;
	wire         LOE_N;
	wire         LDSF;
	wire         LSC;
	wire         LQSF;
	wire [ 3: 0] LCODE;
	wire [23: 2] RA;
	wire         RRAS0_N;
	wire         RRAS2_N;
	wire         RRAS3_N;
	wire         RCAS_N;
	wire [ 1: 0] RWE_N;
	wire         ROE_N;
	wire         RDSF;
	wire         RSC;
	wire         RQSF;
	wire [ 3: 0] RCODE;
	wire [31: 0] RAM_DI;
	wire [31: 0] RAM_DO;
	
	wire         PBDIN;
	wire         PBDOUT;
	wire         PBCLK;
	
	wire [19: 0] PA;
	wire [31: 0] PDI;
	wire [ 7: 0] PDO;
	wire         ROMCS_N;
	wire         SRAMW_N;
	wire         SRAMR_N;
	
	wire         ROM_SEL;
	
	wire [ 7: 0] CDDI;
	wire [ 7: 0] CDDO;
	wire         CDEN_N;
	wire         CDCMD_N;
	wire         CDHWR_N;
	wire         CDHRD_N;
	wire         CDRST_N;
	wire         CDSTEN_N;
	wire         CDDTEN_N;
	wire         CDMDCHG;
	wire [15: 0] CDCRC;
	
	wire [31: 0] VRAM_SQ;
	wire         P3DO_FIELD;
	
	wire [ 7: 0] R, G, B;
	wire         HS_N,VS_N;
	wire         DCLK;
	wire         HBL_N, VBL_N;
	
	wire         MCLK_CE;

	wire [31:0] in_clk = 50000000;
	
	bit CLK_DIV;
	always @(posedge clk_sys) 
		CLK_DIV <= ~CLK_DIV;
	wire CE_R =  CLK_DIV;
	wire CE_F = ~CLK_DIV;
		
	wire SYS_CE_R = CE_R;
	wire SYS_CE_F = CE_F;
	
	wire VCE;	//Video clock
	CEGen VCE_CEGen
	(
		.CLK(clk_sys),
		.RST_N(1),
		.IN_CLK(in_clk),
		.IN_CE(1),
		.OUT_CLK(/*!PAL ?*/ 24545400 /*: 29500000*/),
		.CE(VCE)
	);
	
	wire ACLK_CE;	//Audio clock
	CEGen AUD_CEGen
	(
		.CLK(clk_sys),
		.RST_N(1),
		.IN_CLK(in_clk),
		.IN_CE(1),
		.OUT_CLK(16934400),
		.CE(ACLK_CE)
	);
	
	reg POWER_ON;
	always @(posedge clk_sys) begin
		if (reset) POWER_ON <= 1;
		else if (CE_R) POWER_ON <= 0;
	end
	
	P3DO p3do
	(
		.RST_N(~reset),
		.CLK(clk_sys),
		.VCLK(clk_vid),
		.EN(1),
		.PAUSE(pause),
		.DSP_PAUSE(pause & NEED_DSP_PAUSE),
		
		.PAL(PAL),
		
		.CE_F(SYS_CE_F),
		.CE_R(SYS_CE_R),
		
		.PON(POWER_ON),
				
		.LA(LA),
		.LRAS0_N(LRAS0_N),
		.LRAS2_N(LRAS2_N),
		.LRAS3_N(LRAS3_N),
		.LCAS_N(LCAS_N),
		.LWE_N(LWE_N),
		.LOE_N(LOE_N),
		.LDSF(LDSF),
		.LSC(LSC),
		.LQSF(LQSF),
		.LCODE(LCODE),
		.RA(RA),
		.RRAS0_N(RRAS0_N),
		.RRAS2_N(RRAS2_N),
		.RRAS3_N(RRAS3_N),
		.RCAS_N(RCAS_N),
		.RWE_N(RWE_N),
		.ROE_N(ROE_N),
		.RDSF(RDSF),
		.RSC(RSC),
		.RQSF(RQSF),
		.RCODE(RCODE),
		.DI(RAM_DI),
		.DO(RAM_DO),
		
		.PBDIN(PBDIN),
		.PBDOUT(PBDOUT),
		.PBCLK(PBCLK),
			
		.PA(PA),
		.PDI(PDI),
		.PDO(PDO),
		.ROMCS_N(ROMCS_N),
		.SRAMW_N(SRAMW_N),
		.SRAMR_N(SRAMR_N),
		
		.ROM_SEL(ROM_SEL),
		
		.CDDI(CDDI),
		.CDDO(CDDO),
		.CDEN_N(CDEN_N),
		.CDCMD_N(CDCMD_N),
		.CDHWR_N(CDHWR_N),
		.CDHRD_N(CDHRD_N),
		.CDRST_N(CDRST_N),
		.CDSTEN_N(CDSTEN_N),
		.CDDTEN_N(CDDTEN_N),
		.CDMDCHG(CDMDCHG),
		
		.S(VRAM_SQ),
		
		.FIELD(P3DO_FIELD),
		
		.VCE(VCE),
		.RGB({R,G,B}),
		.HS_N(HS_N),
		.VS_N(VS_N),
		.HBLK_N(HBL_N),
		.VBLK_N(VBL_N),
		.DCLK(DCLK),
		
		.ACLK_CE(ACLK_CE),
		.AUDIOL(AUDIO_L),
		.AUDIOR(AUDIO_R),
		
		.MCLK_CE(MCLK_CE),
		
		.HINTREPOL_DISABLE(~status[17]),
		.VINTREPOL_DISABLE(~status[18]),
		.SCRN_EN(SCRN_EN[2:0]),
		.DBG_EXT(DBG_EXT)
	);
	
	P3DO_CDROM cdrom
	(
		.RST_N(~reset),
		.CLK(clk_sys),
		.EN(1),
		
		.CE(CE_R),
		
		.CDDI(CDDO),
		.CDDO(CDDI),
		.CDEN_N(CDEN_N),
		.CDCMD_N(CDCMD_N),
		.CDHWR_N(CDHWR_N),
		.CDHRD_N(CDHRD_N),
		.CDRST_N(CDRST_N),
		.CDSTEN_N(CDSTEN_N),
		.CDDTEN_N(CDDTEN_N),
		.CDMDCHG(CDMDCHG),
		
		.CDD_DATA(ioctl_data),
		.CDD_WR(ioctl_wr),
		.CDD_DTEN(cdd_data_download),
		.CDD_DIEN(cdd_info_download),
	
		.EXT_BUS(EXT_BUS),
		
		.TRAY_OPEN(1'b0)
	);
	
	
	wire [2:0] pad_sel = status[34:32] >= 3'd4 ? 3'd0 : status[34:32] + 3'd1;
	wire [1:0] arcade_sel = status[38:37];
	wire stick_mask = ~(pad_sel <= 3'd1 && !arcade_sel);
	wire mouse_mask = ~(pad_sel <= 3'd2 && !arcade_sel);
	
	HPS2PAD pad
	(
		.RST(reset),
		.CLK(clk_sys),
		
		.CE(CE_R),
		
		.PBDIN(PBDIN),
		.PBDOUT(PBDOUT),
		.PBCLK(PBCLK),
		
		.EXPBDIN(1'b1),
		.EXPBDOUT(),
	
		.PAD_SEL(pad_sel),
		.ARCADE_SEL(arcade_sel),
		.STICK_EN(status[35]&~stick_mask),
		.MOUSE_EN(status[36]&~mouse_mask),
		.ARCADE_SERVICE(status[39]),
	
		.joystick_0(joystick_0[12:0]),
		.joystick_1(joystick_1[12:0]),
		.joystick_2(joystick_2[12:0]),
		.joystick_3(joystick_3[12:0]),
		.joy0_x0(joy0_x0),
		.joy0_y0(joy0_y0),
		.joy0_x1(joy0_x1),
		.joy0_y1(joy0_y1),
		.joy1_x0(joy1_x0),
		.joy1_y0(joy1_y0),
		.joy1_x1(joy1_x1),
		.joy1_y1(joy1_y1),
		.ps2_mouse(ps2_mouse)
	);
	
	
	wire [31:0] sdr_dout;
	sdram sdram1
	(
		.SDRAM_CLK(SDRAM_CLK),
		.SDRAM_A(SDRAM_A),
		.SDRAM_BA(SDRAM_BA),
		.SDRAM_DQ(SDRAM_DQ),
		.SDRAM_DQML(SDRAM_DQML),
		.SDRAM_DQMH(SDRAM_DQMH),
		.SDRAM_nCS(SDRAM_nCS),
		.SDRAM_nWE(SDRAM_nWE),
		.SDRAM_nRAS(SDRAM_nRAS),
		.SDRAM_nCAS(SDRAM_nCAS),
		.SDRAM_CKE(SDRAM_CKE),
		
		.clk(clk_mem),
		.init(status[0]),
		.sync(MCLK_CE),
	
		.laddr({2'b00,~LRAS3_N,LA[19:2]}),
		.lwe  (~LWE_N),
		.lras(!LRAS2_N || !LRAS3_N),
		.lcode(LCODE),
		
		.raddr({2'b00,~RRAS3_N,RA[19:2]}),
		.rwe  (~RWE_N),
		.rras(!RRAS2_N || !RRAS3_N),
		.rcode(RCODE),
		
		.din  (RAM_DO),
		.dout(sdr_dout),
		
		.rfs(!LRAS0_N || !RRAS0_N )
	);
	

	bit  [31: 0] VRAM_Q;
	bit          VRAM_LRDY,VRAM_RRDY;
	bit  [31: 0] vram_bldata;
	
	P3DO_VRAM #(`USE_BRAM_BLOCKS_FOR_VRAM) vram_l
	(
		.CLK(clk_sys),
		.CLK_MEM(clk_mem),
		.RST_N(~reset),
		
		.A(LA[19:2]),
		.D(RAM_DO[31:16]),
		.Q(VRAM_Q[31:16]),
		.RAS_N(LRAS0_N),
		.CAS_N(LCAS_N),
		.WE_N(LWE_N),
		.OE_N(LOE_N),
		.DSF1(LDSF),
		
		.SC(LSC),
		.SE_N(0),
		.SQ(VRAM_SQ[31:16]),
		.QSF(LQSF),
		
		.RDY(VRAM_LRDY),
		
		.EQ(ddr_do[31:16]),
		.ESADDR(ddr_bladdr),
		.ESDATA(vram_bldata),
		.ESWR(ddr_blwr),
		.ESRD(ddr_blrd),
		.ESFW(ddr_bfw),
		.ESQ({ddr_bout[63:48],ddr_bout[31:16]}),
		.ESTE(ddr_blte),
		
		.BRAM4_OFFS(BRAM4_OFFS),
		.BRAM2_OFFS(BRAM2_OFFS),
		.BRAM1_OFFS(BRAM1_OFFS)
	);
	
	bit  [31: 0] vram_brdata;
	P3DO_VRAM #(`USE_BRAM_BLOCKS_FOR_VRAM) vram_r
	(
		.CLK(clk_sys),
		.CLK_MEM(clk_mem),
		.RST_N(~reset),
		
		.A(RA[19:2]),
		.D(RAM_DO[15:0]),
		.Q(VRAM_Q[15:0]),
		.RAS_N(RRAS0_N),
		.CAS_N(RCAS_N),
		.WE_N(RWE_N),
		.OE_N(ROE_N),
		.DSF1(RDSF),
		
		.SC(RSC),
		.SE_N(0),
		.SQ(VRAM_SQ[15:0]),
		.QSF(RQSF),
		
		.RDY(VRAM_RRDY),
		
		.EQ(ddr_do[15:0]),
		.ESADDR(ddr_braddr),
		.ESDATA(vram_brdata),
		.ESWR(ddr_brwr),
		.ESRD(ddr_brrd),
		.ESFW(),
		.ESQ({ddr_bout[47:32],ddr_bout[15:0]}),
		.ESTE(ddr_brte),
		
		.BRAM4_OFFS(BRAM4_OFFS),
		.BRAM2_OFFS(BRAM2_OFFS),
		.BRAM1_OFFS(BRAM1_OFFS)
	);
	
	assign RAM_DI = !LRAS0_N || !RRAS0_N ? VRAM_Q : sdr_dout;
	assign PDI = !SRAMR_N ? (ddr_io_do>>{~PA[3:2],3'b000}) & 32'h000000FF : ddr_io_do;

	
	//DDRAM
	wire [31: 0] ddr_io_do;
	wire         ddr_io_busy;
	reg          ioctl_wr_delayed;
	always @(posedge clk_sys) begin
		ioctl_wr_delayed <= ioctl_wr;
	end
	
	wire [15: 0] ddr_nvram_do;
	wire         ddr_nvram_busy;
	wire [15: 0] nvram_load_data;
	
	wire [31: 0] ddr_do;
	wire         ddr_busy;
	wire [17: 0] ddr_bladdr,ddr_braddr;
	wire         ddr_blwr,ddr_brwr;
	wire         ddr_blrd,ddr_brrd;
	wire         ddr_bfw;
	wire [63: 0] ddr_bin = {vram_bldata[31:16],vram_brdata[31:16],vram_bldata[15:0],vram_brdata[15:0]};
	wire [63: 0] ddr_bout;
	wire         ddr_blte,ddr_brte;
	wire         ddr_bbusy;
	
	wire         ddr_luse = ~((`USE_BRAM_BLOCKS_FOR_VRAM && LA[19:2] >= ({BRAM4_OFFS+0,16'h0000}>>2) && LA[19:2] <= ({BRAM4_OFFS+3,16'hFFFF}>>2)) || (`USE_BRAM_BLOCKS_FOR_VRAM && LA[19:2] >= ({BRAM2_OFFS+0,16'h0000}>>2) && LA[19:2] <= ({BRAM2_OFFS+1,16'hFFFF}>>2)) || (LA[19:2] >= ({BRAM1_OFFS+0,16'h0000}>>2) && LA[19:2] <= ({BRAM1_OFFS+0,16'hBFFF}>>2)) || (LA[19:2] >= (20'hFC000>>2)));
	wire         ddr_ruse = ~((`USE_BRAM_BLOCKS_FOR_VRAM && RA[19:2] >= ({BRAM4_OFFS+0,16'h0000}>>2) && RA[19:2] <= ({BRAM4_OFFS+3,16'hFFFF}>>2)) || (`USE_BRAM_BLOCKS_FOR_VRAM && RA[19:2] >= ({BRAM2_OFFS+0,16'h0000}>>2) && RA[19:2] <= ({BRAM2_OFFS+1,16'hFFFF}>>2)) || (RA[19:2] >= ({BRAM1_OFFS+0,16'h0000}>>2) && RA[19:2] <= ({BRAM1_OFFS+0,16'hBFFF}>>2)) || (RA[19:2] >= (20'hFC000>>2)));
	
	ddram ddram
	(
		.*,
		.clk(clk_mem),
		.rst(mem_rst),
	
		//
		.io_addr(bios_download || kanji_download ? {1'b0,kanji_download,ioctl_addr[19:2]} : !SRAMW_N || !SRAMR_N ? {1'b1,6'b000000,PA[16:4]} : {1'b0,ROM_SEL,PA[19:2]}),
		.io_din (bios_download || kanji_download ? {2{ioctl_data[7:0],ioctl_data[15:8]}} : {4{PDO}}),
		.io_we  (bios_download || kanji_download ? {~ioctl_addr[1],~ioctl_addr[1],ioctl_addr[1],ioctl_addr[1]}&{4{ioctl_wr|ioctl_wr_delayed}} : !SRAMW_N ? (4'h8>>PA[3:2])&{4{MCLK_CE}} : 4'b0000),
		.io_rd  (bios_download || kanji_download ? 1'b0 : (~ROMCS_N|~SRAMR_N)&MCLK_CE),
		.io_dout(ddr_io_do),
		.io_busy(ddr_io_busy),
		
		.nvram_addr({sd_lba[5:0],tmpram_addr}),
		.nvram_din (nvram_load_data),
		.nvram_wr  (tmpram_req & bk_loading),
		.nvram_rd  (tmpram_req & ~bk_loading),
		.nvram_dout(ddr_nvram_do),
		.nvram_busy(ddr_nvram_busy),
		
		.sclk(SYS_CE_R),
		.laddr(LA[19:2]),
		.ldin (RAM_DO[31:16]),
		.lras (!LRAS0_N),
		.lwe  (ddr_luse ? ~LWE_N : '0),
		.lrd  (ddr_luse ? ~LOE_N : 0),
		.ldout(ddr_do[31:16]),
		.raddr(RA[19:2]),
		.rdin (RAM_DO[15:0]),
		.rras (!RRAS0_N),
		.rwe  (ddr_ruse ? ~RWE_N : '0),
		.rrd  (ddr_ruse ? ~ROE_N : 0),
		.rdout(ddr_do[15:0]),
		.busy(ddr_busy),
		
		.bladdr(ddr_bladdr),
		.blwr  (ddr_blwr),
		.blrd  (ddr_blrd),
		.braddr(ddr_braddr),
		.brwr  (ddr_brwr),
		.brrd  (ddr_brrd),
		.bfw   (ddr_bfw),
		.ba(),
		.bin(ddr_bin),
		.bout(ddr_bout),
		.blte(ddr_blte),
		.brte(ddr_brte),
		.bbusy(ddr_bbusy)
	);

	reg pause;
	always @(posedge clk_sys) begin
		bit cond;
		
		if (reset) begin
			pause <= 0;
		end else if (CE_F) begin
			cond = ddr_io_busy || ddr_busy || !VRAM_LRDY || !VRAM_RRDY || DBG_PAUSE;
			if (cond && !pause) begin
				pause <= 1;
			end
			if (!cond && pause) begin
				pause <= 0;
			end
		end
	end
	
	/////////////////////////  STATE SAVE/LOAD  /////////////////////////////
	wire downloading = save_download;
	wire bk_change  = ~SRAMW_N;
	wire bk_load    = status[12];
	wire bk_save    = status[13];
	wire autosave   = status[14];

	reg bk_ena = 0;
	reg sav_pending = 0;
	always @(posedge clk_sys) begin
		reg old_downloading = 0;
		reg old_change = 0;

		old_downloading <= downloading;
		if(downloading && !old_downloading) bk_ena <= 0;

		//Save file always mounted in the end of downloading state.
		if(downloading && img_mounted && !img_readonly) bk_ena <= 1;

		old_change <= bk_change;
		if (bk_change && !old_change) sav_pending <= 1;
		else if (bk_state) sav_pending <= 0;
	end

	wire bk_save_a  = autosave & OSD_STATUS;
	reg  bk_loading = 0;
	reg  bk_state   = 0;
	always @(posedge clk_sys) begin
		reg old_downloading = 0;
		reg old_load = 0, old_save = 0, old_save_a = 0, old_ack;
		reg [1:0] state;

		old_downloading <= downloading;

		old_load   <= bk_load;
		old_save   <= bk_save;
		old_save_a <= bk_save_a;
		old_ack    <= sd_ack;

		if(sd_ack && !old_ack) {sd_rd, sd_wr} <= 0;

		if (!bk_state) begin
			tmpram_tx_start <= 0;
			state <= 0;
			sd_lba <= 0;
			bk_loading <= 0;
			if (bk_ena && ((bk_load && !old_load) | (bk_save && !old_save) | (bk_save_a && !old_save_a && sav_pending))) begin
				bk_state <= 1;
				bk_loading <= bk_load;
				sd_rd <=  bk_load;
				sd_wr <= 0;
			end
			if (old_downloading && !bios_download && !kanji_download && bk_ena) begin
				bk_state <= 1;
				bk_loading <= 1;
				sd_rd <= 1;
				sd_wr <= 0;
			end
		end
		else begin
			if (bk_loading) begin
				case(state)
					0: begin
							sd_rd <= 1;
							state <= 1;
						end
					1: if (!sd_ack && old_ack) begin
							tmpram_tx_start <= 1;
							state <= 2;
						end
					2: if(tmpram_tx_finish) begin
							tmpram_tx_start <= 0;
							state <= 0;
							sd_lba <= sd_lba + 1'd1;
							if (sd_lba == 32'h3F) bk_state <= 0;
						end
				endcase
			end
			else begin
				case(state)
					0: begin
							tmpram_tx_start <= 1;
							state <= 1;
						end
					1: if (tmpram_tx_finish) begin
							tmpram_tx_start <= 0;
							sd_wr <= 1;
							state <= 2;
						end
					2: if (!sd_ack && old_ack) begin
							state <= 0;
							sd_lba <= sd_lba + 1'd1;
							if (sd_lba == 32'h3F) bk_state <= 0;
						end
				endcase
			end
		end
	end

	wire [15:0] tmpram_dout;
	wire [15:0] tmpram_din = {ddr_nvram_do[7:0],ddr_nvram_do[15:8]};
	wire        tmpram_busy = ddr_nvram_busy;

	wire [15:0] tmpram_sd_buff_q;
	dpram_dif #(8,16,8,16) tmpram
	(
		.clock(clk_sys),

		.address_a(tmpram_addr),
		.wren_a(~bk_loading & tmpram_req & ~tmpram_busy),
		.data_a(tmpram_din),
		.q_a(tmpram_dout),

		.address_b(sd_buff_addr),
		.wren_b(sd_buff_wr & sd_ack),
		.data_b(sd_buff_dout),
		.q_b(tmpram_sd_buff_q)
	);

	reg  [8:1] tmpram_addr;
	reg tmpram_tx_start;
	reg tmpram_tx_finish;
	reg tmpram_req;
	always @(posedge clk_sys) begin
		reg state;
		
		if (tmpram_req && !tmpram_busy) tmpram_req <= 0;

		if (~tmpram_tx_start) {tmpram_addr, state, tmpram_tx_finish} <= '0;
		else if (~tmpram_tx_finish) begin
			if (!state) begin
				tmpram_req <= 1;
				state <= 1;
			end
			else if (tmpram_req && !tmpram_busy) begin
				state <= 0;
				if (~&tmpram_addr) tmpram_addr <= tmpram_addr + 1'd1;
				else tmpram_tx_finish <= 1;
			end
		end
	end

	assign sd_buff_din = tmpram_sd_buff_q; 

	//A save file without a volume label is loaded as a blank formatted NVRAM
	P3DO_NVRAM_FMT nvram_fmt
	(
		.CLK(clk_sys),
		.LOAD(bk_loading),
		.SD_WR(sd_buff_wr & sd_ack),
		.SD_ADDR(sd_buff_addr),
		.SD_DATA(sd_buff_dout),
		.SECTOR(sd_lba[5:0]),
		.ADDR(tmpram_addr),
		.DIN({tmpram_dout[7:0],tmpram_dout[15:8]}),
		.DOUT(nvram_load_data)
	);
	

	////////////////////////////////////////////////////////////////
	wire [ 2: 0] scale = '0;//status[3:1];
	reg          forced_scandoubler_sync;
	reg  [ 2: 0] scale_sync;
	
	reg          INTERLACE,FIELD;
	always @(posedge clk_vid) begin
		forced_scandoubler_sync <= 0;//forced_scandoubler;
		scale_sync <= scale;
		INTERLACE <= status[19];
		FIELD <= P3DO_FIELD;
	end
	wire [ 2: 0] sl = scale_sync;
	
	assign CLK_VIDEO = clk_vid;
	assign VGA_SL = {~INTERLACE,~INTERLACE} & sl[1:0];
	assign VGA_F1 = INTERLACE & FIELD;
	
	wire vga_de;
	video_mixer #(.LINE_LENGTH(8), .HALF_DEPTH(0), .GAMMA(1)) video_mixer
	(
		.*,
	
		.ce_pix(DCLK),	
		.scandoubler(~INTERLACE && (scale_sync || forced_scandoubler_sync)),
		.hq2x(0),	
		.freeze_sync(),
	
		.VGA_DE(vga_de),

		.R(R),
		.G(G),
		.B(B),
	
		// Positive pulses.
		.HSync(~HS_N),
		.VSync(~VS_N),
		.HBlank(~HBL_N),
		.VBlank(~VBL_N)
	);
	
	reg [ 1: 0] vcrop_mode;
	reg [ 3: 0] vcopt;
	reg [ 1: 0] vf_scale;
	reg         en216p;
	reg [ 4: 0] voff;
	reg [ 9: 0] crop_size;
	always @(posedge CLK_VIDEO) begin
		vcrop_mode <= status[9:8];
		vcopt <= '0;
		vf_scale <= status[7:6];
		en216p <= ((HDMI_WIDTH == 1920) && (HDMI_HEIGHT == 1080) && !forced_scandoubler_sync && !scale_sync);
		voff <= (vcopt < 6) ? {vcopt,1'b0} : ({vcopt,1'b0} - 5'd24);
		case (vcrop_mode)
			  2'b01: crop_size <= 10'd216;  // 216p
			  2'b10: crop_size <= 10'd224;  // 224p
			  default: crop_size <= 10'd0;  // Disabled
		 endcase
	end
	
	video_freak video_freak
	(
		.*,
		.VGA_DE_IN(vga_de),
		.ARX(12'd4),
		.ARY(12'd3),
		.CROP_SIZE((en216p && vcrop_mode == 2'd1) || vcrop_mode >= 2'd2 ? crop_size : 10'd0),
		.CROP_OFF(voff),
		.SCALE(vf_scale)
	);


	//debug
	reg  [7:0] SCRN_EN = 8'b11111111;
	reg  [2:0] SND_EN = 3'b111;
	reg        DBG_PAUSE = 0;
//	reg        DBG_BREAK = 0;
//	reg        DBG_RUN = 0;
	
	reg  [7:0] DBG_EXT = '1;
	
	wire       pressed = ps2_key[9];
	wire [8:0] code    = ps2_key[8:0];
	always @(posedge clk_sys) begin
		reg old_state = 0;
	
//		DBG_RUN <= 0;
		DBG_EXT[7:4] <= '0;
		
		old_state <= ps2_key[10];
		if((ps2_key[10] != old_state) && pressed) begin
			casex(code)
				'h005: begin SCRN_EN[0] <= ~SCRN_EN[0]; end 	// F1
				'h006: begin SCRN_EN[1] <= ~SCRN_EN[1]; end 	// F2
				'h004: begin SCRN_EN[2] <= ~SCRN_EN[2]; end 	// F3
				'h00C: begin SCRN_EN[3] <= ~SCRN_EN[3]; end 	// F4
				'h003: begin SCRN_EN[4] <= ~SCRN_EN[4]; end 	// F5
				'h00B: begin SCRN_EN[5] <= ~SCRN_EN[5]; end 	// F6
				'h083: begin SCRN_EN[6] <= ~SCRN_EN[6]; end 	// F7
				'h00A: begin SND_EN[0] <= ~SND_EN[0]; end 	// F8
				'h001: begin SND_EN[1] <= ~SND_EN[1]; end 	// F9
				'h009: begin SND_EN[2] <= ~SND_EN[2]; end 	// F10
				'h078: begin SCRN_EN <= '1; SND_EN <= '1; DBG_EXT <= '1; end 	// F11
`ifdef DEBUG
//				'h009: begin DBG_BREAK <= ~DBG_BREAK; end 	// F10
//				'h078: begin DBG_RUN <= 1; end 	// F11
				'h177: begin DBG_PAUSE <= ~DBG_PAUSE; end 	// Pause
				'h016: begin DBG_EXT[0] <= ~DBG_EXT[0]; end 	// 1
				'h01E: begin DBG_EXT[1] <= ~DBG_EXT[1]; end 	// 2
				'h026: begin DBG_EXT[2] <= ~DBG_EXT[2]; end 	// 3
				'h025: begin DBG_EXT[3] <= ~DBG_EXT[3]; end 	// 4
`endif
			endcase
		end
		
		if(pressed) begin
			casex(code)
`ifdef DEBUG
				'h02E: begin DBG_EXT[4] <= 1; end 	// 5
				'h036: begin DBG_EXT[5] <= 1; end 	// 6
				'h03D: begin DBG_EXT[6] <= 1; end 	// 7
				'h03E: begin DBG_EXT[7] <= 1; end 	// 8
`endif
				'h07B: begin DBG_EXT[6] <= 1; end 	// Num-
				'h079: begin DBG_EXT[7] <= 1; end 	// Num+
				default:;
			endcase
		end
	end

endmodule
