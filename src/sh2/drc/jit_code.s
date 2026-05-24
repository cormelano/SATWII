
#include <ppc-asm.h>
#include <ogc/machine/asm.h>

	.extern _jit_GenBlock
	.extern HashGet
	.extern sh2_HandleInterrupt

//r3 contains sh2 context and r4 the number of cycles to exectue
FUNC_START(sh2_DrcExec)
	stwu r1, -92(r1)
	mflr r0
	stw r0, (92+4)(r1)
	stmw r14, (92-((31-14)*4))(r1)	//store host regs
	mr r31, r3						//move to sh2 context (r31)
	lwz r5, (25*4)(r31)  			//load cycles
	subf r5, r4, r5 				//subtract the cycles we need to run
	stw r5, (25*4)(r31)				//store cycles
	bl sh2_HandleInterrupt			//handle interrupts at the start
	//Load sh2 regs
	lwz r14, (0*4)(r31)
	lwz r15, (1*4)(r31)
	lwz r16, (2*4)(r31)
	lwz r17, (3*4)(r31)
	lwz r18, (4*4)(r31)
	lwz r19, (5*4)(r31)
	lwz r20, (6*4)(r31)
	lwz r21, (7*4)(r31)
	lwz r22, (8*4)(r31)
	lwz r23, (9*4)(r31)
	lwz r24, (10*4)(r31)
	lwz r25, (11*4)(r31)
	lwz r26, (12*4)(r31)
	lwz r27, (13*4)(r31)
	lwz r28, (14*4)(r31)
	lwz r29, (15*4)(r31)			//load R15 register
	lwz r30, (16*4)(r31)			//load SR register
	li r3, 0						//clear r3
	b jit_endblock_test
FUNC_END(sh2_DrcExec)


FUNC_START(jit_exit)
	//Store all the sh2 regs
	stw r14, (0*4)(r31)
	stw r15, (1*4)(r31)
	stw r16, (2*4)(r31)
	stw r17, (3*4)(r31)
	stw r18, (4*4)(r31)
	stw r19, (5*4)(r31)
	stw r20, (6*4)(r31)
	stw r21, (7*4)(r31)
	stw r22, (8*4)(r31)
	stw r23, (9*4)(r31)
	stw r24, (10*4)(r31)
	stw r25, (11*4)(r31)
	stw r26, (12*4)(r31)
	stw r27, (13*4)(r31)
	stw r28, (14*4)(r31)
	stw r29, (15*4)(r31)
	stw r30, (16*4)(r31) //SR
	//Load host regs and return to SH2Exec
	lwz r0, (92+4)(r1)
	mtlr r0
	lmw r14, (92 - ((31-14)*4))(r1)
	addi r1, r1, 92
	blr
FUNC_END(jit_exit)

//In r3 are the number cycles that are added to the sh2 cycles
FUNC_START(jit_endblock_test)
	//check if we need to exit because we finished cycles
	lwz r4, (25*4)(r31)  			//load cycles
	add. r4, r4, r3 				//update and check if cycles >= 0
	stw r4, (25*4)(r31)				//store cycles
	bc 0b00100, 0, jit_exit			//move to JIT exit if cycles >= 0
	lwz r3, (17*4)(r31)				//get the next block form PC
	bl HashGet
	lwz r4, (17*4)(r31)				//reload PC if block was not found
	lis r5, _jit_GenBlock@ha		//load _jit_GenBlock()
	ori r5, r5, _jit_GenBlock@l
	mtctr r5
	lwz r5, 0(r3)					//Get block address
	cmpi cr0,0,r5,0
	bcctrl 0b01100, 2 				//Generate block if not found
	lwz r3, 0(r3)					//Get block address
	mtctr r3
	bcctr 0b10100, 1				//move to exit if cycles > 0
FUNC_END(jit_endblock_test)

//================================
//Implementation of DIV1/MACL/MACW
//================================

//Use r3 and r4 for rn and rm
FUNC_START(jit_div1)
	mtcrf	0x07, r30
	creqv	3, 31-9, 31-8	//(M == oldQ)
	bc	    0b00100, 3,	div1_skip_rm_neg // do not negate if false
	neg     r4, r4					//Rm = -Rm
div1_skip_rm_neg:
	mtcrf	0x80, r3			//Q = MSB(Rn)
	crxor   31-8, 0, 31-8		//Q ^= oldQ
	rlwimi  r30, r3, 1, 0, 30	// Rn = (Rn << 1) | T
	addc    r3, r30, r4			// Rn += Rm
	mcrxr   0					// Q ^= carry(Rn += Rm)
	creqv   31-8, 2, 31-8
	creqv   31, 31-8, 31-9		//T = (Q == M)
	mfcr    r5
	andi.	r30, r5, 0xFFF
	blr
FUNC_END(jit_div1)


//Use r3 and r4 for @rn and @rm
FUNC_START(jit_macl)
	mullw r8, r3, r4			// calc low(rn*rm)
	xor r9, r3, r4				// xor rn * rm and MSB for flipping saturation
	srawi r9, r9, 31			// extend MSB
	lwz r6, (22*4)(r31)  		// load macl
	mulhw r7, r3, r4			// calc high(rn*rm)
	addc r6, r6, r8				// result low macl + low(rn*rm)
	mtcrf 0x01, r30		 		// is S set? move S to CR
	lwz r5, (21*4)(r31)  		// load mach
	adde r5, r5, r7				// result high macl + high(rn*rm)
	addic. r8, r5, -0x8000		// add 0xFFFF8000_00000000 to result
	crandc 0, 30, 0				// is S set and is it negative?
	bc	0b00100, 0,	macl_skip_saturation // branch to end if false
	xori r5, r9, 0x7FFF
	not r6, r9
macl_skip_saturation:
	stw r5, (21*4)(r31)  		// store mach
	stw r6, (22*4)(r31)  		// store macl
	blr
FUNC_END(jit_macl)


//Use r3 and r4 for @rn and @rm
FUNC_START(jit_macw)
	mullw r3, r3, r4
	lwz r6, (22*4)(r31)  		//load macl
	lwz r7, (21*4)(r31)  		//load mach
	andi. r5, r30, 0x2			//Check for saturation (S bit)
	bc 0b01100, 1, macw_saturate
	addc r6, r6, r3 			//TODO: Add lower, this can be optimized with addco
	addze r7, r7,
	stw r6, (22*4)(r31)  			//store macl
	stw r7, (21*4)(r31)  			//store mach
	blr
macw_saturate:
	addo r3, r6, r3
	mfxer r5
	rlwinm r5, r5, 2, 31, 31
	neg r5, r5
	andc r6, r3, r5
	srawi r3, r3, 31
	addis r3, r3, 0x8000
	and r3, r3, r5
	or r6, r6, r5
	ori r7, r5, 0x1
	stw r6, (22*4)(r31)  			//store macl
	stw r7, (21*4)(r31)  			//store mach
	blr
FUNC_END(jit_macw)