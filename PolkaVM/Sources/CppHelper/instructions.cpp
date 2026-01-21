#include "instructions.hh"
#include "asmjit/asmjit.h"

namespace Instructions {
    // to workaround duplicated .init issue in Swift
    Trap::Trap() {}
    Fallthrough::Fallthrough() {}

    const uint8_t Trap::opcode = static_cast<uint8_t>(PVM::Opcode::Trap);
    const uint8_t Fallthrough::opcode = static_cast<uint8_t>(PVM::Opcode::Halt);
    const uint8_t Ecalli::opcode = 10;
    const uint8_t LoadImm64::opcode = static_cast<uint8_t>(PVM::Opcode::LoadImmU64);
    const uint8_t StoreImmU8::opcode = static_cast<uint8_t>(PVM::Opcode::StoreImmU8);
    const uint8_t StoreImmU16::opcode = static_cast<uint8_t>(PVM::Opcode::StoreImmU16);
    const uint8_t StoreImmU32::opcode = static_cast<uint8_t>(PVM::Opcode::StoreImmU32);
    const uint8_t StoreImmU64::opcode = static_cast<uint8_t>(PVM::Opcode::StoreImmU64);
    const uint8_t Jump::opcode = static_cast<uint8_t>(PVM::Opcode::Jump);
    const uint8_t JumpInd::opcode = static_cast<uint8_t>(PVM::Opcode::JumpInd);
    const uint8_t LoadImm::opcode = static_cast<uint8_t>(PVM::Opcode::LoadImm);
    const uint8_t LoadU8::opcode = static_cast<uint8_t>(PVM::Opcode::LoadU8);
    const uint8_t LoadI8::opcode = static_cast<uint8_t>(PVM::Opcode::LoadI8);
    const uint8_t LoadU16::opcode = static_cast<uint8_t>(PVM::Opcode::LoadU16);
    const uint8_t LoadI16::opcode = static_cast<uint8_t>(PVM::Opcode::LoadI16);
    const uint8_t LoadU32::opcode = static_cast<uint8_t>(PVM::Opcode::LoadU32);
    const uint8_t LoadI32::opcode = static_cast<uint8_t>(PVM::Opcode::LoadI32);
    const uint8_t LoadU64::opcode = static_cast<uint8_t>(PVM::Opcode::LoadU64);
    const uint8_t StoreU8::opcode = static_cast<uint8_t>(PVM::Opcode::StoreU8);
    const uint8_t StoreU16::opcode = static_cast<uint8_t>(PVM::Opcode::StoreU16);
    const uint8_t StoreU32::opcode = static_cast<uint8_t>(PVM::Opcode::StoreU32);
    const uint8_t StoreU64::opcode = static_cast<uint8_t>(PVM::Opcode::StoreU64);
    const uint8_t StoreImmIndU8::opcode = 70;
    const uint8_t StoreImmIndU16::opcode = 71;
    const uint8_t StoreImmIndU32::opcode = 72;
    const uint8_t StoreImmIndU64::opcode = 73;
    const uint8_t LoadImmJump::opcode = 80;
    const uint8_t BranchEqImm::opcode = 81;
    const uint8_t BranchNeImm::opcode = 82;
    const uint8_t BranchLtUImm::opcode = 83;
    const uint8_t BranchLeUImm::opcode = 84;
    const uint8_t BranchGeUImm::opcode = 85;
    const uint8_t BranchGtUImm::opcode = 86;
    const uint8_t BranchLtSImm::opcode = 87;
    const uint8_t BranchLeSImm::opcode = 88;
    const uint8_t BranchGeSImm::opcode = 89;
    const uint8_t BranchGtSImm::opcode = 90;
    const uint8_t MoveReg::opcode = 100;
    const uint8_t Sbrk::opcode = 101;
    const uint8_t CountSetBits64::opcode = 102;
    const uint8_t CountSetBits32::opcode = 103;
    const uint8_t LeadingZeroBits64::opcode = 104;
    const uint8_t LeadingZeroBits32::opcode = 105;
    const uint8_t TrailingZeroBits64::opcode = 106;
    const uint8_t TrailingZeroBits32::opcode = 107;
    const uint8_t SignExtend8::opcode = 108;
    const uint8_t SignExtend16::opcode = 109;
    const uint8_t ZeroExtend16::opcode = 110;
    const uint8_t ReverseBytes::opcode = 111;
    const uint8_t StoreIndU8::opcode = 120;
    const uint8_t StoreIndU16::opcode = 121;
    const uint8_t StoreIndU32::opcode = 122;
    const uint8_t StoreIndU64::opcode = 123;
    const uint8_t LoadIndU8::opcode = 124;
    const uint8_t LoadIndI8::opcode = 125;
    const uint8_t LoadIndU16::opcode = 126;
    const uint8_t LoadIndI16::opcode = 127;
    const uint8_t LoadIndU32::opcode = 128;
    const uint8_t LoadIndI32::opcode = 129;
    const uint8_t LoadIndU64::opcode = 130;
    const uint8_t AddImm32::opcode = 131;
    const uint8_t AndImm::opcode = 132;
    const uint8_t XorImm::opcode = 133;
    const uint8_t OrImm::opcode = 134;
    const uint8_t MulImm32::opcode = 135;
    const uint8_t SetLtUImm::opcode = 136;
    const uint8_t SetLtSImm::opcode = 137;
    const uint8_t ShloLImm32::opcode = 138;
    const uint8_t ShloRImm32::opcode = 139;
    const uint8_t SharRImm32::opcode = 140;
    const uint8_t NegAddImm32::opcode = 141;
    const uint8_t SetGtUImm::opcode = 142;
    const uint8_t SetGtSImm::opcode = 143;
    const uint8_t ShloLImmAlt32::opcode = 144;
    const uint8_t ShloRImmAlt32::opcode = 145;
    const uint8_t SharRImmAlt32::opcode = 146;
    const uint8_t CmovIzImm::opcode = 147;
    const uint8_t CmovNzImm::opcode = 148;
    const uint8_t AddImm64::opcode = 149;
    const uint8_t MulImm64::opcode = 150;
    const uint8_t ShloLImm64::opcode = 151;
    const uint8_t ShloRImm64::opcode = 152;
    const uint8_t SharRImm64::opcode = 153;
    const uint8_t NegAddImm64::opcode = 154;
    const uint8_t ShloLImmAlt64::opcode = 155;
    const uint8_t ShloRImmAlt64::opcode = 156;
    const uint8_t SharRImmAlt64::opcode = 157;
    const uint8_t RotR64Imm::opcode = 158;
    const uint8_t RotR64ImmAlt::opcode = 159;
    const uint8_t RotR32Imm::opcode = 160;
    const uint8_t RotR32ImmAlt::opcode = 161;
    const uint8_t BranchEq::opcode = 170;
    const uint8_t BranchNe::opcode = 171;
    const uint8_t BranchLtU::opcode = 172;
    const uint8_t BranchLtS::opcode = 173;
    const uint8_t BranchGeU::opcode = 174;
    const uint8_t BranchGeS::opcode = 175;
    const uint8_t LoadImmJumpInd::opcode = 180;
    const uint8_t Add32::opcode = 190;
    const uint8_t Sub32::opcode = 191;
    const uint8_t Mul32::opcode = 192;
    const uint8_t DivU32::opcode = 193;
    const uint8_t DivS32::opcode = 194;
    const uint8_t RemU32::opcode = 195;
    const uint8_t RemS32::opcode = 196;
    const uint8_t ShloL32::opcode = 197;
    const uint8_t ShloR32::opcode = 198;
    const uint8_t SharR32::opcode = 199;
    const uint8_t Add64::opcode = 200;
    const uint8_t Sub64::opcode = 201;
    const uint8_t Mul64::opcode = 202;
    const uint8_t DivU64::opcode = 203;
    const uint8_t DivS64::opcode = 204;
    const uint8_t RemU64::opcode = 205;
    const uint8_t RemS64::opcode = 206;
    const uint8_t ShloL64::opcode = 207;
    const uint8_t ShloR64::opcode = 208;
    const uint8_t SharR64::opcode = 209;
    const uint8_t And::opcode = 210;
    const uint8_t Xor::opcode = 211;
    const uint8_t Or::opcode = 212;
    const uint8_t MulUpperSS::opcode = 213;
    const uint8_t MulUpperUU::opcode = 214;
    const uint8_t MulUpperSU::opcode = 215;
    const uint8_t SetLtU::opcode = 216;
    const uint8_t SetLtS::opcode = 217;
    const uint8_t CmovIz::opcode = 218;
    const uint8_t CmovNz::opcode = 219;
    const uint8_t RotL64::opcode = 220;
    const uint8_t RotL32::opcode = 221;
    const uint8_t RotR64::opcode = 222;
    const uint8_t RotR32::opcode = 223;
    const uint8_t AndInv::opcode = 224;
    const uint8_t OrInv::opcode = 225;
    const uint8_t Xnor::opcode = 226;
    const uint8_t Max::opcode = 227;
    const uint8_t MaxU::opcode = 228;
    const uint8_t Min::opcode = 229;
    const uint8_t MinU::opcode = 230;
}

// JIT Instruction Translation Namespace
namespace jit_instruction {

using namespace asmjit;
using namespace asmjit::x86;

// VM Register mapping (already defined in x64_helper.cpp:48-62)
// - rbx: VM_REGISTERS_PTR
// - r12: VM_MEMORY_PTR
// - r13d: VM_MEMORY_SIZE
// - r14: VM_GAS_PTR
// - r15d: VM_PC
// - rbp: VM_CONTEXT_PTR

// Helper to get native register for VM register
inline Gp get_vm_register(uint8_t vm_reg) {
    // VM register to x86_64 register mapping
    static const Gp vm_reg_map[] = {
        rdi,  // A0 (arg0/return)
        rax,  // A1 (arg1/return)
        rsi,  // SP
        rbx,  // RA
        rdx,  // A2
        rbp,  // A3
        r8,   // S0
        r9,   // S1
        r10,  // A4
        r11,  // A5
        r13,  // T0
        r14,  // T1
        r12   // T2
    };

    if (vm_reg < 13) {
        return vm_reg_map[vm_reg];
    }
    return rax; // Fallback
}

// Proof of concept: Implement Trap instruction
bool jit_emit_trap(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false; // Only x86_64 for now
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Trap: Return -1 to indicate trap/panic
    // Matches Swift exit code mapping: case -1 => .panic(.trap)

    // Set return value to indicate trap
    a->mov(x86::eax, -1);  // Exit reason: trap

    // Jump to exit handler (will be implemented later)
    // For now, just return to caller

    return true;
}

// Proof of concept: Implement LoadImmU32 instruction
bool jit_emit_load_imm_u32(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint32_t immediate)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load immediate into temp register
    a->mov(x86::rax, immediate);

    // Store to VM register array
    // [VM_REGISTERS_PTR + dest_reg * 8]
    a->mov(x86::qword_ptr(rbx, dest_reg * 8), x86::rax);

    return true;
}

// Proof of concept: Implement Add32 instruction
bool jit_emit_add_32(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t src_reg)
{
    using namespace asmjit;

    if (strcmp(target_arch, "x86_64") == 0) {
        auto* a = static_cast<x86::Assembler*>(assembler);

        // Load source register from VM array (VM_REGISTERS_PTR in rbx)
        a->mov(x86::eax, x86::dword_ptr(x86::rbx, src_reg * 8));

        // Load dest register from VM array
        a->mov(x86::edx, x86::dword_ptr(x86::rbx, dest_reg * 8));

        // Add: dest = dest + src
        a->add(x86::edx, x86::eax);

        // Store result back to VM register array
        a->mov(x86::dword_ptr(x86::rbx, dest_reg * 8), x86::edx);

        return true;
    } else if (strcmp(target_arch, "aarch64") == 0) {
        auto* a = static_cast<a64::Assembler*>(assembler);

        // Load source register from VM array (VM_REGISTERS_PTR in x19)
        a64::Gp temp = a64::w0;
        a64::Gp dest = a64::w1;
        a64::Gp regPtr = a64::x19;

        a->ldr(dest, a64::ptr(regPtr, dest_reg * 8));
        a->ldr(temp, a64::ptr(regPtr, src_reg * 8));

        // Add: dest = dest + src
        a->add(dest, dest, temp);

        // Store result back to VM register array
        a->str(dest, a64::ptr(regPtr, dest_reg * 8));

        return true;
    }

    return false;
}

// LoadImmU8: Load 8-bit unsigned immediate
bool jit_emit_load_imm_u8(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t immediate)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load immediate into temp register (zero-extended to 64-bit)
    a->mov(x86::rax, immediate);

    // Store to VM register array
    a->mov(x86::qword_ptr(rbx, dest_reg * 8), x86::rax);

    return true;
}

// LoadImmU16: Load 16-bit unsigned immediate
bool jit_emit_load_imm_u16(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint16_t immediate)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load immediate into temp register (zero-extended to 64-bit)
    a->mov(x86::rax, immediate);

    // Store to VM register array
    a->mov(x86::qword_ptr(rbx, dest_reg * 8), x86::rax);

    return true;
}

// LoadImmU64: Load 64-bit unsigned immediate
bool jit_emit_load_imm_u64(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint64_t immediate)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load 64-bit immediate into temp register
    a->mov(x86::rax, immediate);

    // Store to VM register array
    a->mov(x86::qword_ptr(rbx, dest_reg * 8), x86::rax);

    return true;
}

// LoadImmS32: Load 32-bit signed immediate (sign-extended to 64-bit)
bool jit_emit_load_imm_s32(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    int32_t immediate)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load signed 32-bit immediate with sign extension to 64-bit
    // movsxd rax, immediate (sign-extended)
    a->movsxd(x86::rax, x86::dword_ptr(reinterpret_cast<intptr_t>(&immediate)));

    // Store to VM register array
    a->mov(x86::qword_ptr(rbx, dest_reg * 8), x86::rax);

    return true;
}

// Sub32: Subtraction (32-bit)
bool jit_emit_sub_32(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t src_reg)
{
    using namespace asmjit;

    if (strcmp(target_arch, "x86_64") == 0) {
        auto* a = static_cast<x86::Assembler*>(assembler);

        // Load source register from VM array (VM_REGISTERS_PTR in rbx)
        a->mov(x86::eax, x86::dword_ptr(x86::rbx, src_reg * 8));

        // Load dest register from VM array
        a->mov(x86::edx, x86::dword_ptr(x86::rbx, dest_reg * 8));

        // Subtract: dest = dest - src
        a->sub(x86::edx, x86::eax);

        // Store result back to VM register array
        a->mov(x86::dword_ptr(x86::rbx, dest_reg * 8), x86::edx);

        return true;
    } else if (strcmp(target_arch, "aarch64") == 0) {
        auto* a = static_cast<a64::Assembler*>(assembler);

        // Load source register from VM array (VM_REGISTERS_PTR in x19)
        a64::Gp temp = a64::w0;
        a64::Gp dest = a64::w1;
        a64::Gp regPtr = a64::x19;

        a->ldr(dest, a64::ptr(regPtr, dest_reg * 8));
        a->ldr(temp, a64::ptr(regPtr, src_reg * 8));

        // Subtract: dest = dest - src
        a->sub(dest, dest, temp);

        // Store result back to VM register array
        a->str(dest, a64::ptr(regPtr, dest_reg * 8));

        return true;
    }

    return false;
}

// Mul32: Multiplication (32-bit)
bool jit_emit_mul_32(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t src_reg)
{
    using namespace asmjit;

    if (strcmp(target_arch, "x86_64") == 0) {
        auto* a = static_cast<x86::Assembler*>(assembler);

        // Load source register from VM array (VM_REGISTERS_PTR in rbx)
        a->mov(x86::eax, x86::dword_ptr(x86::rbx, src_reg * 8));

        // Load dest register from VM array
        a->mov(x86::edx, x86::dword_ptr(x86::rbx, dest_reg * 8));

        // Multiply: dest = dest * src
        a->imul(x86::edx, x86::eax);

        // Store result back to VM register array
        a->mov(x86::dword_ptr(x86::rbx, dest_reg * 8), x86::edx);

        return true;
    } else if (strcmp(target_arch, "aarch64") == 0) {
        auto* a = static_cast<a64::Assembler*>(assembler);

        // Load source register from VM array (VM_REGISTERS_PTR in x19)
        a64::Gp temp = a64::w0;
        a64::Gp dest = a64::w1;
        a64::Gp regPtr = a64::x19;

        a->ldr(dest, a64::ptr(regPtr, dest_reg * 8));
        a->ldr(temp, a64::ptr(regPtr, src_reg * 8));

        // Multiply: dest = dest * src
        a->mul(dest, dest, temp);

        // Store result back to VM register array
        a->str(dest, a64::ptr(regPtr, dest_reg * 8));

        return true;
    }

    return false;
}

// LoadU8: Load unsigned 8-bit from memory
bool jit_emit_load_u8(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t ptr_reg,
    int16_t offset)
{
    using namespace asmjit;

    if (strcmp(target_arch, "x86_64") == 0) {
        auto* a = static_cast<x86::Assembler*>(assembler);

        // Load pointer register from VM array (VM_REGISTERS_PTR in rbx)
        a->mov(x86::rax, x86::qword_ptr(x86::rbx, ptr_reg * 8));

        // Load unsigned byte from memory at [VM_MEMORY_PTR + ptr + offset]
        a->movzx(x86::eax, x86::byte_ptr(x86::r12, x86::rax, 1, offset));

        // Zero-extend and store to VM register array
        a->mov(x86::qword_ptr(x86::rbx, dest_reg * 8), x86::rax);

        return true;
    } else if (strcmp(target_arch, "aarch64") == 0) {
        auto* a = static_cast<a64::Assembler*>(assembler);

        // Load pointer register from VM array (VM_REGISTERS_PTR in x19)
        a64::Gp ptr = a64::x0;
        a64::Gp memBase = a64::x20; // VM_MEMORY_PTR
        a64::Gp dest = a64::x1;
        a64::Gp regPtr = a64::x19;

        a->ldr(ptr, a64::ptr(regPtr, ptr_reg * 8));

        // Calculate address: memBase + ptr
        a->add(ptr, memBase, ptr);

        // Load unsigned byte from memory with zero-extension
        a->ldrb(dest.w(), a64::ptr(ptr, offset));

        // Store to VM register array
        a->str(dest.x(), a64::ptr(regPtr, dest_reg * 8));

        return true;
    }

    return false;
}

