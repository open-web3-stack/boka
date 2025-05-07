#include <sys/mman.h>
#include <fcntl.h>
#include <stdint.h>
#include <string.h>
#include <stdio.h>
#include "ctools.h"

#if defined(__aarch64__)

// Fixed encoding for MOVZ: base opcode 0xD2800000 for 64-bit immediate move with zero.
static uint32_t encodeMovZ(unsigned int xReg, unsigned int imm16, unsigned int shift)
{
    uint32_t insn = 0xD2800000;
    insn |= ((shift & 3) << 21);
    insn |= ((imm16 & 0xFFFF) << 5);
    insn |= (xReg & 0x1F);
    return insn;
}

// Fixed encoding for MOVK: base opcode 0xF2A00000 for inserting a 16-bit constant.
static uint32_t encodeMovK(unsigned int xReg, unsigned int imm16, unsigned int shift)
{
    uint32_t insn = 0xF2A00000;
    insn |= ((shift & 3) << 21);
    insn |= ((imm16 & 0xFFFF) << 5);
    insn |= (xReg & 0x1F);
    return insn;
}

// Encode "ldr wReg, [xReg]" with immediate offset zero.
static uint32_t encodeLdrWRegXReg(unsigned int wReg, unsigned int xReg)
{
    uint32_t insn = 0xB9400000;
    insn |= ((xReg & 0x1F) << 5);
    insn |= (wReg & 0x1F);
    return insn;
}

// Encode "add wDest, wSrc1, wSrc2" (shifted register variant with shift=0).
static uint32_t encodeAddWReg(unsigned int wd, unsigned int wn, unsigned int wm)
{
    uint32_t insn = 0x0B000000;
    insn |= ((wm & 0x1F) << 16);
    insn |= ((wn & 0x1F) << 5);
    insn |= (wd & 0x1F);
    return insn;
}

// Encode "add xDest, xSrc1, xSrc2" (64‑bit, shifted register, shift = 0)
static uint32_t encodeAddXReg(unsigned int xd, unsigned int xn, unsigned int xm)
{
    uint32_t insn = 0x8B000000;          /* base opcode for 64‑bit ADD (shifted register) */
    insn |= ((xm & 0x1F) << 16);         /* Rm */
    insn |= ((xn & 0x1F) << 5);          /* Rn */
    insn |= (xd & 0x1F);                 /* Rd */
    return insn;
}

// Encode "str wReg, [xReg]" with immediate offset zero.
static uint32_t encodeStrWRegXReg(unsigned int wReg, unsigned int xReg)
{
    uint32_t insn = 0xB9000000;
    insn |= ((xReg & 0x1F) << 5);
    insn |= (wReg & 0x1F);
    return insn;
}

// Encode "ret"
static uint32_t encodeRet()
{
    return 0xD65F03C0;
}

// Build a 64-bit constant into register xReg using MOVZ/MOVK.
static int emitLoadAddress64(unsigned char **p, unsigned int xReg, uint64_t addr)
{
    uint32_t insn;
    insn = encodeMovZ(xReg, (uint16_t)(addr & 0xFFFF), 0);
    memcpy(*p, &insn, 4);
    *p += 4;
    insn = encodeMovK(xReg, (uint16_t)((addr >> 16) & 0xFFFF), 1);
    memcpy(*p, &insn, 4);
    *p += 4;
    insn = encodeMovK(xReg, (uint16_t)((addr >> 32) & 0xFFFF), 2);
    memcpy(*p, &insn, 4);
    *p += 4;
    insn = encodeMovK(xReg, (uint16_t)((addr >> 48) & 0xFFFF), 3);
    memcpy(*p, &insn, 4);
    *p += 4;
    return 16;
}

int emitAddExample(void *codePtr)
{
    unsigned char *p = (unsigned char *)codePtr;

    /* add x0, x0, x1 */
    uint32_t insn = encodeAddXReg(0, 0, 1);
    memcpy(p, &insn, 4);
    p += 4;

    /* ret */
    insn = encodeRet();
    memcpy(p, &insn, 4);
    p += 4;

    return (int)(p - (unsigned char *)codePtr);   /* should be 8 bytes */
}

#else
// Fallback for unsupported architectures
int emitAddExample(void *codePtr)
{
    (void)codePtr;
    return 0;
}
#endif

int ctools_shm_open(const char *name, int oflag, mode_t mode) {
    return shm_open(name, oflag, mode);
}
