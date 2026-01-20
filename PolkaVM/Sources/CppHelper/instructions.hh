#pragma once

#include <cstdint>
#include "opcodes.hh"

struct RegisterIndex {
    uint8_t value;
};

namespace Instructions {

// MARK: Instructions without Arguments (5.1)
struct Trap {
    static const uint8_t opcode;
    Trap();
};
struct Fallthrough {
    static const uint8_t opcode;
    Fallthrough();
};

// MARK: Instructions with Arguments of One Immediate (5.2)
struct Ecalli {
    static const uint8_t opcode;
    uint32_t callIndex;
};

// MARK: Instructions with Arguments of One Register and One Extended Width Immediate (5.3)
struct LoadImm64 {
    static const uint8_t opcode;
    RegisterIndex reg;
    uint64_t value;
};

// MARK: Instructions with Arguments of Two Immediates (5.4)
struct StoreImmU8 {
    static const uint8_t opcode;
    uint32_t address;
    uint8_t value;
};

struct StoreImmU16 {
    static const uint8_t opcode;
    uint32_t address;
    uint16_t value;
};

struct StoreImmU32 {
    static const uint8_t opcode;
    uint32_t address;
    uint32_t value;
};

struct StoreImmU64 {
    static const uint8_t opcode;
    uint32_t address;
    uint64_t value;
};

// MARK: Instructions with Arguments of One Offset (5.5)
struct Jump {
    static const uint8_t opcode;
    uint32_t offset;
};

// MARK: Instructions with Arguments of One Register &amp; One Immediate (5.6)
struct JumpInd {
    static const uint8_t opcode;
    RegisterIndex reg;
    uint32_t offset;
};

struct LoadImm {
    static const uint8_t opcode;
    RegisterIndex reg;
    uint32_t value;
};

struct LoadU8 {
    static const uint8_t opcode;
    RegisterIndex reg;
    uint32_t address;
};

struct LoadI8 {
    static const uint8_t opcode;
    RegisterIndex reg;
    uint32_t address;
};

struct LoadU16 {
    static const uint8_t opcode;
    RegisterIndex reg;
    uint32_t address;
};

struct LoadI16 {
    static const uint8_t opcode;
    RegisterIndex reg;
    uint32_t address;
};

struct LoadU32 {
    static const uint8_t opcode;
    RegisterIndex reg;
    uint32_t address;
};

struct LoadI32 {
    static const uint8_t opcode;
    RegisterIndex reg;
    uint32_t address;
};

struct LoadU64 {
    static const uint8_t opcode;
    RegisterIndex reg;
    uint32_t address;
};

struct StoreU8 {
    static const uint8_t opcode;
    RegisterIndex reg;
    uint32_t address;
};

struct StoreU16 {
    static const uint8_t opcode;
    RegisterIndex reg;
    uint32_t address;
};

struct StoreU32 {
    static const uint8_t opcode;
    RegisterIndex reg;
    uint32_t address;
};

struct StoreU64 {
    static const uint8_t opcode;
    RegisterIndex reg;
    uint32_t address;
};

// MARK: Instructions with Arguments of One Register &amp; Two Immediates (5.7)
struct StoreImmIndU8 {
    static const uint8_t opcode;
    RegisterIndex reg;
    uint32_t address;
    uint8_t value;
};

struct StoreImmIndU16 {
    static const uint8_t opcode;
    RegisterIndex reg;
    uint32_t address;
    uint16_t value;
};

struct StoreImmIndU32 {
    static const uint8_t opcode;
    RegisterIndex reg;
    uint32_t address;
    uint32_t value;
};

struct StoreImmIndU64 {
    static const uint8_t opcode;
    RegisterIndex reg;
    uint32_t address;
    uint64_t value;
};

// MARK: Instructions with Arguments of One Register, One Immediate and One Offset (5.8)
struct LoadImmJump {
    static const uint8_t opcode;
    RegisterIndex reg;
    uint32_t value;
    uint32_t offset;
};

struct BranchEqImm {
    static const uint8_t opcode;
    RegisterIndex reg;
    uint64_t value;
    uint32_t offset;
};

struct BranchNeImm {
    static const uint8_t opcode;
    RegisterIndex reg;
    uint64_t value;
    uint32_t offset;
};

struct BranchLtUImm {
    static const uint8_t opcode;
    RegisterIndex reg;
    uint64_t value;
    uint32_t offset;
};

struct BranchLeUImm {
    static const uint8_t opcode;
    RegisterIndex reg;
    uint64_t value;
    uint32_t offset;
};

struct BranchGeUImm {
    static const uint8_t opcode;
    RegisterIndex reg;
    uint64_t value;
    uint32_t offset;
};

struct BranchGtUImm {
    static const uint8_t opcode;
    RegisterIndex reg;
    uint64_t value;
    uint32_t offset;
};

struct BranchLtSImm {
    static const uint8_t opcode;
    RegisterIndex reg;
    uint64_t value;
    uint32_t offset;
};

struct BranchLeSImm {
    static const uint8_t opcode;
    RegisterIndex reg;
    uint64_t value;
    uint32_t offset;
};

struct BranchGeSImm {
    static const uint8_t opcode;
    RegisterIndex reg;
    uint64_t value;
    uint32_t offset;
};

struct BranchGtSImm {
    static const uint8_t opcode;
    RegisterIndex reg;
    uint64_t value;
    uint32_t offset;
};

// MARK: Instructions with Arguments of Two Registers (5.9)
struct MoveReg {
    static const uint8_t opcode;
    RegisterIndex src;
    RegisterIndex dest;
};

struct Sbrk {
    static const uint8_t opcode;
    RegisterIndex src;
    RegisterIndex dest;
};

struct CountSetBits64 {
    static const uint8_t opcode;
    RegisterIndex ra;
    RegisterIndex dest;
};

struct CountSetBits32 {
    static const uint8_t opcode;
    RegisterIndex ra;
    RegisterIndex dest;
};

struct LeadingZeroBits64 {
    static const uint8_t opcode;
    RegisterIndex ra;
    RegisterIndex dest;
};

struct LeadingZeroBits32 {
    static const uint8_t opcode;
    RegisterIndex ra;
    RegisterIndex dest;
};

struct TrailingZeroBits64 {
    static const uint8_t opcode;
    RegisterIndex ra;
    RegisterIndex dest;
};

struct TrailingZeroBits32 {
    static const uint8_t opcode;
    RegisterIndex ra;
    RegisterIndex dest;
};

struct SignExtend8 {
    static const uint8_t opcode;
    RegisterIndex ra;
    RegisterIndex dest;
};

struct SignExtend16 {
    static const uint8_t opcode;
    RegisterIndex ra;
    RegisterIndex dest;
};

struct ZeroExtend16 {
    static const uint8_t opcode;
    RegisterIndex ra;
    RegisterIndex dest;
};

struct ReverseBytes {
    static const uint8_t opcode;
    RegisterIndex ra;
    RegisterIndex dest;
};

// MARK: Instructions with Arguments of Two Registers &amp; One Immediate (5.10)
struct StoreIndU8 {
    static const uint8_t opcode;
    RegisterIndex src;
    RegisterIndex dest;
    uint32_t offset;
};

struct StoreIndU16 {
    static const uint8_t opcode;
    RegisterIndex src;
    RegisterIndex dest;
    uint32_t offset;
};

struct StoreIndU32 {
    static const uint8_t opcode;
    RegisterIndex src;
    RegisterIndex dest;
    uint32_t offset;
};

struct StoreIndU64 {
    static const uint8_t opcode;
    RegisterIndex src;
    RegisterIndex dest;
    uint32_t offset;
};

struct LoadIndU8 {
    static const uint8_t opcode;
    RegisterIndex ra;
    RegisterIndex rb;
    uint32_t offset;
};

struct LoadIndI8 {
    static const uint8_t opcode;
    RegisterIndex ra;
    RegisterIndex rb;
    uint32_t offset;
};

struct LoadIndU16 {
    static const uint8_t opcode;
    RegisterIndex ra;
    RegisterIndex rb;
    uint32_t offset;
};

struct LoadIndI16 {
    static const uint8_t opcode;
    RegisterIndex ra;
    RegisterIndex rb;
    uint32_t offset;
};

struct LoadIndU32 {
    static const uint8_t opcode;
    RegisterIndex ra;
    RegisterIndex rb;
    uint32_t offset;
};

struct LoadIndI32 {
    static const uint8_t opcode;
    RegisterIndex ra;
    RegisterIndex rb;
    uint32_t offset;
};

struct LoadIndU64 {
    static const uint8_t opcode;
    RegisterIndex ra;
    RegisterIndex rb;
    uint32_t offset;
};

struct AddImm32 {
    static const uint8_t opcode;
    RegisterIndex ra;
    RegisterIndex rb;
    uint32_t value;
};

struct AndImm {
    static const uint8_t opcode;
    RegisterIndex ra;
    RegisterIndex rb;
    uint64_t value;
};

struct XorImm {
    static const uint8_t opcode;
    RegisterIndex ra;
    RegisterIndex rb;
    uint64_t value;
};

struct OrImm {
    static const uint8_t opcode;
    RegisterIndex ra;
    RegisterIndex rb;
    uint64_t value;
};

struct MulImm32 {
    static const uint8_t opcode;
    RegisterIndex ra;
    RegisterIndex rb;
    uint32_t value;
};

struct SetLtUImm {
    static const uint8_t opcode;
    RegisterIndex ra;
    RegisterIndex rb;
    uint64_t value;
};

struct SetLtSImm {
    static const uint8_t opcode;
    RegisterIndex ra;
    RegisterIndex rb;
    uint64_t value;
};

struct ShloLImm32 {
    static const uint8_t opcode;
    RegisterIndex ra;
    RegisterIndex rb;
    uint32_t value;
};

struct ShloRImm32 {
    static const uint8_t opcode;
    RegisterIndex ra;
    RegisterIndex rb;
    uint32_t value;
};

struct SharRImm32 {
    static const uint8_t opcode;
    RegisterIndex ra;
    RegisterIndex rb;
    uint32_t value;
};

struct NegAddImm32 {
    static const uint8_t opcode;
    RegisterIndex ra;
    RegisterIndex rb;
    uint32_t value;
};

struct SetGtUImm {
    static const uint8_t opcode;
    RegisterIndex ra;
    RegisterIndex rb;
    uint64_t value;
};

struct SetGtSImm {
    static const uint8_t opcode;
    RegisterIndex ra;
    RegisterIndex rb;
    uint64_t value;
};

struct ShloLImmAlt32 {
    static const uint8_t opcode;
    RegisterIndex ra;
    RegisterIndex rb;
    uint32_t value;
};

struct ShloRImmAlt32 {
    static const uint8_t opcode;
    RegisterIndex ra;
    RegisterIndex rb;
    uint32_t value;
};

struct SharRImmAlt32 {
    static const uint8_t opcode;
    RegisterIndex ra;
    RegisterIndex rb;
    uint32_t value;
};

struct CmovIzImm {
    static const uint8_t opcode;
    RegisterIndex ra;
    RegisterIndex rb;
    uint64_t value;
};

struct CmovNzImm {
    static const uint8_t opcode;
    RegisterIndex ra;
    RegisterIndex rb;
    uint64_t value;
};

struct AddImm64 {
    static const uint8_t opcode;
    RegisterIndex ra;
    RegisterIndex rb;
    uint64_t value;
};

struct MulImm64 {
    static const uint8_t opcode;
    RegisterIndex ra;
    RegisterIndex rb;
    uint64_t value;
};

struct ShloLImm64 {
    static const uint8_t opcode;
    RegisterIndex ra;
    RegisterIndex rb;
    uint64_t value;
};

struct ShloRImm64 {
    static const uint8_t opcode;
    RegisterIndex ra;
    RegisterIndex rb;
    uint64_t value;
};

struct SharRImm64 {
    static const uint8_t opcode;
    RegisterIndex ra;
    RegisterIndex rb;
    uint64_t value;
};

struct NegAddImm64 {
    static const uint8_t opcode;
    RegisterIndex ra;
    RegisterIndex rb;
    uint64_t value;
};

struct ShloLImmAlt64 {
    static const uint8_t opcode;
    RegisterIndex ra;
    RegisterIndex rb;
    uint64_t value;
};

struct ShloRImmAlt64 {
    static const uint8_t opcode;
    RegisterIndex ra;
    RegisterIndex rb;
    uint64_t value;
};

struct SharRImmAlt64 {
    static const uint8_t opcode;
    RegisterIndex ra;
    RegisterIndex rb;
    uint64_t value;
};

struct RotR64Imm {
    static const uint8_t opcode;
    RegisterIndex ra;
    RegisterIndex rb;
    uint64_t value;
};

struct RotR64ImmAlt {
    static const uint8_t opcode;
    RegisterIndex ra;
    RegisterIndex rb;
    uint64_t value;
};

struct RotR32Imm {
    static const uint8_t opcode;
    RegisterIndex ra;
    RegisterIndex rb;
    uint32_t value;
};

struct RotR32ImmAlt {
    static const uint8_t opcode;
    RegisterIndex ra;
    RegisterIndex rb;
    uint32_t value;
};

// MARK: Instructions with Arguments of Two Registers &amp; One Offset (5.11)
struct BranchEq {
    static const uint8_t opcode;
    RegisterIndex reg1;
    RegisterIndex reg2;
    uint32_t offset;
};

struct BranchNe {
    static const uint8_t opcode;
    RegisterIndex reg1;
    RegisterIndex reg2;
    uint32_t offset;
};

struct BranchLtU {
    static const uint8_t opcode;
    RegisterIndex reg1;
    RegisterIndex reg2;
    uint32_t offset;
};

struct BranchLtS {
    static const uint8_t opcode;
    RegisterIndex reg1;
    RegisterIndex reg2;
    uint32_t offset;
};

struct BranchGeU {
    static const uint8_t opcode;
    RegisterIndex reg1;
    RegisterIndex reg2;
    uint32_t offset;
};

struct BranchGeS {
    static const uint8_t opcode;
    RegisterIndex reg1;
    RegisterIndex reg2;
    uint32_t offset;
};

// MARK: Instruction with Arguments of Two Registers and Two Immediates (5.12)
struct LoadImmJumpInd {
    static const uint8_t opcode;
    RegisterIndex ra;
    RegisterIndex rb;
    uint32_t value;
    uint32_t offset;
};

// MARK: Instructions with Arguments of Three Registers (5.13)
struct Add32 {
    static const uint8_t opcode;
    RegisterIndex ra;
    RegisterIndex rb;
    RegisterIndex rd;
};

struct Sub32 {
    static const uint8_t opcode;
    RegisterIndex ra;
    RegisterIndex rb;
    RegisterIndex rd;
};

struct Mul32 {
    static const uint8_t opcode;
    RegisterIndex ra;
    RegisterIndex rb;
    RegisterIndex rd;
};

struct DivU32 {
    static const uint8_t opcode;
    RegisterIndex ra;
    RegisterIndex rb;
    RegisterIndex rd;
};

struct DivS32 {
    static const uint8_t opcode;
    RegisterIndex ra;
    RegisterIndex rb;
    RegisterIndex rd;
};

struct RemU32 {
    static const uint8_t opcode;
    RegisterIndex ra;
    RegisterIndex rb;
    RegisterIndex rd;
};

struct RemS32 {
    static const uint8_t opcode;
    RegisterIndex ra;
    RegisterIndex rb;
    RegisterIndex rd;
};

struct ShloL32 {
    static const uint8_t opcode;
    RegisterIndex ra;
    RegisterIndex rb;
    RegisterIndex rd;
};

struct ShloR32 {
    static const uint8_t opcode;
    RegisterIndex ra;
    RegisterIndex rb;
    RegisterIndex rd;
};

struct SharR32 {
    static const uint8_t opcode;
    RegisterIndex ra;
    RegisterIndex rb;
    RegisterIndex rd;
};

struct Add64 {
    static const uint8_t opcode;
    RegisterIndex ra;
    RegisterIndex rb;
    RegisterIndex rd;
};

struct Sub64 {
    static const uint8_t opcode;
    RegisterIndex ra;
    RegisterIndex rb;
    RegisterIndex rd;
};

struct Mul64 {
    static const uint8_t opcode;
    RegisterIndex ra;
    RegisterIndex rb;
    RegisterIndex rd;
};

struct DivU64 {
    static const uint8_t opcode;
    RegisterIndex ra;
    RegisterIndex rb;
    RegisterIndex rd;
};

struct DivS64 {
    static const uint8_t opcode;
    RegisterIndex ra;
    RegisterIndex rb;
    RegisterIndex rd;
};

struct RemU64 {
    static const uint8_t opcode;
    RegisterIndex ra;
    RegisterIndex rb;
    RegisterIndex rd;
};

struct RemS64 {
    static const uint8_t opcode;
    RegisterIndex ra;
    RegisterIndex rb;
    RegisterIndex rd;
};

struct ShloL64 {
    static const uint8_t opcode;
    RegisterIndex ra;
    RegisterIndex rb;
    RegisterIndex rd;
};

struct ShloR64 {
    static const uint8_t opcode;
    RegisterIndex ra;
    RegisterIndex rb;
    RegisterIndex rd;
};

struct SharR64 {
    static const uint8_t opcode;
    RegisterIndex ra;
    RegisterIndex rb;
    RegisterIndex rd;
};

struct And {
    static const uint8_t opcode;
    RegisterIndex ra;
    RegisterIndex rb;
    RegisterIndex rd;
};

struct Xor {
    static const uint8_t opcode;
    RegisterIndex ra;
    RegisterIndex rb;
    RegisterIndex rd;
};

struct Or {
    static const uint8_t opcode;
    RegisterIndex ra;
    RegisterIndex rb;
    RegisterIndex rd;
};

struct MulUpperSS {
    static const uint8_t opcode;
    RegisterIndex ra;
    RegisterIndex rb;
    RegisterIndex rd;
};

struct MulUpperUU {
    static const uint8_t opcode;
    RegisterIndex ra;
    RegisterIndex rb;
    RegisterIndex rd;
};

struct MulUpperSU {
    static const uint8_t opcode;
    RegisterIndex ra;
    RegisterIndex rb;
    RegisterIndex rd;
};

struct SetLtU {
    static const uint8_t opcode;
    RegisterIndex ra;
    RegisterIndex rb;
    RegisterIndex rd;
};

struct SetLtS {
    static const uint8_t opcode;
    RegisterIndex ra;
    RegisterIndex rb;
    RegisterIndex rd;
};

struct CmovIz {
    static const uint8_t opcode;
    RegisterIndex ra;
    RegisterIndex rb;
    RegisterIndex rd;
};

struct CmovNz {
    static const uint8_t opcode;
    RegisterIndex ra;
    RegisterIndex rb;
    RegisterIndex rd;
};

struct RotL64 {
    static const uint8_t opcode;
    RegisterIndex ra;
    RegisterIndex rb;
    RegisterIndex rd;
};

struct RotL32 {
    static const uint8_t opcode;
    RegisterIndex ra;
    RegisterIndex rb;
    RegisterIndex rd;
};

struct RotR64 {
    static const uint8_t opcode;
    RegisterIndex ra;
    RegisterIndex rb;
    RegisterIndex rd;
};

struct RotR32 {
    static const uint8_t opcode;
    RegisterIndex ra;
    RegisterIndex rb;
    RegisterIndex rd;
};

struct AndInv {
    static const uint8_t opcode;
    RegisterIndex ra;
    RegisterIndex rb;
    RegisterIndex rd;
};

struct OrInv {
    static const uint8_t opcode;
    RegisterIndex ra;
    RegisterIndex rb;
    RegisterIndex rd;
};

struct Xnor {
    static const uint8_t opcode;
    RegisterIndex ra;
    RegisterIndex rb;
    RegisterIndex rd;
};

struct Max {
    static const uint8_t opcode;
    RegisterIndex ra;
    RegisterIndex rb;
    RegisterIndex rd;
};

struct MaxU {
    static const uint8_t opcode;
    RegisterIndex ra;
    RegisterIndex rb;
    RegisterIndex rd;
};

struct Min {
    static const uint8_t opcode;
    RegisterIndex ra;
    RegisterIndex rb;
    RegisterIndex rd;
};

struct MinU {
    static const uint8_t opcode;
    RegisterIndex ra;
    RegisterIndex rb;
    RegisterIndex rd;
};

} // namespace Instructions