// LoadI8: Load signed 8-bit from memory (sign-extended)
bool jit_emit_load_i8(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t ptr_reg,
    int16_t offset)
{
    using namespace asmjit;

    if (strcmp(target_arch, "x86_64") == 0) {
        auto* a = static_cast<x86::Assembler*>(assembler);

        // Load pointer register from VM array (VM_REGISTERS_PTR in rbx)
        a->mov(x86::rax, x86::qword_ptr(x86::rbx, ptr_reg * 8));

        // Load signed byte from memory at [VM_MEMORY_PTR + ptr + offset] with sign extension
        a->movsx(x86::rax, x86::byte_ptr(x86::r12, x86::rax, 1, offset));

        // Store to VM register array
        a->mov(x86::qword_ptr(x86::rbx, dest_reg * 8), x86::rax);

        return true;
    } else if (strcmp(target_arch, "aarch64") == 0) {
        auto* a = static_cast<a64::Assembler*>(assembler);

        // Load pointer register from VM array (VM_REGISTERS_PTR in x19)
        a64::Gp ptr = a64::x0;
        a64::Gp memBase = a64::x20; // VM_MEMORY_PTR
        a64::Gp dest = a64::x1;
        a64::Gp regPtr = a64::x19;

        a->ldr(ptr, a64::ptr(regPtr, ptr_reg * 8));

        // Calculate address: memBase + ptr
        a->add(ptr, memBase, ptr);

        // Load signed byte from memory with sign-extension
        a->ldrsb(dest.x(), a64::ptr(ptr, offset));

        // Store to VM register array
        a->str(dest, a64::ptr(regPtr, dest_reg * 8));

        return true;
    }

    return false;
}

// LoadU16: Load unsigned 16-bit from memory
bool jit_emit_load_u16(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t ptr_reg,
    int16_t offset)
{
    using namespace asmjit;

    if (strcmp(target_arch, "x86_64") == 0) {
        auto* a = static_cast<x86::Assembler*>(assembler);

        // Load pointer register from VM array (VM_REGISTERS_PTR in rbx)
        a->mov(x86::rax, x86::qword_ptr(x86::rbx, ptr_reg * 8));

        // Load unsigned word from memory at [VM_MEMORY_PTR + ptr + offset]
        a->movzx(x86::eax, x86::word_ptr(x86::r12, x86::rax, 1, offset));

        // Zero-extend and store to VM register array
        a->mov(x86::qword_ptr(x86::rbx, dest_reg * 8), x86::rax);

        return true;
    } else if (strcmp(target_arch, "aarch64") == 0) {
        auto* a = static_cast<a64::Assembler*>(assembler);

        // Load pointer register from VM array (VM_REGISTERS_PTR in x19)
        a64::Gp ptr = a64::x0;
        a64::Gp memBase = a64::x20; // VM_MEMORY_PTR
        a64::Gp dest = a64::x1;
        a64::Gp regPtr = a64::x19;

        a->ldr(ptr, a64::ptr(regPtr, ptr_reg * 8));

        // Calculate address: memBase + ptr
        a->add(ptr, memBase, ptr);

        // Load unsigned halfword from memory with zero-extension
        a->ldrh(dest.w(), a64::ptr(ptr, offset));

        // Store to VM register array
        a->str(dest.x(), a64::ptr(regPtr, dest_reg * 8));

        return true;
    }

    return false;
}

// LoadI16: Load signed 16-bit from memory (sign-extended)
bool jit_emit_load_i16(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t ptr_reg,
    int16_t offset)
{
    using namespace asmjit;

    if (strcmp(target_arch, "x86_64") == 0) {
        auto* a = static_cast<x86::Assembler*>(assembler);

        // Load pointer register from VM array (VM_REGISTERS_PTR in rbx)
        a->mov(x86::rax, x86::qword_ptr(x86::rbx, ptr_reg * 8));

        // Load signed word from memory at [VM_MEMORY_PTR + ptr + offset] with sign extension
        a->movsx(x86::rax, x86::word_ptr(x86::r12, x86::rax, 1, offset));

        // Store to VM register array
        a->mov(x86::qword_ptr(x86::rbx, dest_reg * 8), x86::rax);

        return true;
    } else if (strcmp(target_arch, "aarch64") == 0) {
        auto* a = static_cast<a64::Assembler*>(assembler);

        // Load pointer register from VM array (VM_REGISTERS_PTR in x19)
        a64::Gp ptr = a64::x0;
        a64::Gp memBase = a64::x20; // VM_MEMORY_PTR
        a64::Gp dest = a64::x1;
        a64::Gp regPtr = a64::x19;

        a->ldr(ptr, a64::ptr(regPtr, ptr_reg * 8));

        // Calculate address: memBase + ptr
        a->add(ptr, memBase, ptr);

        // Load signed halfword from memory with sign-extension
        a->ldrsh(dest.x(), a64::ptr(ptr, offset));

        // Store to VM register array
        a->str(dest, a64::ptr(regPtr, dest_reg * 8));

        return true;
    }

    return false;
}

// LoadU64: Load unsigned 64-bit from memory
bool jit_emit_load_u64(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t ptr_reg,
    int16_t offset)
{
    using namespace asmjit;

    if (strcmp(target_arch, "x86_64") == 0) {
        auto* a = static_cast<x86::Assembler*>(assembler);

        // Load pointer register from VM array (VM_REGISTERS_PTR in rbx)
        a->mov(x86::rax, x86::qword_ptr(x86::rbx, ptr_reg * 8));

        // Load qword from memory at [VM_MEMORY_PTR + ptr + offset]
        a->mov(x86::rax, x86::qword_ptr(x86::r12, x86::rax, 1, offset));

        // Store to VM register array
        a->mov(x86::qword_ptr(x86::rbx, dest_reg * 8), x86::rax);

        return true;
    } else if (strcmp(target_arch, "aarch64") == 0) {
        auto* a = static_cast<a64::Assembler*>(assembler);

        // Load pointer register from VM array (VM_REGISTERS_PTR in x19)
        a64::Gp ptr = a64::x0;
        a64::Gp memBase = a64::x20; // VM_MEMORY_PTR
        a64::Gp dest = a64::x1;
        a64::Gp regPtr = a64::x19;

        a->ldr(ptr, a64::ptr(regPtr, ptr_reg * 8));

        // Calculate address: memBase + ptr
        a->add(ptr, memBase, ptr);

        // Load qword from memory
        a->ldr(dest, a64::ptr(ptr, offset));

        // Store to VM register array
        a->str(dest, a64::ptr(regPtr, dest_reg * 8));

        return true;
    }

    return false;
}

// StoreU8: Store unsigned 8-bit to memory
bool jit_emit_store_u8(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t ptr_reg,
    int16_t offset,
    uint8_t src_reg)
{
    using namespace asmjit;

    if (strcmp(target_arch, "x86_64") == 0) {
        auto* a = static_cast<x86::Assembler*>(assembler);

        // Load pointer register from VM array (VM_REGISTERS_PTR in rbx)
        a->mov(x86::rax, x86::qword_ptr(x86::rbx, ptr_reg * 8));

        // Load source register from VM array
        a->mov(x86::rdx, x86::qword_ptr(x86::rbx, src_reg * 8));

        // Store byte to memory at [VM_MEMORY_PTR + ptr + offset]
        a->mov(x86::byte_ptr(x86::r12, x86::rax, 1, offset), x86::dl);

        return true;
    } else if (strcmp(target_arch, "aarch64") == 0) {
        auto* a = static_cast<a64::Assembler*>(assembler);

        // Load pointer register from VM array (VM_REGISTERS_PTR in x19)
        a64::Gp ptr = a64::x0;
        a64::Gp memBase = a64::x20; // VM_MEMORY_PTR
        a64::Gp src = a64::x1;
        a64::Gp regPtr = a64::x19;

        a->ldr(ptr, a64::ptr(regPtr, ptr_reg * 8));
        a->ldr(src, a64::ptr(regPtr, src_reg * 8));

        // Calculate address: memBase + ptr
        a->add(ptr, memBase, ptr);

        // Store byte to memory
        a->strb(src.w(), a64::ptr(ptr, offset));

        return true;
    }

    return false;
}

// StoreU16: Store unsigned 16-bit to memory
bool jit_emit_store_u16(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t ptr_reg,
    int16_t offset,
    uint8_t src_reg)
{
    using namespace asmjit;

    if (strcmp(target_arch, "x86_64") == 0) {
        auto* a = static_cast<x86::Assembler*>(assembler);

        // Load pointer register from VM array (VM_REGISTERS_PTR in rbx)
        a->mov(x86::rax, x86::qword_ptr(x86::rbx, ptr_reg * 8));

        // Load source register from VM array
        a->mov(x86::rdx, x86::qword_ptr(x86::rbx, src_reg * 8));

        // Store word to memory at [VM_MEMORY_PTR + ptr + offset]
        a->mov(x86::word_ptr(x86::r12, x86::rax, 1, offset), x86::dx);

        return true;
    } else if (strcmp(target_arch, "aarch64") == 0) {
        auto* a = static_cast<a64::Assembler*>(assembler);

        // Load pointer register from VM array (VM_REGISTERS_PTR in x19)
        a64::Gp ptr = a64::x0;
        a64::Gp memBase = a64::x20; // VM_MEMORY_PTR
        a64::Gp src = a64::x1;
        a64::Gp regPtr = a64::x19;

        a->ldr(ptr, a64::ptr(regPtr, ptr_reg * 8));
        a->ldr(src, a64::ptr(regPtr, src_reg * 8));

        // Calculate address: memBase + ptr
        a->add(ptr, memBase, ptr);

        // Store halfword to memory
        a->strh(src.w(), a64::ptr(ptr, offset));

        return true;
    }

    return false;
}

// StoreU32: Store unsigned 32-bit to memory
bool jit_emit_store_u32(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t ptr_reg,
    int16_t offset,
    uint8_t src_reg)
{
    using namespace asmjit;

    if (strcmp(target_arch, "x86_64") == 0) {
        auto* a = static_cast<x86::Assembler*>(assembler);

        // Load pointer register from VM array (VM_REGISTERS_PTR in rbx)
        a->mov(x86::rax, x86::qword_ptr(x86::rbx, ptr_reg * 8));

        // Load source register from VM array
        a->mov(x86::rdx, x86::qword_ptr(x86::rbx, src_reg * 8));

        // Store dword to memory at [VM_MEMORY_PTR + ptr + offset]
        a->mov(x86::dword_ptr(x86::r12, x86::rax, 1, offset), x86::edx);

        return true;
    } else if (strcmp(target_arch, "aarch64") == 0) {
        auto* a = static_cast<a64::Assembler*>(assembler);

        // Load pointer register from VM array (VM_REGISTERS_PTR in x19)
        a64::Gp ptr = a64::x0;
        a64::Gp memBase = a64::x20; // VM_MEMORY_PTR
        a64::Gp src = a64::x1;
        a64::Gp regPtr = a64::x19;

        a->ldr(ptr, a64::ptr(regPtr, ptr_reg * 8));
        a->ldr(src, a64::ptr(regPtr, src_reg * 8));

        // Calculate address: memBase + ptr
        a->add(ptr, memBase, ptr);

        // Store word to memory
        a->str(src.w(), a64::ptr(ptr, offset));

        return true;
    }

    return false;
}

// StoreU64: Store unsigned 64-bit to memory
bool jit_emit_store_u64(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t ptr_reg,
    int16_t offset,
    uint8_t src_reg)
{
    using namespace asmjit;

    if (strcmp(target_arch, "x86_64") == 0) {
        auto* a = static_cast<x86::Assembler*>(assembler);

        // Load pointer register from VM array (VM_REGISTERS_PTR in rbx)
        a->mov(x86::rax, x86::qword_ptr(x86::rbx, ptr_reg * 8));

        // Load source register from VM array
        a->mov(x86::rdx, x86::qword_ptr(x86::rbx, src_reg * 8));

        // Store qword to memory at [VM_MEMORY_PTR + ptr + offset]
        a->mov(x86::qword_ptr(x86::r12, x86::rax, 1, offset), x86::rdx);

        return true;
    } else if (strcmp(target_arch, "aarch64") == 0) {
        auto* a = static_cast<a64::Assembler*>(assembler);

        // Load pointer register from VM array (VM_REGISTERS_PTR in x19)
        a64::Gp ptr = a64::x0;
        a64::Gp memBase = a64::x20; // VM_MEMORY_PTR
        a64::Gp src = a64::x1;
        a64::Gp regPtr = a64::x19;

        a->ldr(ptr, a64::ptr(regPtr, ptr_reg * 8));
        a->ldr(src, a64::ptr(regPtr, src_reg * 8));

        // Calculate address: memBase + ptr
        a->add(ptr, memBase, ptr);

        // Store qword to memory
        a->str(src, a64::ptr(ptr, offset));

        return true;
    }

    return false;
}

// Add64: Addition (64-bit)
bool jit_emit_add_64(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t src_reg)
{
    using namespace asmjit;

    if (strcmp(target_arch, "x86_64") == 0) {
        auto* a = static_cast<x86::Assembler*>(assembler);

        // Load source register from VM array (VM_REGISTERS_PTR in rbx)
        a->mov(x86::rax, x86::qword_ptr(x86::rbx, src_reg * 8));

        // Load dest register from VM array
        a->mov(x86::rdx, x86::qword_ptr(x86::rbx, dest_reg * 8));

        // Add: dest = dest + src
        a->add(x86::rdx, x86::rax);

        // Store result back to VM register array
        a->mov(x86::qword_ptr(x86::rbx, dest_reg * 8), x86::rdx);

        return true;
    } else if (strcmp(target_arch, "aarch64") == 0) {
        auto* a = static_cast<a64::Assembler*>(assembler);

        // Load source register from VM array (VM_REGISTERS_PTR in x19)
        a64::Gp temp = a64::x0;
        a64::Gp dest = a64::x1;
        a64::Gp regPtr = a64::x19;

        a->ldr(dest, a64::ptr(regPtr, dest_reg * 8));
        a->ldr(temp, a64::ptr(regPtr, src_reg * 8));

        // Add: dest = dest + src
        a->add(dest, dest, temp);

        // Store result back to VM register array
        a->str(dest, a64::ptr(regPtr, dest_reg * 8));

        return true;
    }

    return false;
}

// Sub64: Subtraction (64-bit)
bool jit_emit_sub_64(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t src_reg)
{
    using namespace asmjit;

    if (strcmp(target_arch, "x86_64") == 0) {
        auto* a = static_cast<x86::Assembler*>(assembler);

        // Load source register from VM array (VM_REGISTERS_PTR in rbx)
        a->mov(x86::rax, x86::qword_ptr(x86::rbx, src_reg * 8));

        // Load dest register from VM array
        a->mov(x86::rdx, x86::qword_ptr(x86::rbx, dest_reg * 8));

        // Subtract: dest = dest - src
        a->sub(x86::rdx, x86::rax);

        // Store result back to VM register array
        a->mov(x86::qword_ptr(x86::rbx, dest_reg * 8), x86::rdx);

        return true;
    } else if (strcmp(target_arch, "aarch64") == 0) {
        auto* a = static_cast<a64::Assembler*>(assembler);

        // Load source register from VM array (VM_REGISTERS_PTR in x19)
        a64::Gp temp = a64::x0;
        a64::Gp dest = a64::x1;
        a64::Gp regPtr = a64::x19;

        a->ldr(dest, a64::ptr(regPtr, dest_reg * 8));
        a->ldr(temp, a64::ptr(regPtr, src_reg * 8));

        // Subtract: dest = dest - src
        a->sub(dest, dest, temp);

        // Store result back to VM register array
        a->str(dest, a64::ptr(regPtr, dest_reg * 8));

        return true;
    }

    return false;
}

// Mul64: Multiplication (64-bit)
bool jit_emit_mul_64(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t src_reg)
{
    using namespace asmjit;

    if (strcmp(target_arch, "x86_64") == 0) {
        auto* a = static_cast<x86::Assembler*>(assembler);

        // Load source register from VM array (VM_REGISTERS_PTR in rbx)
        a->mov(x86::rax, x86::qword_ptr(x86::rbx, src_reg * 8));

        // Load dest register from VM array
        a->mov(x86::rdx, x86::qword_ptr(x86::rbx, dest_reg * 8));

        // Multiply: dest = dest * src
        a->imul(x86::rdx, x86::rax);

        // Store result back to VM register array
        a->mov(x86::qword_ptr(x86::rbx, dest_reg * 8), x86::rdx);

        return true;
    } else if (strcmp(target_arch, "aarch64") == 0) {
        auto* a = static_cast<a64::Assembler*>(assembler);

        // Load source register from VM array (VM_REGISTERS_PTR in x19)
        a64::Gp temp = a64::x0;
        a64::Gp dest = a64::x1;
        a64::Gp regPtr = a64::x19;

        a->ldr(dest, a64::ptr(regPtr, dest_reg * 8));
        a->ldr(temp, a64::ptr(regPtr, src_reg * 8));

        // Multiply: dest = dest * src
        a->mul(dest, dest, temp);

        // Store result back to VM register array
        a->str(dest, a64::ptr(regPtr, dest_reg * 8));

        return true;
    }

    return false;
}

