#!/bin/bash
# Build and run one testbench with Verilator (5.x).
#   sim/run_tb.sh <tb_name> [simulation plusargs]   (VARGS="..." for extra verilator args)
# The core RTL is prepared with prep_rtl.py (translate_off regions removed),
# so the simulation compiles the code Quartus synthesises; the Altera
# megafunctions come from sim/models/altera_sim.sv.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(dirname "$HERE")
TB=$1; shift
BUILD=${BUILD:-/tmp/3do_sim}
RTL=$BUILD/rtl
mkdir -p "$BUILD"
python3 -I "$HERE/prep_rtl.py" "$ROOT/rtl" "$RTL"
RTL_FILES=(
    3DO/3DO_pkg.sv ARM6/ARM6_pkg.sv
    ARM6/ARM6_RB.sv ARM6/ARM6_CORE.sv
    3DO/MADAM_mem.sv 3DO/MADAM_ARB.sv 3DO/MADAM_CPUIF.sv 3DO/MADAM_AG.sv 3DO/MADAM_SE.sv
    3DO/MADAM_SPORT.sv 3DO/MADAM_PLAYER.sv 3DO/MADAM_SLOWBUS.sv 3DO/MADAM_EXTPIF.sv 3DO/MADAM.sv
    3DO/CLIO_mem.sv 3DO/CLIO_CLUT.sv 3DO/CLIO_INTERPOL.sv 3DO/CLIO_VIDEO.sv 3DO/CLIO_DSP.sv
    3DO/CLIO_XBUS.sv 3DO/CLIO.sv
    3DO/OSA.sv 3DO/VE.sv 3DO_mem.sv
    hps2pad.sv gun_cross.sv vram.sv ddram.sv
)
FILES=("$HERE/models/altera_sim.sv" "$HERE/models/ce_gen.sv")
for f in "${RTL_FILES[@]}"; do FILES+=("$RTL/$f"); done
FILES+=("$HERE/tb/$TB.sv")
verilator --binary --timing -j "$(nproc)" -Wno-fatal -Wno-lint -Wno-style -Wno-MULTIDRIVEN \
    -Wno-PINMISSING -Wno-DEFPARAM -Wno-IMPLICITSTATIC -Wno-TIMESCALEMOD -Wno-UNOPTFLAT \
    -Wno-INITIALDLY -Wno-COMBDLY -Wno-MULTITOP -Wno-ASCRANGE -Wno-SELRANGE -Wno-ZERODLY \
    --timescale 1ns/1ps -O2 --top-module "$TB" --Mdir "$BUILD/obj_$TB" -o "$TB" "${FILES[@]}" $VARGS > "$BUILD/$TB.build.log" 2>&1 \
    || { grep -E "%Error" -A6 "$BUILD/$TB.build.log" | head -60; exit 1; }
"$BUILD/obj_$TB/$TB" "$@"
