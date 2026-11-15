module ddram
(
	output         DDRAM_CLK,
	input          DDRAM_BUSY,
	output [ 7: 0] DDRAM_BURSTCNT,
	output [28: 0] DDRAM_ADDR,
	input  [63: 0] DDRAM_DOUT,
	input          DDRAM_DOUT_READY,
	output         DDRAM_RD,
	output [63: 0] DDRAM_DIN,
	output [ 7: 0] DDRAM_BE,
	output         DDRAM_WE,
	
	input          clk,
	input          rst,
	
	input  [21: 2] io_addr,
	output [31: 0] io_dout,
	input  [31: 0] io_din,
	input          io_rd,
	input  [ 3: 0] io_we,
	output         io_busy,
	
	input  [14: 1] nvram_addr,
	output reg [15: 0] nvram_dout,
	input  [15: 0] nvram_din,
	input          nvram_rd,
	input          nvram_wr,
	output reg         nvram_busy,

	input          sclk,
	input  [19: 2] laddr,
	input  [15: 0] ldin,
	output reg [15: 0] ldout,
	input          lras,
	input          lras_d,   // lras at the clock before (the previous clk_sys edge)
	input  [ 1: 0] lwe,
	input          lrd,
	input  [19: 2] raddr,
	input  [15: 0] rdin,
	output reg [15: 0] rdout,
	input          rras,
	input          rras_d,
	input  [ 1: 0] rwe,
	input          rrd,
	output         busy,
	
	input  [19: 2] bladdr,
	input          blwr,
	input          blrd,
	input  [19: 2] braddr,
	input          brwr,
	input          brrd,
	input          bfw,
	output reg [ 9: 2] ba,
	input  [63: 0] bin,
	output [63: 0] bout,
	output reg         blte,
	output reg         brte,
	output         bbusy
);

	reg  [ 27:  1] ram_address;
	reg  [ 63:  0] ram_din;
	reg  [  7:  0] ram_ba;
	reg  [  7:  0] ram_burst;
	reg            ram_read = 0;
	reg            ram_write = 0;
	
	reg  [ 63:  0] dout_buf;
	reg            burst_read_lbusy = 0,burst_read_rbusy = 0;
	reg            burst_write_lbusy = 0,burst_write_rbusy = 0;
	reg            read_lbusy = 0,read_rbusy = 0;
	reg            write_lpend = 0,write_rpend = 0;
	reg            write_lbusy = 0,write_rbusy = 0;
	reg            write_lcache_update,write_rcache_update;
	reg            io_read_busy = 0;
	reg            io_write_busy = 0,io_write_pend,io_write_pend2;
	reg            nvram_read_busy = 0;
	reg            nvram_write_busy = 0;

	reg  [ 19:  2] burst_laddr,burst_raddr;
	reg  [ 19:  2] write_laddr,write_raddr;
	reg  [ 15:  0] write_ldata,write_rdata;
	reg  [  7:  0] write_lbe,write_rbe;
	reg  [ 19:  2] read_laddr = '1,read_raddr = '1;
	// Game Bub port: the random-read blocks are valid only until a write
	// burst (page copy, write transfer, masked flash write) or a lazy flash
	// write could have changed their rows; read_*addr alone kept serving
	// a block from before such a write (a translucent cel or the CPU read
	// the old frame buffer pixels after a SPORT clear or copy)
	reg            read_lval,read_rval;     // cleared by rst
	reg            read_lact,read_ract;
	reg  [  3:  0] lcache_wren,rcache_wren;
	reg            lcache_load,rcache_load;
	reg  [  3:  0] lrcache_addr;
	reg  [ 21:  2] io_write_addr;
	reg  [ 31:  0] io_write_data;
	reg  [  3:  0] io_write_be;
	reg  [ 21:  2] io_read_addr;
	reg  [ 31:  0] io_rbuf;
	reg  [ 14:  1] nvram_write_addr;
	reg  [ 15:  0] nvram_write_data;
	reg  [ 14:  1] nvram_read_addr;
	reg  [ 31:  0] nvram_rbuf;

	reg  [  3:  0] state = 0;
	reg  [  7:  0] rpos,wpos = '0;
	
	
	reg  [ 12:  0] vram_fw_init_addr;
	always @(posedge clk) begin
		vram_fw_init_addr <= vram_fw_init_addr + 13'd1;
	end
	
	reg  [ 19:  3] vram_fw_baddr;
	reg            vram_fw_brd,vram_fw_bwr;
	// Game Bub port: while a random write waits to be issued, look up the
	// flash-write flag and row colour of the address it writes. The original
	// used the address on the bus, which is MADAM's next access once the
	// write has been held up (SDRAM busy): the word was then completed with
	// the wrong flag, so the flash colour overwrote neighbouring pixels.
	// The bus address is not looked up at all any more: a write is issued
	// only once the lookup is for its own latched address (vram_fw_qaddr),
	// and reads look up their burst address. That keeps MADAM's address bus
	// (clk_sys) out of this clk_mem RAM's address path.
	wire [ 19:  3] vram_fw_raddr1 = write_lpend ? write_laddr[19:3] : write_raddr[19:3];
	wire [ 19:  3] vram_fw_addr1 = vram_fw_brd || vram_fw_bwr ? vram_fw_baddr : vram_fw_raddr1;
	reg  [ 19:  3] vram_fw_qaddr;   // address the flag/colour outputs now belong to
	always @(posedge clk) vram_fw_qaddr <= vram_fw_addr1;
	wire           vram_fw_q1;
	VRAM_FW #(18) vram_fw
	(
		.CLK1(clk),
		.ADDR1(vram_fw_addr1),
		.DATA1(1'b0),
		.WREN1(vram_fw_bwr),
		.Q1(vram_fw_q1),
		
		.CLK2(clk),
		.ADDR2(rst ? vram_fw_init_addr : bladdr[19:7]),
		.DATA2(rst ? 16'h0000 : 16'hFFFF),
		.WREN2(bfw),
		.Q2()
	);
	
	wire [ 31:  0] vram_fw_data;
	wire [ 31:  0] vram_color_q;
	VRAM_COLOR #(18) vram_color
	(
		.CLK(clk),
		.WADDR(bladdr[19:11]),
		.DATA(bin[31:0]),
		.WREN(bfw),
		.RADDR(vram_fw_addr1[19:11]),
		.Q(vram_fw_data)
	);
	
	always @(posedge clk) begin
		bit old_io_rd, old_io_we,old_nvram_rd,old_nvram_wr;
		bit old_blrd, old_blwr, old_brrd, old_brwr;
		bit old_lrd, old_lwe, old_rrd, old_rwe;
		bit old_rst;
		bit read_lpend,read_rpend;
		bit write_lprepend,write_rprepend;
		bit burst_lact,burst_ract,burst_interrupted;
		bit burst_write;
		bit [7:0] burst_ba;
		bit [63:0] bin_save;
		
		old_blwr <= blwr; old_brwr <= brwr;
		old_blrd <= blrd; old_brrd <= brrd;
		old_lrd <= lrd; old_rrd <= rrd;
		old_lwe <= |lwe; old_rwe <= |rwe;
		old_rst <= rst;
		
		if (rst) begin
			burst_write_lbusy <= 0;
		end else if (blwr && !old_blwr) begin
			burst_laddr <= bladdr;
			burst_write_lbusy <= 1;
		end
		if (rst) begin
			burst_write_rbusy <= 0;
		end else if (brwr && !old_brwr) begin
			burst_raddr <= braddr;
			burst_write_rbusy <= 1;
		end
		if (rst) begin
			burst_read_lbusy <= 0;
		end else if (blrd && !old_blrd) begin
			burst_laddr <= bladdr;
			burst_read_lbusy <= 1;
		end
		if (rst) begin
			burst_read_rbusy <= 0;
		end else if (brrd && !old_brrd) begin
			burst_raddr <= braddr;
			burst_read_rbusy <= 1;
		end
		
		if (rst) begin
			read_lbusy <= 0;
		end else if (lrd && !old_lrd && lras && lras_d) begin
			read_laddr <= laddr;
			if (!read_lval || read_laddr[19:7] != laddr[19:7]) begin
				read_lbusy <= 1;
				read_lval <= 1;
			end
		end
		if (rst) begin
			read_rbusy <= 0;
		end else if (rrd && !old_rrd && rras && rras_d) begin
			read_raddr <= raddr;
			if (!read_rval || read_raddr[19:7] != raddr[19:7]) begin
				read_rbusy <= 1;
				read_rval <= 1;
			end
		end
		// a write burst starting or a lazy flash write: drop both blocks (the
		// burst's end drops them again, below, for a block read between its
		// passes)
		if (rst || (blwr && !old_blwr) || (brwr && !old_brwr) || bfw) begin
			read_lval <= 0;
			read_rval <= 0;
		end
		
		if (rst) begin
//			write_lprepend <= 0;
			write_lbusy <= 0;
		end else if (|lwe && !old_lwe && lras && lras_d) begin
//			write_lprepend <= 1;
			write_lbusy <= |state | DDRAM_BUSY;
//		end
//		if (rst) begin
//			write_lpend <= 0;
//		end else if (write_lprepend && sclk) begin
//			write_lprepend <= 0;
			if (read_laddr[19:7] == laddr[19:7]) begin
				write_lcache_update <= 1;
			end else begin
				write_lcache_update <= 0;
			end
			write_laddr <= laddr;
			write_ldata <= ldin;
			write_lbe <= !laddr[2] ? {lwe,6'b000000} : {4'b0000,lwe,2'b00};
			write_lpend <= 1;
		end
		
		if (rst) begin
//			write_rprepend <= 0;
			write_rbusy <= 0;
		end else if (|rwe && !old_rwe && rras && rras_d) begin
//			write_rprepend <= 1;
			write_rbusy <= |state | DDRAM_BUSY;
//		end
//		if (rst) begin
//			write_rpend <= 0;
//		end else if (write_rprepend && sclk) begin
//			write_rprepend <= 0;
			if (read_raddr[19:7] == raddr[19:7]) begin
				write_rcache_update <= 1;
			end else begin
				write_rcache_update <= 0;
			end
			write_raddr <= raddr;
			write_rdata <= rdin;
			write_rbe <= !raddr[2] ? {2'b00,rwe,4'b0000} : {6'b000000,rwe};
			write_rpend <= 1;
		end
		
		old_io_rd <= io_rd;
		old_io_we <= |io_we;
		if (rst && !old_rst) begin
			io_read_busy <= 0;
		end else if (io_rd && !old_io_rd) begin
			io_read_addr <= io_addr;
			io_read_busy <= 1;
		end
		if (rst && !old_rst) begin
			io_write_busy <= 0;
		end else if (|io_we && !old_io_we) begin
			io_write_busy <= 1;
		end
		if (io_write_busy && !io_write_pend) begin
			io_write_pend <= 1;
		end
		if (io_write_pend && !io_write_pend2) begin
			io_write_addr <= io_addr;
			io_write_data <= io_din;
			io_write_be <= io_we;
			io_write_pend2 <= 1;
			io_write_pend <= 0;
		end
		
		old_nvram_rd <= nvram_rd;
		old_nvram_wr <= nvram_wr;
		if (rst && !old_rst) begin
			nvram_read_busy <= 0;
		end else if (nvram_rd && !old_nvram_rd) begin
			nvram_read_addr <= nvram_addr;
			nvram_read_busy <= 1;
		end
		if (rst && !old_rst) begin
			nvram_write_busy <= 0;
		end else if (nvram_wr && !old_nvram_wr) begin
			nvram_write_addr <= nvram_addr;
			nvram_write_data <= nvram_din;
			nvram_write_busy <= 1;
		end
		
		{blte,brte} <= '0;
		{lcache_load,rcache_load} <= '0;
		vram_fw_bwr <= 0;
		if (rst && !old_rst) begin
			state <= 0;
		end else if (DDRAM_BUSY) begin
			case (state)
				4'd1: if (blte || brte) begin
					bin_save		<= bin;
					burst_interrupted <= 1;
				end
			endcase
		end else if (!DDRAM_BUSY) begin
			ram_write <= 0;
			ram_read  <= 0;
			case (state)
				0: begin
					// Game Bub port: a write burst is two passes of 128 beats,
					// one per half-row; wpos[7] says which pass this is, and
					// the second ends the burst. It is the half-row of the
					// burst's address (a write transfer starts at column 0 and
					// the address moves to the second half after the first
					// pass). The original kept wpos[7] from the previous pass,
					// whichever half's it was: a left burst started between
					// the right half's two passes (the halves out of step, a
					// video transfer on one half when a write transfer comes)
					// ended after one pass, its VRAM module waited for the
					// rest for ever (the 3DO stayed paused), and the right
					// half's second pass was taken as a first one, so a third
					// ran on into the next row.
					if (burst_write_lbusy) begin
						burst_lact <= 1;
						if (burst_write_rbusy && burst_raddr == burst_laddr) burst_ract <= 1;
						vram_fw_baddr <= burst_laddr[19:3];
						vram_fw_bwr <= 1;
						ram_address <= {8'b00000000,burst_laddr[19:3],2'b00};
						ram_burst   <= 128;
						wpos <= {burst_laddr[10], 7'b0000000};
						blte <= 1;
						if (burst_write_rbusy && burst_raddr == burst_laddr) brte <= 1;
						state       <= 4'd1;
					end
					else if (burst_write_rbusy) begin  
						burst_ract <= 1;
						vram_fw_baddr <= burst_raddr[19:3];
						vram_fw_bwr <= 1;
						ram_address <= {8'b00000000,burst_raddr[19:3],2'b00};
						ram_burst   <= 128;
						wpos <= {burst_raddr[10], 7'b0000000};
						brte <= 1;
						state       <= 4'd1;
					end
					else if (burst_read_lbusy) begin
						burst_lact <= 1;
						if (burst_read_rbusy && burst_raddr == burst_laddr) burst_ract <= 1;
						vram_fw_baddr <= burst_laddr[19:3];
						vram_fw_brd <= 1;
						ram_address <= {8'b00000000,burst_laddr[19:3],2'b00};
						ram_ba      <= 8'hFF;
						ram_read 	<= 1;
						ram_burst   <= 8'd128 - burst_laddr[9:3];
						rpos        <= {1'b0,burst_laddr[9:3]};
						state       <= 4'd2;
					end
					else if (burst_read_rbusy) begin
						burst_ract <= 1;
						vram_fw_baddr <= burst_raddr[19:3];
						vram_fw_brd <= 1;
						ram_address <= {8'b00000000,burst_raddr[19:3],2'b00};
						ram_ba      <= 8'hFF;
						ram_read 	<= 1;
						ram_burst   <= 8'd128 - burst_raddr[9:3];
						rpos        <= {1'b0,burst_raddr[9:3]};
						state       <= 4'd2;
					end
					else if ((write_lpend || write_rpend) && vram_fw_qaddr != (write_lpend ? write_laddr[19:3] : write_raddr[19:3])) begin
						// Game Bub port: the flag/colour lookup above is not yet for
						// this write's address (e.g. right after a burst): wait a cycle
					end
					else if (write_lpend && write_rpend && write_laddr == write_raddr) begin
						{write_lpend,write_rpend} <= '0;
						{write_lbusy,write_rbusy} <= '0;
						lcache_wren <= !write_lcache_update ? 4'b0000 : {write_lbe[7:6],write_lbe[3:2]};
						rcache_wren <= !write_rcache_update ? 4'b0000 : {write_rbe[5:4],write_rbe[1:0]};
						vram_fw_baddr <= write_laddr[19:3];
						vram_fw_bwr <= vram_fw_q1;
						ram_address <= {8'b00000000,write_laddr[19:3],2'b00};
						ram_din		<= {write_lbe[7] ? write_ldata[15: 8] : vram_fw_data[31:24],write_lbe[6] ? write_ldata[ 7: 0] : vram_fw_data[23:16],write_rbe[5] ? write_rdata[15: 8] : vram_fw_data[15: 8],write_rbe[4] ? write_rdata[ 7: 0] : vram_fw_data[ 7: 0],
						                write_lbe[3] ? write_ldata[15: 8] : vram_fw_data[31:24],write_lbe[2] ? write_ldata[ 7: 0] : vram_fw_data[23:16],write_rbe[1] ? write_rdata[15: 8] : vram_fw_data[15: 8],write_rbe[0] ? write_rdata[ 7: 0] : vram_fw_data[ 7: 0]};
						ram_ba      <= vram_fw_q1 ? 8'hFF : write_lbe | write_rbe;
						ram_write 	<= 1;
						ram_burst   <= 1;
						state       <= 4'd6;
					end
					else if (write_lpend) begin 
						write_lpend <= 0;
						write_lbusy <= 0;
						lcache_wren <= !write_lcache_update ? 4'b0000 : {write_lbe[7:6],write_lbe[3:2]};
						vram_fw_baddr <= write_laddr[19:3];
						vram_fw_bwr <= vram_fw_q1;
						ram_address <= {8'b00000000,write_laddr[19:3],2'b00};
						ram_din		<= {write_lbe[7] ? write_ldata[15: 8] : vram_fw_data[31:24],write_lbe[6] ? write_ldata[ 7: 0] : vram_fw_data[23:16],vram_fw_data[15: 8],vram_fw_data[ 7: 0],
						                write_lbe[3] ? write_ldata[15: 8] : vram_fw_data[31:24],write_lbe[2] ? write_ldata[ 7: 0] : vram_fw_data[23:16],vram_fw_data[15: 8],vram_fw_data[ 7: 0]};
						ram_ba      <= vram_fw_q1 ? 8'hFF : write_lbe;
						ram_write 	<= 1;
						ram_burst   <= 1;
						state       <= 4'd6;
					end
					else if (write_rpend) begin 
						write_rpend <= 0;
						write_rbusy <= 0;
						rcache_wren <= !write_rcache_update ? 4'b0000 : {write_rbe[5:4],write_rbe[1:0]};
						vram_fw_baddr <= write_raddr[19:3];
						vram_fw_bwr <= vram_fw_q1;
						ram_address <= {8'b00000000,write_raddr[19:3],2'b00};
						ram_din		<= {vram_fw_data[31:24],vram_fw_data[23:16],write_rbe[5] ? write_rdata[15: 8] : vram_fw_data[15: 8],write_rbe[4] ? write_rdata[ 7: 0] : vram_fw_data[ 7: 0],
						                vram_fw_data[31:24],vram_fw_data[23:16],write_rbe[1] ? write_rdata[15: 8] : vram_fw_data[15: 8],write_rbe[0] ? write_rdata[ 7: 0] : vram_fw_data[ 7: 0]};
						ram_ba      <= vram_fw_q1 ? 8'hFF : write_rbe;
						ram_write 	<= 1;
						ram_burst   <= 1;
						state       <= 4'd6;
					end
					else if (read_lbusy) begin 
						read_lact <= 1;
						if (read_rbusy && read_raddr == read_laddr) read_ract <= 1;
						vram_fw_baddr <= {read_laddr[19:7],4'b0000};
						vram_fw_brd <= 1;
						ram_address <= {8'b00000000,read_laddr[19:7],6'b000000};
						ram_ba      <= 8'hFF;
						ram_read    <= 1;
						ram_burst   <= 16;
						rpos        <= '0;
						state       <= 4'd7;
					end
					else if (read_rbusy) begin 
						read_ract <= 1;
						vram_fw_baddr <= {read_raddr[19:7],4'b0000};
						vram_fw_brd <= 1;
						ram_address <= {8'b00000000,read_raddr[19:7],6'b000000};
						ram_ba      <= 8'hFF;
						ram_read    <= 1;
						ram_burst   <= 16;
						rpos        <= '0;
						state       <= 4'd7;
					end
					else if (io_write_pend2) begin 
						ram_address <= {6'b000001,io_write_addr[21:3],2'b00};
						ram_din		<= {2{io_write_data}};
						ram_ba      <= !io_write_addr[2] ? {io_write_be,4'b0000} : {4'b0000,io_write_be};
						ram_write 	<= 1;
						ram_burst   <= 1;
						state       <= 4'd8;
					end
					else if (io_read_busy) begin 
						ram_address <= {6'b000001,io_read_addr[21:3],2'b00};
						ram_ba      <= 8'hFF;
						ram_read    <= 1;
						ram_burst   <= 1;
//						rpos        <= '0;
						state       <= 4'd9;
					end
					else if (nvram_write_busy) begin 
						ram_address <= {6'b000001,7'b1000000,nvram_write_addr[14:3],2'b00};
						ram_din		<= {4{nvram_write_data}};
						ram_ba      <= 8'hC0 >> {nvram_write_addr[2:1],1'b0};
						ram_write 	<= 1;
						ram_burst   <= 1;
						state       <= 4'd10;
					end
					else if (nvram_read_busy) begin 
						ram_address <= {6'b000001,7'b1000000,nvram_read_addr[14:3],2'b00};
						ram_ba      <= 8'hFF;
						ram_read    <= 1;
						ram_burst   <= 1;
//						rpos        <= '0;
						state       <= 4'd11;
					end
				end
				
				4'd1: begin
					ram_din		<= burst_interrupted ? bin_save : bin;
					ram_write 	<= 1;
					ram_ba      <= {{2{burst_lact}},{2{burst_ract}},{2{burst_lact}},{2{burst_ract}}};
					burst_interrupted <= 0;
					
					vram_fw_baddr <= vram_fw_baddr + 17'h00001;
					
					ba <= wpos;
					if (wpos != 8'd127 && wpos != 8'd255) begin
						blte <= burst_lact;
						brte <= burst_ract;
						vram_fw_bwr <= 1;
					end
					wpos <= wpos + 8'd1;
					if (wpos == 8'd127) begin
						if (burst_lact) burst_laddr <= burst_laddr + 18'h00100;
						if (burst_ract) burst_raddr <= burst_raddr + 18'h00100;
						burst_lact <= 0;
						burst_ract <= 0;
						state <= 4'd4;
					end
					if (wpos == 8'd255) begin
						if (burst_lact) burst_write_lbusy <= 0;
						if (burst_ract) burst_write_rbusy <= 0;
						read_lval <= 0;
						read_rval <= 0;
						burst_lact <= 0;
						burst_ract <= 0;
						state <= burst_read_lbusy || burst_read_rbusy ? 4'd3 : 4'd4;
					end
				end
				
				4'd2: if (DDRAM_DOUT_READY) begin
					dout_buf <= DDRAM_DOUT;
					ba <= rpos;
					blte <= burst_lact;
					brte <= burst_ract;
					vram_fw_baddr <= vram_fw_baddr + 17'h00001;
					
					rpos <= rpos + 8'd1;
					if (rpos[6:0] == 7'd127) begin
						if (burst_lact) burst_read_lbusy <= 0;
						if (burst_ract) burst_read_rbusy <= 0;
						burst_lact <= 0;
						burst_ract <= 0;
						state <= 4'd3;
					end
					
				end
				
				4'd3: begin
					vram_fw_brd <= 0;
					state <= 4'd4;
				end
				
				4'd4: begin
					state <= 4'd5;
				end
				
				4'd5: begin
					state <= 4'd0;
				end
				
				4'd6: begin
					lcache_wren <= '0;
					rcache_wren <= '0;
					state <= vram_fw_bwr ? 4'd5 : 4'd0;
				end
				
				4'd7: if (DDRAM_DOUT_READY) begin
					dout_buf <= DDRAM_DOUT;
					lcache_load <= read_lact;
					rcache_load <= read_ract;
					lrcache_addr <= rpos[4:1];
					vram_fw_baddr <= vram_fw_baddr + 17'h00001;
					
					rpos[4:0] <= rpos[4:0] + 5'd2;
					if (rpos[4:0] == 5'h1E) begin
						vram_fw_brd <= 0;
						state <= 4'd12;
					end
				end
				
				// the block's last words go into the block cache a clock later
				// (lc_load below): the read is over, and the next access starts,
				// a clock later too
				4'd12: begin
					if (read_lact) read_lbusy <= 0;
					if (read_ract) read_rbusy <= 0;
					read_lact <= 0;
					read_ract <= 0;
					state <= 4'd0;
				end
				
				4'd8: begin
					io_write_busy <= 0;
					io_write_pend2 <= 0;
					state <= 4'd0;
				end
				
				4'd9: if (DDRAM_DOUT_READY) begin
					io_rbuf <= !io_read_addr[2] ? DDRAM_DOUT[63:32] : DDRAM_DOUT[31:0];
					io_read_busy <= 0;
					state <= 4'd0;
				end
				
				4'd10: begin
					nvram_write_busy <= 0;
					state <= 4'd0;
				end
				
				4'd11: if (DDRAM_DOUT_READY) begin
					nvram_rbuf <= !nvram_read_addr[2] ? DDRAM_DOUT[63:32] : DDRAM_DOUT[31:0];
					nvram_read_busy <= 0;
					state <= 4'd0;
				end
			endcase
		end
	end
	
	wire [ 63:  0] dout = vram_fw_q1 ? {2{vram_fw_data}} : dout_buf;
	
	wire [ 31:  0] lcache_q,rcache_q;
	// The words read for the block cache go through a register into it (they
	// went from the flash-flag RAM's output through the colour select straight
	// into the cache's write port).
	reg  [ 31:  0] lc_data,rc_data;
	reg            lc_load,rc_load;
	reg  [  3:  0] lrc_addr;
	always @(posedge clk) begin
		lc_data <= {dout[63:48],dout[31:16]};
		rc_data <= {dout[47:32],dout[15:00]};
		lc_load <= lcache_load;
		rc_load <= rcache_load;
		lrc_addr <= lrcache_addr;
	end
	ddr_cache_ram #(4) lcache (clk, lc_load ? lrc_addr : write_laddr[6:3], lc_load ? lc_data : {2{write_ldata}}, ({4{lc_load}} | lcache_wren), read_laddr[6:3], lcache_q);
	ddr_cache_ram #(4) rcache (clk, rc_load ? lrc_addr : write_raddr[6:3], rc_load ? rc_data : {2{write_rdata}}, ({4{rc_load}} | rcache_wren), read_raddr[6:3], rcache_q);

	always_comb begin
		case (read_laddr[2])
			1'b0: ldout = lcache_q[31:16];
			1'b1: ldout = lcache_q[15:00];
		endcase
	
		case (read_raddr[2])
			1'b0: rdout = rcache_q[31:16];
			1'b1: rdout = rcache_q[15:00];
		endcase
	end
	
	
	assign bout = dout;
	// Game Bub port: a write that has not been issued yet keeps MADAM paused.
	// write_*busy only reflects whether ddram.sv was busy when the write was
	// latched; if a burst (served first) started right after, the write
	// waited without a pause and the next CEL-engine write (one per MCLK)
	// replaced it.
	assign busy = write_lbusy | write_rbusy | write_lpend | write_rpend | read_lbusy | read_rbusy;
	assign bbusy = burst_read_lbusy | burst_read_rbusy | burst_write_lbusy | burst_write_rbusy;
	
	assign io_dout = io_rbuf;
	assign io_busy = io_read_busy | io_write_busy;
	
	always_comb begin
		case (nvram_read_addr[1])
			1'b0: nvram_dout = nvram_rbuf[31:16];
			1'b1: nvram_dout = nvram_rbuf[15:00];
		endcase
		nvram_busy = nvram_read_busy | nvram_write_busy;
	end
	
	assign DDRAM_CLK      = clk;
	assign DDRAM_BURSTCNT = ram_burst;
	assign DDRAM_BE       = ram_ba;
	assign DDRAM_ADDR     = {4'b0011, ram_address[27:3]}; // RAM at 0x30000000
	assign DDRAM_RD       = ram_read;
	assign DDRAM_DIN      = ram_din;
	assign DDRAM_WE       = ram_write;

endmodule

module ddr_cache_ram #(parameter wa = 3) (
	clock,
	wraddress,
	data,
	wren,
	rdaddress,
	q);

	input	  clock;
	input	[wa-1:0]  wraddress;
	input	[31:0] data;
	input	[3:0] wren;
	input	[wa-1:0]  rdaddress;
	output	[31:0]  q;

	wire [31:0] sub_wire0;

	altdpram	altdpram_component (
				.data (data),
				.inclock (clock),
				.rdaddress (rdaddress),
				.wraddress (wraddress),
				.wren (|wren),
				.q (sub_wire0),
				.aclr (1'b0),
				.byteena (wren),
				.inclocken (1'b1),
				.rdaddressstall (1'b0),
				.rden (1'b1),
				//.sclr (1'b0),
				.wraddressstall (1'b0));
	defparam
		altdpram_component.indata_aclr = "OFF",
		altdpram_component.indata_reg = "INCLOCK",
		altdpram_component.intended_device_family = "Cyclone V",
		altdpram_component.lpm_type = "altdpram",
		altdpram_component.outdata_aclr = "OFF",
		altdpram_component.outdata_reg = "UNREGISTERED",
		altdpram_component.power_up_uninitialized = "TRUE",
		altdpram_component.ram_block_type = "MLAB",
		altdpram_component.rdaddress_aclr = "OFF",
		altdpram_component.rdaddress_reg = "UNREGISTERED",
		altdpram_component.rdcontrol_aclr = "OFF",
		altdpram_component.rdcontrol_reg = "UNREGISTERED",
		altdpram_component.read_during_write_mode_mixed_ports = "CONSTRAINED_DONT_CARE",
		altdpram_component.width = 32,
		altdpram_component.widthad = wa,
		altdpram_component.byte_size = 8,
		altdpram_component.width_byteena = 4,
		altdpram_component.wraddress_aclr = "OFF",
		altdpram_component.wraddress_reg = "INCLOCK",
		altdpram_component.wrcontrol_aclr = "OFF",
		altdpram_component.wrcontrol_reg = "INCLOCK";

	wire [31:0] q = sub_wire0;
	
endmodule

module VRAM_FW 
#( parameter addr_width = 18 )
(
	input                    CLK1,
	input  [addr_width-1: 1] ADDR1,
	input  [           0: 0] DATA1,
	input                    WREN1,
	output [           0: 0] Q1,
	
	input                    CLK2,
	input  [addr_width-1: 5] ADDR2,
	input  [          15: 0] DATA2,
	input                    WREN2,
	output [          15: 0] Q2
);
	
	wire [0:0] sub_wire0;
	wire [15:0] sub_wire1;

	altsyncram	altsyncram_component (
				.address_a (ADDR1),
				.address_b (ADDR2),
				.clock0 (CLK1),
				.clock1 (CLK2),
				.data_a (DATA1),
				.data_b (DATA2),
				.wren_a (WREN1),
				.wren_b (WREN2),
				.q_a (sub_wire0),
				.q_b (sub_wire1),
				.aclr0 (1'b0),
				.aclr1 (1'b0),
				.addressstall_a (1'b0),
				.addressstall_b (1'b0),
				.byteena_a (1'b1),
				.byteena_b (1'b1),
				.clocken0 (1'b1),
				.clocken1 (1'b1),
				.clocken2 (1'b1),
				.clocken3 (1'b1),
				.eccstatus (),
				.rden_a (1'b1),
				.rden_b (1'b1));
	defparam
		altsyncram_component.address_reg_b = "CLOCK1",
		altsyncram_component.clock_enable_input_a = "BYPASS",
		altsyncram_component.clock_enable_input_b = "BYPASS",
		altsyncram_component.clock_enable_output_a = "BYPASS",
		altsyncram_component.clock_enable_output_b = "BYPASS",
		altsyncram_component.indata_reg_b = "CLOCK1",
		altsyncram_component.intended_device_family = "Cyclone V",
		altsyncram_component.lpm_type = "altsyncram",
		altsyncram_component.numwords_a = 2**(addr_width-1),
		altsyncram_component.numwords_b = 2**(addr_width-5),
		altsyncram_component.operation_mode = "BIDIR_DUAL_PORT",
		altsyncram_component.outdata_aclr_a = "NONE",
		altsyncram_component.outdata_aclr_b = "NONE",
		altsyncram_component.outdata_reg_a = "UNREGISTERED",
		altsyncram_component.outdata_reg_b = "UNREGISTERED",
		altsyncram_component.power_up_uninitialized = "FALSE",		
		altsyncram_component.read_during_write_mode_port_a = "NEW_DATA_NO_NBE_READ",
		altsyncram_component.read_during_write_mode_port_b = "NEW_DATA_NO_NBE_READ",
		altsyncram_component.widthad_a = addr_width-1,
		altsyncram_component.widthad_b = addr_width-5,
		altsyncram_component.width_a = 1,
		altsyncram_component.width_b = 16,
		altsyncram_component.width_byteena_b = 1,
		altsyncram_component.init_file = ""; 

	assign Q1 = sub_wire0;
	assign Q2 = sub_wire1;

endmodule

module VRAM_COLOR #(parameter addr_width = 18) 
(
	input                    CLK,
	input  [addr_width-1: 9] WADDR,
	input  [          31: 0] DATA,
	input                    WREN,
	input  [addr_width-1: 9] RADDR,
	output [          31: 0] Q
);

	wire [31:0] sub_wire0;

	altsyncram	altsyncram_component (
				.address_a (WADDR),
				.address_b (RADDR),
				.clock0 (CLK),
				.clock1 (CLK),
				.data_a (DATA),
				.wren_a (WREN),
				.q_b (sub_wire0),
				.aclr0 (1'b0),
				.aclr1 (1'b0),
				.addressstall_a (1'b0),
				.addressstall_b (1'b0),
				.byteena_a (1'b1),
				.byteena_b (1'b1),
				.clocken0 (1'b1),
				.clocken1 (1'b1),
				.clocken2 (1'b1),
				.clocken3 (1'b1),
				.data_b ({32{1'b1}}),
				.eccstatus (),
				.q_a (),
				.rden_a (1'b1),
				.rden_b (1'b1),
				.wren_b (1'b0));
	defparam
		altsyncram_component.address_aclr_b = "NONE",
		altsyncram_component.address_reg_b = "CLOCK1",
		altsyncram_component.clock_enable_input_a = "BYPASS",
		altsyncram_component.clock_enable_input_b = "BYPASS",
		altsyncram_component.clock_enable_output_b = "BYPASS",
		altsyncram_component.intended_device_family = "Cyclone V",
		altsyncram_component.lpm_type = "altsyncram",
		altsyncram_component.numwords_a = 2**(addr_width-9),
		altsyncram_component.numwords_b = 2**(addr_width-9),
		altsyncram_component.operation_mode = "DUAL_PORT",
		altsyncram_component.outdata_aclr_b = "NONE",
		altsyncram_component.outdata_reg_b = "UNREGISTERED",
		altsyncram_component.power_up_uninitialized = "FALSE",
		altsyncram_component.widthad_a = addr_width-9,
		altsyncram_component.widthad_b = addr_width-9,
		altsyncram_component.width_a = 32,
		altsyncram_component.width_b = 32,
//		altsyncram_component.byte_size = 8,
		altsyncram_component.width_byteena_a = 1;

	assign Q = sub_wire0;
	
endmodule
