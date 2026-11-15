@ ARM60 instruction set checks for tb_arm6 (big-endian, ARMv3).
@
@ Each check stores a result word to RES + 4*k; the expected values are the
@ table at `expected` (from the ARM60 datasheet, not computed by the CPU under
@ test), compared by tb_arm6 when the program writes DONE. Covered: shifts by
@ immediate (LSR #32, ASR #32, RRX, LSL #0) and by register (0..256), MSR
@ (immediate and register, _flg and whole PSR, CPSR and SPSR, User mode),
@ word loads from unaligned addresses (LDR, SWP rotate; LDM does not), STM/LDM
@ with the S bit (User bank, with and without R15; exception return), the
@ undefined instruction trap (undefined space, coprocessor instructions,
@ condition false, a non-trapping undefined code), writes to R15 with bits
@ [1:0] set (MOV, LDR, LDM; R15 then reads with bits [1:0] zero), and nTRANS of
@ LDRT/STRT/LDRBT/STRBT (User mode access) against the other transfers (the
@ tb records nTRANS of each access to TRANS_A + n at TRANS_LOG + n).
@ tb_arm6 runs it with the core paused at pseudo-random points (EN low).
@
@ Copyright (c) 2026 Adam Polkosnik
@ SPDX-License-Identifier: GPL-3.0-or-later

	.syntax unified
	.arm

	.equ RES,   0x8000          @ results
	.equ DONE,  0xFFFC          @ written when finished
	.equ UNDCNT, 0x9000         @ undefined instruction traps taken
	.equ UNDLOG, 0x9010         @ handler log: CPSR, SPSR, R14 of the last trap
	.equ TRANS_A, 0xA000        @ accesses here have their nTRANS recorded ...
	.equ TRANS_LOG, 0xA100      @ ... at the same offset here by tb_arm6

	.macro RES k, reg
	str	\reg, [r12, #(\k * 4)]
	.endm
	.macro FLAGS0                @ clear N Z C V
	msr	cpsr_f, #0
	.endm

	.org 0
	b	reset                   @ 0x00 reset
	b	und_handler             @ 0x04 undefined instruction
	b	swi_handler             @ 0x08 SWI
	b	.                       @ 0x0C prefetch abort
	b	.                       @ 0x10 data abort
	b	.                       @ 0x14
	b	.                       @ 0x18 IRQ
	b	.                       @ 0x1C FIQ

und_handler:                    @ log CPSR, SPSR, R14 and count; return to the next instruction
	ldr	r9, =UNDCNT
	ldr	r10, [r9]
	add	r10, r10, #1
	str	r10, [r9]
	ldr	r9, =UNDLOG
	mrs	r10, cpsr
	str	r10, [r9, #0]
	mrs	r10, spsr
	str	r10, [r9, #4]
	str	r14, [r9, #8]
	movs	pc, r14

swi_handler:                    @ only used to leave User mode: continue in SVC mode
	b	after_user

reset:
	ldr	r12, =RES
	ldr	r9, =UNDCNT
	mov	r0, #0
	str	r0, [r9]

	@ ---------------- shifts by an immediate ----------------
	mvn	r0, #0                  @ r0 = FFFFFFFF
	FLAGS0
	movs	r1, r0, lsr #32         @ 0, C = bit 31
	RES	0, r1
	mrs	r2, cpsr
	RES	1, r2
	mov	r3, #0x80000000
	FLAGS0
	movs	r1, r3, asr #32         @ FFFFFFFF, C = 1
	RES	2, r1
	mrs	r2, cpsr
	RES	3, r2
	mov	r3, #1
	msr	cpsr_f, #0x20000000     @ C = 1
	movs	r1, r3, rrx             @ 80000000, C = bit 0 = 1
	RES	4, r1
	mrs	r2, cpsr
	RES	5, r2
	FLAGS0
	movs	r1, r0, lsl #0          @ FFFFFFFF, C unchanged (0)
	RES	6, r1
	mrs	r2, cpsr
	RES	7, r2

	@ ---------------- shifts by a register (r0 = FFFFFFFF) ----------------
	.macro RSHIFT k, op, src, amt
	mov	r3, #\amt
	FLAGS0
	movs	r1, \src, \op r3
	RES	\k, r1
	mrs	r2, cpsr
	RES	(\k + 1), r2
	.endm
	RSHIFT	8,  lsl, r0, 0          @ unchanged, C unchanged
	RSHIFT	10, lsl, r0, 1
	RSHIFT	12, lsl, r0, 31
	RSHIFT	14, lsl, r0, 32         @ 0, C = bit 0
	RSHIFT	16, lsl, r0, 33         @ 0, C = 0
	RSHIFT	18, lsl, r0, 64         @ 0, C = 0
	RSHIFT	20, lsl, r0, 255
	RSHIFT	22, lsr, r0, 32         @ 0, C = bit 31
	RSHIFT	24, lsr, r0, 33
	RSHIFT	26, lsr, r0, 64
	RSHIFT	28, lsr, r0, 96
	mov	r5, #0x80000000
	RSHIFT	30, asr, r5, 32         @ FFFFFFFF, C = 1
	RSHIFT	32, asr, r5, 64
	RSHIFT	34, asr, r5, 255
	mov	r6, #0x40000000
	RSHIFT	36, asr, r6, 64         @ 0, C = 0
	ldr	r7, =0x80000001
	RSHIFT	38, ror, r7, 32         @ unchanged, C = bit 31
	RSHIFT	40, ror, r7, 33         @ as ROR 1
	RSHIFT	42, ror, r7, 64         @ as ROR 32
	RSHIFT	44, ror, r7, 0          @ unchanged, C unchanged
	RSHIFT	46, ror, r7, 4
	mov	r3, #0x100              @ only the bottom byte counts: by 0
	FLAGS0
	movs	r1, r0, lsl r3
	RES	48, r1
	mrs	r2, cpsr
	RES	49, r2

	@ ---------------- MSR ----------------
	msr	cpsr_f, #0x20000000     @ flags only, immediate
	mrs	r2, cpsr
	RES	50, r2
	msr	cpsr_f, #0xF0000000
	mrs	r2, cpsr
	RES	51, r2
	ldr	r0, =0x5000001F         @ flags only from a register: mode bits ignored
	msr	cpsr_f, r0
	mrs	r2, cpsr
	RES	52, r2
	ldr	r0, =0x900000D3         @ whole CPSR
	msr	cpsr_fc, r0
	mrs	r2, cpsr
	RES	53, r2
	ldr	r0, =0x000000D1         @ whole SPSR_svc
	msr	spsr_fc, r0
	mov	r1, #0xA0000000         @ SPSR flags only, register
	msr	spsr_f, r1
	mrs	r2, spsr
	RES	54, r2
	msr	spsr_f, #0x40000000     @ SPSR flags only, immediate
	mrs	r2, spsr
	RES	55, r2

	@ ---------------- word loads from unaligned addresses ----------------
	ldr	r4, =data
	ldr	r1, [r4, #0]
	RES	56, r1
	ldr	r1, [r4, #1]
	RES	57, r1
	ldr	r1, [r4, #2]
	RES	58, r1
	ldr	r1, [r4, #3]
	RES	59, r1
	ldrb	r1, [r4, #0]
	RES	60, r1
	ldrb	r1, [r4, #1]
	RES	61, r1
	ldrb	r1, [r4, #2]
	RES	62, r1
	ldrb	r1, [r4, #3]
	RES	63, r1
	ldr	r4, =swpdata
	add	r2, r4, #2
	mov	r3, #0x55
	swp	r1, r3, [r2]            @ loads rotated, stores the word unrotated
	RES	64, r1
	ldr	r1, [r4]
	RES	65, r1
	ldr	r4, =ldmdata
	add	r2, r4, #1
	ldmia	r2, {r3, r5}            @ LDM: no rotation
	RES	66, r3
	RES	67, r5

	@ ---------------- STM / LDM with the S bit ----------------
	ldr	r0, =0x000000D3
	msr	cpsr_fc, r0             @ SVC, flags clear
	mov	r8, #0x11               @ User r8 (shared with SVC)
	ldr	r4, =usr14
	ldmia	r4, {r14}^              @ User r14 = 0x66
	mov	r0, #0xD1
	msr	cpsr_fc, r0             @ FIQ mode
	ldr	r12, =RES               @ r12_fiq (R8-R14 are banked in FIQ mode)
	mov	r8, #0x22               @ r8_fiq
	mov	r14, #0x44              @ r14_fiq
	ldr	r4, =stmbuf
	stmia	r4, {r8, r14}^          @ User r8, r14
	ldr	r1, [r4, #0]
	RES	68, r1
	ldr	r1, [r4, #4]
	RES	69, r1
	add	r4, r4, #8
stm_pc:
	stmia	r4, {r8, pc}^           @ still the User r8
	ldr	r1, [r4, #0]
	RES	70, r1
	ldr	r2, [r4, #4]            @ stored PC: the STM's address plus 12
	adr	r3, stm_pc
	add	r3, r3, #12
	sub	r1, r2, r3
	RES	71, r1
	ldr	r0, =0x200000D3         @ SPSR_fiq: SVC, C set
	msr	spsr_fc, r0
	ldr	r4, =ldmret
	adr	r1, after_ldm
	str	r1, [r4, #4]
	ldmia	r4, {r8, pc}^           @ r8_fiq = 0x77, return to SVC with CPSR = SPSR_fiq
	b	.
after_ldm:
	mrs	r2, cpsr
	RES	72, r2
	RES	73, r8                  @ SVC sees the User r8
	mov	r0, #0xD1
	msr	cpsr_fc, r0
	RES	74, r8                  @ r8_fiq
	mov	r0, #0xD3
	msr	cpsr_fc, r0

	@ ---------------- undefined instruction trap ----------------
	msr	cpsr_f, #0x80000000     @ N set
und1:
	.word	0xE6000010              @ undefined (cond AL)
	mrs	r2, cpsr                @ restored by MOVS PC,R14
	RES	75, r2
	ldr	r9, =UNDLOG
	ldr	r1, [r9, #0]
	RES	76, r1                  @ CPSR in the handler
	ldr	r1, [r9, #4]
	RES	77, r1                  @ SPSR_und
	ldr	r1, [r9, #8]
	adr	r3, und1
	add	r3, r3, #4
	sub	r1, r1, r3
	RES	78, r1                  @ R14_und - (address + 4)
	FLAGS0
	.word	0x06000010              @ undefined, condition EQ false: no trap
	.word	0xEE100F10              @ MRC p15,0,r0,c0,c0: no coprocessor, traps
	.word	0xEE000000              @ CDP p0: traps
	.word	0xED900000              @ LDC p0,c0,[r0]: traps
	.word	0xE0000ED1              @ multiply with bit 6 set: not defined, does not trap
	ldr	r9, =UNDCNT
	ldr	r1, [r9]
	RES	79, r1                  @ traps taken: 1 + 3

	@ ---------------- R15 written with bits 1:0 set ----------------
	@ (datasheet 3.3: when R15 is read, bits [1:0] are zero). The expected
	@ values are the labels, not computed with the PC.
	ldr	r0, =pcw_mov + 3
	mov	pc, r0                  @ data processing
	b	.
pcw_mov:
	mov	r1, pc
	RES	81, r1                  @ pcw_mov + 8
	ldr	r1, pcw_lit             @ PC relative
	RES	82, r1
	bl	pcw_sub
pcw_bl:
	ldr	r4, =pcw_ptr
	ldr	pc, [r4]                @ LDR: pcw_ldr + 3
	b	.
pcw_ldr:
	mov	r1, pc
	RES	84, r1                  @ pcw_ldr + 8
	ldr	r1, pcw_lit
	RES	85, r1
	ldr	r4, =pcw_ptr + 4
	ldmia	r4, {pc}                @ LDM: pcw_ldm + 2
	b	.
pcw_ldm:
	mov	r1, pc
	RES	86, r1                  @ pcw_ldm + 8
	ldr	r1, pcw_lit
	RES	87, r1
	b	pcw_end
pcw_sub:
	RES	83, r14                 @ R14 = pcw_bl
	mov	pc, r14
pcw_lit: .word	0x12345678
pcw_ptr: .word	pcw_ldr + 3, pcw_ldm + 2
pcw_end:

	@ ---------------- LDRT / STRT: a User mode transfer ----------------
	@ (datasheet 4.7.1: in a post-indexed transfer the W bit forces
	@ non-privileged mode for the transfer cycle; nTRANS LOW means User mode)
	ldr	r4, =TRANS_A
	mov	r1, #0x5A
	ldr	r3, =0x00001234
	str	r1, [r4, #0x00]         @ A000 STR: privileged
	add	r5, r4, #0x04
	strt	r1, [r5], #4            @ A004 STRT: User; r5 = A008
	str	r3, [r4, #0x08]
	ldrt	r2, [r5], #4            @ A008 LDRT: User; r5 = A00C
	RES	88, r2                  @ 0x1234
	strbt	r1, [r5], #1            @ A00C STRBT: User; r5 = A00D
	RES	89, r5
	add	r6, r4, #0x10
	mov	r7, #4
	ldrbt	r2, [r6], r7            @ A010 LDRBT, register offset: User; r6 = A014
	RES	90, r2                  @ byte 0 of A010 (never written: MOV r0,r0)
	RES	91, r6
	mov	r10, r4
	ldr	r2, [r10, #0x14]!       @ A014 pre-indexed with write-back: privileged
	RES	92, r10
	add	r11, r4, #0x18
	ldr	r2, [r11], #4           @ A018 post-indexed, W clear: privileged
	RES	93, r11

	@ ---------------- MSR in User mode ----------------
	mov	r0, #0x10
	msr	cpsr_fc, r0             @ User mode
	ldr	r0, =0x700000D3
	msr	cpsr_fc, r0             @ User mode: the flags only
	mrs	r2, cpsr
	RES	80, r2
	str	r1, [r4, #0x1C]         @ A01C STR in User mode
	ldr	r2, [r4, #0x20]         @ A020 LDR in User mode
	swi	0
after_user:
	ldr	r4, =TRANS_LOG          @ nTRANS of each access to TRANS_A + n
	ldr	r1, [r4, #0x00]
	RES	94, r1
	ldr	r1, [r4, #0x04]
	RES	95, r1
	ldr	r1, [r4, #0x08]
	RES	96, r1
	ldr	r1, [r4, #0x0C]
	RES	97, r1
	ldr	r1, [r4, #0x10]
	RES	98, r1
	ldr	r1, [r4, #0x14]
	RES	99, r1
	ldr	r1, [r4, #0x18]
	RES	100, r1
	ldr	r1, [r4, #0x1C]
	RES	101, r1
	ldr	r1, [r4, #0x20]
	RES	102, r1
	ldr	r4, =TRANS_A            @ (these reads are logged, after the readback)
	ldr	r1, [r4, #0x04]
	RES	103, r1                 @ stored by STRT
	ldr	r1, [r4, #0x0C]
	RES	104, r1                 @ byte stored by STRBT

	ldr	r0, =DONE
	str	r0, [r0]
	b	.

	.ltorg

	.align	2
data:	.word	0x11223344
swpdata: .word	0xA1B2C3D4
ldmdata: .word	0xAABBCCDD, 0x01020304
usr14:	.word	0x00000066
stmbuf:	.word	0, 0, 0, 0
ldmret:	.word	0x00000077, 0

	@ ---------------- expected results (at 0x7000, read by tb_arm6) ----------------
	.org	0x7000
n_expected:
	.word	105
expected:
	.word	0x00000000, 0x600000D3      @ 0-1   LSR #32
	.word	0xFFFFFFFF, 0xA00000D3      @ 2-3   ASR #32
	.word	0x80000000, 0xA00000D3      @ 4-5   RRX
	.word	0xFFFFFFFF, 0x800000D3      @ 6-7   LSL #0: C unchanged
	.word	0xFFFFFFFF, 0x800000D3      @ 8-9   LSL r=0
	.word	0xFFFFFFFE, 0xA00000D3      @ 10-11 LSL r=1
	.word	0x80000000, 0xA00000D3      @ 12-13 LSL r=31
	.word	0x00000000, 0x600000D3      @ 14-15 LSL r=32: C = bit 0
	.word	0x00000000, 0x400000D3      @ 16-17 LSL r=33: C = 0
	.word	0x00000000, 0x400000D3      @ 18-19 LSL r=64
	.word	0x00000000, 0x400000D3      @ 20-21 LSL r=255
	.word	0x00000000, 0x600000D3      @ 22-23 LSR r=32: C = bit 31
	.word	0x00000000, 0x400000D3      @ 24-25 LSR r=33
	.word	0x00000000, 0x400000D3      @ 26-27 LSR r=64
	.word	0x00000000, 0x400000D3      @ 28-29 LSR r=96
	.word	0xFFFFFFFF, 0xA00000D3      @ 30-31 ASR r=32
	.word	0xFFFFFFFF, 0xA00000D3      @ 32-33 ASR r=64
	.word	0xFFFFFFFF, 0xA00000D3      @ 34-35 ASR r=255
	.word	0x00000000, 0x400000D3      @ 36-37 ASR r=64, positive
	.word	0x80000001, 0xA00000D3      @ 38-39 ROR r=32: C = bit 31
	.word	0xC0000000, 0xA00000D3      @ 40-41 ROR r=33 = ROR 1
	.word	0x80000001, 0xA00000D3      @ 42-43 ROR r=64 = ROR 32
	.word	0x80000001, 0x800000D3      @ 44-45 ROR r=0: C unchanged
	.word	0x18000000, 0x000000D3      @ 46-47 ROR r=4
	.word	0xFFFFFFFF, 0x800000D3      @ 48-49 LSL r=256: by 0
	.word	0x200000D3                  @ 50    MSR CPSR_flg,#
	.word	0xF00000D3                  @ 51    MSR CPSR_flg,#
	.word	0x500000D3                  @ 52    MSR CPSR_flg,Rm: mode bits ignored
	.word	0x900000D3                  @ 53    MSR CPSR_all,Rm
	.word	0xA00000D1                  @ 54    MSR SPSR_flg,Rm keeps the control bits
	.word	0x400000D1                  @ 55    MSR SPSR_flg,#
	.word	0x11223344                  @ 56    LDR +0
	.word	0x44112233                  @ 57    LDR +1: rotated right 8
	.word	0x33441122                  @ 58    LDR +2: rotated right 16
	.word	0x22334411                  @ 59    LDR +3: rotated right 24
	.word	0x00000011, 0x00000022      @ 60-61 LDRB +0, +1
	.word	0x00000033, 0x00000044      @ 62-63 LDRB +2, +3
	.word	0xC3D4A1B2                  @ 64    SWP +2: loaded rotated
	.word	0x00000055                  @ 65    SWP: the word stored unrotated
	.word	0xAABBCCDD, 0x01020304      @ 66-67 LDM from base +1: not rotated
	.word	0x00000011, 0x00000066      @ 68-69 STM^ {r8,r14}: User r8, r14
	.word	0x00000011                  @ 70    STM^ {r8,pc}: User r8
	.word	0x00000000                  @ 71    stored PC = STM + 12
	.word	0x200000D3                  @ 72    LDM^ {..,pc}: CPSR = SPSR_fiq
	.word	0x00000011                  @ 73    SVC r8 = User r8
	.word	0x00000077                  @ 74    r8_fiq loaded
	.word	0x800000D3                  @ 75    after the trap: CPSR restored
	.word	0x800000DB                  @ 76    in the handler: Undefined mode, I set
	.word	0x800000D3                  @ 77    SPSR_und
	.word	0x00000000                  @ 78    R14_und = address + 4
	.word	0x00000004                  @ 79    traps: undefined, MRC, CDP, LDC
	.word	0x70000010                  @ 80    MSR CPSR_all in User mode: flags only
	.word	pcw_mov + 8                 @ 81    MOV PC,#x+3: R15 reads x+8
	.word	0x12345678                  @ 82    PC relative load
	.word	pcw_bl                      @ 83    BL: R14
	.word	pcw_ldr + 8                 @ 84    LDR PC with x+3
	.word	0x12345678                  @ 85
	.word	pcw_ldm + 8                 @ 86    LDM {PC} with x+2
	.word	0x12345678                  @ 87
	.word	0x00001234                  @ 88    LDRT data
	.word	0x0000A00D                  @ 89    STRBT post-index write-back
	.word	0x000000E1                  @ 90    LDRBT data
	.word	0x0000A014                  @ 91    LDRBT register post-index write-back
	.word	0x0000A014                  @ 92    LDR pre-indexed write-back
	.word	0x0000A01C                  @ 93    LDR post-indexed write-back
	.word	1                           @ 94    nTRANS: STR in SVC mode
	.word	0                           @ 95    STRT
	.word	0                           @ 96    LDRT
	.word	0                           @ 97    STRBT
	.word	0                           @ 98    LDRBT
	.word	1                           @ 99    LDR pre-indexed, write-back: not T
	.word	1                           @ 100   LDR post-indexed, W clear
	.word	0                           @ 101   STR in User mode
	.word	0                           @ 102   LDR in User mode
	.word	0x0000005A                  @ 103   STRT stored the word
	.word	0x5AA00000                  @ 104   STRBT stored byte 0 (big endian)
