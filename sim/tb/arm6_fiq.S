@ ARM60 interrupt checks for tb_arm6 (big-endian, ARMv3): a video-decoder-like
@ kernel run once with interrupts masked and once with FIQs and IRQs injected
@ by the testbench (+fiq, +irq) at pseudo-random times; the outputs must be
@ the same.
@
@ The kernel is modelled on Killing Time's EZFlix decoder as Opera executes
@ it: User mode with FIQ enabled, packed-byte AND/ORR/ADD/SUB with immediate
@ shifts, masks kept in r8-r11, the input stream read with LDMIA r12!, the
@ output stored with STMIA r13!/STMIA r13, LDMIB r14!/STMDB r14, a few
@ conditional instructions, no stack. The FIQ handler alternates between a
@ short path (its banked registers only) and a task-switch-like path that
@ saves the User bank with STM^, clobbers every register and restores the
@ bank with LDM^; both return with SUBS PC, R14, #4. The IRQ handler pushes
@ and pops on the IRQ stack.
@
@ Results: 5 checksums of the output after the second (interrupted) pass at
@ RES; the same after the first pass as the expected table at 0x7000 (count,
@ then the values), compared by tb_arm6 when DONE is written. FIQCNT/IRQCNT
@ count the interrupts taken.
@
@ Copyright (c) 2026 Adam Polkosnik
@ SPDX-License-Identifier: GPL-3.0-or-later

	.syntax unified
	.arm

	.equ RES,       0x8000      @ results (pass 2)
	.equ EXP,       0x7000      @ count, then the expected values (pass 1)
	.equ DONE,      0xFFFC      @ written when finished
	.equ FIQCNT,    0x9000      @ FIQs taken
	.equ IRQCNT,    0x9004      @ IRQs taken
	.equ STREAM,    0x2000      @ input stream, 1024 words
	.equ OUT,       0x4000      @ output, 1536 words (cleared before each pass)
	.equ OUT2,      0x4800      @ ... the second pointer's area, inside OUT
	.equ OUTW,      1536
	.equ SVC_STACK, 0x6E00
	.equ IRQ_STACK, 0x6F00
	.equ FIQ_STACK, 0x6FF0
	.equ ITER,      200

	.org 0
	b	reset                   @ 0x00 reset
	b	.                       @ 0x04 undefined instruction
	b	swi_handler             @ 0x08 SWI
	b	.                       @ 0x0C prefetch abort
	b	.                       @ 0x10 data abort
	b	.                       @ 0x14
	b	irq_handler             @ 0x18 IRQ
	b	fiq_handler             @ 0x1C FIQ

swi_handler:                    @ leaves User mode: continue after the SWI in SVC mode
	mov	pc, r14

irq_handler:
	stmfd	r13!, {r0, r1, r2, r3}
	ldr	r0, =IRQCNT
	ldr	r1, [r0]
	add	r1, r1, #1
	str	r1, [r0]
	mvn	r2, #0
	mov	r3, #0x33
	ldmfd	r13!, {r0, r1, r2, r3}
	subs	pc, r14, #4

fiq_handler:                    @ r8-r14 are FIQ's own
	ldr	r8, =FIQCNT
	ldr	r9, [r8]
	add	r9, r9, #1
	str	r9, [r8]
	tst	r9, #1
	beq	1f
	mov	r10, #0                 @ short path: FIQ registers only
	mvn	r11, #0
	mov	r12, #0x55
	subs	pc, r14, #4
1:	sub	r13, r13, #60           @ task switch: the User bank saved ...
	stmia	r13, {r0-r14}^
	mov	r0, #0                  @ ... everything clobbered ...
	mvn	r1, #0
	mov	r2, #0x11
	mov	r3, #0x22
	mov	r4, #0x33
	mov	r5, #0x44
	mov	r6, #0x55
	mov	r7, #0x66
	mov	r10, #0x77
	mov	r11, #0x88
	mov	r12, #0x99
	ldmia	r13, {r0-r14}^          @ ... and restored
	mov	r10, r10                @ (no banked register right after LDM^)
	add	r13, r13, #60
	subs	pc, r14, #4

