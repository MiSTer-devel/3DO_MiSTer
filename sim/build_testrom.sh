#!/bin/bash
# Assemble the ARM60 (ARMv3, big-endian) programs for tb_arm6:
# sim/tb/arm6_isa.S (instruction set checks) and sim/tb/arm6_fiq.S (interrupts).
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${BUILD:-/tmp/3do_sim}
CROSS=${CROSS:-arm-none-linux-gnueabihf-}
mkdir -p "$OUT"
for p in arm6_isa arm6_fiq; do
	${CROSS}as -EB -march=armv4 -mfloat-abi=soft "$HERE/tb/$p.S" -o "$OUT/$p.o"
	${CROSS}ld -EB -Ttext=0 -o "$OUT/$p.elf" "$OUT/$p.o"
	${CROSS}objcopy -O binary "$OUT/$p.elf" "$OUT/$p.bin"
	${CROSS}objdump -d "$OUT/$p.elf" > "$OUT/$p.lst"
	echo "$p: $(stat -c %s "$OUT/$p.bin") bytes"
done