// And: Bitwise AND
bool jit_emit_and(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t src_reg)
{
    using namespace asmjit;

    if (strcmp(target_arch, "x86_64") == 0) {
        auto* a = static_cast<x86::Assembler*>(assembler);

        // Load source register from VM array (VM_REGISTERS_PTR in rbx)
        a->mov(x86::rax, x86::qword_ptr(x86::rbx, src_reg * 8));

        // Load dest register from VM array
        a->mov(x86::rdx, x86::qword_ptr(x86::rbx, dest_reg * 8));

        // AND: dest = dest & src
        a->and_(x86::rdx, x86::rax);

        // Store result back to VM register array
        a->mov(x86::qword_ptr(x86::rbx, dest_reg * 8), x86::rdx);

        return true;
    } else if (strcmp(target_arch, "aarch64") == 0) {
        auto* a = static_cast<a64::Assembler*>(assembler);

        // Load source register from VM array (VM_REGISTERS_PTR in x19)
        a64::Gp temp = a64::x0;
        a64::Gp dest = a64::x1;
        a64::Gp regPtr = a64::x19;

        a->ldr(dest, a64::ptr(regPtr, dest_reg * 8));
        a->ldr(temp, a64::ptr(regPtr, src_reg * 8));

        // AND: dest = dest & src
        a->and_(dest, dest, temp);

        // Store result back to VM register array
        a->str(dest, a64::ptr(regPtr, dest_reg * 8));

        return true;
    }

    return false;
}

// Or: Bitwise OR
bool jit_emit_or(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t src_reg)
{
    using namespace asmjit;

    if (strcmp(target_arch, "x86_64") == 0) {
        auto* a = static_cast<x86::Assembler*>(assembler);

        // Load source register from VM array (VM_REGISTERS_PTR in rbx)
        a->mov(x86::rax, x86::qword_ptr(x86::rbx, src_reg * 8));

        // Load dest register from VM array
        a->mov(x86::rdx, x86::qword_ptr(x86::rbx, dest_reg * 8));

        // OR: dest = dest | src
        a->or_(x86::rdx, x86::rax);

        // Store result back to VM register array
        a->mov(x86::qword_ptr(x86::rbx, dest_reg * 8), x86::rdx);

        return true;
    } else if (strcmp(target_arch, "aarch64") == 0) {
        auto* a = static_cast<a64::Assembler*>(assembler);

        // Load source register from VM array (VM_REGISTERS_PTR in x19)
        a64::Gp temp = a64::x0;
        a64::Gp dest = a64::x1;
        a64::Gp regPtr = a64::x19;

        a->ldr(dest, a64::ptr(regPtr, dest_reg * 8));
        a->ldr(temp, a64::ptr(regPtr, src_reg * 8));

        // OR: dest = dest | src
        a->orr(dest, dest, temp);

        // Store result back to VM register array
        a->str(dest, a64::ptr(regPtr, dest_reg * 8));

        return true;
    }

    return false;
}

// Xor: Bitwise XOR
bool jit_emit_xor(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t src_reg)
{
    using namespace asmjit;

    if (strcmp(target_arch, "x86_64") == 0) {
        auto* a = static_cast<x86::Assembler*>(assembler);

        // Load source register from VM array (VM_REGISTERS_PTR in rbx)
        a->mov(x86::rax, x86::qword_ptr(x86::rbx, src_reg * 8));

        // Load dest register from VM array
        a->mov(x86::rdx, x86::qword_ptr(x86::rbx, dest_reg * 8));

        // XOR: dest = dest ^ src
        a->xor_(x86::rdx, x86::rax);

        // Store result back to VM register array
        a->mov(x86::qword_ptr(x86::rbx, dest_reg * 8), x86::rdx);

        return true;
    } else if (strcmp(target_arch, "aarch64") == 0) {
        auto* a = static_cast<a64::Assembler*>(assembler);

        // Load source register from VM array (VM_REGISTERS_PTR in x19)
        a64::Gp temp = a64::x0;
        a64::Gp dest = a64::x1;
        a64::Gp regPtr = a64::x19;

        a->ldr(dest, a64::ptr(regPtr, dest_reg * 8));
        a->ldr(temp, a64::ptr(regPtr, src_reg * 8));

        // XOR: dest = dest ^ src
        a->eor(dest, dest, temp);

        // Store result back to VM register array
        a->str(dest, a64::ptr(regPtr, dest_reg * 8));

        return true;
    }

    return false;
}

// Jump: Unconditional jump
bool jit_emit_jump(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint32_t target_pc)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Update PC
    a->mov(x86::r15d, target_pc);

    // Jump to dispatch loop (will be implemented later)
    // For now, just return to caller

    return true;
}

// BranchEqImm: Branch if equal to immediate
bool jit_emit_branch_eq_imm(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t src_reg,
    uint64_t immediate,
    uint32_t target_pc)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load source register from VM array
    a->mov(x86::rax, x86::qword_ptr(rbx, src_reg * 8));

    // Compare with immediate
    a->cmp(x86::rax, immediate);

    // If equal, jump to target (update PC)
    // TODO: This needs proper label handling
    // For now, just update PC unconditionally (stub)
    a->mov(x86::r15d, target_pc);

    return true;
}

// BranchNeImm: Branch if not equal to immediate
bool jit_emit_branch_ne_imm(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t src_reg,
    uint64_t immediate,
    uint32_t target_pc)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load source register from VM array
    a->mov(x86::rax, x86::qword_ptr(rbx, src_reg * 8));

    // Compare with immediate
    a->cmp(x86::rax, immediate);

    // If not equal, jump to target (update PC)
    // TODO: This needs proper label handling
    // For now, just update PC unconditionally (stub)
    a->mov(x86::r15d, target_pc);

    return true;
}

// DivU32: Unsigned division (32-bit)
bool jit_emit_div_u32(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t src_reg)
{
    if (strcmp(target_arch, "x86_64") == 0) {
        auto* a = static_cast<x86::Assembler*>(assembler);

        // Load dividend (dest_reg) into eax
        a->mov(x86::eax, x86::dword_ptr(rbx, dest_reg * 8));

        // Load divisor (src_reg) into ecx
        a->mov(x86::ecx, x86::dword_ptr(rbx, src_reg * 8));

        // Zero-extend eax into edx:eax (dividend)
        a->xor_(x86::edx, x86::edx);

        // Divide: edx:eax / ecx -> eax (quotient), edx (remainder)
        a->div(x86::ecx);

        // Store quotient back to VM register array
        a->mov(x86::dword_ptr(rbx, dest_reg * 8), x86::eax);

        return true;
    } else if (strcmp(target_arch, "aarch64") == 0) {
        auto* a = static_cast<a64::Assembler*>(assembler);

        // ARM64 registers
        a64::Gp dividend = a64::w0;  // Dividend
        a64::Gp divisor = a64::w1;   // Divisor
        a64::Gp quotient = a64::w2;  // Quotient result
        a64::Gp regPtr = a64::x19;   // VM_REGISTERS_PTR

        // Load dividend (dest_reg) and divisor (src_reg)
        a->ldr(dividend, a64::ptr(regPtr, dest_reg * 8));
        a->ldr(divisor, a64::ptr(regPtr, src_reg * 8));

        // Unsigned divide: quotient = dividend / divisor
        a->udiv(quotient, dividend, divisor);

        // Store quotient back to VM register array
        a->str(quotient, a64::ptr(regPtr, dest_reg * 8));

        return true;
    }

    return false;
}

// DivS32: Signed division (32-bit)
bool jit_emit_div_s32(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t src_reg)
{
    if (strcmp(target_arch, "x86_64") == 0) {
        auto* a = static_cast<x86::Assembler*>(assembler);

        // Load dividend (dest_reg) into eax
        a->mov(x86::eax, x86::dword_ptr(rbx, dest_reg * 8));

        // Load divisor (src_reg) into ecx
        a->mov(x86::ecx, x86::dword_ptr(rbx, src_reg * 8));

        // Sign extend dividend in eax to edx:eax
        a->cdq();

        // Divide: edx:eax / ecx -> eax (quotient), edx (remainder)
        a->idiv(x86::ecx);

        // Store quotient back to VM register array
        a->mov(x86::dword_ptr(rbx, dest_reg * 8), x86::eax);

        return true;
    } else if (strcmp(target_arch, "aarch64") == 0) {
        auto* a = static_cast<a64::Assembler*>(assembler);

        // ARM64 registers
        a64::Gp dividend = a64::w0;  // Dividend
        a64::Gp divisor = a64::w1;   // Divisor
        a64::Gp quotient = a64::w2;  // Quotient result
        a64::Gp regPtr = a64::x19;   // VM_REGISTERS_PTR

        // Load dividend (dest_reg) and divisor (src_reg)
        a->ldr(dividend, a64::ptr(regPtr, dest_reg * 8));
        a->ldr(divisor, a64::ptr(regPtr, src_reg * 8));

        // Signed divide: quotient = dividend / divisor
        a->sdiv(quotient, dividend, divisor);

        // Store quotient back to VM register array
        a->str(quotient, a64::ptr(regPtr, dest_reg * 8));

        return true;
    }

    return false;
}

// RemU32: Unsigned remainder (32-bit)
bool jit_emit_rem_u32(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t src_reg)
{
    if (strcmp(target_arch, "x86_64") == 0) {
        auto* a = static_cast<x86::Assembler*>(assembler);

        // Load dividend (dest_reg) into eax
        a->mov(x86::eax, x86::dword_ptr(rbx, dest_reg * 8));

        // Load divisor (src_reg) into ecx
        a->mov(x86::ecx, x86::dword_ptr(rbx, src_reg * 8));

        // Zero-extend eax into edx:eax (dividend)
        a->xor_(x86::edx, x86::edx);

        // Divide: edx:eax / ecx -> eax (quotient), edx (remainder)
        a->div(x86::ecx);

        // Store remainder back to VM register array
        a->mov(x86::dword_ptr(rbx, dest_reg * 8), x86::edx);

        return true;
    } else if (strcmp(target_arch, "aarch64") == 0) {
        auto* a = static_cast<a64::Assembler*>(assembler);

        // ARM64 registers
        a64::Gp dividend = a64::w0;  // Dividend
        a64::Gp divisor = a64::w1;   // Divisor
        a64::Gp quotient = a64::w2;  // Quotient (temporary)
        a64::Gp remainder = a64::w3; // Remainder result
        a64::Gp regPtr = a64::x19;   // VM_REGISTERS_PTR

        // Load dividend (dest_reg) and divisor (src_reg)
        a->ldr(dividend, a64::ptr(regPtr, dest_reg * 8));
        a->ldr(divisor, a64::ptr(regPtr, src_reg * 8));

        // Unsigned divide to get quotient
        a->udiv(quotient, dividend, divisor);

        // Calculate remainder: remainder = dividend - (quotient * divisor)
        // Using msub: remainder = dividend - quotient * divisor
        a->msub(remainder, quotient, divisor, dividend);

        // Store remainder back to VM register array
        a->str(remainder, a64::ptr(regPtr, dest_reg * 8));

        return true;
    }

    return false;
}

// RemS32: Signed remainder (32-bit)
bool jit_emit_rem_s32(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t src_reg)
{
    if (strcmp(target_arch, "x86_64") == 0) {
        auto* a = static_cast<x86::Assembler*>(assembler);

        // Load dividend (dest_reg) into eax
        a->mov(x86::eax, x86::dword_ptr(rbx, dest_reg * 8));

        // Load divisor (src_reg) into ecx
        a->mov(x86::ecx, x86::dword_ptr(rbx, src_reg * 8));

        // Sign extend dividend in eax to edx:eax
        a->cdq();

        // Divide: edx:eax / ecx -> eax (quotient), edx (remainder)
        a->idiv(x86::ecx);

        // Store remainder back to VM register array
        a->mov(x86::dword_ptr(rbx, dest_reg * 8), x86::edx);

        return true;
    } else if (strcmp(target_arch, "aarch64") == 0) {
        auto* a = static_cast<a64::Assembler*>(assembler);

        // ARM64 registers
        a64::Gp dividend = a64::w0;  // Dividend
        a64::Gp divisor = a64::w1;   // Divisor
        a64::Gp quotient = a64::w2;  // Quotient (temporary)
        a64::Gp remainder = a64::w3; // Remainder result
        a64::Gp regPtr = a64::x19;   // VM_REGISTERS_PTR

        // Load dividend (dest_reg) and divisor (src_reg)
        a->ldr(dividend, a64::ptr(regPtr, dest_reg * 8));
        a->ldr(divisor, a64::ptr(regPtr, src_reg * 8));

        // Signed divide to get quotient
        a->sdiv(quotient, dividend, divisor);

        // Calculate remainder: remainder = dividend - (quotient * divisor)
        // Using msub: remainder = dividend - quotient * divisor
        a->msub(remainder, quotient, divisor, dividend);

        // Store remainder back to VM register array
        a->str(remainder, a64::ptr(regPtr, dest_reg * 8));

        return true;
    }

    return false;
}

// ShloL32: Shift left logical (32-bit)
bool jit_emit_shlo_l_32(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t src_reg)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load source register from VM array (shift count)
    a->mov(x86::eax, x86::dword_ptr(rbx, src_reg * 8));

    // Load dest register from VM array (value to shift)
    a->mov(x86::edx, x86::dword_ptr(rbx, dest_reg * 8));

    // Mask shift count to 5 bits
    a->and_(x86::eax, 0x1F);

    // Shift left: dest = dest << src
    a->shl(x86::edx, x86::cl);

    // Store result back to VM register array
    a->mov(x86::dword_ptr(rbx, dest_reg * 8), x86::edx);

    return true;
}

// ShloR32: Shift right logical (32-bit)
bool jit_emit_shlo_r_32(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t src_reg)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load source register from VM array (shift count)
    a->mov(x86::eax, x86::dword_ptr(rbx, src_reg * 8));

    // Load dest register from VM array (value to shift)
    a->mov(x86::edx, x86::dword_ptr(rbx, dest_reg * 8));

    // Mask shift count to 5 bits
    a->and_(x86::eax, 0x1F);

    // Shift right logical: dest = dest >> src
    a->shr(x86::edx, x86::cl);

    // Store result back to VM register array
    a->mov(x86::dword_ptr(rbx, dest_reg * 8), x86::edx);

    return true;
}

// SharR32: Shift right arithmetic (32-bit)
bool jit_emit_shar_r_32(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t src_reg)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load source register from VM array (shift count)
    a->mov(x86::eax, x86::dword_ptr(rbx, src_reg * 8));

    // Load dest register from VM array (value to shift)
    a->mov(x86::edx, x86::dword_ptr(rbx, dest_reg * 8));

    // Mask shift count to 5 bits
    a->and_(x86::eax, 0x1F);

    // Shift right arithmetic: dest = dest >> src (sign-extending)
    a->sar(x86::edx, x86::cl);

    // Store result back to VM register array
    a->mov(x86::dword_ptr(rbx, dest_reg * 8), x86::edx);

    return true;
}

// ShloL64: Shift left logical (64-bit)
bool jit_emit_shlo_l_64(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t src_reg)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load source register from VM array (shift count)
    a->mov(x86::rax, x86::qword_ptr(rbx, src_reg * 8));

    // Load dest register from VM array (value to shift)
    a->mov(x86::rdx, x86::qword_ptr(rbx, dest_reg * 8));

    // Mask shift count to 6 bits
    a->and_(x86::rax, 0x3F);

    // Shift left: dest = dest << src
    a->shl(x86::rdx, x86::cl);

    // Store result back to VM register array
    a->mov(x86::qword_ptr(rbx, dest_reg * 8), x86::rdx);

    return true;
}

// ShloR64: Shift right logical (64-bit)
bool jit_emit_shlo_r_64(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t src_reg)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load source register from VM array (shift count)
    a->mov(x86::rax, x86::qword_ptr(rbx, src_reg * 8));

    // Load dest register from VM array (value to shift)
    a->mov(x86::rdx, x86::qword_ptr(rbx, dest_reg * 8));

    // Mask shift count to 6 bits
    a->and_(x86::rax, 0x3F);

    // Shift right logical: dest = dest >> src
    a->shr(x86::rdx, x86::cl);

    // Store result back to VM register array
    a->mov(x86::qword_ptr(rbx, dest_reg * 8), x86::rdx);

    return true;
}

// SharR64: Shift right arithmetic (64-bit)
bool jit_emit_shar_r_64(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t src_reg)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load source register from VM array (shift count)
    a->mov(x86::rax, x86::qword_ptr(rbx, src_reg * 8));

    // Load dest register from VM array (value to shift)
    a->mov(x86::rdx, x86::qword_ptr(rbx, dest_reg * 8));

    // Mask shift count to 6 bits
    a->and_(x86::rax, 0x3F);

    // Shift right arithmetic: dest = dest >> src (sign-extending)
    a->sar(x86::rdx, x86::cl);

    // Store result back to VM register array
    a->mov(x86::qword_ptr(rbx, dest_reg * 8), x86::rdx);

    return true;
}

// RotL32: Rotate left (32-bit)
bool jit_emit_rot_l_32(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t src_reg)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load source register from VM array (shift count)
    a->mov(x86::eax, x86::dword_ptr(rbx, src_reg * 8));

    // Load dest register from VM array (value to rotate)
    a->mov(x86::edx, x86::dword_ptr(rbx, dest_reg * 8));

    // Mask shift count to 5 bits (x86 requires this for rotate)
    a->and_(x86::eax, 0x1F);

    // Rotate left through carry: dest = dest << src | dest >> (32 - src)
    // Using rol instruction which does the full rotation
    a->rol(x86::edx, x86::cl);

    // Store result back to VM register array
    a->mov(x86::dword_ptr(rbx, dest_reg * 8), x86::edx);

    return true;
}