reset:
	mov	r0, #0xD2               @ IRQ mode: its stack
	msr	cpsr_fc, r0
	ldr	r13, =IRQ_STACK
	mov	r0, #0xD1               @ FIQ mode: its stack
	msr	cpsr_fc, r0
	ldr	r13, =FIQ_STACK
	mov	r0, #0xD3               @ SVC
	msr	cpsr_fc, r0
	ldr	r13, =SVC_STACK
	mov	r0, #0
	ldr	r1, =FIQCNT
	str	r0, [r1]
	str	r0, [r1, #4]
	@ the stream: 1024 words from an LFSR
	ldr	r1, =STREAM
	ldr	r2, =0xACE1F00D
	mov	r3, #1024
2:	str	r2, [r1], #4
	movs	r2, r2, lsr #1
	ldr	r4, =0xD0000001
	eorcs	r2, r2, r4
	subs	r3, r3, #1
	bne	2b

	@ ---- pass 1: User mode, IRQ and FIQ masked ----
	bl	clear_out
	mov	r0, #0xD0
	msr	cpsr_fc, r0
	bl	kernel
	swi	0
	ldr	r0, =EXP
	mov	r1, #5
	str	r1, [r0], #4
	bl	checksums

	@ ---- pass 2: User mode, IRQ and FIQ enabled (the testbench injects them) ----
	bl	clear_out
	mov	r0, #0x10
	msr	cpsr_fc, r0
	bl	kernel
	swi	0
	ldr	r0, =RES
	bl	checksums

	ldr	r0, =DONE
	str	r0, [r0]
	b	.

clear_out:
	ldr	r1, =OUT
	mov	r2, #0
	mov	r3, #OUTW
3:	str	r2, [r1], #4
	subs	r3, r3, #1
	bne	3b
	mov	pc, lr

@ 5 checksums of OUT at r0: sum, xor, a rotating hash, the first word, the last
checksums:
	ldr	r1, =OUT
	mov	r2, #0
	mov	r3, #0
	mov	r4, #0
	mov	r5, #OUTW
4:	ldr	r6, [r1], #4
	add	r2, r2, r6
	eor	r3, r3, r6
	eor	r4, r6, r4, ror #27
	subs	r5, r5, #1
	bne	4b
	str	r2, [r0], #4
	str	r3, [r0], #4
	str	r4, [r0], #4
	ldr	r1, =OUT
	ldr	r6, [r1]
	str	r6, [r0], #4
	ldr	r1, =OUT + OUTW * 4 - 4
	ldr	r6, [r1]
	str	r6, [r0], #4
	mov	pc, lr

@ the kernel (User mode; r14 is a data pointer, so it returns through a word)
kernel:
	ldr	r0, =kret
	str	lr, [r0]
	ldr	r12, =STREAM
	ldr	r13, =OUT
	ldr	r14, =OUT2
	ldr	r8, =0x7E7E7E7E
	ldr	r9, =0xFF000000
	ldr	r11, =0x40404040
	mov	r7, #ITER
5:	ldmia	r12!, {r0, r2, r3, r5}
	and	r4, r0, r8
	add	r4, r4, r2, lsr #5
	orr	r4, r4, r9
	sub	r6, r3, r4, lsl #3
	and	r6, r6, r8
	orr	r10, r6, r5, lsr #8
	add	r10, r10, r11
	bic	r10, r10, r9
	and	r1, r5, r8, lsr #1
	add	r1, r1, r0, lsl #16
	sub	r1, r1, r2, lsr #16
	orr	r1, r1, r3, lsl #24
	and	r2, r2, r4, lsr #24
	add	r3, r3, r1, lsl #5
	sub	r5, r5, r10, lsl #8
	and	r5, r5, r8
	orr	r0, r0, r6, lsr #2
	stmia	r13!, {r0, r2, r3, r5}
	stmia	r13, {r4, r6, r10}
	add	r13, r13, #12
	ldmib	r14!, {r10, r11}
	add	r10, r10, r4
	eor	r11, r11, r6
	stmdb	r14, {r10, r11}
	ldr	r11, =0x40404040
	cmp	r4, r6
	addne	r0, r0, #1
	sublt	r2, r2, r4
	moveq	r3, r6
	str	r0, [r14], #8
	str	r2, [r14, #-4]
	subs	r7, r7, #1
	bne	5b
	ldr	r1, =jtab               @ LDM with the base in the list and PC in it
	ldmia	r1, {r1, pc}
jtab:	.word	0x12345678
	.word	6f
6:	str	r1, [r13], #4
	ldr	r0, =kret
	ldr	pc, [r0]

	.ltorg
	.align	2
kret:	.word	0
