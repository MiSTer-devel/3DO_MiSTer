derive_pll_clocks
derive_clock_uncertainty

set_clock_groups -exclusive \
   -group [get_clocks { *|pll|pll_inst|altera_pll_i|*[*].*|divclk}] \
   -group [get_clocks { *|pll2|pll2_inst|altera_pll_i|*[*].*|divclk}] \
   -group [get_clocks { pll_hdmi|pll_hdmi_inst|altera_pll_i|*[0].*|divclk}] \
   -group [get_clocks { pll_audio|pll_audio_inst|altera_pll_i|*[0].*|divclk}] \
   -group [get_clocks { spi_sck}] \
   -group [get_clocks { hdmi_sck}] \
   -group [get_clocks { *|h2f_user0_clk}] \
   -group [get_clocks { FPGA_CLK1_50 }] \
   -group [get_clocks { FPGA_CLK2_50 }] \
   -group [get_clocks { FPGA_CLK3_50 }]

set_multicycle_path -to {*Hq2x*} -setup 4
set_multicycle_path -to {*Hq2x*} -hold 3

set_false_path -to [get_registers {emu:emu|P3DO:p3do|MADAM:madam|MATH_M[*]}]

# The matrix divider is combinational and its result is taken several cycles later
# (MADAM MATH_DIV, DIV_DELAY); MATH_M can be packed into the multiplier's DSP block
set_false_path -through [get_pins -compatibility_mode {*|MADAM:madam|madam_div:div|*}]