// RotR32: Rotate right (32-bit)
bool jit_emit_rot_r_32(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t src_reg)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load source register from VM array (shift count)
    a->mov(x86::eax, x86::dword_ptr(rbx, src_reg * 8));

    // Load dest register from VM array (value to rotate)
    a->mov(x86::edx, x86::dword_ptr(rbx, dest_reg * 8));

    // Mask shift count to 5 bits (x86 requires this for rotate)
    a->and_(x86::eax, 0x1F);

    // Rotate right through carry: dest = dest >> src | dest << (32 - src)
    // Using ror instruction which does the full rotation
    a->ror(x86::edx, x86::cl);

    // Store result back to VM register array
    a->mov(x86::dword_ptr(rbx, dest_reg * 8), x86::edx);

    return true;
}

// Eq: Equality comparison
bool jit_emit_eq(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t src_reg)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load source register from VM array
    a->mov(x86::rax, x86::qword_ptr(rbx, src_reg * 8));

    // Load dest register from VM array
    a->mov(x86::rdx, x86::qword_ptr(rbx, dest_reg * 8));

    // Compare: dest - src
    // Set flags, result is 0 if equal, 1 if dest > src, -1 if dest < src
    // We want: 1 if equal, 0 otherwise
    a->cmp(x86::rdx, x86::rax);

    // Set result to 1 if equal (ZF=1), 0 otherwise
    // Use sete which sets to 1 if zero flag is set
    a->sete(x86::al);

    // Zero-extend to 64-bit
    a->movzx(x86::rax, x86::al);

    // Store result back to VM register array
    a->mov(x86::qword_ptr(rbx, dest_reg * 8), x86::rax);

    return true;
}

// Ne: Not-equal comparison
bool jit_emit_ne(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t src_reg)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load source register from VM array
    a->mov(x86::rax, x86::qword_ptr(rbx, src_reg * 8));

    // Load dest register from VM array
    a->mov(x86::rdx, x86::qword_ptr(rbx, dest_reg * 8));

    // Compare: dest - src
    a->cmp(x86::rdx, x86::rax);

    // Set result to 1 if not equal (ZF=0), 0 otherwise
    // Use setne which sets to 1 if zero flag is clear
    a->setne(x86::al);

    // Zero-extend to 64-bit
    a->movzx(x86::rax, x86::al);

    // Store result back to VM register array
    a->mov(x86::qword_ptr(rbx, dest_reg * 8), x86::rax);

    return true;
}

// Lt: Less-than signed (32-bit)
bool jit_emit_lt_32(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t src_reg)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load source register from VM array
    a->mov(x86::eax, x86::dword_ptr(rbx, src_reg * 8));

    // Load dest register from VM array
    a->mov(x86::edx, x86::dword_ptr(rbx, dest_reg * 8));

    // Compare: dest - src (signed)
    a->cmp(x86::edx, x86::eax);

    // Set result to 1 if less (SF!=OF and ZF=0), 0 otherwise
    // Use setl which sets to 1 if less (signed)
    a->setl(x86::al);

    // Zero-extend to 64-bit
    a->movzx(x86::rax, x86::al);

    // Store result back to VM register array
    a->mov(x86::qword_ptr(rbx, dest_reg * 8), x86::rax);

    return true;
}

// LtU: Less-than unsigned (32-bit)
bool jit_emit_lt_u_32(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t src_reg)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load source register from VM array
    a->mov(x86::eax, x86::dword_ptr(rbx, src_reg * 8));

    // Load dest register from VM array
    a->mov(x86::edx, x86::dword_ptr(rbx, dest_reg * 8));

    // Compare: dest - src (unsigned)
    a->cmp(x86::edx, x86::eax);

    // Set result to 1 if less (unsigned), 0 otherwise
    // Use setb which sets to 1 if below (unsigned)
    a->setb(x86::al);

    // Zero-extend to 64-bit
    a->movzx(x86::rax, x86::al);

    // Store result back to VM register array
    a->mov(x86::qword_ptr(rbx, dest_reg * 8), x86::rax);

    return true;
}

// Gt: Greater-than signed (32-bit)
bool jit_emit_gt_32(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t src_reg)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load source register from VM array
    a->mov(x86::eax, x86::dword_ptr(rbx, src_reg * 8));

    // Load dest register from VM array
    a->mov(x86::edx, x86::dword_ptr(rbx, dest_reg * 8));

    // Compare: dest - src (signed)
    a->cmp(x86::edx, x86::eax);

    // Set result to 1 if greater (SF=OF and ZF=0), 0 otherwise
    // Use setg which sets to 1 if greater (signed)
    a->setg(x86::al);

    // Zero-extend to 64-bit
    a->movzx(x86::rax, x86::al);

    // Store result back to VM register array
    a->mov(x86::qword_ptr(rbx, dest_reg * 8), x86::rax);

    return true;
}

// GtU: Greater-than unsigned (32-bit)
bool jit_emit_gt_u_32(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t src_reg)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load source register from VM array
    a->mov(x86::eax, x86::dword_ptr(rbx, src_reg * 8));

    // Load dest register from VM array
    a->mov(x86::edx, x86::dword_ptr(rbx, dest_reg * 8));

    // Compare: dest - src (unsigned)
    a->cmp(x86::edx, x86::eax);

    // Set result to 1 if greater (unsigned), 0 otherwise
    // Use seta which sets to 1 if above (unsigned)
    a->seta(x86::al);

    // Zero-extend to 64-bit
    a->movzx(x86::rax, x86::al);

    // Store result back to VM register array
    a->mov(x86::qword_ptr(rbx, dest_reg * 8), x86::rax);

    return true;
}

// BranchEq: Branch if equal (register-register)
bool jit_emit_branch_eq(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t src1_reg,
    uint8_t src2_reg,
    uint32_t target_pc)
{
    using namespace asmjit;

    if (strcmp(target_arch, "x86_64") == 0) {
        auto* a = static_cast<x86::Assembler*>(assembler);

        // Load src1 from VM array (VM_REGISTERS_PTR in rbx)
        a->mov(x86::rax, x86::qword_ptr(x86::rbx, src1_reg * 8));

        // Load src2 from VM array
        a->mov(x86::rdx, x86::qword_ptr(x86::rbx, src2_reg * 8));

        // Compare registers
        a->cmp(x86::rax, x86::rdx);

        // If equal, jump to target (update PC)
        // Otherwise fall through to next instruction
        Label skipLabel = a->newLabel();
        a->jne(skipLabel);  // Skip PC update if not equal
        a->mov(x86::r15d, target_pc);  // Only update PC if equal
        a->bind(skipLabel);

        return true;
    } else if (strcmp(target_arch, "aarch64") == 0) {
        auto* a = static_cast<a64::Assembler*>(assembler);

        // Load src1 from VM array (VM_REGISTERS_PTR in x19)
        a64::Gp src1 = a64::x0;
        a64::Gp src2 = a64::x1;
        a64::Gp pcReg = a64::w23; // PC
        a64::Gp regPtr = a64::x19;

        a->ldr(src1, a64::ptr(regPtr, src1_reg * 8));
        a->ldr(src2, a64::ptr(regPtr, src2_reg * 8));

        // Compare registers
        a->cmp(src1, src2);

        // If equal, jump to target (update PC)
        // Otherwise fall through to next instruction
        Label skipLabel = a->newLabel();
        a->b_ne(skipLabel);  // Skip PC update if not equal
        a->mov(pcReg, target_pc);  // Only update PC if equal
        a->bind(skipLabel);

        return true;
    }

    return false;
}

// BranchNe: Branch if not equal (register-register)
bool jit_emit_branch_ne(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t src1_reg,
    uint8_t src2_reg,
    uint32_t target_pc)
{
    using namespace asmjit;

    if (strcmp(target_arch, "x86_64") == 0) {
        auto* a = static_cast<x86::Assembler*>(assembler);

        // Load src1 from VM array (VM_REGISTERS_PTR in rbx)
        a->mov(x86::rax, x86::qword_ptr(x86::rbx, src1_reg * 8));

        // Load src2 from VM array
        a->mov(x86::rdx, x86::qword_ptr(x86::rbx, src2_reg * 8));

        // Compare registers
        a->cmp(x86::rax, x86::rdx);

        // If not equal, jump to target (update PC)
        // Otherwise fall through to next instruction
        Label skipLabel = a->newLabel();
        a->je(skipLabel);  // Skip PC update if equal
        a->mov(x86::r15d, target_pc);  // Only update PC if not equal
        a->bind(skipLabel);

        return true;
    } else if (strcmp(target_arch, "aarch64") == 0) {
        auto* a = static_cast<a64::Assembler*>(assembler);

        // Load src1 from VM array (VM_REGISTERS_PTR in x19)
        a64::Gp src1 = a64::x0;
        a64::Gp src2 = a64::x1;
        a64::Gp pcReg = a64::w23; // PC
        a64::Gp regPtr = a64::x19;

        a->ldr(src1, a64::ptr(regPtr, src1_reg * 8));
        a->ldr(src2, a64::ptr(regPtr, src2_reg * 8));

        // Compare registers
        a->cmp(src1, src2);

        // If not equal, jump to target (update PC)
        // Otherwise fall through to next instruction
        Label skipLabel = a->newLabel();
        a->b_eq(skipLabel);  // Skip PC update if equal
        a->mov(pcReg, target_pc);  // Only update PC if not equal
        a->bind(skipLabel);

        return true;
    }

    return false;
}

// LoadImmJump: Load immediate and jump
bool jit_emit_load_imm_jump(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint32_t immediate)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load immediate into PC register (jump to immediate)
    a->mov(x86::r15d, immediate);

    return true;
}

// JumpInd: Indirect jump through register
bool jit_emit_jump_ind(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t ptr_reg,
    uint32_t offset)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load target address from register
    a->mov(x86::rax, x86::qword_ptr(rbx, ptr_reg * 8));

    // Add offset to get target address
    a->add(x86::rax, offset);

    // Jump to target (update PC)
    a->mov(x86::r15d, x86::eax);

    return true;
}

// Fallthrough: No-op instruction
bool jit_emit_fallthrough(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Fallthrough is essentially a no-op in JIT context
    // Just increment PC (handled by dispatch loop)
    // No code generation needed here

    return true;
}

// Ecalli: External call interface
bool jit_emit_ecalli(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint32_t call_index)
{
    // Ecalli is handled directly in the labeled helpers
    // This is a stub for the dispatcher
    return true;
}

// Sbrk: System break (allocate memory)
bool jit_emit_sbrk(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t ptr_reg,
    int32_t offset)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // TODO: Implement memory allocation
    // For now, just return error
    a->mov(x86::rax, 0xFFFFFFFF);  // Error: not implemented

    return true;
}

// BranchLtImm: Branch if less-than signed (immediate)
bool jit_emit_branch_lt_imm(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t src_reg,
    uint64_t immediate,
    uint32_t target_pc)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load source register from VM array
    a->mov(x86::rax, x86::qword_ptr(rbx, src_reg * 8));

    // Compare with immediate (signed)
    a->cmp(x86::rax, immediate);

    // If less, jump to target (update PC)
    // TODO: This needs proper label handling with conditional jump
    // For now, just update PC unconditionally (stub)
    a->mov(x86::r15d, target_pc);

    return true;
}

// BranchLtUImm: Branch if less-than unsigned (immediate)
bool jit_emit_branch_lt_u_imm(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t src_reg,
    uint64_t immediate,
    uint32_t target_pc)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load source register from VM array
    a->mov(x86::rax, x86::qword_ptr(rbx, src_reg * 8));

    // Compare with immediate (unsigned)
    a->cmp(x86::rax, immediate);

    // If less (unsigned), jump to target (update PC)
    // TODO: This needs proper label handling with conditional jump
    // For now, just update PC unconditionally (stub)
    a->mov(x86::r15d, target_pc);

    return true;
}

// BranchGtImm: Branch if greater-than signed (immediate)
bool jit_emit_branch_gt_imm(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t src_reg,
    uint64_t immediate,
    uint32_t target_pc)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load source register from VM array
    a->mov(x86::rax, x86::qword_ptr(rbx, src_reg * 8));

    // Compare with immediate (signed)
    a->cmp(x86::rax, immediate);

    // If greater, jump to target (update PC)
    // TODO: This needs proper label handling with conditional jump
    // For now, just update PC unconditionally (stub)
    a->mov(x86::r15d, target_pc);

    return true;
}

// BranchGtUImm: Branch if greater-than unsigned (immediate)
bool jit_emit_branch_gt_u_imm(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t src_reg,
    uint64_t immediate,
    uint32_t target_pc)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load source register from VM array
    a->mov(x86::rax, x86::qword_ptr(rbx, src_reg * 8));

    // Compare with immediate (unsigned)
    a->cmp(x86::rax, immediate);

    // If greater (unsigned), jump to target (update PC)
    // TODO: This needs proper label handling with conditional jump
    // For now, just update PC unconditionally (stub)
    a->mov(x86::r15d, target_pc);

    return true;
}

// BranchLt: Branch if less-than signed (register-register)
bool jit_emit_branch_lt(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t src1_reg,
    uint8_t src2_reg,
    uint32_t target_pc)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load src1 from VM array
    a->mov(x86::rax, x86::qword_ptr(rbx, src1_reg * 8));

    // Load src2 from VM array
    a->mov(x86::rdx, x86::qword_ptr(rbx, src2_reg * 8));

    // Compare registers (signed)
    a->cmp(x86::rax, x86::rdx);

    // If less, jump to target (update PC)
    // TODO: This needs proper label handling with conditional jump
    // For now, just update PC unconditionally (stub)
    a->mov(x86::r15d, target_pc);

    return true;
}

// BranchLtU: Branch if less-than unsigned (register-register)
bool jit_emit_branch_lt_u(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t src1_reg,
    uint8_t src2_reg,
    uint32_t target_pc)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load src1 from VM array
    a->mov(x86::rax, x86::qword_ptr(rbx, src1_reg * 8));

    // Load src2 from VM array
    a->mov(x86::rdx, x86::qword_ptr(rbx, src2_reg * 8));

    // Compare registers (unsigned)
    a->cmp(x86::rax, x86::rdx);

    // If less (unsigned), jump to target (update PC)
    // TODO: This needs proper label handling with conditional jump
    // For now, just update PC unconditionally (stub)
    a->mov(x86::r15d, target_pc);

    return true;
}

// BranchGt: Branch if greater-than signed (register-register)
bool jit_emit_branch_gt(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t src1_reg,
    uint8_t src2_reg,
    uint32_t target_pc)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load src1 from VM array
    a->mov(x86::rax, x86::qword_ptr(rbx, src1_reg * 8));

    // Load src2 from VM array
    a->mov(x86::rdx, x86::qword_ptr(rbx, src2_reg * 8));

    // Compare registers (signed)
    a->cmp(x86::rax, x86::rdx);

    // If greater, jump to target (update PC)
    // TODO: This needs proper label handling with conditional jump
    // For now, just update PC unconditionally (stub)
    a->mov(x86::r15d, target_pc);

    return true;
}

// BranchGtU: Branch if greater-than unsigned (register-register)
bool jit_emit_branch_gt_u(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t src1_reg,
    uint8_t src2_reg,
    uint32_t target_pc)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load src1 from VM array
    a->mov(x86::rax, x86::qword_ptr(rbx, src1_reg * 8));

    // Load src2 from VM array
    a->mov(x86::rdx, x86::qword_ptr(rbx, src2_reg * 8));

    // Compare registers (unsigned)
    a->cmp(x86::rax, x86::rdx);

    // If greater (unsigned), jump to target (update PC)
    // TODO: This needs proper label handling with conditional jump
    // For now, just update PC unconditionally (stub)
    a->mov(x86::r15d, target_pc);

    return true;
}

// Max: Maximum of two values (signed)
bool jit_emit_max(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t src_reg)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load source register from VM array
    a->mov(x86::rax, x86::qword_ptr(rbx, src_reg * 8));

    // Load dest register from VM array
    a->mov(x86::rdx, x86::qword_ptr(rbx, dest_reg * 8));

    // Compare: dest - src (signed)
    a->cmp(x86::rdx, x86::rax);

    // Conditional move: if dest >= src, keep dest; otherwise, move src to dest
    // Use cmovge (conditional move if greater or equal)
    a->cmovge(x86::rdx, x86::rax);

    // Store result back to VM register array
    a->mov(x86::qword_ptr(rbx, dest_reg * 8), x86::rdx);

    return true;
}

// MaxU: Maximum of two values (unsigned)
bool jit_emit_max_u(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t src_reg)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load source register from VM array
    a->mov(x86::rax, x86::qword_ptr(rbx, src_reg * 8));

    // Load dest register from VM array
    a->mov(x86::rdx, x86::qword_ptr(rbx, dest_reg * 8));

    // Compare: dest - src (unsigned)
    a->cmp(x86::rdx, x86::rax);

    // Conditional move: if dest >= src (unsigned), keep dest; otherwise, move src to dest
    // Use cmovae (conditional move if above or equal)
    a->cmovae(x86::rdx, x86::rax);

    // Store result back to VM register array
    a->mov(x86::qword_ptr(rbx, dest_reg * 8), x86::rdx);

    return true;
}

// Min: Minimum of two values (signed)
bool jit_emit_min(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t src_reg)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load source register from VM array
    a->mov(x86::rax, x86::qword_ptr(rbx, src_reg * 8));

    // Load dest register from VM array
    a->mov(x86::rdx, x86::qword_ptr(rbx, dest_reg * 8));

    // Compare: dest - src (signed)
    a->cmp(x86::rdx, x86::rax);

    // Conditional move: if dest <= src, keep dest; otherwise, move src to dest
    // Use cmovle (conditional move if less or equal)
    a->cmovle(x86::rdx, x86::rax);

    // Store result back to VM register array
    a->mov(x86::qword_ptr(rbx, dest_reg * 8), x86::rdx);

    return true;
}

