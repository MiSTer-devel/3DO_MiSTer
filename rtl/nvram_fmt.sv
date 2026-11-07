//============================================================================
//  3DO NVRAM loading: format a save file that holds no volume.
//
//  The 3DO OS keeps a "linked memory" file system in the 32 KB NVRAM. It starts
//  with a volume label: record type 1, five 0x5A sync bytes, then structure
//  version 2 (linked memory). The OS cannot use a save file without it (an empty
//  or zero-filled file, for instance), and games that do not format the NVRAM
//  themselves report it as full. Such a file is loaded as the blank volume that
//  Main_MiSTer creates for a new save (save_blank in support/3do/3do.cpp): the
//  label, the anchor block and one free block in sector 0, zeros elsewhere. The
//  Opera emulator does the same after loading its NVRAM file. A file with a
//  label loads unchanged.
//============================================================================
module P3DO_NVRAM_FMT
(
	input             CLK,
	input             LOAD,      // the save file is being loaded
	input             SD_WR,     // a word of the current sector arrives from the SD card
	input      [ 7:0] SD_ADDR,   // index of that word in the sector
	input      [15:0] SD_DATA,   // its value (file byte 2k in bits 7:0)
	input      [ 5:0] SECTOR,    // current sector of the save file
	input      [ 7:0] ADDR,      // index of the word written to the NVRAM
	input      [15:0] DIN,       // that word from the file (NVRAM order: byte 2k in bits 15:8)
	output     [15:0] DOUT       // word written to the NVRAM
);

	// First 7 bytes of the file. Sector 0 arrives from the SD card before any of it
	// is written to the NVRAM, so both flags are settled by then.
	reg  [55:0] LABEL;
	reg         FORMATTED, SECTOR0;
	always @(posedge CLK) begin
		if (!LOAD) LABEL <= '0;
		else if (SD_WR && SECTOR == 6'd0 && SD_ADDR < 8'd4) begin
			case (SD_ADDR[1:0])
				2'd0: LABEL[15: 0] <= SD_DATA;
				2'd1: LABEL[31:16] <= SD_DATA;
				2'd2: LABEL[47:32] <= SD_DATA;
				2'd3: LABEL[55:48] <= SD_DATA[7:0];	// byte 6; byte 7 (flags) is not checked
			endcase
		end
		FORMATTED <= LABEL == {8'h02, 16'h5A5A, 16'h5A5A, 16'h5A01};
		SECTOR0 <= SECTOR == 6'd0;
	end

	// Blank volume, 16-bit word k = NVRAM bytes 2k (bits 15:8) and 2k+1
	function automatic [15:0] Blank(input [7:0] k);
		case (k)
			8'h00: Blank = 16'h015A;	// record type 1, sync bytes
			8'h01: Blank = 16'h5A5A;
			8'h02: Blank = 16'h5A5A;
			8'h03: Blank = 16'h0200;	// structure version 2 (linked memory), flags 0
			8'h14: Blank = 16'h4E56;	// volume identifier "NVRAM"
			8'h15: Blank = 16'h5241;
			8'h16: Blank = 16'h4D00;
			8'h24: Blank = 16'hFFFF;	// volume unique identifier
			8'h25: Blank = 16'hFFFF;
			8'h27: Blank = 16'h0001;	// block size 1
			8'h29: Blank = 16'h8000;	// block count 0x8000
			8'h2A: Blank = 16'hFFFF;	// root directory unique identifier
			8'h2B: Blank = 16'hFFFE;
			8'h2F: Blank = 16'h0001;	// root directory block size 1
			8'h33: Blank = 16'h0084;	// root directory avatar: the anchor block
			8'h42: Blank = 16'h855A;	// 0x84: anchor block
			8'h43: Blank = 16'h02B6;
			8'h45: Blank = 16'h0098;	// next block 0x98
			8'h47: Blank = 16'h0098;	// previous block 0x98
			8'h49: Blank = 16'h0014;	// size 0x14
			8'h4B: Blank = 16'h0014;	// header size 0x14
			8'h4C: Blank = 16'h7AA5;	// 0x98: free block
			8'h4D: Blank = 16'h65BD;
			8'h4F: Blank = 16'h0084;	// next block 0x84
			8'h51: Blank = 16'h0084;	// previous block 0x84
			8'h53: Blank = 16'h7F68;	// size 0x7F68, up to the end of the NVRAM
			8'h55: Blank = 16'h0014;	// header size 0x14
			default: Blank = 16'h0000;
		endcase
	endfunction

	assign DOUT = FORMATTED ? DIN : SECTOR0 ? Blank(ADDR) : 16'h0000;

endmodule