// MinU: Minimum of two values (unsigned)
bool jit_emit_min_u(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t src_reg)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load source register from VM array
    a->mov(x86::rax, x86::qword_ptr(rbx, src_reg * 8));

    // Load dest register from VM array
    a->mov(x86::rdx, x86::qword_ptr(rbx, dest_reg * 8));

    // Compare: dest - src (unsigned)
    a->cmp(x86::rdx, x86::rax);

    // Conditional move: if dest <= src (unsigned), keep dest; otherwise, move src to dest
    // Use cmovbe (conditional move if below or equal)
    a->cmovbe(x86::rdx, x86::rax);

    // Store result back to VM register array
    a->mov(x86::qword_ptr(rbx, dest_reg * 8), x86::rdx);

    return true;
}

// AndInv: Bitwise AND with inverted source
bool jit_emit_and_inv(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t src_reg)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load source register from VM array
    a->mov(x86::rax, x86::qword_ptr(rbx, src_reg * 8));

    // Load dest register from VM array
    a->mov(x86::rdx, x86::qword_ptr(rbx, dest_reg * 8));

    // Invert source
    a->not_(x86::rax);

    // AND: dest = dest & ~src
    a->and_(x86::rdx, x86::rax);

    // Store result back to VM register array
    a->mov(x86::qword_ptr(rbx, dest_reg * 8), x86::rdx);

    return true;
}

// OrInv: Bitwise OR with inverted source
bool jit_emit_or_inv(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t src_reg)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load source register from VM array
    a->mov(x86::rax, x86::qword_ptr(rbx, src_reg * 8));

    // Load dest register from VM array
    a->mov(x86::rdx, x86::qword_ptr(rbx, dest_reg * 8));

    // Invert source
    a->not_(x86::rax);

    // OR: dest = dest | ~src
    a->or_(x86::rdx, x86::rax);

    // Store result back to VM register array
    a->mov(x86::qword_ptr(rbx, dest_reg * 8), x86::rdx);

    return true;
}

// Xnor: Bitwise XNOR (exclusive NOR)
bool jit_emit_xnor(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t src_reg)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load source register from VM array
    a->mov(x86::rax, x86::qword_ptr(rbx, src_reg * 8));

    // Load dest register from VM array
    a->mov(x86::rdx, x86::qword_ptr(rbx, dest_reg * 8));

    // XOR: dest = dest ^ src
    a->xor_(x86::rdx, x86::rax);

    // Invert result: ~(dest ^ src)
    a->not_(x86::rdx);

    // Store result back to VM register array
    a->mov(x86::qword_ptr(rbx, dest_reg * 8), x86::rdx);

    return true;
}

// Lea: Load effective address
bool jit_emit_lea(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t ptr_reg,
    int16_t offset)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load pointer register from VM array
    a->mov(x86::rax, x86::qword_ptr(rbx, ptr_reg * 8));

    // Calculate effective address: ptr + offset
    a->add(x86::rax, offset);

    // Store result to VM register array
    a->mov(x86::qword_ptr(rbx, dest_reg * 8), x86::rax);

    return true;
}

// LeadingZeros: Count leading zeros in 64-bit value
bool jit_emit_leading_zeros(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t src_reg)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load source register from VM array
    a->mov(x86::rax, x86::qword_ptr(rbx, src_reg * 8));

    // Save original value for zero check
    a->mov(x86::rdx, x86::rax);

    // Count leading zeros using lzcnt (BMI1 instruction)
    // If lzcnt is not available, we need to use bsr + calculation
    // For now, let's use the lzcnt approach which is simpler
    // lzcnt: counts leading zeros, returns 64 if input is zero
    a->lzcnt(x86::rax, x86::rdx);

    // Store result back to VM register array
    a->mov(x86::qword_ptr(rbx, dest_reg * 8), x86::rax);

    return true;
}

// TrailingZeros: Count trailing zeros in 64-bit value
bool jit_emit_trailing_zeros(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t src_reg)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load source register from VM array
    a->mov(x86::rax, x86::qword_ptr(rbx, src_reg * 8));

    // Test if value is zero
    a->test(x86::rax, x86::rax);

    // Count trailing zeros using tzcnt (BMI1 instruction)
    // For compatibility, use bsf + calculation
    a->bsf(x86::rax, x86::rax);

    // If value was zero, bsf doesn't change destination, so we need to handle it
    // If zero, result is 64
    a->mov(x86::rdx, 64);
    a->cmovne(x86::rdx, x86::rax);  // If not zero, use bsf result

    // Store result back to VM register array
    a->mov(x86::qword_ptr(rbx, dest_reg * 8), x86::rdx);

    return true;
}

// PopCount: Count set bits in 64-bit value
bool jit_emit_pop_count(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t src_reg)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load source register from VM array
    a->mov(x86::rax, x86::qword_ptr(rbx, src_reg * 8));

    // Count set bits using popcnt (SSE4.2 instruction)
    // This is widely available on modern x86_64 processors
    a->popcnt(x86::rax, x86::rax);

    // Store result back to VM register array
    a->mov(x86::qword_ptr(rbx, dest_reg * 8), x86::rax);

    return true;
}

// ZeroExtend8: Zero-extend 8-bit to 64-bit
bool jit_emit_zero_extend_8(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t src_reg)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load source register from VM array (8-bit)
    a->mov(x86::eax, x86::dword_ptr(rbx, src_reg * 8));

    // Zero-extend 8-bit to 64-bit
    a->movzx(x86::rax, x86::al);

    // Store result back to VM register array
    a->mov(x86::qword_ptr(rbx, dest_reg * 8), x86::rax);

    return true;
}

// ZeroExtend16: Zero-extend 16-bit to 64-bit
bool jit_emit_zero_extend_16(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t src_reg)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load source register from VM array (16-bit)
    a->mov(x86::eax, x86::dword_ptr(rbx, src_reg * 8));

    // Zero-extend 16-bit to 64-bit
    a->movzx(x86::rax, x86::ax);

    // Store result back to VM register array
    a->mov(x86::qword_ptr(rbx, dest_reg * 8), x86::rax);

    return true;
}

// ZeroExtend32: Zero-extend 32-bit to 64-bit
bool jit_emit_zero_extend_32(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t src_reg)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load source register from VM array (32-bit)
    a->mov(x86::eax, x86::dword_ptr(rbx, src_reg * 8));

    // Zero-extend 32-bit to 64-bit (mov to rax automatically zero-extends)
    a->mov(x86::rax, x86::eax);

    // Store result back to VM register array
    a->mov(x86::qword_ptr(rbx, dest_reg * 8), x86::rax);

    return true;
}

// SignExtend8: Sign-extend 8-bit to 64-bit
bool jit_emit_sign_extend_8(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t src_reg)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load source register from VM array (8-bit)
    a->movsx(x86::rax, x86::byte_ptr(rbx, src_reg * 8));

    // Store result back to VM register array
    a->mov(x86::qword_ptr(rbx, dest_reg * 8), x86::rax);

    return true;
}

// SignExtend16: Sign-extend 16-bit to 64-bit
bool jit_emit_sign_extend_16(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t src_reg)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load source register from VM array (16-bit)
    a->movsx(x86::rax, x86::word_ptr(rbx, src_reg * 8));

    // Store result back to VM register array
    a->mov(x86::qword_ptr(rbx, dest_reg * 8), x86::rax);

    return true;
}

// SignExtend32: Sign-extend 32-bit to 64-bit
bool jit_emit_sign_extend_32(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t src_reg)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load source register from VM array (32-bit)
    a->movsx(x86::rax, x86::dword_ptr(rbx, src_reg * 8));

    // Store result back to VM register array
    a->mov(x86::qword_ptr(rbx, dest_reg * 8), x86::rax);

    return true;
}

// LoadU32: Load unsigned 32-bit from memory
bool jit_emit_load_u32(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t ptr_reg,
    int16_t offset)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load pointer register from VM array
    a->mov(x86::rax, x86::qword_ptr(rbx, ptr_reg * 8));

    // Load unsigned dword from memory at [ptr + offset]
    a->mov(x86::eax, x86::dword_ptr(x86::r12, x86::rax, 1, offset));

    // Zero-extend and store to VM register array
    a->mov(x86::qword_ptr(rbx, dest_reg * 8), x86::rax);

    return true;
}

// LoadI32: Load signed 32-bit from memory (sign-extended)
bool jit_emit_load_i32(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t ptr_reg,
    int16_t offset)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load pointer register from VM array
    a->mov(x86::rax, x86::qword_ptr(rbx, ptr_reg * 8));

    // Load signed dword from memory at [ptr + offset] with sign extension
    a->movsx(x86::rax, x86::dword_ptr(x86::r12, x86::rax, 1, offset));

    // Store to VM register array
    a->mov(x86::qword_ptr(rbx, dest_reg * 8), x86::rax);

    return true;
}

// Copy: Copy register to register
bool jit_emit_copy(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t src_reg)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load source register from VM array
    a->mov(x86::rax, x86::qword_ptr(rbx, src_reg * 8));

    // Store to destination register in VM array
    a->mov(x86::qword_ptr(rbx, dest_reg * 8), x86::rax);

    return true;
}

// Select: Conditional select (if condition is true, select true_reg, else false_reg)
bool jit_emit_select(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t condition_reg,
    uint8_t true_reg,
    uint8_t false_reg)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load condition register from VM array
    a->mov(x86::rax, x86::qword_ptr(rbx, condition_reg * 8));

    // Test if condition is non-zero
    a->test(x86::rax, x86::rax);

    // Load true value
    a->mov(x86::rdx, x86::qword_ptr(rbx, true_reg * 8));

    // Load false value
    a->mov(x86::rcx, x86::qword_ptr(rbx, false_reg * 8));

    // Conditional move: if condition != 0, move rdx to rax, else move rcx to rax
    a->cmovne(x86::rdx, x86::rcx);

    // Store result back to VM register array
    a->mov(x86::qword_ptr(rbx, dest_reg * 8), x86::rdx);

    return true;
}

// Store32: Store 32-bit to memory
bool jit_emit_store_32(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t ptr_reg,
    uint8_t src_reg,
    int16_t offset)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load pointer register from VM array
    a->mov(x86::rax, x86::qword_ptr(rbx, ptr_reg * 8));

    // Load source value from VM array (32-bit)
    a->mov(x86::edx, x86::dword_ptr(rbx, src_reg * 8));

    // Store dword to memory at [ptr + offset]
    a->mov(x86::dword_ptr(x86::r12, x86::rax, 1, offset), x86::edx);

    return true;
}

// Store64: Store 64-bit to memory
bool jit_emit_store_64(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t ptr_reg,
    uint8_t src_reg,
    int16_t offset)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load pointer register from VM array
    a->mov(x86::rax, x86::qword_ptr(rbx, ptr_reg * 8));

    // Load source value from VM array (64-bit)
    a->mov(x86::rdx, x86::qword_ptr(rbx, src_reg * 8));

    // Store qword to memory at [ptr + offset]
    a->mov(x86::qword_ptr(x86::r12, x86::rax, 1, offset), x86::rdx);

    return true;
}

// Store16: Store 16-bit to memory
bool jit_emit_store_16(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t ptr_reg,
    uint8_t src_reg,
    int16_t offset)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load pointer register from VM array
    a->mov(x86::rax, x86::qword_ptr(rbx, ptr_reg * 8));

    // Load source value from VM array (16-bit)
    a->movzx(x86::edx, x86::word_ptr(rbx, src_reg * 8));

    // Store word to memory at [ptr + offset]
    a->mov(x86::word_ptr(x86::r12, x86::rax, 1, offset), x86::dx);

    return true;
}

// Store8: Store 8-bit to memory
bool jit_emit_store_8(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t ptr_reg,
    uint8_t src_reg,
    int16_t offset)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load pointer register from VM array
    a->mov(x86::rax, x86::qword_ptr(rbx, ptr_reg * 8));

    // Load source value from VM array (8-bit)
    a->movzx(x86::edx, x86::byte_ptr(rbx, src_reg * 8));

    // Store byte to memory at [ptr + offset]
    a->mov(x86::byte_ptr(x86::r12, x86::rax, 1, offset), x86::dl);

    return true;
}

// MulU32Imm: Multiply unsigned 32-bit by immediate
bool jit_emit_mul_u32_imm(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint32_t immediate)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load dest register from VM array (32-bit)
    a->mov(x86::eax, x86::dword_ptr(rbx, dest_reg * 8));

    // Multiply by immediate (unsigned 32-bit)
    a->mov(x86::edx, immediate);
    a->mul(x86::edx);  // edx:eax = eax * edx (unsigned)

    // Store result back to VM register array (32-bit)
    a->mov(x86::dword_ptr(rbx, dest_reg * 8), x86::eax);

    return true;
}

// MulS32Imm: Multiply signed 32-bit by immediate
bool jit_emit_mul_s32_imm(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    int32_t immediate)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load dest register from VM array (32-bit)
    a->mov(x86::eax, x86::dword_ptr(rbx, dest_reg * 8));

    // Multiply by immediate (signed 32-bit)
    a->mov(x86::edx, immediate);
    a->imul(x86::edx);  // edx:eax = eax * edx (signed)

    // Store result back to VM register array (32-bit)
    a->mov(x86::dword_ptr(rbx, dest_reg * 8), x86::eax);

    return true;
}

// AddImm64: Add 64-bit immediate
bool jit_emit_add_imm_64(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint64_t immediate)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load dest register from VM array
    a->mov(x86::rax, x86::qword_ptr(rbx, dest_reg * 8));

    // Add immediate
    a->add(x86::rax, immediate);

    // Store result back to VM register array
    a->mov(x86::qword_ptr(rbx, dest_reg * 8), x86::rax);

    return true;
}

// SubImm: Subtract immediate (64-bit)
bool jit_emit_sub_imm(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint64_t immediate)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load dest register from VM array
    a->mov(x86::rax, x86::qword_ptr(rbx, dest_reg * 8));

    // Subtract immediate
    a->sub(x86::rax, immediate);

    // Store result back to VM register array
    a->mov(x86::qword_ptr(rbx, dest_reg * 8), x86::rax);

    return true;
}

// AndImm: Bitwise AND with immediate
bool jit_emit_and_imm(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint64_t immediate)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load dest register from VM array
    a->mov(x86::rax, x86::qword_ptr(rbx, dest_reg * 8));

    // AND with immediate
    a->and_(x86::rax, immediate);

    // Store result back to VM register array
    a->mov(x86::qword_ptr(rbx, dest_reg * 8), x86::rax);

    return true;
}

// OrImm: Bitwise OR with immediate
bool jit_emit_or_imm(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint64_t immediate)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load dest register from VM array
    a->mov(x86::rax, x86::qword_ptr(rbx, dest_reg * 8));

    // OR with immediate
    a->or_(x86::rax, immediate);

    // Store result back to VM register array
    a->mov(x86::qword_ptr(rbx, dest_reg * 8), x86::rax);

    return true;
}

// XorImm: Bitwise XOR with immediate
bool jit_emit_xor_imm(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint64_t immediate)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load dest register from VM array
    a->mov(x86::rax, x86::qword_ptr(rbx, dest_reg * 8));

    // XOR with immediate
    a->xor_(x86::rax, immediate);

    // Store result back to VM register array
    a->mov(x86::qword_ptr(rbx, dest_reg * 8), x86::rax);

    return true;
}

// MemSet: Fill memory with byte value
bool jit_emit_memset(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t ptr_reg,
    uint8_t value_reg,
    uint8_t count_reg)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load pointer from VM array
    a->mov(x86::rdi, x86::qword_ptr(rbx, ptr_reg * 8));

    // Load value from VM array (8-bit)
    a->movzx(x86::rsi, x86::byte_ptr(rbx, value_reg * 8));

    // Load count from VM array
    a->mov(x86::rdx, x86::qword_ptr(rbx, count_reg * 8));

    // Save VM registers that will be clobbered
    a->push(x86::rbx);
    a->push(x86::r12);
    a->push(x86::r15);

    // Set up memset: rdi=dest, rsi=value, rdx=count
    // We need to use rep stosb
    a->mov(x86::rcx, x86::rdx);  // count
    a->mov(x86::al, x86::sil);   // value
    a->rep();  // Repeat prefix
    a->stosb();  // Store byte

    // Restore VM registers
    a->pop(x86::r15);
    a->pop(x86::r12);
    a->pop(x86::rbx);

    return true;
}

// MemCpy: Copy memory from source to destination
bool jit_emit_memcpy(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t src_reg,
    uint8_t count_reg)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load destination pointer from VM array
    a->mov(x86::rdi, x86::qword_ptr(rbx, dest_reg * 8));

    // Load source pointer from VM array
    a->mov(x86::rsi, x86::qword_ptr(rbx, src_reg * 8));

    // Load count from VM array
    a->mov(x86::rdx, x86::qword_ptr(rbx, count_reg * 8));

    // Save VM registers that will be clobbered
    a->push(x86::rbx);
    a->push(x86::r12);
    a->push(x86::r15);

    // Set up memcpy: rdi=dest, rsi=src, rdx=count
    // We need to use rep movsb
    a->mov(x86::rcx, x86::rdx);  // count
    a->rep();  // Repeat prefix
    a->movsb();  // Move byte

    // Restore VM registers
    a->pop(x86::r15);
    a->pop(x86::r12);
    a->pop(x86::rbx);

    return true;
}

// LoadImm32: Load 32-bit immediate into register
bool jit_emit_load_imm_32(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint32_t immediate)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load immediate into register
    a->mov(x86::eax, immediate);

    // Store to VM register array (zero-extended to 64-bit)
    a->mov(x86::qword_ptr(rbx, dest_reg * 8), x86::rax);

    return true;
}

// LoadImm64: Load 64-bit immediate into register
bool jit_emit_load_imm_64(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint64_t immediate)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load immediate into register
    a->mov(x86::rax, immediate);

    // Store to VM register array
    a->mov(x86::qword_ptr(rbx, dest_reg * 8), x86::rax);

    return true;
}

// LoadImm32Hi: Load 32-bit immediate into high 32 bits of register
bool jit_emit_load_imm_32_hi(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint32_t immediate)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load current value from VM array
    a->mov(x86::rax, x86::qword_ptr(rbx, dest_reg * 8));

    // Clear high 32 bits
    a->mov(x86::eax, x86::eax);  // This zero-extends eax to rax

    // Load immediate into high 32 bits
    a->shl(x86::rax, 32);
    a->or_(x86::rax, immediate);

    // Store to VM register array
    a->mov(x86::qword_ptr(rbx, dest_reg * 8), x86::rax);

    return true;
}

// MulImm32: Multiply 32-bit by immediate (signed)
bool jit_emit_mul_imm_32(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    int32_t immediate)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load dest register from VM array (32-bit)
    a->mov(x86::eax, x86::dword_ptr(rbx, dest_reg * 8));

    // Multiply by immediate (signed 32-bit) using imul
    a->imul(x86::eax, immediate);

    // Store result back to VM register array (32-bit)
    a->mov(x86::dword_ptr(rbx, dest_reg * 8), x86::eax);

    return true;
}

// MulImm64: Multiply 64-bit by immediate (signed)
bool jit_emit_mul_imm_64(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    int64_t immediate)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load dest register from VM array (64-bit)
    a->mov(x86::rax, x86::qword_ptr(rbx, dest_reg * 8));

    // Multiply by immediate (signed 64-bit) using imul
    a->imul(x86::rax, immediate);

    // Store result back to VM register array
    a->mov(x86::qword_ptr(rbx, dest_reg * 8), x86::rax);

    return true;
}

// DivU32Imm: Divide unsigned 32-bit by immediate
bool jit_emit_div_u32_imm(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint32_t immediate)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Check for division by zero
    if (immediate == 0) {
        return false;
    }

    // Load dest register from VM array (32-bit)
    a->mov(x86::eax, x86::dword_ptr(rbx, dest_reg * 8));

    // Zero-extend to 64-bit
    a->mov(x86::edx, 0);

    // Divide by immediate (unsigned)
    a->mov(x86::ecx, immediate);
    a->div(x86::ecx);  // eax = eax / ecx

    // Store result back to VM register array (32-bit)
    a->mov(x86::dword_ptr(rbx, dest_reg * 8), x86::eax);

    return true;
}

// DivS32Imm: Divide signed 32-bit by immediate
bool jit_emit_div_s32_imm(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    int32_t immediate)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Check for division by zero
    if (immediate == 0) {
        return false;
    }

    // Load dest register from VM array (32-bit)
    a->mov(x86::eax, x86::dword_ptr(rbx, dest_reg * 8));

    // Sign-extend to 64-bit (cdq)
    a->cdq();

    // Divide by immediate (signed)
    a->mov(x86::ecx, immediate);
    a->idiv(x86::ecx);  // eax = eax / ecx

    // Store result back to VM register array (32-bit)
    a->mov(x86::dword_ptr(rbx, dest_reg * 8), x86::eax);

    return true;
}

// RemU32Imm: Remainder of unsigned 32-bit division by immediate
bool jit_emit_rem_u32_imm(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint32_t immediate)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Check for division by zero
    if (immediate == 0) {
        return false;
    }

    // Load dest register from VM array (32-bit)
    a->mov(x86::eax, x86::dword_ptr(rbx, dest_reg * 8));

    // Zero-extend to 64-bit
    a->mov(x86::edx, 0);

    // Divide by immediate (unsigned)
    a->mov(x86::ecx, immediate);
    a->div(x86::ecx);  // eax = quotient, edx = remainder

    // Store remainder back to VM register array (32-bit)
    a->mov(x86::dword_ptr(rbx, dest_reg * 8), x86::edx);

    return true;
}

// RemS32Imm: Remainder of signed 32-bit division by immediate
bool jit_emit_rem_s32_imm(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    int32_t immediate)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Check for division by zero
    if (immediate == 0) {
        return false;
    }

    // Load dest register from VM array (32-bit)
    a->mov(x86::eax, x86::dword_ptr(rbx, dest_reg * 8));

    // Sign-extend to 64-bit (cdq)
    a->cdq();

    // Divide by immediate (signed)
    a->mov(x86::ecx, immediate);
    a->idiv(x86::ecx);  // eax = quotient, edx = remainder

    // Store remainder back to VM register array (32-bit)
    a->mov(x86::dword_ptr(rbx, dest_reg * 8), x86::edx);

    return true;
}

// Neg: Negate value (two's complement)
bool jit_emit_neg(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load dest register from VM array
    a->mov(x86::rax, x86::qword_ptr(rbx, dest_reg * 8));

    // Negate: rax = -rax
    a->neg(x86::rax);

    // Store result back to VM register array
    a->mov(x86::qword_ptr(rbx, dest_reg * 8), x86::rax);

    return true;
}

// Not: Bitwise NOT
bool jit_emit_not(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load dest register from VM array
    a->mov(x86::rax, x86::qword_ptr(rbx, dest_reg * 8));

    // Bitwise NOT: rax = ~rax
    a->not_(x86::rax);

    // Store result back to VM register array
    a->mov(x86::qword_ptr(rbx, dest_reg * 8), x86::rax);

    return true;
}

// Abs: Absolute value
bool jit_emit_abs(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load dest register from VM array
    a->mov(x86::rax, x86::qword_ptr(rbx, dest_reg * 8));

    // Save original value
    a->mov(x86::rdx, x86::rax);

    // Negate
    a->neg(x86::rax);

    // If original was negative (rdx < 0), keep negated value; otherwise, restore original
    // For signed 64-bit: if rdx was negative, MSB is set
    a->test(x86::rdx, x86::rdx);
    a->cmovl(x86::rax, x86::rdx);

    // Store result back to VM register array
    a->mov(x86::qword_ptr(rbx, dest_reg * 8), x86::rax);

    return true;
}

// AddImm32: Add 32-bit immediate
bool jit_emit_add_imm_32(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    int32_t immediate)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load dest register from VM array (32-bit)
    a->mov(x86::eax, x86::dword_ptr(rbx, dest_reg * 8));

    // Add immediate
    a->add(x86::eax, immediate);

    // Store result back to VM register array (32-bit)
    a->mov(x86::dword_ptr(rbx, dest_reg * 8), x86::eax);

    return true;
}

// SubImm32: Subtract 32-bit immediate
bool jit_emit_sub_imm_32(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    int32_t immediate)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load dest register from VM array (32-bit)
    a->mov(x86::eax, x86::dword_ptr(rbx, dest_reg * 8));

    // Subtract immediate
    a->sub(x86::eax, immediate);

    // Store result back to VM register array (32-bit)
    a->mov(x86::dword_ptr(rbx, dest_reg * 8), x86::eax);

    return true;
}

// AndImm32: Bitwise AND with 32-bit immediate
bool jit_emit_and_imm_32(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint32_t immediate)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load dest register from VM array (32-bit)
    a->mov(x86::eax, x86::dword_ptr(rbx, dest_reg * 8));

    // AND with immediate
    a->and_(x86::eax, immediate);

    // Store result back to VM register array (32-bit)
    a->mov(x86::dword_ptr(rbx, dest_reg * 8), x86::eax);

    return true;
}

// OrImm32: Bitwise OR with 32-bit immediate
bool jit_emit_or_imm_32(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint32_t immediate)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load dest register from VM array (32-bit)
    a->mov(x86::eax, x86::dword_ptr(rbx, dest_reg * 8));

    // OR with immediate
    a->or_(x86::eax, immediate);

    // Store result back to VM register array (32-bit)
    a->mov(x86::dword_ptr(rbx, dest_reg * 8), x86::eax);

    return true;
}

// XorImm32: Bitwise XOR with 32-bit immediate
bool jit_emit_xor_imm_32(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint32_t immediate)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load dest register from VM array (32-bit)
    a->mov(x86::eax, x86::dword_ptr(rbx, dest_reg * 8));

    // XOR with immediate
    a->xor_(x86::eax, immediate);

    // Store result back to VM register array (32-bit)
    a->mov(x86::dword_ptr(rbx, dest_reg * 8), x86::eax);

    return true;
}

// ShlImm32: Shift left logical by immediate (32-bit)
bool jit_emit_shl_imm_32(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t immediate)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load dest register from VM array (32-bit)
    a->mov(x86::eax, x86::dword_ptr(rbx, dest_reg * 8));

    // Mask immediate to 5 bits for 32-bit shift
    uint8_t shift_count = immediate & 0x1F;

    // Shift left by immediate
    a->shl(x86::eax, shift_count);

    // Store result back to VM register array (32-bit)
    a->mov(x86::dword_ptr(rbx, dest_reg * 8), x86::eax);

    return true;
}

// ShrImm32: Shift right logical by immediate (32-bit)
bool jit_emit_shr_imm_32(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t immediate)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load dest register from VM array (32-bit)
    a->mov(x86::eax, x86::dword_ptr(rbx, dest_reg * 8));

    // Mask immediate to 5 bits for 32-bit shift
    uint8_t shift_count = immediate & 0x1F;

    // Shift right logical by immediate
    a->shr(x86::eax, shift_count);

    // Store result back to VM register array (32-bit)
    a->mov(x86::dword_ptr(rbx, dest_reg * 8), x86::eax);

    return true;
}

// SarImm32: Shift right arithmetic by immediate (32-bit)
bool jit_emit_sar_imm_32(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t immediate)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load dest register from VM array (32-bit)
    a->mov(x86::eax, x86::dword_ptr(rbx, dest_reg * 8));

    // Mask immediate to 5 bits for 32-bit shift
    uint8_t shift_count = immediate & 0x1F;

    // Shift right arithmetic by immediate
    a->sar(x86::eax, shift_count);

    // Store result back to VM register array (32-bit)
    a->mov(x86::dword_ptr(rbx, dest_reg * 8), x86::eax);

    return true;
}

// ShlImm64: Shift left logical by immediate (64-bit)
bool jit_emit_shl_imm_64(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t immediate)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load dest register from VM array (64-bit)
    a->mov(x86::rax, x86::qword_ptr(rbx, dest_reg * 8));

    // Mask immediate to 6 bits for 64-bit shift
    uint8_t shift_count = immediate & 0x3F;

    // Shift left by immediate
    a->shl(x86::rax, shift_count);

    // Store result back to VM register array
    a->mov(x86::qword_ptr(rbx, dest_reg * 8), x86::rax);

    return true;
}

// ShrImm64: Shift right logical by immediate (64-bit)
bool jit_emit_shr_imm_64(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t immediate)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load dest register from VM array (64-bit)
    a->mov(x86::rax, x86::qword_ptr(rbx, dest_reg * 8));

    // Mask immediate to 6 bits for 64-bit shift
    uint8_t shift_count = immediate & 0x3F;

    // Shift right logical by immediate
    a->shr(x86::rax, shift_count);

    // Store result back to VM register array
    a->mov(x86::qword_ptr(rbx, dest_reg * 8), x86::rax);

    return true;
}

// SarImm64: Shift right arithmetic by immediate (64-bit)
bool jit_emit_sar_imm_64(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t immediate)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load dest register from VM array (64-bit)
    a->mov(x86::rax, x86::qword_ptr(rbx, dest_reg * 8));

    // Mask immediate to 6 bits for 64-bit shift
    uint8_t shift_count = immediate & 0x3F;

    // Shift right arithmetic by immediate
    a->sar(x86::rax, shift_count);

    // Store result back to VM register array
    a->mov(x86::qword_ptr(rbx, dest_reg * 8), x86::rax);

    return true;
}

// RotLImm32: Rotate left by immediate (32-bit)
bool jit_emit_rot_l_imm_32(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t immediate)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load dest register from VM array (32-bit)
    a->mov(x86::eax, x86::dword_ptr(rbx, dest_reg * 8));

    // Mask immediate to 5 bits for 32-bit rotate
    uint8_t rotate_count = immediate & 0x1F;

    // Rotate left by immediate
    a->rol(x86::eax, rotate_count);

    // Store result back to VM register array (32-bit)
    a->mov(x86::dword_ptr(rbx, dest_reg * 8), x86::eax);

    return true;
}

// RotRImm32: Rotate right by immediate (32-bit)
bool jit_emit_rot_r_imm_32(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t immediate)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load dest register from VM array (32-bit)
    a->mov(x86::eax, x86::dword_ptr(rbx, dest_reg * 8));

    // Mask immediate to 5 bits for 32-bit rotate
    uint8_t rotate_count = immediate & 0x1F;

    // Rotate right by immediate
    a->ror(x86::eax, rotate_count);

    // Store result back to VM register array (32-bit)
    a->mov(x86::dword_ptr(rbx, dest_reg * 8), x86::eax);

    return true;
}

// RotLImm64: Rotate left by immediate (64-bit)
bool jit_emit_rot_l_imm_64(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t immediate)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load dest register from VM array (64-bit)
    a->mov(x86::rax, x86::qword_ptr(rbx, dest_reg * 8));

    // Mask immediate to 6 bits for 64-bit rotate
    uint8_t rotate_count = immediate & 0x3F;

    // Rotate left by immediate
    a->rol(x86::rax, rotate_count);

    // Store result back to VM register array
    a->mov(x86::qword_ptr(rbx, dest_reg * 8), x86::rax);

    return true;
}

// RotRImm64: Rotate right by immediate (64-bit)
bool jit_emit_rot_r_imm_64(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t immediate)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load dest register from VM array (64-bit)
    a->mov(x86::rax, x86::qword_ptr(rbx, dest_reg * 8));

    // Mask immediate to 6 bits for 64-bit rotate
    uint8_t rotate_count = immediate & 0x3F;

    // Rotate right by immediate
    a->ror(x86::rax, rotate_count);

    // Store result back to VM register array
    a->mov(x86::qword_ptr(rbx, dest_reg * 8), x86::rax);

    return true;
}

// EqImm: Equality comparison with immediate
bool jit_emit_eq_imm(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint64_t immediate)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load dest register from VM array
    a->mov(x86::rax, x86::qword_ptr(rbx, dest_reg * 8));

    // Compare with immediate
    a->cmp(x86::rax, immediate);

    // Set to 1 if equal (ZF=1), 0 otherwise
    a->sete(x86::al);

    // Zero-extend to 64-bit
    a->movzx(x86::rax, x86::al);

    // Store result back to VM register array
    a->mov(x86::qword_ptr(rbx, dest_reg * 8), x86::rax);

    return true;
}

// NeImm: Not-equal comparison with immediate
bool jit_emit_ne_imm(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint64_t immediate)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load dest register from VM array
    a->mov(x86::rax, x86::qword_ptr(rbx, dest_reg * 8));

    // Compare with immediate
    a->cmp(x86::rax, immediate);

    // Set to 1 if not-equal (ZF=0), 0 otherwise
    a->setne(x86::al);

    // Zero-extend to 64-bit
    a->movzx(x86::rax, x86::al);

    // Store result back to VM register array
    a->mov(x86::qword_ptr(rbx, dest_reg * 8), x86::rax);

    return true;
}

// LtImm: Less-than signed comparison with immediate
bool jit_emit_lt_imm(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    int64_t immediate)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load dest register from VM array
    a->mov(x86::rax, x86::qword_ptr(rbx, dest_reg * 8));

    // Compare with immediate (signed)
    a->cmp(x86::rax, immediate);

    // Set to 1 if less-than (signed), 0 otherwise
    a->setl(x86::al);

    // Zero-extend to 64-bit
    a->movzx(x86::rax, x86::al);

    // Store result back to VM register array
    a->mov(x86::qword_ptr(rbx, dest_reg * 8), x86::rax);

    return true;
}

// GtImm: Greater-than signed comparison with immediate
bool jit_emit_gt_imm(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    int64_t immediate)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load dest register from VM array
    a->mov(x86::rax, x86::qword_ptr(rbx, dest_reg * 8));

    // Compare with immediate (signed)
    a->cmp(x86::rax, immediate);

    // Set to 1 if greater-than (signed), 0 otherwise
    a->setg(x86::al);

    // Zero-extend to 64-bit
    a->movzx(x86::rax, x86::al);

    // Store result back to VM register array
    a->mov(x86::qword_ptr(rbx, dest_reg * 8), x86::rax);

    return true;
}

// LtImmU: Less-than unsigned comparison with immediate
bool jit_emit_lt_imm_u(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint64_t immediate)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load dest register from VM array
    a->mov(x86::rax, x86::qword_ptr(rbx, dest_reg * 8));

    // Compare with immediate (unsigned)
    a->cmp(x86::rax, immediate);

    // Set to 1 if less-than (unsigned/below), 0 otherwise
    a->setb(x86::al);

    // Zero-extend to 64-bit
    a->movzx(x86::rax, x86::al);

    // Store result back to VM register array
    a->mov(x86::qword_ptr(rbx, dest_reg * 8), x86::rax);

    return true;
}

// GtImmU: Greater-than unsigned comparison with immediate
bool jit_emit_gt_imm_u(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint64_t immediate)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load dest register from VM array
    a->mov(x86::rax, x86::qword_ptr(rbx, dest_reg * 8));

    // Compare with immediate (unsigned)
    a->cmp(x86::rax, immediate);

    // Set to 1 if greater-than (unsigned/above), 0 otherwise
    a->seta(x86::al);

    // Zero-extend to 64-bit
    a->movzx(x86::rax, x86::al);

    // Store result back to VM register array
    a->mov(x86::qword_ptr(rbx, dest_reg * 8), x86::rax);

    return true;
}

// Clz: Count leading zeros (32-bit)
bool jit_emit_clz(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t src_reg)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load source register from VM array (32-bit)
    a->mov(x86::eax, x86::dword_ptr(rbx, src_reg * 8));

    // Count leading zeros using lzcnt
    a->lzcnt(x86::eax, x86::eax);

    // Zero-extend to 64-bit
    a->movzx(x86::rax, x86::eax);

    // Store result back to VM register array
    a->mov(x86::qword_ptr(rbx, dest_reg * 8), x86::rax);

    return true;
}

// Clz64: Count leading zeros (64-bit)
bool jit_emit_clz_64(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t src_reg)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load source register from VM array
    a->mov(x86::rax, x86::qword_ptr(rbx, src_reg * 8));

    // Count leading zeros using lzcnt
    a->lzcnt(x86::rax, x86::rax);

    // Store result back to VM register array
    a->mov(x86::qword_ptr(rbx, dest_reg * 8), x86::rax);

    return true;
}

// Ctz: Count trailing zeros (32-bit)
bool jit_emit_ctz(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t src_reg)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load source register from VM array (32-bit)
    a->mov(x86::eax, x86::dword_ptr(rbx, src_reg * 8));

    // Count trailing zeros using tzcnt
    a->tzcnt(x86::eax, x86::eax);

    // Zero-extend to 64-bit
    a->movzx(x86::rax, x86::eax);

    // Store result back to VM register array
    a->mov(x86::qword_ptr(rbx, dest_reg * 8), x86::rax);

    return true;
}

// Ctz64: Count trailing zeros (64-bit)
bool jit_emit_ctz_64(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t src_reg)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load source register from VM array
    a->mov(x86::rax, x86::qword_ptr(rbx, src_reg * 8));

    // Count trailing zeros using tzcnt
    a->tzcnt(x86::rax, x86::rax);

    // Store result back to VM register array
    a->mov(x86::qword_ptr(rbx, dest_reg * 8), x86::rax);

    return true;
}

// Bswap: Byte swap (reverse byte order)
bool jit_emit_bswap(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load dest register from VM array
    a->mov(x86::rax, x86::qword_ptr(rbx, dest_reg * 8));

    // Byte swap
    a->bswap(x86::rax);

    // Store result back to VM register array
    a->mov(x86::qword_ptr(rbx, dest_reg * 8), x86::rax);

    return true;
}

// Bswap32: Byte swap 32-bit
bool jit_emit_bswap_32(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load dest register from VM array (32-bit)
    a->mov(x86::eax, x86::dword_ptr(rbx, dest_reg * 8));

    // Byte swap
    a->bswap(x86::eax);

    // Store result back to VM register array (32-bit)
    a->mov(x86::dword_ptr(rbx, dest_reg * 8), x86::eax);

    return true;
}

// Ctpop: Count population (set bits) - 32-bit
bool jit_emit_ctpop(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t src_reg)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load source register from VM array (32-bit)
    a->mov(x86::eax, x86::dword_ptr(rbx, src_reg * 8));

    // Count set bits using popcnt
    a->popcnt(x86::eax, x86::eax);

    // Zero-extend to 64-bit
    a->movzx(x86::rax, x86::eax);

    // Store result back to VM register array
    a->mov(x86::qword_ptr(rbx, dest_reg * 8), x86::rax);

    return true;
}

// Sext8: Sign extend 8-bit to 32-bit
bool jit_emit_sext_8(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t src_reg)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load source register from VM array (8-bit sign-extended)
    a->movsx(x86::eax, x86::byte_ptr(rbx, src_reg * 8));

    // Store result back to VM register array (32-bit)
    a->mov(x86::dword_ptr(rbx, dest_reg * 8), x86::eax);

    return true;
}

// Sext16: Sign extend 16-bit to 32-bit
bool jit_emit_sext_16(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t src_reg)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load source register from VM array (16-bit sign-extended)
    a->movsx(x86::eax, x86::word_ptr(rbx, src_reg * 8));

    // Store result back to VM register array (32-bit)
    a->mov(x86::dword_ptr(rbx, dest_reg * 8), x86::eax);

    return true;
}

// Zext8: Zero extend 8-bit to 32-bit
bool jit_emit_zext_8(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t src_reg)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load source register from VM array (8-bit zero-extended)
    a->movzx(x86::eax, x86::byte_ptr(rbx, src_reg * 8));

    // Store result back to VM register array (32-bit)
    a->mov(x86::dword_ptr(rbx, dest_reg * 8), x86::eax);

    return true;
}

// Zext16: Zero extend 16-bit to 32-bit
bool jit_emit_zext_16(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t src_reg)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load source register from VM array (16-bit zero-extended)
    a->movzx(x86::eax, x86::word_ptr(rbx, src_reg * 8));

    // Store result back to VM register array (32-bit)
    a->mov(x86::dword_ptr(rbx, dest_reg * 8), x86::eax);

    return true;
}

// MulU64: Multiply unsigned 64-bit
bool jit_emit_mul_u_64(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t src_reg)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load source register from VM array
    a->mov(x86::rax, x86::qword_ptr(rbx, src_reg * 8));

    // Load dest register from VM array
    a->mov(x86::rdx, x86::qword_ptr(rbx, dest_reg * 8));

    // Multiply unsigned (64-bit) - only keep low 64 bits
    a->imul(x86::rdx, x86::rax);

    // Store result back to VM register array
    a->mov(x86::qword_ptr(rbx, dest_reg * 8), x86::rdx);

    return true;
}

// DivU64: Divide unsigned 64-bit
bool jit_emit_div_u_64(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t src_reg)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load dividend (dest_reg) into rax
    a->mov(x86::rax, x86::qword_ptr(rbx, dest_reg * 8));

    // Zero-extend to rdx:rax
    a->xor_(x86::edx, x86::edx);

    // Load divisor (src_reg) into rcx (use qword_ptr for 64-bit)
    a->mov(x86::rcx, x86::qword_ptr(rbx, src_reg * 8));

    // Divide unsigned: rax = rdx:rax / rcx
    a->div(x86::rcx);

    // Store quotient back to VM register array
    a->mov(x86::qword_ptr(rbx, dest_reg * 8), x86::rax);

    return true;
}

// DivS64: Divide signed 64-bit
bool jit_emit_div_s_64(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t src_reg)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load dest register (dividend) from VM array
    a->mov(x86::rax, x86::qword_ptr(rbx, dest_reg * 8));

    // Sign-extend to rdx:rax (cqo)
    a->cqo();

    // Load source register (divisor) from VM array
    a->mov(x86::rcx, x86::qword_ptr(rbx, src_reg * 8));

    // Divide signed: rax = rdx:rax / rcx
    a->idiv(x86::rcx);

    // Store quotient back to VM register array
    a->mov(x86::qword_ptr(rbx, dest_reg * 8), x86::rax);

    return true;
}

// RemU64: Remainder of unsigned 64-bit division
bool jit_emit_rem_u_64(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t src_reg)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load dest register (dividend) from VM array
    a->mov(x86::rax, x86::qword_ptr(rbx, dest_reg * 8));

    // Zero-extend to rdx:rax
    a->xor_(x86::edx, x86::edx);

    // Load source register (divisor) from VM array
    a->mov(x86::rcx, x86::qword_ptr(rbx, src_reg * 8));

    // Divide unsigned: rax = quotient, rdx = remainder
    a->div(x86::rcx);

    // Store remainder back to VM register array
    a->mov(x86::qword_ptr(rbx, dest_reg * 8), x86::rdx);

    return true;
}

// RemS64: Remainder of signed 64-bit division
bool jit_emit_rem_s_64(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t src_reg)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load dest register (dividend) from VM array
    a->mov(x86::rax, x86::qword_ptr(rbx, dest_reg * 8));

    // Sign-extend to rdx:rax (cqo)
    a->cqo();

    // Load source register (divisor) from VM array
    a->mov(x86::rcx, x86::qword_ptr(rbx, src_reg * 8));

    // Divide signed: rax = quotient, rdx = remainder
    a->idiv(x86::rcx);

    // Store remainder back to VM register array
    a->mov(x86::qword_ptr(rbx, dest_reg * 8), x86::rdx);

    return true;
}

// And64: Bitwise AND 64-bit
bool jit_emit_and_64(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t src_reg)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load source register from VM array
    a->mov(x86::rax, x86::qword_ptr(rbx, src_reg * 8));

    // Load dest register from VM array
    a->mov(x86::rdx, x86::qword_ptr(rbx, dest_reg * 8));

    // AND: dest = dest & src
    a->and_(x86::rdx, x86::rax);

    // Store result back to VM register array
    a->mov(x86::qword_ptr(rbx, dest_reg * 8), x86::rdx);

    return true;
}

// Or64: Bitwise OR 64-bit
bool jit_emit_or_64(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t src_reg)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load source register from VM array
    a->mov(x86::rax, x86::qword_ptr(rbx, src_reg * 8));

    // Load dest register from VM array
    a->mov(x86::rdx, x86::qword_ptr(rbx, dest_reg * 8));

    // OR: dest = dest | src
    a->or_(x86::rdx, x86::rax);

    // Store result back to VM register array
    a->mov(x86::qword_ptr(rbx, dest_reg * 8), x86::rdx);

    return true;
}

// Xor64: Bitwise XOR 64-bit
bool jit_emit_xor_64(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t src_reg)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load source register from VM array
    a->mov(x86::rax, x86::qword_ptr(rbx, src_reg * 8));

    // Load dest register from VM array
    a->mov(x86::rdx, x86::qword_ptr(rbx, dest_reg * 8));

    // XOR: dest = dest ^ src
    a->xor_(x86::rdx, x86::rax);

    // Store result back to VM register array
    a->mov(x86::qword_ptr(rbx, dest_reg * 8), x86::rdx);

    return true;
}

// Add64WithCarry: Add 64-bit with carry
bool jit_emit_add_64_carry(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t src_reg)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load source register from VM array
    a->mov(x86::rax, x86::qword_ptr(rbx, src_reg * 8));

    // Load dest register from VM array
    a->mov(x86::rdx, x86::qword_ptr(rbx, dest_reg * 8));

    // Add with carry
    a->add(x86::rdx, x86::rax);

    // Store result back to VM register array
    a->mov(x86::qword_ptr(rbx, dest_reg * 8), x86::rdx);

    return true;
}

// Sub64WithBorrow: Subtract 64-bit with borrow
bool jit_emit_sub_64_borrow(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t src_reg)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load source register from VM array
    a->mov(x86::rax, x86::qword_ptr(rbx, src_reg * 8));

    // Load dest register from VM array
    a->mov(x86::rdx, x86::qword_ptr(rbx, dest_reg * 8));

    // Subtract with borrow
    a->sub(x86::rdx, x86::rax);

    // Store result back to VM register array
    a->mov(x86::qword_ptr(rbx, dest_reg * 8), x86::rdx);

    return true;
}

// Sll64: Shift left logical 64-bit
bool jit_emit_sll_64(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t src_reg)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load shift count from VM array
    a->mov(x86::ecx, x86::dword_ptr(rbx, src_reg * 8));

    // Load dest register from VM array
    a->mov(x86::rdx, x86::qword_ptr(rbx, dest_reg * 8));

    // Mask shift count to 6 bits for 64-bit shift
    a->and_(x86::ecx, 0x3F);

    // Shift left
    a->shl(x86::rdx, x86::cl);

    // Store result back to VM register array
    a->mov(x86::qword_ptr(rbx, dest_reg * 8), x86::rdx);

    return true;
}

// Srl64: Shift right logical 64-bit
bool jit_emit_srl_64(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t src_reg)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load shift count from VM array
    a->mov(x86::ecx, x86::dword_ptr(rbx, src_reg * 8));

    // Load dest register from VM array
    a->mov(x86::rdx, x86::qword_ptr(rbx, dest_reg * 8));

    // Mask shift count to 6 bits for 64-bit shift
    a->and_(x86::ecx, 0x3F);

    // Shift right logical
    a->shr(x86::rdx, x86::cl);

    // Store result back to VM register array
    a->mov(x86::qword_ptr(rbx, dest_reg * 8), x86::rdx);

    return true;
}

// Sra64: Shift right arithmetic 64-bit
bool jit_emit_sra_64(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t src_reg)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load shift count from VM array
    a->mov(x86::ecx, x86::dword_ptr(rbx, src_reg * 8));

    // Load dest register from VM array
    a->mov(x86::rdx, x86::qword_ptr(rbx, dest_reg * 8));

    // Mask shift count to 6 bits for 64-bit shift
    a->and_(x86::ecx, 0x3F);

    // Shift right arithmetic
    a->sar(x86::rdx, x86::cl);

    // Store result back to VM register array
    a->mov(x86::qword_ptr(rbx, dest_reg * 8), x86::rdx);

    return true;
}

// Rol64: Rotate left 64-bit
bool jit_emit_rol_64(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t src_reg)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load rotate count from VM array
    a->mov(x86::ecx, x86::dword_ptr(rbx, src_reg * 8));

    // Load dest register from VM array
    a->mov(x86::rdx, x86::qword_ptr(rbx, dest_reg * 8));

    // Mask rotate count to 6 bits for 64-bit rotate
    a->and_(x86::ecx, 0x3F);

    // Rotate left
    a->rol(x86::rdx, x86::cl);

    // Store result back to VM register array
    a->mov(x86::qword_ptr(rbx, dest_reg * 8), x86::rdx);

    return true;
}

// Ror64: Rotate right 64-bit
bool jit_emit_ror_64(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t src_reg)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load rotate count from VM array
    a->mov(x86::ecx, x86::dword_ptr(rbx, src_reg * 8));

    // Load dest register from VM array
    a->mov(x86::rdx, x86::qword_ptr(rbx, dest_reg * 8));

    // Mask rotate count to 6 bits for 64-bit rotate
    a->and_(x86::ecx, 0x3F);

    // Rotate right
    a->ror(x86::rdx, x86::cl);

    // Store result back to VM register array
    a->mov(x86::qword_ptr(rbx, dest_reg * 8), x86::rdx);

    return true;
}

// Fence: Memory fence (no-op for x86_64 with strong memory model)
bool jit_emit_fence(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // MFENCE - memory fence
    a->mfence();

    return true;
}

// LoadReserved: Load reserved (for atomic operations)
bool jit_emit_load_reserved(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t ptr_reg)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load pointer from VM array
    a->mov(x86::rax, x86::qword_ptr(rbx, ptr_reg * 8));

    // Load with reserved semantics (using normal load for now)
    a->mov(x86::rax, x86::qword_ptr(x86::r12, x86::rax));

    // Store to VM register array
    a->mov(x86::qword_ptr(rbx, dest_reg * 8), x86::rax);

    return true;
}

// StoreConditional: Store conditional (for atomic operations)
bool jit_emit_store_conditional(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t ptr_reg,
    uint8_t src_reg)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load pointer from VM array
    a->mov(x86::rax, x86::qword_ptr(rbx, ptr_reg * 8));

    // Load source value from VM array
    a->mov(x86::rdx, x86::qword_ptr(rbx, src_reg * 8));

    // Store with conditional semantics (using normal store for now)
    a->mov(x86::qword_ptr(x86::r12, x86::rax), x86::rdx);

    // Return success (1)
    a->mov(x86::rax, 1);

    // Store result to VM register array
    a->mov(x86::qword_ptr(rbx, dest_reg * 8), x86::rax);

    return true;
}

// Nop: No operation
bool jit_emit_nop(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // NOP instruction
    a->nop();

    return true;
}

// Call: Call subroutine
bool jit_emit_call(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint32_t target_pc)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Update PC to target
    a->mov(x86::r15d, target_pc);

    return true;
}

// Ret: Return from subroutine
bool jit_emit_ret(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Return - for now just a nop, actual return handling depends on calling convention
    a->nop();

    return true;
}

// Syscall: System call
bool jit_emit_syscall(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // TODO: Implement actual system call handling
    // For now, just nop
    a->nop();

    return true;
}

// Break: Breakpoint/debug trap
bool jit_emit_break(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // INT3 instruction - software breakpoint
    a->int3();

    return true;
}

// Unimp: Unimplemented instruction
bool jit_emit_unimp(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // UD2 instruction - undefined instruction (traps)
    a->ud2();

    return true;
}

// CZero: Conditional zero
bool jit_emit_c_zero(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t condition_reg)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load condition register
    a->mov(x86::rax, x86::qword_ptr(rbx, condition_reg * 8));

    // Test if condition is zero
    a->test(x86::rax, x86::rax);

    // Load zero into rax
    a->xor_(x86::rdx, x86::rdx);

    // If condition != 0, keep zero; otherwise, keep dest value
    a->mov(x86::rcx, x86::qword_ptr(rbx, dest_reg * 8));
    a->cmovne(x86::rdx, x86::rcx);

    // Store result
    a->mov(x86::qword_ptr(rbx, dest_reg * 8), x86::rdx);

    return true;
}

// CNot: Conditional not
bool jit_emit_c_not(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t condition_reg)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load condition register
    a->mov(x86::rax, x86::qword_ptr(rbx, condition_reg * 8));

    // Test if condition is zero
    a->test(x86::rax, x86::rax);

    // Load dest register
    a->mov(x86::rdx, x86::qword_ptr(rbx, dest_reg * 8));

    // Compute NOT
    a->mov(x86::rcx, x86::rdx);
    a->not_(x86::rcx);

    // If condition != 0, use NOT; otherwise, keep original
    a->cmovne(x86::rdx, x86::rcx);

    // Store result
    a->mov(x86::qword_ptr(rbx, dest_reg * 8), x86::rdx);

    return true;
}

// Merge: Merge bits based on condition
bool jit_emit_merge(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t src1_reg,
    uint8_t src2_reg,
    uint8_t condition_reg)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load condition
    a->mov(x86::rax, x86::qword_ptr(rbx, condition_reg * 8));

    // Load src1 and src2
    a->mov(x86::rdx, x86::qword_ptr(rbx, src1_reg * 8));
    a->mov(x86::rcx, x86::qword_ptr(rbx, src2_reg * 8));

    // Test condition
    a->test(x86::rax, x86::rax);

    // If condition != 0, use src2; otherwise, use src1
    a->cmovne(x86::rdx, x86::rcx);

    // Store result
    a->mov(x86::qword_ptr(rbx, dest_reg * 8), x86::rdx);

    return true;
}

// AddCarry: Add with carry flag
bool jit_emit_add_carry(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t src_reg)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load source register
    a->mov(x86::rax, x86::qword_ptr(rbx, src_reg * 8));

    // Load dest register
    a->mov(x86::rdx, x86::qword_ptr(rbx, dest_reg * 8));

    // Add with carry
    a->adc(x86::rdx, x86::rax);

    // Store result
    a->mov(x86::qword_ptr(rbx, dest_reg * 8), x86::rdx);

    return true;
}

// SubBorrow: Subtract with borrow
bool jit_emit_sub_borrow(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t src_reg)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load source register
    a->mov(x86::rax, x86::qword_ptr(rbx, src_reg * 8));

    // Load dest register
    a->mov(x86::rdx, x86::qword_ptr(rbx, dest_reg * 8));

    // Subtract with borrow
    a->sbb(x86::rdx, x86::rax);

    // Store result
    a->mov(x86::qword_ptr(rbx, dest_reg * 8), x86::rdx);

    return true;
}

// Inc: Increment by 1
bool jit_emit_inc(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load dest register
    a->mov(x86::rax, x86::qword_ptr(rbx, dest_reg * 8));

    // Increment
    a->inc(x86::rax);

    // Store result
    a->mov(x86::qword_ptr(rbx, dest_reg * 8), x86::rax);

    return true;
}

// Dec: Decrement by 1
bool jit_emit_dec(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load dest register
    a->mov(x86::rax, x86::qword_ptr(rbx, dest_reg * 8));

    // Decrement
    a->dec(x86::rax);

    // Store result
    a->mov(x86::qword_ptr(rbx, dest_reg * 8), x86::rax);

    return true;
}

// Test: Test bits (AND without storing result)
bool jit_emit_test(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint8_t src_reg)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load source register
    a->mov(x86::rax, x86::qword_ptr(rbx, src_reg * 8));

    // Load dest register
    a->mov(x86::rdx, x86::qword_ptr(rbx, dest_reg * 8));

    // Test (AND and set flags)
    a->test(x86::rdx, x86::rax);

    // Set zero flag result to dest (1 if any bit set, 0 otherwise)
    a->setne(x86::dl);
    a->movzx(x86::rdx, x86::dl);

    // Store result
    a->mov(x86::qword_ptr(rbx, dest_reg * 8), x86::rdx);

    return true;
}

// TestImm: Test bits with immediate
bool jit_emit_test_imm(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t dest_reg,
    uint64_t immediate)
{
    if (strcmp(target_arch, "x86_64") != 0) {
        return false;
    }

    auto* a = static_cast<x86::Assembler*>(assembler);

    // Load dest register
    a->mov(x86::rax, x86::qword_ptr(rbx, dest_reg * 8));

    // Test with immediate
    a->test(x86::rax, immediate);

    // Set zero flag result to dest (1 if any bit set, 0 otherwise)
    a->setne(x86::dl);
    a->movzx(x86::rdx, x86::dl);

    // Store result
    a->mov(x86::qword_ptr(rbx, dest_reg * 8), x86::rdx);

    return true;
}

// ============================================================================
// 3-Register Instructions (MulUpper, SetLt, Cmov, Rot)
// Format: [ra][rb][rd] - all registers are passed as parameters
// These instructions compute: rd = op(ra, rb)
// ============================================================================

// MulUpperUU: rd = (UInt128(ra) * UInt128(rb)) >> 64
bool jit_emit_mul_upper_uu(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t ra,
    uint8_t rb,
    uint8_t rd)
{
    if (strcmp(target_arch, "x86_64") == 0) {
        auto* a = static_cast<x86::Assembler*>(assembler);

        // Load ra and rb
        a->mov(x86::rax, x86::qword_ptr(rbx, ra * 8));
        a->mov(x86::r8, x86::qword_ptr(rbx, rb * 8));

        // Multiply: rdx:rax = rax * r8 (unsigned)
        a->mul(x86::r8);

        // Store high half (rdx) to rd
        a->mov(x86::qword_ptr(rbx, rd * 8), x86::rdx);

        return true;
    } else if (strcmp(target_arch, "aarch64") == 0) {
        auto* a = static_cast<asmjit::a64::Assembler*>(assembler);

        // Load ra and rb into temporary registers
        a->ldr(a64::x0, a64::ptr(a64::x29, ra * 8));
        a->ldr(a64::x1, a64::ptr(a64::x29, rb * 8));

        // Multiply unsigned high: x2 = (x0 * x1) >> 64
        a->umulh(a64::x2, a64::x0, a64::x1);

        // Store result to rd
        a->str(a64::x2, a64::ptr(a64::x29, rd * 8));

        return true;
    }

    return false;
}

// MulUpperSU: rd = (Int128(ra) * UInt128(rb)) >> 64
bool jit_emit_mul_upper_su(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t ra,
    uint8_t rb,
    uint8_t rd)
{
    if (strcmp(target_arch, "x86_64") == 0) {
        auto* a = static_cast<x86::Assembler*>(assembler);

        // Load ra and rb
        a->mov(x86::rax, x86::qword_ptr(rbx, ra * 8));
        a->mov(x86::r8, x86::qword_ptr(rbx, rb * 8));

        // Save ra (signed operand) to check sign later
        a->mov(x86::r9, x86::rax);

        // Unsigned multiply: rdx:rax = rax * r8
        // This gives us UInt128(ra) * UInt128(rb)
        a->mul(x86::r8);

        // If ra was negative (signed), we need to adjust the result
        // Int128(ra) * UInt128(rb) = UInt128(ra) * UInt128(rb) - UInt128(rb) * 2^64
        // So we subtract rb from the high half (rdx)
        Label skipSub = a->newLabel();
        a->test(x86::r9, x86::r9);  // Test sign bit
        a->jns(skipSub);            // Skip if positive
        a->sub(x86::rdx, x86::r8);  // Subtract rb from high half
        a->bind(skipSub);

        // Store high half (rdx) to rd
        a->mov(x86::qword_ptr(rbx, rd * 8), x86::rdx);

        return true;
    } else if (strcmp(target_arch, "aarch64") == 0) {
        auto* a = static_cast<asmjit::a64::Assembler*>(assembler);

        // Load ra and rb into temporary registers
        a->ldr(a64::x0, a64::ptr(a64::x29, ra * 8));
        a->ldr(a64::x1, a64::ptr(a64::x29, rb * 8));

        // Multiply unsigned high: x2 = (UInt128(x0) * UInt128(x1)) >> 64
        // We use unsigned multiply as the base, then adjust if ra is negative
        a->umulh(a64::x2, a64::x0, a64::x1);

        // If ra was negative (signed), subtract rb from the result
        // Int128(ra) * UInt128(rb) = UInt128(ra) * UInt128(rb) - UInt128(rb) * 2^64
        // So the high part needs adjustment when ra < 0
        Label skipSub = a->newLabel();
        a->tbz(a64::x0, 63, skipSub);  // Test sign bit (bit 63), skip if clear
        a->sub(a64::x2, a64::x2, a64::x1);  // Subtract rb from result
        a->bind(skipSub);

        // Store result to rd
        a->str(a64::x2, a64::ptr(a64::x29, rd * 8));

        return true;
    }

    return false;
}

// SetLtU: rd = (ra < rb) ? 1 : 0 (unsigned comparison)
bool jit_emit_set_lt_u(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t ra,
    uint8_t rb,
    uint8_t rd)
{
    if (strcmp(target_arch, "x86_64") == 0) {
        auto* a = static_cast<x86::Assembler*>(assembler);

        // Load ra and rb
        a->mov(x86::rax, x86::qword_ptr(rbx, ra * 8));
        a->mov(x86::r8, x86::qword_ptr(rbx, rb * 8));

        // Compare: ra - rb (unsigned)
        a->cmp(x86::rax, x86::r8);

        // Set rd to 1 if below (ra < rb), 0 otherwise
        a->setb(x86::r8b);
        a->movzx(x86::r8, x86::r8b);

        // Store result to rd
        a->mov(x86::qword_ptr(rbx, rd * 8), x86::r8);

        return true;
    } else if (strcmp(target_arch, "aarch64") == 0) {
        auto* a = static_cast<asmjit::a64::Assembler*>(assembler);

        // Load ra and rb into temporary registers
        a->ldr(a64::x0, a64::ptr(a64::x29, ra * 8));
        a->ldr(a64::x1, a64::ptr(a64::x29, rb * 8));

        // Compare: ra - rb (unsigned)
        a->cmp(a64::x0, a64::x1);

        // Set x2 to 1 if less (ra < rb), 0 otherwise
        a->cset(a64::x2, asmjit::a64::CondCode::kLO);

        // Store result to rd
        a->str(a64::x2, a64::ptr(a64::x29, rd * 8));

        return true;
    }

    return false;
}

// SetLtS: rd = (ra < rb) ? 1 : 0 (signed comparison)
bool jit_emit_set_lt_s(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t ra,
    uint8_t rb,
    uint8_t rd)
{
    if (strcmp(target_arch, "x86_64") == 0) {
        auto* a = static_cast<x86::Assembler*>(assembler);

        // Load ra and rb
        a->mov(x86::rax, x86::qword_ptr(rbx, ra * 8));
        a->mov(x86::r8, x86::qword_ptr(rbx, rb * 8));

        // Compare: ra - rb (signed)
        a->cmp(x86::rax, x86::r8);

        // Set rd to 1 if less (ra < rb), 0 otherwise
        a->setl(x86::r8b);
        a->movzx(x86::r8, x86::r8b);

        // Store result to rd
        a->mov(x86::qword_ptr(rbx, rd * 8), x86::r8);

        return true;
    } else if (strcmp(target_arch, "aarch64") == 0) {
        auto* a = static_cast<asmjit::a64::Assembler*>(assembler);

        // Load ra and rb into temporary registers
        a->ldr(a64::x0, a64::ptr(a64::x29, ra * 8));
        a->ldr(a64::x1, a64::ptr(a64::x29, rb * 8));

        // Compare: ra - rb (signed)
        a->cmp(a64::x0, a64::x1);

        // Set x2 to 1 if less (ra < rb), 0 otherwise
        a->cset(a64::x2, asmjit::a64::CondCode::kLT);

        // Store result to rd
        a->str(a64::x2, a64::ptr(a64::x29, rd * 8));

        return true;
    }

    return false;
}

// CmovIz: rd = (rb == 0) ? ra : rd (conditional move if zero)
bool jit_emit_cmov_iz(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t ra,
    uint8_t rb,
    uint8_t rd)
{
    if (strcmp(target_arch, "x86_64") == 0) {
        auto* a = static_cast<x86::Assembler*>(assembler);

        // Load ra
        a->mov(x86::rax, x86::qword_ptr(rbx, ra * 8));

        // Load current rd value
        a->mov(x86::rdx, x86::qword_ptr(rbx, rd * 8));

        // Test rb
        a->cmp(x86::qword_ptr(rbx, rb * 8), 0);

        // Conditional move: if rb == 0, move ra to rd
        a->cmovz(x86::rdx, x86::rax);

        // Store result to rd
        a->mov(x86::qword_ptr(rbx, rd * 8), x86::rdx);

        return true;
    } else if (strcmp(target_arch, "aarch64") == 0) {
        auto* a = static_cast<asmjit::a64::Assembler*>(assembler);

        // Load ra and rd into temporary registers
        a->ldr(a64::x0, a64::ptr(a64::x29, ra * 8));
        a->ldr(a64::x2, a64::ptr(a64::x29, rd * 8));

        // Load rb and compare with 0
        a->ldr(a64::x1, a64::ptr(a64::x29, rb * 8));
        a->cmp(a64::x1, 0);

        // Conditional move: if rb == 0, move x0 to x2, else keep x2
        a->csel(a64::x2, a64::x0, a64::x2, asmjit::a64::CondCode::kEQ);

        // Store result to rd
        a->str(a64::x2, a64::ptr(a64::x29, rd * 8));

        return true;
    }

    return false;
}

// CmovNz: rd = (rb != 0) ? ra : rd (conditional move if not zero)
bool jit_emit_cmov_nz(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t ra,
    uint8_t rb,
    uint8_t rd)
{
    if (strcmp(target_arch, "x86_64") == 0) {
        auto* a = static_cast<x86::Assembler*>(assembler);

        // Load ra
        a->mov(x86::rax, x86::qword_ptr(rbx, ra * 8));

        // Load current rd value
        a->mov(x86::rdx, x86::qword_ptr(rbx, rd * 8));

        // Test rb
        a->cmp(x86::qword_ptr(rbx, rb * 8), 0);

        // Conditional move: if rb != 0, move ra to rd
        a->cmovnz(x86::rdx, x86::rax);

        // Store result to rd
        a->mov(x86::qword_ptr(rbx, rd * 8), x86::rdx);

        return true;
    } else if (strcmp(target_arch, "aarch64") == 0) {
        auto* a = static_cast<asmjit::a64::Assembler*>(assembler);

        // Load ra and rd into temporary registers
        a->ldr(a64::x0, a64::ptr(a64::x29, ra * 8));
        a->ldr(a64::x2, a64::ptr(a64::x29, rd * 8));

        // Load rb and compare with 0
        a->ldr(a64::x1, a64::ptr(a64::x29, rb * 8));
        a->cmp(a64::x1, 0);

        // Conditional move: if rb != 0, move x0 to x2, else keep x2
        a->csel(a64::x2, a64::x0, a64::x2, asmjit::a64::CondCode::kNE);

        // Store result to rd
        a->str(a64::x2, a64::ptr(a64::x29, rd * 8));

        return true;
    }

    return false;
}

// RolL64: rd = ra rotated left by rb bits (64-bit rotate left)
bool jit_emit_rol_64(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t ra,
    uint8_t rb,
    uint8_t rd)
{
    if (strcmp(target_arch, "x86_64") == 0) {
        auto* a = static_cast<x86::Assembler*>(assembler);

        // Load ra
        a->mov(x86::rax, x86::qword_ptr(rbx, ra * 8));

        // Load rb (shift count)
        a->mov(x86::rcx, x86::qword_ptr(rbx, rb * 8));

        // Rotate left by rcx bits
        a->rol(x86::rax, x86::cl);

        // Store result to rd
        a->mov(x86::qword_ptr(rbx, rd * 8), x86::rax);

        return true;
    } else if (strcmp(target_arch, "aarch64") == 0) {
        auto* a = static_cast<asmjit::a64::Assembler*>(assembler);

        // Load ra and rb into temporary registers
        a->ldr(a64::x0, a64::ptr(a64::x29, ra * 8));
        a->ldr(a64::x1, a64::ptr(a64::x29, rb * 8));

        // ARM64 doesn't have register-based rotate instructions
        // Implement left rotate using shift combination:
        // x2 = (x0 << x1) | (x0 >> (64 - x1))
        // First, mask shift count to 6 bits
        a->and_(a64::x1, a64::x1, 0x3F);

        // Compute inverse shift amount: x3 = 64 - x1
        a->mov(a64::x3, 64);
        a->sub(a64::x3, a64::x3, a64::x1);

        // Left shift: x4 = x0 << x1
        a->lsl(a64::x4, a64::x0, a64::x1);

        // Right shift: x5 = x0 >> x3
        a->lsr(a64::x5, a64::x0, a64::x3);

        // Combine: x2 = x4 | x5
        a->orr(a64::x2, a64::x4, a64::x5);

        // Store result to rd
        a->str(a64::x2, a64::ptr(a64::x29, rd * 8));

        return true;
    }

    return false;
}

// RorL64: rd = ra rotated right by rb bits (64-bit rotate right)
bool jit_emit_ror_64(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t ra,
    uint8_t rb,
    uint8_t rd)
{
    if (strcmp(target_arch, "x86_64") == 0) {
        auto* a = static_cast<x86::Assembler*>(assembler);

        // Load ra
        a->mov(x86::rax, x86::qword_ptr(rbx, ra * 8));

        // Load rb (shift count)
        a->mov(x86::rcx, x86::qword_ptr(rbx, rb * 8));

        // Rotate right by rcx bits
        a->ror(x86::rax, x86::cl);

        // Store result to rd
        a->mov(x86::qword_ptr(rbx, rd * 8), x86::rax);

        return true;
    } else if (strcmp(target_arch, "aarch64") == 0) {
        auto* a = static_cast<asmjit::a64::Assembler*>(assembler);

        // Load ra and rb into temporary registers
        a->ldr(a64::x0, a64::ptr(a64::x29, ra * 8));
        a->ldr(a64::x1, a64::ptr(a64::x29, rb * 8));

        // ARM64 doesn't have register-based rotate instructions
        // Implement right rotate using shift combination:
        // x2 = (x0 >> x1) | (x0 << (64 - x1))
        // First, mask shift count to 6 bits
        a->and_(a64::x1, a64::x1, 0x3F);

        // Compute inverse shift amount: x3 = 64 - x1
        a->mov(a64::x3, 64);
        a->sub(a64::x3, a64::x3, a64::x1);

        // Right shift: x4 = x0 >> x1
        a->lsr(a64::x4, a64::x0, a64::x1);

        // Left shift: x5 = x0 << x3
        a->lsl(a64::x5, a64::x0, a64::x3);

        // Combine: x2 = x4 | x5
        a->orr(a64::x2, a64::x4, a64::x5);

        // Store result to rd
        a->str(a64::x2, a64::ptr(a64::x29, rd * 8));

        return true;
    }

    return false;
}

} // namespace jit_instruction
