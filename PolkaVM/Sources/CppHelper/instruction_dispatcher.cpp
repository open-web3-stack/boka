// Comprehensive Instruction Decoder and Dispatcher for JIT
// This file provides the integration layer between Swift bytecode and C++ emitters

#include "jit_instructions.hh"
#include "helper.hh"
#include "opcodes.hh"
#include <asmjit/asmjit.h>

using namespace asmjit;
using namespace asmjit::x86;
using namespace PVM;

namespace jit_emitter {

// Decoded instruction with all possible operands
struct DecodedInstruction {
    uint8_t opcode;
    uint8_t dest_reg;
    uint8_t src1_reg;
    uint8_t src2_reg;
    uint64_t immediate;
    uint32_t target_pc;
    uint32_t address;
    uint16_t offset;
    uint8_t size;
};

// Decode LoadImm64 instruction
bool decode_load_imm_64(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    decoded.opcode = bytecode[pc];

    // Format: [opcode][reg_index][value_64bit]
    decoded.dest_reg = bytecode[pc + 1];
    decoded.immediate = *reinterpret_cast<const uint64_t*>(&bytecode[pc + 2]);
    decoded.size = 10; // 1 + 1 + 8 = 10 bytes

    return true;
}

// Decode LoadImm instruction
bool decode_load_imm(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    decoded.opcode = bytecode[pc];

    // Format: [opcode][reg_index][value_32bit]
    decoded.dest_reg = bytecode[pc + 1];
    decoded.immediate = *reinterpret_cast<const uint32_t*>(&bytecode[pc + 2]);
    decoded.size = 6; // 1 + 1 + 4 = 6 bytes

    return true;
}

// Decode LoadImmJump instruction (opcode 80)
bool decode_load_imm_jump(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    decoded.opcode = bytecode[pc];

    // Format: [opcode][reg_index][immediate_32bit][offset_32bit]
    decoded.dest_reg = bytecode[pc + 1];
    decoded.immediate = *reinterpret_cast<const uint32_t*>(&bytecode[pc + 2]);
    decoded.offset = *reinterpret_cast<const int32_t*>(&bytecode[pc + 6]);
    // Offset is relative to the START of the instruction (not the end)
    // This matches the Swift implementation (Instructions.swift:422) and x64_labeled_helper.cpp
    decoded.target_pc = pc + static_cast<uint32_t>(decoded.offset); // PC-relative
    decoded.size = 10; // 1 + 1 + 4 + 4 = 10 bytes

    return true;
}

// Decode LoadU8 instruction
bool decode_load_u8(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    decoded.opcode = bytecode[pc];

    // Format: [opcode][reg_index][address_32bit]
    decoded.dest_reg = bytecode[pc + 1];
    decoded.address = *reinterpret_cast<const uint32_t*>(&bytecode[pc + 2]);
    decoded.size = 6;

    return true;
}

// Decode LoadI8 instruction
bool decode_load_i8(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    decoded.opcode = bytecode[pc];

    // Format: [opcode][reg_index][address_32bit]
    decoded.dest_reg = bytecode[pc + 1];
    decoded.address = *reinterpret_cast<const uint32_t*>(&bytecode[pc + 2]);
    decoded.size = 6;

    return true;
}

// Decode LoadU16 instruction
bool decode_load_u16(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    decoded.opcode = bytecode[pc];

    // Format: [opcode][reg_index][address_32bit]
    decoded.dest_reg = bytecode[pc + 1];
    decoded.address = *reinterpret_cast<const uint32_t*>(&bytecode[pc + 2]);
    decoded.size = 6;

    return true;
}

// Decode LoadI16 instruction
bool decode_load_i16(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    decoded.opcode = bytecode[pc];

    // Format: [opcode][reg_index][address_32bit]
    decoded.dest_reg = bytecode[pc + 1];
    decoded.address = *reinterpret_cast<const uint32_t*>(&bytecode[pc + 2]);
    decoded.size = 6;

    return true;
}

// Decode LoadU32 instruction
bool decode_load_u32(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    decoded.opcode = bytecode[pc];

    // Format: [opcode][reg_index][address_32bit]
    decoded.dest_reg = bytecode[pc + 1];
    decoded.address = *reinterpret_cast<const uint32_t*>(&bytecode[pc + 2]);
    decoded.size = 6;

    return true;
}

// Decode LoadI32 instruction
bool decode_load_i32(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    decoded.opcode = bytecode[pc];

    // Format: [opcode][reg_index][address_32bit]
    decoded.dest_reg = bytecode[pc + 1];
    decoded.address = *reinterpret_cast<const uint32_t*>(&bytecode[pc + 2]);
    decoded.size = 6;

    return true;
}

// Decode LoadU64 instruction
bool decode_load_u64(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    decoded.opcode = bytecode[pc];

    // Format: [opcode][reg_index][address_32bit]
    decoded.dest_reg = bytecode[pc + 1];
    decoded.address = *reinterpret_cast<const uint32_t*>(&bytecode[pc + 2]);
    decoded.size = 6;

    return true;
}

// Decode Add32 instruction (opcode 190)
bool decode_add_32(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    decoded.opcode = bytecode[pc];
    // Format: [opcode][ra | (rb << 4)][rd] - 3 registers: rd = ra + rb
    decoded.src1_reg = bytecode[pc + 1] & 0x0F;      // ra (lower 4 bits)
    decoded.src2_reg = (bytecode[pc + 1] >> 4) & 0x0F; // rb (upper 4 bits)
    decoded.dest_reg = bytecode[pc + 2];               // rd
    decoded.size = 3;
    return true;
}

// Decode Sub32 instruction (opcode 191)
bool decode_sub_32(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    decoded.opcode = bytecode[pc];
    // Format: [opcode][ra | (rb << 4)][rd] - 3 registers: rd = ra - rb
    decoded.src1_reg = bytecode[pc + 1] & 0x0F;      // ra (lower 4 bits)
    decoded.src2_reg = (bytecode[pc + 1] >> 4) & 0x0F; // rb (upper 4 bits)
    decoded.dest_reg = bytecode[pc + 2];               // rd
    decoded.size = 3;
    return true;
}

// Decode Jump instruction
bool decode_jump(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    decoded.opcode = bytecode[pc];

    // Format: [opcode][offset_32bit]
    decoded.offset = *reinterpret_cast<const int32_t*>(&bytecode[pc + 1]);
    // Offset is relative to the START of the instruction (not the end)
    // This matches the Swift implementation (Instructions.swift:141) and x64_labeled_helper.cpp
    decoded.target_pc = pc + static_cast<uint32_t>(decoded.offset); // PC-relative
    decoded.size = 5;

    return true;
}

// Decode Trap instruction
bool decode_trap(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    decoded.opcode = bytecode[pc];
    decoded.size = 1;
    return true;
}

// Decode Fallthrough instruction
bool decode_fallthrough(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    decoded.opcode = bytecode[pc];
    decoded.size = 1;
    return true;
}

// Decode StoreImmU8 instruction (opcode 30)
bool decode_store_imm_u8(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    decoded.opcode = bytecode[pc];
    // Format: [opcode][value_8bit][address_32bit]
    decoded.immediate = bytecode[pc + 1];
    decoded.address = *reinterpret_cast<const uint32_t*>(&bytecode[pc + 2]);
    decoded.size = 6; // 1 + 1 + 4 = 6 bytes
    return true;
}

// Decode StoreImmU16 instruction (opcode 31)
bool decode_store_imm_u16(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    decoded.opcode = bytecode[pc];
    // Format: [opcode][value_16bit][address_32bit]
    decoded.immediate = *reinterpret_cast<const uint16_t*>(&bytecode[pc + 1]);
    decoded.address = *reinterpret_cast<const uint32_t*>(&bytecode[pc + 3]);
    decoded.size = 7; // 1 + 2 + 4 = 7 bytes
    return true;
}

// Decode StoreImmU32 instruction (opcode 32)
bool decode_store_imm_u32(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    decoded.opcode = bytecode[pc];
    // Format: [opcode][value_32bit][address_32bit]
    decoded.immediate = *reinterpret_cast<const uint32_t*>(&bytecode[pc + 1]);
    decoded.address = *reinterpret_cast<const uint32_t*>(&bytecode[pc + 5]);
    decoded.size = 9; // 1 + 4 + 4 = 9 bytes
    return true;
}

// Decode StoreImmU64 instruction (opcode 33)
bool decode_store_imm_u64(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    decoded.opcode = bytecode[pc];
    // Format: [opcode][value_64bit][address_32bit]
    decoded.immediate = *reinterpret_cast<const uint64_t*>(&bytecode[pc + 1]);
    decoded.address = *reinterpret_cast<const uint32_t*>(&bytecode[pc + 9]);
    decoded.size = 13; // 1 + 8 + 4 = 13 bytes
    return true;
}

// Decode StoreImmIndU8 instruction (opcode 70)
// Format: [opcode][reg_index][address_32bit][value_8bit]
// Address and value share 32 bits: 16-bit address offset + 8-bit value
bool decode_store_imm_ind_u8(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    decoded.opcode = bytecode[pc];
    decoded.dest_reg = bytecode[pc + 1];  // reg_index
    // Combined 32-bit field: [16-bit address][16-bit padding/value]
    decoded.address = *reinterpret_cast<const uint32_t*>(&bytecode[pc + 2]);
    decoded.immediate = bytecode[pc + 6];  // 8-bit value
    decoded.size = 7; // 1 + 1 + 4 + 1 = 7 bytes
    return true;
}

// Decode StoreImmIndU16 instruction (opcode 71)
// Format: [opcode][reg_index][address_32bit][value_16bit]
bool decode_store_imm_ind_u16(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    decoded.opcode = bytecode[pc];
    decoded.dest_reg = bytecode[pc + 1];  // reg_index
    decoded.address = *reinterpret_cast<const uint32_t*>(&bytecode[pc + 2]);
    decoded.immediate = *reinterpret_cast<const uint16_t*>(&bytecode[pc + 6]);
    decoded.size = 8; // 1 + 1 + 4 + 2 = 8 bytes
    return true;
}

// Decode StoreImmIndU32 instruction (opcode 72)
// Format: [opcode][reg_index][address_32bit][value_32bit]
bool decode_store_imm_ind_u32(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    decoded.opcode = bytecode[pc];
    decoded.dest_reg = bytecode[pc + 1];  // reg_index
    decoded.address = *reinterpret_cast<const uint32_t*>(&bytecode[pc + 2]);
    decoded.immediate = *reinterpret_cast<const uint32_t*>(&bytecode[pc + 6]);
    decoded.size = 10; // 1 + 1 + 4 + 4 = 10 bytes
    return true;
}

// Decode StoreImmIndU64 instruction (opcode 73)
// Format: [opcode][reg_index][address_32bit][value_64bit]
bool decode_store_imm_ind_u64(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    decoded.opcode = bytecode[pc];
    decoded.dest_reg = bytecode[pc + 1];  // reg_index
    decoded.address = *reinterpret_cast<const uint32_t*>(&bytecode[pc + 2]);
    decoded.immediate = *reinterpret_cast<const uint64_t*>(&bytecode[pc + 6]);
    decoded.size = 14; // 1 + 1 + 4 + 8 = 14 bytes
    return true;
}

// Decode StoreIndU8 instruction (opcode 120)
// Format: [opcode][src_reg][dest_reg][offset_32bit]
bool decode_store_ind_u8(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    decoded.opcode = bytecode[pc];
    decoded.dest_reg = bytecode[pc + 1];  // src_reg (value to store)
    decoded.src1_reg = bytecode[pc + 2];  // dest_reg (base address)
    decoded.address = *reinterpret_cast<const uint32_t*>(&bytecode[pc + 3]);
    decoded.size = 7; // 1 + 1 + 1 + 4 = 7 bytes
    return true;
}

// Decode StoreIndU16 instruction (opcode 121)
// Same format as StoreIndU8
bool decode_store_ind_u16(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    decoded.opcode = bytecode[pc];
    decoded.dest_reg = bytecode[pc + 1];  // src_reg
    decoded.src1_reg = bytecode[pc + 2];  // dest_reg
    decoded.address = *reinterpret_cast<const uint32_t*>(&bytecode[pc + 3]);
    decoded.size = 7;
    return true;
}

// Decode StoreIndU32 instruction (opcode 122)
// Same format as StoreIndU8
bool decode_store_ind_u32(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    decoded.opcode = bytecode[pc];
    decoded.dest_reg = bytecode[pc + 1];  // src_reg
    decoded.src1_reg = bytecode[pc + 2];  // dest_reg
    decoded.address = *reinterpret_cast<const uint32_t*>(&bytecode[pc + 3]);
    decoded.size = 7;
    return true;
}

// Decode StoreIndU64 instruction (opcode 123)
// Same format as StoreIndU8
bool decode_store_ind_u64(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    decoded.opcode = bytecode[pc];
    decoded.dest_reg = bytecode[pc + 1];  // src_reg
    decoded.src1_reg = bytecode[pc + 2];  // dest_reg
    decoded.address = *reinterpret_cast<const uint32_t*>(&bytecode[pc + 3]);
    decoded.size = 7;
    return true;
}

// Decode LoadIndU8 instruction (opcode 124)
// Format: [opcode][ra][rb][offset_32bit]
bool decode_load_ind_u8(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    decoded.opcode = bytecode[pc];
    decoded.dest_reg = bytecode[pc + 1];  // ra (destination)
    decoded.src1_reg = bytecode[pc + 2];  // rb (base address)
    decoded.address = *reinterpret_cast<const uint32_t*>(&bytecode[pc + 3]);
    decoded.size = 7; // 1 + 1 + 1 + 4 = 7 bytes
    return true;
}

// Decode LoadIndI8 instruction (opcode 125)
// Same format as LoadIndU8
bool decode_load_ind_i8(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    decoded.opcode = bytecode[pc];
    decoded.dest_reg = bytecode[pc + 1];  // ra
    decoded.src1_reg = bytecode[pc + 2];  // rb
    decoded.address = *reinterpret_cast<const uint32_t*>(&bytecode[pc + 3]);
    decoded.size = 7;
    return true;
}

// Decode LoadIndU16 instruction (opcode 126)
// Same format as LoadIndU8
bool decode_load_ind_u16(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    decoded.opcode = bytecode[pc];
    decoded.dest_reg = bytecode[pc + 1];  // ra
    decoded.src1_reg = bytecode[pc + 2];  // rb
    decoded.address = *reinterpret_cast<const uint32_t*>(&bytecode[pc + 3]);
    decoded.size = 7;
    return true;
}

// Decode LoadIndI16 instruction (opcode 127)
// Same format as LoadIndU8
bool decode_load_ind_i16(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    decoded.opcode = bytecode[pc];
    decoded.dest_reg = bytecode[pc + 1];  // ra
    decoded.src1_reg = bytecode[pc + 2];  // rb
    decoded.address = *reinterpret_cast<const uint32_t*>(&bytecode[pc + 3]);
    decoded.size = 7;
    return true;
}

// Decode LoadIndU32 instruction (opcode 128)
// Same format as LoadIndU8
bool decode_load_ind_u32(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    decoded.opcode = bytecode[pc];
    decoded.dest_reg = bytecode[pc + 1];  // ra
    decoded.src1_reg = bytecode[pc + 2];  // rb
    decoded.address = *reinterpret_cast<const uint32_t*>(&bytecode[pc + 3]);
    decoded.size = 7;
    return true;
}

// Decode LoadIndI32 instruction (opcode 129)
// Same format as LoadIndU8
bool decode_load_ind_i32(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    decoded.opcode = bytecode[pc];
    decoded.dest_reg = bytecode[pc + 1];  // ra
    decoded.src1_reg = bytecode[pc + 2];  // rb
    decoded.address = *reinterpret_cast<const uint32_t*>(&bytecode[pc + 3]);
    decoded.size = 7;
    return true;
}

// Decode LoadIndU64 instruction (opcode 130)
// Same format as LoadIndU8
bool decode_load_ind_u64(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    decoded.opcode = bytecode[pc];
    decoded.dest_reg = bytecode[pc + 1];  // ra
    decoded.src1_reg = bytecode[pc + 2];  // rb
    decoded.address = *reinterpret_cast<const uint32_t*>(&bytecode[pc + 3]);
    decoded.size = 7;
    return true;
}

// Decode BranchEqImm instruction (opcode 81)
// Format: [opcode][reg_index][value_64bit][offset_32bit]
bool decode_branch_eq_imm(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    decoded.opcode = bytecode[pc];
    decoded.dest_reg = bytecode[pc + 1];  // reg_index
    decoded.immediate = *reinterpret_cast<const uint64_t*>(&bytecode[pc + 2]);
    decoded.offset = *reinterpret_cast<const int32_t*>(&bytecode[pc + 10]);
    // Offset is relative to the START of the instruction (not the end)
    // This matches the Swift implementation (BranchInstructionBase.swift:23)
    decoded.target_pc = pc + static_cast<uint32_t>(decoded.offset);
    decoded.size = 14; // 1 + 1 + 8 + 4 = 14 bytes
    return true;
}

// The remaining BranchImm opcodes (82-90) have the same format
bool decode_branch_ne_imm(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    return decode_branch_eq_imm(bytecode, pc, decoded);
}

bool decode_branch_lt_u_imm(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    return decode_branch_eq_imm(bytecode, pc, decoded);
}

bool decode_branch_le_u_imm(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    return decode_branch_eq_imm(bytecode, pc, decoded);
}

bool decode_branch_ge_u_imm(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    return decode_branch_eq_imm(bytecode, pc, decoded);
}

bool decode_branch_gt_u_imm(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    return decode_branch_eq_imm(bytecode, pc, decoded);
}

bool decode_branch_lt_s_imm(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    return decode_branch_eq_imm(bytecode, pc, decoded);
}

bool decode_branch_le_s_imm(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    return decode_branch_eq_imm(bytecode, pc, decoded);
}

bool decode_branch_ge_s_imm(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    return decode_branch_eq_imm(bytecode, pc, decoded);
}

bool decode_branch_gt_s_imm(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    return decode_branch_eq_imm(bytecode, pc, decoded);
}

// Decode AddImm32 instruction (opcode 131)
// Format: [opcode][ra][rb][value_32bit]
bool decode_add_imm_32(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    decoded.opcode = bytecode[pc];
    decoded.dest_reg = bytecode[pc + 1];  // ra
    decoded.src1_reg = bytecode[pc + 2];  // rb
    decoded.immediate = *reinterpret_cast<const uint32_t*>(&bytecode[pc + 3]);
    decoded.size = 7; // 1 + 1 + 1 + 4 = 7 bytes
    return true;
}

// AndImm, XorImm, OrImm have same format
bool decode_and_imm_32(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    return decode_add_imm_32(bytecode, pc, decoded);
}

bool decode_xor_imm_32(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    return decode_add_imm_32(bytecode, pc, decoded);
}

bool decode_or_imm_32(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    return decode_add_imm_32(bytecode, pc, decoded);
}

bool decode_mul_imm_32(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    return decode_add_imm_32(bytecode, pc, decoded);
}

bool decode_set_lt_u_imm(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    return decode_add_imm_32(bytecode, pc, decoded);
}

bool decode_set_lt_s_imm(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    return decode_add_imm_32(bytecode, pc, decoded);
}

bool decode_shlo_l_imm_32(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    return decode_add_imm_32(bytecode, pc, decoded);
}

bool decode_shlo_r_imm_32(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    return decode_add_imm_32(bytecode, pc, decoded);
}

bool decode_shar_r_imm_32(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    return decode_add_imm_32(bytecode, pc, decoded);
}

bool decode_neg_add_imm_32(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    return decode_add_imm_32(bytecode, pc, decoded);
}

bool decode_set_gt_u_imm(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    return decode_add_imm_32(bytecode, pc, decoded);
}

bool decode_set_gt_s_imm(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    return decode_add_imm_32(bytecode, pc, decoded);
}

// Alt shift variants have same format
bool decode_shlo_l_imm_alt_32(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    return decode_add_imm_32(bytecode, pc, decoded);
}

bool decode_shlo_r_imm_alt_32(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    return decode_add_imm_32(bytecode, pc, decoded);
}

bool decode_shar_r_imm_alt_32(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    return decode_add_imm_32(bytecode, pc, decoded);
}

// Cmov immediate has same format
bool decode_cmov_iz_imm(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    return decode_add_imm_32(bytecode, pc, decoded);
}

bool decode_cmov_nz_imm(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    return decode_add_imm_32(bytecode, pc, decoded);
}

// Decode AddImm64 instruction (opcode 149)
// Format: [opcode][ra][rb][value_64bit]
bool decode_add_imm_64(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    decoded.opcode = bytecode[pc];
    decoded.dest_reg = bytecode[pc + 1];  // ra
    decoded.src1_reg = bytecode[pc + 2];  // rb
    decoded.immediate = *reinterpret_cast<const uint64_t*>(&bytecode[pc + 3]);
    decoded.size = 11; // 1 + 1 + 1 + 8 = 11 bytes
    return true;
}

// Other 64-bit immediate instructions have same format
bool decode_mul_imm_64(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    return decode_add_imm_64(bytecode, pc, decoded);
}

bool decode_shlo_l_imm_64(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    return decode_add_imm_64(bytecode, pc, decoded);
}

bool decode_shlo_r_imm_64(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    return decode_add_imm_64(bytecode, pc, decoded);
}

bool decode_shar_r_imm_64(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    return decode_add_imm_64(bytecode, pc, decoded);
}

bool decode_neg_add_imm_64(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    return decode_add_imm_64(bytecode, pc, decoded);
}

// Alt shift and rotate variants have same format
bool decode_shlo_l_imm_alt_64(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    return decode_add_imm_64(bytecode, pc, decoded);
}

bool decode_shlo_r_imm_alt_64(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    return decode_add_imm_64(bytecode, pc, decoded);
}

bool decode_shar_r_imm_alt_64(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    return decode_add_imm_64(bytecode, pc, decoded);
}

bool decode_rot_r_64_imm(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    return decode_add_imm_64(bytecode, pc, decoded);
}

bool decode_rot_r_64_imm_alt(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    return decode_add_imm_64(bytecode, pc, decoded);
}

bool decode_rot_r_32_imm(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    return decode_add_imm_64(bytecode, pc, decoded);
}

bool decode_rot_r_32_imm_alt(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    return decode_add_imm_64(bytecode, pc, decoded);
}

// Decode JumpInd instruction (opcode 50)
bool decode_jump_ind(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    decoded.opcode = bytecode[pc];
    // Format: [opcode][reg_index]
    decoded.dest_reg = bytecode[pc + 1];
    decoded.size = 2;
    return true;
}

// Decode LoadImmJumpInd instruction (opcode 180)
bool decode_load_imm_jump_ind(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    decoded.opcode = bytecode[pc];
    // Format: [opcode][ra][rb][value_32bit][offset_32bit]
    decoded.dest_reg = bytecode[pc + 1];     // ra
    decoded.src1_reg = bytecode[pc + 2];     // rb
    decoded.immediate = *reinterpret_cast<const uint32_t*>(&bytecode[pc + 3]);  // value
    decoded.target_pc = *reinterpret_cast<const uint32_t*>(&bytecode[pc + 7]);  // offset (used as jump target)
    decoded.size = 11; // 1 + 1 + 1 + 4 + 4 = 11 bytes
    return true;
}

// Decode StoreU8 instruction (opcode 59)
bool decode_store_u8(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    decoded.opcode = bytecode[pc];
    // Format: [opcode][src_reg][address_32bit]
    decoded.dest_reg = bytecode[pc + 1];
    decoded.address = *reinterpret_cast<const uint32_t*>(&bytecode[pc + 2]);
    decoded.size = 6;
    return true;
}

// Decode StoreU16 instruction (opcode 60)
bool decode_store_u16(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    decoded.opcode = bytecode[pc];
    // Format: [opcode][src_reg][address_32bit]
    decoded.dest_reg = bytecode[pc + 1];
    decoded.address = *reinterpret_cast<const uint32_t*>(&bytecode[pc + 2]);
    decoded.size = 6;
    return true;
}

// Decode StoreU32 instruction (opcode 61)
bool decode_store_u32(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    decoded.opcode = bytecode[pc];
    // Format: [opcode][src_reg][address_32bit]
    decoded.dest_reg = bytecode[pc + 1];
    decoded.address = *reinterpret_cast<const uint32_t*>(&bytecode[pc + 2]);
    decoded.size = 6;
    return true;
}

// Decode StoreU64 instruction (opcode 62)
bool decode_store_u64(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    decoded.opcode = bytecode[pc];
    // Format: [opcode][src_reg][address_32bit]
    decoded.dest_reg = bytecode[pc + 1];
    decoded.address = *reinterpret_cast<const uint32_t*>(&bytecode[pc + 2]);
    decoded.size = 6;
    return true;
}

// Decode Mul32 instruction (opcode 192)
bool decode_mul_32(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    decoded.opcode = bytecode[pc];
    // Format: [opcode][ra | (rb << 4)][rd] - 3 registers: rd = ra * rb
    decoded.src1_reg = bytecode[pc + 1] & 0x0F;      // ra (lower 4 bits)
    decoded.src2_reg = (bytecode[pc + 1] >> 4) & 0x0F; // rb (upper 4 bits)
    decoded.dest_reg = bytecode[pc + 2];               // rd
    decoded.size = 3;
    return true;
}

// Decode DivU32 instruction (opcode 193)
bool decode_div_u32(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    decoded.opcode = bytecode[pc];
    // Format: [opcode][ra | (rb << 4)][rd] - 3 registers: rd = ra / rb
    decoded.src1_reg = bytecode[pc + 1] & 0x0F;      // ra (lower 4 bits)
    decoded.src2_reg = (bytecode[pc + 1] >> 4) & 0x0F; // rb (upper 4 bits)
    decoded.dest_reg = bytecode[pc + 2];               // rd
    decoded.size = 3;
    return true;
}

// Decode DivS32 instruction (opcode 194)
bool decode_div_s32(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    decoded.opcode = bytecode[pc];
    // Format: [opcode][ra | (rb << 4)][rd] - 3 registers: rd = ra / rb (signed)
    decoded.src1_reg = bytecode[pc + 1] & 0x0F;      // ra (lower 4 bits)
    decoded.src2_reg = (bytecode[pc + 1] >> 4) & 0x0F; // rb (upper 4 bits)
    decoded.dest_reg = bytecode[pc + 2];               // rd
    decoded.size = 3;
    return true;
}

// Decode RemU32 instruction (opcode 195)
bool decode_rem_u32(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    decoded.opcode = bytecode[pc];
    // Format: [opcode][ra | (rb << 4)][rd] - 3 registers: rd = ra % rb
    decoded.src1_reg = bytecode[pc + 1] & 0x0F;      // ra (lower 4 bits)
    decoded.src2_reg = (bytecode[pc + 1] >> 4) & 0x0F; // rb (upper 4 bits)
    decoded.dest_reg = bytecode[pc + 2];               // rd
    decoded.size = 3;
    return true;
}

// Decode RemS32 instruction (opcode 196)
bool decode_rem_s32(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    decoded.opcode = bytecode[pc];
    // Format: [opcode][ra | (rb << 4)][rd] - 3 registers: rd = ra % rb (signed)
    decoded.src1_reg = bytecode[pc + 1] & 0x0F;      // ra (lower 4 bits)
    decoded.src2_reg = (bytecode[pc + 1] >> 4) & 0x0F; // rb (upper 4 bits)
    decoded.dest_reg = bytecode[pc + 2];               // rd
    decoded.size = 3;
    return true;
}

// Decode Add64 instruction (opcode 200)
bool decode_add_64(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    decoded.opcode = bytecode[pc];
    // Format: [opcode][ra | (rb << 4)][rd] - 3 registers: rd = ra + rb
    decoded.src1_reg = bytecode[pc + 1] & 0x0F;      // ra (lower 4 bits)
    decoded.src2_reg = (bytecode[pc + 1] >> 4) & 0x0F; // rb (upper 4 bits)
    decoded.dest_reg = bytecode[pc + 2];               // rd
    decoded.size = 3;
    return true;
}

// Decode Sub64 instruction (opcode 201)
bool decode_sub_64(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    decoded.opcode = bytecode[pc];
    // Format: [opcode][ra | (rb << 4)][rd] - 3 registers: rd = ra - rb
    decoded.src1_reg = bytecode[pc + 1] & 0x0F;      // ra (lower 4 bits)
    decoded.src2_reg = (bytecode[pc + 1] >> 4) & 0x0F; // rb (upper 4 bits)
    decoded.dest_reg = bytecode[pc + 2];               // rd
    decoded.size = 3;
    return true;
}

// Decode Mul64 instruction (opcode 202)
bool decode_mul_64(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    decoded.opcode = bytecode[pc];
    // Format: [opcode][ra | (rb << 4)][rd] - 3 registers: rd = ra * rb
    decoded.src1_reg = bytecode[pc + 1] & 0x0F;      // ra (lower 4 bits)
    decoded.src2_reg = (bytecode[pc + 1] >> 4) & 0x0F; // rb (upper 4 bits)
    decoded.dest_reg = bytecode[pc + 2];               // rd
    decoded.size = 3;
    return true;
}

// Decode And instruction (opcode 210)
bool decode_and(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    decoded.opcode = bytecode[pc];
    // Format: [opcode][ra | (rb << 4)][rd] - 3 registers: rd = ra & rb
    decoded.src1_reg = bytecode[pc + 1] & 0x0F;      // ra (lower 4 bits)
    decoded.src2_reg = (bytecode[pc + 1] >> 4) & 0x0F; // rb (upper 4 bits)
    decoded.dest_reg = bytecode[pc + 2];               // rd
    decoded.size = 3;
    return true;
}

// Decode Xor instruction (opcode 211)
bool decode_xor(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    decoded.opcode = bytecode[pc];
    // Format: [opcode][ra | (rb << 4)][rd] - 3 registers: rd = ra ^ rb
    decoded.src1_reg = bytecode[pc + 1] & 0x0F;      // ra (lower 4 bits)
    decoded.src2_reg = (bytecode[pc + 1] >> 4) & 0x0F; // rb (upper 4 bits)
    decoded.dest_reg = bytecode[pc + 2];               // rd
    decoded.size = 3;
    return true;
}

// Decode Or instruction (opcode 212)
bool decode_or(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    decoded.opcode = bytecode[pc];
    // Format: [opcode][ra | (rb << 4)][rd] - 3 registers: rd = ra | rb
    decoded.src1_reg = bytecode[pc + 1] & 0x0F;      // ra (lower 4 bits)
    decoded.src2_reg = (bytecode[pc + 1] >> 4) & 0x0F; // rb (upper 4 bits)
    decoded.dest_reg = bytecode[pc + 2];               // rd
    decoded.size = 3;
    return true;
}

// Decode BranchEq instruction (opcode 170)
bool decode_branch_eq(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    decoded.opcode = bytecode[pc];
    // Format: [opcode][reg1][reg2][offset_32bit]
    decoded.src1_reg = bytecode[pc + 1];
    decoded.src2_reg = bytecode[pc + 2];
    decoded.offset = *reinterpret_cast<const int32_t*>(&bytecode[pc + 3]);
    // Offset is relative to the start of the branch instruction (PC at branch)
    // target_pc = pc + offset
    decoded.target_pc = pc + static_cast<uint32_t>(decoded.offset);
    decoded.size = 7;
    return true;
}

// Decode BranchNe instruction (opcode 171)
bool decode_branch_ne(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    decoded.opcode = bytecode[pc];
    // Format: [opcode][reg1][reg2][offset_32bit]
    decoded.src1_reg = bytecode[pc + 1];
    decoded.src2_reg = bytecode[pc + 2];
    decoded.offset = *reinterpret_cast<const int32_t*>(&bytecode[pc + 3]);
    // Offset is relative to the start of the branch instruction (PC at branch)
    decoded.target_pc = pc + static_cast<uint32_t>(decoded.offset);
    decoded.size = 7;
    return true;
}

// Decode Ecalli instruction (opcode 10)
bool decode_ecalli(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    decoded.opcode = bytecode[pc];
    // Format: [opcode][call_index_32bit]
    decoded.immediate = *reinterpret_cast<const uint32_t*>(&bytecode[pc + 1]);
    decoded.size = 5; // 1 + 4 = 5 bytes
    return true;
}

// Decode 2-register instructions (MoveReg, etc.)
// Format: [opcode][dest][src]
bool decode_2_reg(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    decoded.opcode = bytecode[pc];
    decoded.dest_reg = bytecode[pc + 1];  // destination register
    decoded.src1_reg = bytecode[pc + 2];  // source register
    decoded.size = 3; // 1 + 1 + 1 = 3 bytes
    return true;
}

// Decode 3-register instructions (MulUpper, SetLt, Cmov, Rot)
// Format: [opcode][ra][rb][rd]
bool decode_3_reg(const uint8_t* bytecode, uint32_t pc, DecodedInstruction& decoded) {
    decoded.opcode = bytecode[pc];
    decoded.dest_reg = bytecode[pc + 1];  // ra
    decoded.src1_reg = bytecode[pc + 2];  // rb
    decoded.src2_reg = bytecode[pc + 3];  // rd
    decoded.size = 4; // 1 + 1 + 1 + 1 = 4 bytes
    return true;
}

// Generic instruction dispatcher using opcode table
bool emit_instruction_decoded(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    const DecodedInstruction& decoded)
{
    auto* a = static_cast<x86::Assembler*>(assembler);

    // Dispatch based on opcode
    // Note: These opcode numbers match the PVM::Opcode enum from opcodes.hh
    switch (decoded.opcode) {
        case static_cast<uint8_t>(Opcode::Trap):
            return jit_instruction::jit_emit_trap(assembler, target_arch);

        case static_cast<uint8_t>(Opcode::Halt):
            // No emission needed for fallthrough
            return true;

        case 10: // Ecalli - opcode 10
            // Ecalli uses decoded.immediate for call_index
            // gas_ptr is passed as nullptr because the JIT implementation uses the VM_GAS_PTR register (r14/x22) directly
            return jit_instruction::jit_generateEcalli(assembler, target_arch,
                static_cast<uint32_t>(decoded.immediate), nullptr);

        case static_cast<uint8_t>(Opcode::LoadImmU64):
            return jit_instruction::jit_emit_load_imm_64(
                assembler, target_arch,
                decoded.dest_reg,
                decoded.immediate
            );

        case static_cast<uint8_t>(Opcode::StoreImmU8):
        case static_cast<uint8_t>(Opcode::StoreImmU16):
        case static_cast<uint8_t>(Opcode::StoreImmU32):
        case static_cast<uint8_t>(Opcode::StoreImmU64):
            // StoreImm instructions are handled explicitly in x64_labeled_helper.cpp
            // before calling the dispatcher, so these cases should never be reached.
            a->nop();
            return true;

        case static_cast<uint8_t>(Opcode::Jump):
            // NOTE: Jump target calculation handled in dispatcher
            // Labeled JIT implementation (compilePolkaVMCode_x64_labeled) handles labels properly
            return jit_instruction::jit_emit_jump(
                assembler, target_arch,
                decoded.target_pc  // Use target_pc instead of offset
            );

        case static_cast<uint8_t>(Opcode::JumpInd):
            // JumpInd format: [opcode][reg_index]
            // The reg_index specifies which register contains the target PC
            return jit_instruction::jit_emit_jump_ind(
                assembler, target_arch,
                decoded.dest_reg,  // ptr_reg (register containing target PC)
                0  // offset (not used in JumpInd - register contains absolute target)
            );

        case static_cast<uint8_t>(Opcode::LoadImm):
            return jit_instruction::jit_emit_load_imm_32(
                assembler, target_arch,
                decoded.dest_reg,
                static_cast<uint32_t>(decoded.immediate)
            );

        case static_cast<uint8_t>(Opcode::LoadImmJump):
            return jit_instruction::jit_emit_load_imm_jump(
                assembler, target_arch,
                decoded.dest_reg,      // ra (register to load immediate into)
                static_cast<uint32_t>(decoded.immediate),  // immediate value
                decoded.target_pc      // target PC
            );

        case static_cast<uint8_t>(Opcode::LoadImmJumpInd):
            return jit_instruction::jit_emit_load_imm_jump_ind(
                assembler, target_arch,
                decoded.dest_reg,
                decoded.src1_reg,
                static_cast<uint32_t>(decoded.immediate),
                decoded.target_pc      // offset
            );

        // Branch Immediate instructions (opcodes 81-90)
        // Format: [opcode][reg_index][value_64bit][offset_32bit]
        case static_cast<uint8_t>(Opcode::BranchEqImm):
            return jit_instruction::jit_emit_branch_eq_imm(
                assembler, target_arch,
                decoded.dest_reg,
                decoded.immediate,
                decoded.target_pc
            );

        case static_cast<uint8_t>(Opcode::BranchNeImm):
            return jit_instruction::jit_emit_branch_ne_imm(
                assembler, target_arch,
                decoded.dest_reg,
                decoded.immediate,
                decoded.target_pc
            );

        case static_cast<uint8_t>(Opcode::BranchLtUImm):
            return jit_instruction::jit_emit_branch_lt_u_imm(
                assembler, target_arch,
                decoded.dest_reg,
                decoded.immediate,
                decoded.target_pc
            );

        case static_cast<uint8_t>(Opcode::BranchLeUImm):
            return jit_instruction::jit_emit_branch_le_u_imm(
                assembler, target_arch,
                decoded.dest_reg,
                decoded.immediate,
                decoded.target_pc
            );

        case static_cast<uint8_t>(Opcode::BranchGeUImm):
            return jit_instruction::jit_emit_branch_ge_u_imm(
                assembler, target_arch,
                decoded.dest_reg,
                decoded.immediate,
                decoded.target_pc
            );

        case static_cast<uint8_t>(Opcode::BranchGtUImm):
            return jit_instruction::jit_emit_branch_gt_u_imm(
                assembler, target_arch,
                decoded.dest_reg,
                decoded.immediate,
                decoded.target_pc
            );

        case static_cast<uint8_t>(Opcode::BranchLtSImm):
            return jit_instruction::jit_emit_branch_lt_imm(
                assembler, target_arch,
                decoded.dest_reg,
                decoded.immediate,
                decoded.target_pc
            );

        case static_cast<uint8_t>(Opcode::BranchLeSImm):
            return jit_instruction::jit_emit_branch_le_imm(
                assembler, target_arch,
                decoded.dest_reg,
                decoded.immediate,
                decoded.target_pc
            );

        case static_cast<uint8_t>(Opcode::BranchGeSImm):
            return jit_instruction::jit_emit_branch_ge_imm(
                assembler, target_arch,
                decoded.dest_reg,
                decoded.immediate,
                decoded.target_pc
            );

        case static_cast<uint8_t>(Opcode::BranchGtSImm):
            return jit_instruction::jit_emit_branch_gt_imm(
                assembler, target_arch,
                decoded.dest_reg,
                decoded.immediate,
                decoded.target_pc
            );

        // 32-bit Immediate instructions (opcodes 131-148)
        // Format: [opcode][ra][rb][value_32bit]
        case static_cast<uint8_t>(Opcode::AddImm32):
            return jit_instruction::jit_emit_add_imm_32(
                assembler, target_arch,
                decoded.dest_reg,
                decoded.src1_reg,
                static_cast<int32_t>(decoded.immediate)
            );

        case static_cast<uint8_t>(Opcode::AndImm):
            return jit_instruction::jit_emit_and_imm_32(
                assembler, target_arch,
                decoded.dest_reg,
                decoded.src1_reg,
                static_cast<uint32_t>(decoded.immediate)
            );

        case static_cast<uint8_t>(Opcode::XorImm):
            return jit_instruction::jit_emit_xor_imm_32(
                assembler, target_arch,
                decoded.dest_reg,
                decoded.src1_reg,
                static_cast<uint32_t>(decoded.immediate)
            );

        case static_cast<uint8_t>(Opcode::OrImm):
            return jit_instruction::jit_emit_or_imm_32(
                assembler, target_arch,
                decoded.dest_reg,
                decoded.src1_reg,
                static_cast<uint32_t>(decoded.immediate)
            );

        case static_cast<uint8_t>(Opcode::MulImm32):
            return jit_instruction::jit_emit_mul_imm_32(
                assembler, target_arch,
                decoded.dest_reg,
                decoded.src1_reg,
                static_cast<int32_t>(decoded.immediate)
            );

        case static_cast<uint8_t>(Opcode::SetLtUImm):
            return jit_instruction::jit_emit_lt_imm_u(
                assembler, target_arch,
                decoded.dest_reg,
                decoded.src1_reg,
                decoded.immediate
            );

        case static_cast<uint8_t>(Opcode::SetLtSImm):
            return jit_instruction::jit_emit_lt_imm(
                assembler, target_arch,
                decoded.dest_reg,
                decoded.src1_reg,
                static_cast<int32_t>(decoded.immediate)
            );

        case static_cast<uint8_t>(Opcode::ShloLImm32):
            return jit_instruction::jit_emit_shl_imm_32(
                assembler, target_arch,
                decoded.dest_reg,
                decoded.src1_reg,
                static_cast<uint8_t>(decoded.immediate)
            );

        case static_cast<uint8_t>(Opcode::ShloRImm32):
            return jit_instruction::jit_emit_shr_imm_32(
                assembler, target_arch,
                decoded.dest_reg,
                decoded.src1_reg,
                static_cast<uint8_t>(decoded.immediate)
            );

        case static_cast<uint8_t>(Opcode::SharRImm32):
            return jit_instruction::jit_emit_sar_imm_32(
                assembler, target_arch,
                decoded.dest_reg,
                decoded.src1_reg,
                static_cast<uint8_t>(decoded.immediate)
            );

        case static_cast<uint8_t>(Opcode::NegAddImm32):
            // NegAddImm32: ra = value - rb (negated addition)
            return jit_instruction::jit_emit_neg_add_imm_32(
                assembler, target_arch,
                decoded.dest_reg,
                decoded.src1_reg,
                static_cast<int32_t>(decoded.immediate)
            );

        case static_cast<uint8_t>(Opcode::SetGtUImm):
            // SetGtUImm: ra = (rb > value) ? 1 : 0
            // Implemented as: lt_u(value, rb) (swap operands)
            return jit_instruction::jit_emit_gt_imm_u(
                assembler, target_arch,
                decoded.dest_reg,
                decoded.src1_reg,
                decoded.immediate
            );

        case static_cast<uint8_t>(Opcode::SetGtSImm):
            // SetGtSImm: ra = (rb > value) ? 1 : 0 (signed)
            return jit_instruction::jit_emit_gt_imm(
                assembler, target_arch,
                decoded.dest_reg,
                decoded.src1_reg,
                static_cast<int32_t>(decoded.immediate)
            );

        case static_cast<uint8_t>(Opcode::ShloLImmAlt32):
            // Alt shift variants - same functionality
            return jit_instruction::jit_emit_shl_imm_32(
                assembler, target_arch,
                decoded.dest_reg,
                decoded.src1_reg,
                static_cast<uint8_t>(decoded.immediate)
            );

        case static_cast<uint8_t>(Opcode::ShloRImmAlt32):
            return jit_instruction::jit_emit_shr_imm_32(
                assembler, target_arch,
                decoded.dest_reg,
                decoded.src1_reg,
                static_cast<uint8_t>(decoded.immediate)
            );

        case static_cast<uint8_t>(Opcode::SharRImmAlt32):
            return jit_instruction::jit_emit_sar_imm_32(
                assembler, target_arch,
                decoded.dest_reg,
                decoded.src1_reg,
                static_cast<uint8_t>(decoded.immediate)
            );

        case static_cast<uint8_t>(Opcode::CmovIzImm):
            return jit_instruction::jit_emit_cmov_iz_imm(
                assembler, target_arch,
                decoded.dest_reg,
                decoded.src1_reg,
                static_cast<uint32_t>(decoded.immediate)
            );

        case static_cast<uint8_t>(Opcode::CmovNzImm):
            return jit_instruction::jit_emit_cmov_nz_imm(
                assembler, target_arch,
                decoded.dest_reg,
                decoded.src1_reg,
                static_cast<uint32_t>(decoded.immediate)
            );

        // 64-bit Immediate instructions (opcodes 149-161)
        // Format: [opcode][ra][rb][value_64bit]
        case static_cast<uint8_t>(Opcode::AddImm64):
            return jit_instruction::jit_emit_add_imm_64(
                assembler, target_arch,
                decoded.dest_reg,
                decoded.src1_reg,
                decoded.immediate
            );

        case static_cast<uint8_t>(Opcode::MulImm64):
            return jit_instruction::jit_emit_mul_imm_64(
                assembler, target_arch,
                decoded.dest_reg,
                decoded.src1_reg,
                decoded.immediate
            );

        case static_cast<uint8_t>(Opcode::ShloLImm64):
            return jit_instruction::jit_emit_shl_imm_64(
                assembler, target_arch,
                decoded.dest_reg,
                decoded.src1_reg,
                static_cast<uint8_t>(decoded.immediate)
            );

        case static_cast<uint8_t>(Opcode::ShloRImm64):
            return jit_instruction::jit_emit_shr_imm_64(
                assembler, target_arch,
                decoded.dest_reg,
                decoded.src1_reg,
                static_cast<uint8_t>(decoded.immediate)
            );

        case static_cast<uint8_t>(Opcode::SharRImm64):
            return jit_instruction::jit_emit_sar_imm_64(
                assembler, target_arch,
                decoded.dest_reg,
                decoded.src1_reg,
                static_cast<uint8_t>(decoded.immediate)
            );

        case static_cast<uint8_t>(Opcode::NegAddImm64):
            // NegAddImm64: ra = value - rb (negated addition)
            return jit_instruction::jit_emit_neg_add_imm_64(
                assembler, target_arch,
                decoded.dest_reg,
                decoded.src1_reg,
                decoded.immediate
            );

        case static_cast<uint8_t>(Opcode::ShloLImmAlt64):
            return jit_instruction::jit_emit_shl_imm_64(
                assembler, target_arch,
                decoded.dest_reg,
                decoded.src1_reg,
                static_cast<uint8_t>(decoded.immediate)
            );

        case static_cast<uint8_t>(Opcode::ShloRImmAlt64):
            return jit_instruction::jit_emit_shr_imm_64(
                assembler, target_arch,
                decoded.dest_reg,
                decoded.src1_reg,
                static_cast<uint8_t>(decoded.immediate)
            );

        case static_cast<uint8_t>(Opcode::SharRImmAlt64):
            return jit_instruction::jit_emit_sar_imm_64(
                assembler, target_arch,
                decoded.dest_reg,
                decoded.src1_reg,
                static_cast<uint8_t>(decoded.immediate)
            );

        case static_cast<uint8_t>(Opcode::RotR64Imm):
            return jit_instruction::jit_emit_rot_r_imm_64(
                assembler, target_arch,
                decoded.dest_reg,
                decoded.src1_reg,
                static_cast<uint8_t>(decoded.immediate)
            );

        case static_cast<uint8_t>(Opcode::RotR64ImmAlt):
            return jit_instruction::jit_emit_rot_r_imm_64(
                assembler, target_arch,
                decoded.dest_reg,
                decoded.src1_reg,
                static_cast<uint8_t>(decoded.immediate)
            );

        case static_cast<uint8_t>(Opcode::RotR32Imm):
            return jit_instruction::jit_emit_rot_r_imm_32(
                assembler, target_arch,
                decoded.dest_reg,
                decoded.src1_reg,
                static_cast<uint8_t>(decoded.immediate)
            );

        case static_cast<uint8_t>(Opcode::RotR32ImmAlt):
            return jit_instruction::jit_emit_rot_r_imm_32(
                assembler, target_arch,
                decoded.dest_reg,
                decoded.src1_reg,
                static_cast<uint8_t>(decoded.immediate)
            );

        case static_cast<uint8_t>(Opcode::LoadU8):
            // LoadU8 format: [opcode][reg_index][address_32bit]
            // PVM uses direct addressing (no ptr_reg), base register is implicit
            return jit_instruction::jit_emit_load_u8_direct(
                assembler, target_arch,
                decoded.dest_reg,
                decoded.address
            );

        case static_cast<uint8_t>(Opcode::LoadI8):
            // LoadI8 format: [opcode][reg_index][address_32bit]
            return jit_instruction::jit_emit_load_i8_direct(
                assembler, target_arch,
                decoded.dest_reg,
                decoded.address
            );

        case static_cast<uint8_t>(Opcode::LoadU16):
            // LoadU16 format: [opcode][reg_index][address_32bit]
            return jit_instruction::jit_emit_load_u16_direct(
                assembler, target_arch,
                decoded.dest_reg,
                decoded.address
            );

        case static_cast<uint8_t>(Opcode::LoadI16):
            // LoadI16 format: [opcode][reg_index][address_32bit]
            return jit_instruction::jit_emit_load_i16_direct(
                assembler, target_arch,
                decoded.dest_reg,
                decoded.address
            );

        case static_cast<uint8_t>(Opcode::LoadU32):
            // LoadU32 format: [opcode][reg_index][address_32bit]
            return jit_instruction::jit_emit_load_u32_direct(
                assembler, target_arch,
                decoded.dest_reg,
                decoded.address
            );

        case static_cast<uint8_t>(Opcode::LoadI32):
            // LoadI32 format: [opcode][reg_index][address_32bit]
            return jit_instruction::jit_emit_load_i32_direct(
                assembler, target_arch,
                decoded.dest_reg,
                decoded.address
            );

        case static_cast<uint8_t>(Opcode::LoadU64):
            // LoadU64 format: [opcode][reg_index][address_32bit]
            return jit_instruction::jit_emit_load_u64_direct(
                assembler, target_arch,
                decoded.dest_reg,
                decoded.address
            );

        case static_cast<uint8_t>(Opcode::StoreU8):
            // StoreU8 format: [opcode][reg_index][address_32bit]
            // PVM uses direct addressing (no ptr_reg), base register is implicit
            return jit_instruction::jit_emit_store_u8_direct(
                assembler, target_arch,
                decoded.address,
                decoded.dest_reg
            );

        case static_cast<uint8_t>(Opcode::StoreU16):
            // StoreU16 format: [opcode][reg_index][address_32bit]
            // PVM uses direct addressing (no ptr_reg), base register is implicit
            return jit_instruction::jit_emit_store_u16_direct(
                assembler, target_arch,
                decoded.address,
                decoded.dest_reg
            );

        case static_cast<uint8_t>(Opcode::StoreU32):
            // StoreU32 format: [opcode][reg_index][address_32bit]
            // PVM uses direct addressing (no ptr_reg), base register is implicit
            return jit_instruction::jit_emit_store_u32_direct(
                assembler, target_arch,
                decoded.address,
                decoded.dest_reg
            );

        case static_cast<uint8_t>(Opcode::StoreU64):
            // StoreU64 format: [opcode][reg_index][address_32bit]
            // PVM uses direct addressing (no ptr_reg), base register is implicit
            return jit_instruction::jit_emit_store_u64_direct(
                assembler, target_arch,
                decoded.address,
                decoded.dest_reg
            );

        // Store Immediate Indirect instructions (opcodes 70-73)
        // Format: [opcode][reg_index][address_32bit][value_Nbit]
        // Store immediate to memory at reg + address
        case static_cast<uint8_t>(Opcode::StoreImmIndU8):
            {
                auto* a = static_cast<x86::Assembler*>(assembler);
                // Load base address from register
                a->mov(x86::rax, x86::qword_ptr(rbx, decoded.dest_reg * 8));
                // Store 8-bit immediate to [rax + address]
                a->mov(x86::byte_ptr(x86::r12, x86::rax, 1, static_cast<int32_t>(decoded.address)),
                       static_cast<uint8_t>(decoded.immediate));
            }
            return true;

        case static_cast<uint8_t>(Opcode::StoreImmIndU16):
            {
                auto* a = static_cast<x86::Assembler*>(assembler);
                // Load base address from register
                a->mov(x86::rax, x86::qword_ptr(rbx, decoded.dest_reg * 8));
                // Store 16-bit immediate to [rax + address]
                a->mov(x86::word_ptr(x86::r12, x86::rax, 1, static_cast<int32_t>(decoded.address)),
                       static_cast<uint16_t>(decoded.immediate));
            }
            return true;

        case static_cast<uint8_t>(Opcode::StoreImmIndU32):
            {
                auto* a = static_cast<x86::Assembler*>(assembler);
                // Load base address from register
                a->mov(x86::rax, x86::qword_ptr(rbx, decoded.dest_reg * 8));
                // Store 32-bit immediate to [rax + address]
                a->mov(x86::dword_ptr(x86::r12, x86::rax, 1, static_cast<int32_t>(decoded.address)),
                       static_cast<uint32_t>(decoded.immediate));
            }
            return true;

        case static_cast<uint8_t>(Opcode::StoreImmIndU64):
            {
                auto* a = static_cast<x86::Assembler*>(assembler);
                // Load base address from register
                a->mov(x86::rax, x86::qword_ptr(rbx, decoded.dest_reg * 8));
                // Store 64-bit immediate to [rax + address]
                a->mov(x86::qword_ptr(x86::r12, x86::rax, 1, static_cast<int32_t>(decoded.address)),
                       decoded.immediate);
            }
            return true;

        // Store Indirect instructions (opcodes 120-123)
        // Format: [opcode][src_reg][dest_reg][offset_32bit]
        // Store src_reg to memory at dest_reg + offset
        case static_cast<uint8_t>(Opcode::StoreIndU8):
            // Use existing store_8 with ptr_reg = base register
            // NOTE: jit_emit_store_* functions expect int16_t offset
            // This is a known limitation - for now we truncate to 16-bit
            // TODO: Update emitter functions to accept 32-bit offsets
            return jit_instruction::jit_emit_store_8(
                assembler, target_arch,
                decoded.src1_reg,  // ptr_reg (base address register)
                decoded.dest_reg,  // src_reg (value to store)
                static_cast<int32_t>(decoded.address)  // offset truncated to 16-bit
            );

        case static_cast<uint8_t>(Opcode::StoreIndU16):
            return jit_instruction::jit_emit_store_16(
                assembler, target_arch,
                decoded.src1_reg,  // ptr_reg
                decoded.dest_reg,  // src_reg
                static_cast<int32_t>(decoded.address)  // offset truncated to 16-bit
            );

        case static_cast<uint8_t>(Opcode::StoreIndU32):
            return jit_instruction::jit_emit_store_32(
                assembler, target_arch,
                decoded.src1_reg,  // ptr_reg
                decoded.dest_reg,  // src_reg
                static_cast<int32_t>(decoded.address)  // offset truncated to 16-bit
            );

        case static_cast<uint8_t>(Opcode::StoreIndU64):
            return jit_instruction::jit_emit_store_64(
                assembler, target_arch,
                decoded.src1_reg,  // ptr_reg
                decoded.dest_reg,  // src_reg
                static_cast<int32_t>(decoded.address)  // offset truncated to 16-bit
            );

        // Load Indirect instructions (opcodes 124-130)
        // Format: [opcode][ra][rb][offset_32bit]
        // Load from memory at rb + offset into ra
        case static_cast<uint8_t>(Opcode::LoadIndU8):
            return jit_instruction::jit_emit_load_u8(
                assembler, target_arch,
                decoded.dest_reg,  // ra (destination)
                decoded.src1_reg,  // ptr_reg (base address = rb)
                static_cast<int32_t>(decoded.address)  // offset
            );

        case static_cast<uint8_t>(Opcode::LoadIndI8):
            return jit_instruction::jit_emit_load_i8(
                assembler, target_arch,
                decoded.dest_reg,  // ra
                decoded.src1_reg,  // ptr_reg (rb)
                static_cast<int32_t>(decoded.address)
            );

        case static_cast<uint8_t>(Opcode::LoadIndU16):
            return jit_instruction::jit_emit_load_u16(
                assembler, target_arch,
                decoded.dest_reg,  // ra
                decoded.src1_reg,  // ptr_reg (rb)
                static_cast<int32_t>(decoded.address)
            );

        case static_cast<uint8_t>(Opcode::LoadIndI16):
            return jit_instruction::jit_emit_load_i16(
                assembler, target_arch,
                decoded.dest_reg,  // ra
                decoded.src1_reg,  // ptr_reg (rb)
                static_cast<int32_t>(decoded.address)
            );

        case static_cast<uint8_t>(Opcode::LoadIndU32):
            return jit_instruction::jit_emit_load_u32(
                assembler, target_arch,
                decoded.dest_reg,  // ra
                decoded.src1_reg,  // ptr_reg (rb)
                static_cast<int32_t>(decoded.address)
            );

        case static_cast<uint8_t>(Opcode::LoadIndI32):
            return jit_instruction::jit_emit_load_i32(
                assembler, target_arch,
                decoded.dest_reg,  // ra
                decoded.src1_reg,  // ptr_reg (rb)
                static_cast<int32_t>(decoded.address)
            );

        case static_cast<uint8_t>(Opcode::LoadIndU64):
            return jit_instruction::jit_emit_load_u64(
                assembler, target_arch,
                decoded.dest_reg,  // ra
                decoded.src1_reg,  // ptr_reg (rb)
                static_cast<int32_t>(decoded.address)
            );

        case 100: // MoveReg
            return jit_instruction::jit_emit_copy(
                assembler, target_arch,
                decoded.dest_reg,
                decoded.src1_reg
            );

        case 101: // Sbrk
            // Sbrk format: sbrk dest, src
            // dest = register to store result (previous heap end)
            // src = register containing allocation size
            return jit_instruction::jit_emit_sbrk(
                assembler, target_arch,
                decoded.dest_reg,  // destination register (store result)
                decoded.src1_reg   // source register (allocation size)
            );

        case 102: // CountSetBits64
            return jit_instruction::jit_emit_pop_count(
                assembler, target_arch,
                decoded.dest_reg,
                decoded.src1_reg
            );

        case 103: // CountSetBits32
            return jit_instruction::jit_emit_pop_count(
                assembler, target_arch,
                decoded.dest_reg,
                decoded.src1_reg
            );

        case 104: // LeadingZeroBits64
            return jit_instruction::jit_emit_clz_64(
                assembler, target_arch,
                decoded.dest_reg,
                decoded.src1_reg
            );

        case 105: // LeadingZeroBits32
            return jit_instruction::jit_emit_clz(
                assembler, target_arch,
                decoded.dest_reg,
                decoded.src1_reg
            );

        case 106: // TrailingZeroBits64
            return jit_instruction::jit_emit_ctz_64(
                assembler, target_arch,
                decoded.dest_reg,
                decoded.src1_reg
            );

        case 107: // TrailingZeroBits32
            return jit_instruction::jit_emit_ctz(
                assembler, target_arch,
                decoded.dest_reg,
                decoded.src1_reg
            );

        case 108: // SignExtend8
            return jit_instruction::jit_emit_sext_8(
                assembler, target_arch,
                decoded.dest_reg,
                decoded.src1_reg
            );

        case 109: // SignExtend16
            return jit_instruction::jit_emit_sext_16(
                assembler, target_arch,
                decoded.dest_reg,
                decoded.src1_reg
            );

        case 110: // ZeroExtend16
            return jit_instruction::jit_emit_zext_16(
                assembler, target_arch,
                decoded.dest_reg,
                decoded.src1_reg
            );

        case 111: // ReverseBytes
            return jit_instruction::jit_emit_bswap(
                assembler, target_arch,
                decoded.dest_reg  // bswap only takes dest_reg
            );

        case static_cast<uint8_t>(Opcode::BranchEq):
            // NOTE: Branch target calculation handled in dispatcher
            // Labeled JIT implementation handles labels properly
            return jit_instruction::jit_emit_branch_eq(
                assembler, target_arch,
                decoded.src1_reg,
                decoded.src2_reg,
                decoded.target_pc  // Use target_pc instead of offset
            );

        case static_cast<uint8_t>(Opcode::BranchNe):
            // NOTE: Branch target calculation handled in dispatcher
            // Labeled JIT implementation handles labels properly
            return jit_instruction::jit_emit_branch_ne(
                assembler, target_arch,
                decoded.src1_reg,
                decoded.src2_reg,
                decoded.target_pc  // Use target_pc instead of offset
            );

        case static_cast<uint8_t>(Opcode::BranchLtU):
            return jit_instruction::jit_emit_branch_lt_u(
                assembler, target_arch,
                decoded.src1_reg,
                decoded.src2_reg,
                decoded.target_pc
            );

        case static_cast<uint8_t>(Opcode::BranchLtS):
            return jit_instruction::jit_emit_branch_lt(
                assembler, target_arch,
                decoded.src1_reg,
                decoded.src2_reg,
                decoded.target_pc
            );

        case static_cast<uint8_t>(Opcode::BranchGeU):
            return jit_instruction::jit_emit_branch_gt_u(
                assembler, target_arch,
                decoded.src2_reg,  // Swap operands for Ge (a >= b => !(b > a))
                decoded.src1_reg,
                decoded.target_pc
            );

        case static_cast<uint8_t>(Opcode::BranchGeS):
            return jit_instruction::jit_emit_branch_gt(
                assembler, target_arch,
                decoded.src2_reg,  // Swap operands for Ge (a >= b => !(b > a))
                decoded.src1_reg,
                decoded.target_pc
            );

        case static_cast<uint8_t>(Opcode::Add32):
            {
                // rd = ra + rb (3-operand format)
                auto* a = static_cast<x86::Assembler*>(assembler);
                a->mov(x86::eax, x86::dword_ptr(x86::rbx, decoded.src1_reg * 8));  // Load ra
                a->mov(x86::edx, x86::dword_ptr(x86::rbx, decoded.src2_reg * 8));  // Load rb
                a->add(x86::edx, x86::eax);  // edx = eax + edx = ra + rb
                a->mov(x86::dword_ptr(x86::rbx, decoded.dest_reg * 8), x86::edx);  // Store to rd
            }
            return true;

        case static_cast<uint8_t>(Opcode::Sub32):
            {
                // rd = ra - rb (3-operand format)
                auto* a = static_cast<x86::Assembler*>(assembler);
                a->mov(x86::eax, x86::dword_ptr(x86::rbx, decoded.src1_reg * 8));  // Load ra
                a->mov(x86::edx, x86::dword_ptr(x86::rbx, decoded.src2_reg * 8));  // Load rb
                a->sub(x86::eax, x86::edx);  // eax = eax - edx = ra - rb
                a->mov(x86::dword_ptr(x86::rbx, decoded.dest_reg * 8), x86::eax);  // Store to rd
            }
            return true;

        case static_cast<uint8_t>(Opcode::Mul32):
            {
                // rd = ra * rb (3-operand format)
                auto* a = static_cast<x86::Assembler*>(assembler);
                a->mov(x86::eax, x86::dword_ptr(x86::rbx, decoded.src1_reg * 8));  // Load ra
                a->mov(x86::edx, x86::dword_ptr(x86::rbx, decoded.src2_reg * 8));  // Load rb
                a->imul(x86::edx, x86::eax);  // edx = eax * edx = ra * rb
                a->mov(x86::dword_ptr(x86::rbx, decoded.dest_reg * 8), x86::edx);  // Store to rd
            }
            return true;

        case static_cast<uint8_t>(Opcode::DivU32):
            {
                // rd = ra / rb (3-operand format)
                // Per spec: when rb == 0, return UInt64.max (matches interpreter behavior)
                auto* a = static_cast<x86::Assembler*>(assembler);
                asmjit::Label notZero = a->new_label();
                asmjit::Label done = a->new_label();

                a->mov(x86::eax, x86::dword_ptr(x86::rbx, decoded.src1_reg * 8));  // Load ra
                a->mov(x86::ecx, x86::dword_ptr(x86::rbx, decoded.src2_reg * 8));  // Load rb
                a->test(x86::ecx, x86::ecx);  // Check if rb == 0
                a->jnz(notZero);  // If rb != 0, jump to division

                // Division by zero case: set rax to UInt64.max
                a->mov(x86::rax, 0xFFFFFFFFFFFFFFFFULL);
                a->jmp(done);

                // Normal division case
                a->bind(notZero);
                a->xor_(x86::edx, x86::edx);  // edx = 0
                a->div(x86::ecx);  // eax = eax / ecx, edx = eax % ecx
                a->movsxd(x86::rax, x86::eax);  // Sign extend eax to rax

                a->bind(done);
                a->mov(x86::qword_ptr(x86::rbx, decoded.dest_reg * 8), x86::rax);  // Store quotient to rd
            }
            return true;

        case static_cast<uint8_t>(Opcode::DivS32):
            {
                // rd = ra / rb (3-operand format, signed)
                // Per spec: when b == 0, return UInt64.max
                // Also handles a == Int32.min && b == -1 case (returns a, sign-extended)
                auto* a = static_cast<x86::Assembler*>(assembler);
                asmjit::Label notZero = a->new_label();
                asmjit::Label overflow = a->new_label();
                asmjit::Label done = a->new_label();

                a->mov(x86::eax, x86::dword_ptr(x86::rbx, decoded.src1_reg * 8));
                a->mov(x86::ecx, x86::dword_ptr(x86::rbx, decoded.src2_reg * 8));

                // Check for overflow case: a == Int32.min && b == -1
                a->cmp(x86::eax, 0x80000000);  // Check if a == Int32.min
                a->jne(overflow);
                a->cmp(x86::ecx, 0xFFFFFFFF);  // Check if b == -1
                a->jne(overflow);
                // Overflow case: return a (which is Int32.min, sign-extended)
                a->movsxd(x86::rax, x86::eax);
                a->mov(x86::qword_ptr(x86::rbx, decoded.dest_reg * 8), x86::rax);
                a->jmp(done);

                a->bind(overflow);
                a->test(x86::ecx, x86::ecx);
                a->jnz(notZero);

                // Division by zero case
                a->mov(x86::rax, 0xFFFFFFFFFFFFFFFFULL);
                a->jmp(done);

                a->bind(notZero);
                a->cdq();  // Sign extend eax to edx:eax
                a->idiv(x86::ecx);
                a->movsxd(x86::rax, x86::eax);

                a->bind(done);
                a->mov(x86::qword_ptr(x86::rbx, decoded.dest_reg * 8), x86::rax);
            }
            return true;

        case static_cast<uint8_t>(Opcode::RemU32):
            {
                // Per spec: when rb == 0, return ra (the dividend, sign-extended to 64-bit), matches interpreter behavior
                auto* a = static_cast<x86::Assembler*>(assembler);
                asmjit::Label notZero = a->new_label();
                asmjit::Label done = a->new_label();

                a->mov(x86::eax, x86::dword_ptr(x86::rbx, decoded.src1_reg * 8));  // Load ra
                a->mov(x86::ecx, x86::dword_ptr(x86::rbx, decoded.src2_reg * 8));  // Load rb
                a->test(x86::ecx, x86::ecx);  // Check if rb == 0
                a->jnz(notZero);  // If rb != 0, jump to modulo

                // Division by zero case: store the sign-extended dividend
                a->movsxd(x86::rax, x86::eax);  // Sign extend eax to rax
                a->mov(x86::qword_ptr(x86::rbx, decoded.dest_reg * 8), x86::rax);  // Store to rd
                a->jmp(done);

                // Normal modulo case
                a->bind(notZero);
                a->xor_(x86::edx, x86::edx);  // edx = 0
                a->div(x86::ecx);  // eax = eax / ecx, edx = eax % ecx
                a->movsxd(x86::rax, x86::edx);  // Sign extend edx to rax

                a->bind(done);
                a->mov(x86::qword_ptr(x86::rbx, decoded.dest_reg * 8), x86::rax);  // Store to rd
            }
            return true;

        case static_cast<uint8_t>(Opcode::RemS32):
            {
                // Per spec: when b == 0, return a (the dividend, sign-extended to 64-bit), matches interpreter behavior
                // Also handles a == Int32.min && b == -1 case (returns 0)
                auto* a = static_cast<x86::Assembler*>(assembler);
                asmjit::Label notZero = a->new_label();
                asmjit::Label overflow = a->new_label();
                asmjit::Label done = a->new_label();

                a->mov(x86::eax, x86::dword_ptr(x86::rbx, decoded.src1_reg * 8));  // Load ra
                a->mov(x86::ecx, x86::dword_ptr(x86::rbx, decoded.src2_reg * 8));  // Load rb

                // Check for overflow case: a == Int32.min && b == -1
                a->cmp(x86::eax, 0x80000000);  // Check if a == Int32.min
                a->jne(overflow);
                a->cmp(x86::ecx, 0xFFFFFFFF);  // Check if b == -1
                a->jne(overflow);
                // Overflow case: return 0
                a->xor_(x86::eax, x86::eax);  // eax = 0
                a->mov(x86::qword_ptr(x86::rbx, decoded.dest_reg * 8), x86::rax);
                a->jmp(done);

                a->bind(overflow);
                a->test(x86::ecx, x86::ecx);  // Check if rb == 0
                a->jnz(notZero);  // If rb != 0, jump to modulo

                // Division by zero case: store the sign-extended dividend
                a->movsxd(x86::rax, x86::eax);  // Sign extend eax to rax
                a->mov(x86::qword_ptr(x86::rbx, decoded.dest_reg * 8), x86::rax);  // Store to rd
                a->jmp(done);

                // Normal modulo case
                a->bind(notZero);
                a->cdq();  // Sign extend eax to edx:eax
                a->idiv(x86::ecx);  // eax = eax / ecx, edx = eax % ecx (signed)
                a->movsxd(x86::rax, x86::edx);  // Sign extend edx to rax

                a->bind(done);
                a->mov(x86::qword_ptr(x86::rbx, decoded.dest_reg * 8), x86::rax);  // Store to rd
            }
            return true;

        case static_cast<uint8_t>(Opcode::ShloL32):
            return jit_instruction::jit_emit_shlo_l_32(
                assembler, target_arch,
                decoded.dest_reg,
                decoded.src1_reg
            );

        case static_cast<uint8_t>(Opcode::ShloR32):
            return jit_instruction::jit_emit_shlo_r_32(
                assembler, target_arch,
                decoded.dest_reg,
                decoded.src1_reg
            );

        case static_cast<uint8_t>(Opcode::SharR32):
            return jit_instruction::jit_emit_shar_r_32(
                assembler, target_arch,
                decoded.dest_reg,
                decoded.src1_reg
            );

        case static_cast<uint8_t>(Opcode::Add64):
            {
                // rd = ra + rb (3-operand format, 64-bit)
                auto* a = static_cast<x86::Assembler*>(assembler);
                a->mov(x86::rax, x86::qword_ptr(x86::rbx, decoded.src1_reg * 8));  // Load ra
                a->mov(x86::rcx, x86::qword_ptr(x86::rbx, decoded.src2_reg * 8));  // Load rb
                a->add(x86::rax, x86::rcx);  // rax = rax + rcx = ra + rb
                a->mov(x86::qword_ptr(x86::rbx, decoded.dest_reg * 8), x86::rax);  // Store to rd
            }
            return true;

        case static_cast<uint8_t>(Opcode::Sub64):
            {
                // rd = ra - rb (3-operand format, 64-bit)
                auto* a = static_cast<x86::Assembler*>(assembler);
                a->mov(x86::rax, x86::qword_ptr(x86::rbx, decoded.src1_reg * 8));  // Load ra
                a->mov(x86::rcx, x86::qword_ptr(x86::rbx, decoded.src2_reg * 8));  // Load rb
                a->sub(x86::rax, x86::rcx);  // rax = rax - rcx = ra - rb
                a->mov(x86::qword_ptr(x86::rbx, decoded.dest_reg * 8), x86::rax);  // Store to rd
            }
            return true;

        case static_cast<uint8_t>(Opcode::Mul64):
            {
                // rd = ra * rb (3-operand format, 64-bit)
                auto* a = static_cast<x86::Assembler*>(assembler);
                a->mov(x86::rax, x86::qword_ptr(x86::rbx, decoded.src1_reg * 8));  // Load ra
                a->mov(x86::rcx, x86::qword_ptr(x86::rbx, decoded.src2_reg * 8));  // Load rb
                a->imul(x86::rcx, x86::rax);  // rcx = rax * rcx = ra * rb
                a->mov(x86::qword_ptr(x86::rbx, decoded.dest_reg * 8), x86::rcx);  // Store to rd
            }
            return true;

        case static_cast<uint8_t>(Opcode::DivU64):
            {
                // rd = ra / rb (3-operand format, 64-bit unsigned)
                auto* a = static_cast<x86::Assembler*>(assembler);
                a->mov(x86::rax, x86::qword_ptr(x86::rbx, decoded.src1_reg * 8));  // Load ra
                a->xor_(x86::rdx, x86::rdx);  // rdx = 0
                a->mov(x86::rcx, x86::qword_ptr(x86::rbx, decoded.src2_reg * 8));  // Load rb
                a->div(x86::rcx);  // rax = rax / rcx, rdx = rax % rcx
                a->mov(x86::qword_ptr(x86::rbx, decoded.dest_reg * 8), x86::rax);  // Store quotient to rd
            }
            return true;

        case static_cast<uint8_t>(Opcode::DivS64):
            {
                // rd = ra / rb (3-operand format, 64-bit signed)
                auto* a = static_cast<x86::Assembler*>(assembler);
                a->mov(x86::rax, x86::qword_ptr(x86::rbx, decoded.src1_reg * 8));  // Load ra
                a->cqo();  // Sign extend rax to rdx:rax
                a->mov(x86::rcx, x86::qword_ptr(x86::rbx, decoded.src2_reg * 8));  // Load rb
                a->idiv(x86::rcx);  // rax = rax / rcx (signed)
                a->mov(x86::qword_ptr(x86::rbx, decoded.dest_reg * 8), x86::rax);  // Store quotient to rd
            }
            return true;

        case static_cast<uint8_t>(Opcode::RemU64):
            {
                // rd = ra % rb (3-operand format, 64-bit unsigned)
                auto* a = static_cast<x86::Assembler*>(assembler);
                a->mov(x86::rax, x86::qword_ptr(x86::rbx, decoded.src1_reg * 8));  // Load ra
                a->xor_(x86::rdx, x86::rdx);  // rdx = 0
                a->mov(x86::rcx, x86::qword_ptr(x86::rbx, decoded.src2_reg * 8));  // Load rb
                a->div(x86::rcx);  // rax = rax / rcx, rdx = rax % rcx
                a->mov(x86::qword_ptr(x86::rbx, decoded.dest_reg * 8), x86::rdx);  // Store remainder to rd
            }
            return true;

        case static_cast<uint8_t>(Opcode::RemS64):
            {
                // rd = ra % rb (3-operand format, 64-bit signed)
                auto* a = static_cast<x86::Assembler*>(assembler);
                a->mov(x86::rax, x86::qword_ptr(x86::rbx, decoded.src1_reg * 8));  // Load ra
                a->cqo();  // Sign extend rax to rdx:rax
                a->mov(x86::rcx, x86::qword_ptr(x86::rbx, decoded.src2_reg * 8));  // Load rb
                a->idiv(x86::rcx);  // rax = rax / rcx, rdx = rax % rcx (signed)
                a->mov(x86::qword_ptr(x86::rbx, decoded.dest_reg * 8), x86::rdx);  // Store remainder to rd
            }
            return true;

        case static_cast<uint8_t>(Opcode::ShloL64):
            return jit_instruction::jit_emit_shlo_l_64(
                assembler, target_arch,
                decoded.dest_reg,
                decoded.src1_reg
            );

        case static_cast<uint8_t>(Opcode::ShloR64):
            return jit_instruction::jit_emit_shlo_r_64(
                assembler, target_arch,
                decoded.dest_reg,
                decoded.src1_reg
            );

        case static_cast<uint8_t>(Opcode::SharR64):
            return jit_instruction::jit_emit_shar_r_64(
                assembler, target_arch,
                decoded.dest_reg,
                decoded.src1_reg
            );

        case static_cast<uint8_t>(Opcode::And):
            {
                // rd = ra & rb (3-operand format)
                auto* a = static_cast<x86::Assembler*>(assembler);
                a->mov(x86::eax, x86::dword_ptr(x86::rbx, decoded.src1_reg * 8));  // Load ra
                a->mov(x86::edx, x86::dword_ptr(x86::rbx, decoded.src2_reg * 8));  // Load rb
                a->and_(x86::edx, x86::eax);  // edx = eax & edx = ra & rb
                a->mov(x86::dword_ptr(x86::rbx, decoded.dest_reg * 8), x86::edx);  // Store to rd
            }
            return true;

        case static_cast<uint8_t>(Opcode::Xor):
            {
                // rd = ra ^ rb (3-operand format)
                auto* a = static_cast<x86::Assembler*>(assembler);
                a->mov(x86::eax, x86::dword_ptr(x86::rbx, decoded.src1_reg * 8));  // Load ra
                a->mov(x86::edx, x86::dword_ptr(x86::rbx, decoded.src2_reg * 8));  // Load rb
                a->xor_(x86::edx, x86::eax);  // edx = eax ^ edx = ra ^ rb
                a->mov(x86::dword_ptr(x86::rbx, decoded.dest_reg * 8), x86::edx);  // Store to rd
            }
            return true;

        case static_cast<uint8_t>(Opcode::Or):
            {
                // rd = ra | rb (3-operand format)
                auto* a = static_cast<x86::Assembler*>(assembler);
                a->mov(x86::eax, x86::dword_ptr(x86::rbx, decoded.src1_reg * 8));  // Load ra
                a->mov(x86::edx, x86::dword_ptr(x86::rbx, decoded.src2_reg * 8));  // Load rb
                a->or_(x86::edx, x86::eax);  // edx = eax | edx = ra | rb
                a->mov(x86::dword_ptr(x86::rbx, decoded.dest_reg * 8), x86::edx);  // Store to rd
            }
            return true;

        case 213: // MulUpperSS
            return jit_instruction::jit_emit_mul_upper_s_s(
                assembler, target_arch,
                decoded.dest_reg,  // ra
                decoded.src1_reg,  // rb
                decoded.src2_reg   // rd
            );

        case 214: // MulUpperUU
            return jit_instruction::jit_emit_mul_upper_uu(
                assembler, target_arch,
                decoded.dest_reg,  // ra
                decoded.src1_reg,  // rb
                decoded.src2_reg   // rd
            );

        case 215: // MulUpperSU
            return jit_instruction::jit_emit_mul_upper_su(
                assembler, target_arch,
                decoded.dest_reg,  // ra
                decoded.src1_reg,  // rb
                decoded.src2_reg   // rd
            );

        case 216: // SetLtU
            return jit_instruction::jit_emit_set_lt_u(
                assembler, target_arch,
                decoded.dest_reg,  // ra
                decoded.src1_reg,  // rb
                decoded.src2_reg   // rd
            );

        case 217: // SetLtS
            return jit_instruction::jit_emit_set_lt_s(
                assembler, target_arch,
                decoded.dest_reg,  // ra
                decoded.src1_reg,  // rb
                decoded.src2_reg   // rd
            );

        case 218: // CmovIz
            return jit_instruction::jit_emit_cmov_iz(
                assembler, target_arch,
                decoded.dest_reg,  // ra
                decoded.src1_reg,  // rb
                decoded.src2_reg   // rd
            );

        case 219: // CmovNz
            return jit_instruction::jit_emit_cmov_nz(
                assembler, target_arch,
                decoded.dest_reg,  // ra
                decoded.src1_reg,  // rb
                decoded.src2_reg   // rd
            );

        case 220: // RotL64
            return jit_instruction::jit_emit_rol_64(
                assembler, target_arch,
                decoded.dest_reg,  // ra
                decoded.src1_reg,  // rb
                decoded.src2_reg   // rd
            );

        case 221: // RotL32
            return jit_instruction::jit_emit_rot_l_32(
                assembler, target_arch,
                decoded.dest_reg,  // ra
                decoded.src1_reg,  // rb
                decoded.src2_reg   // rd
            );

        case 222: // RotR64
            return jit_instruction::jit_emit_ror_64(
                assembler, target_arch,
                decoded.dest_reg,  // ra
                decoded.src1_reg,  // rb
                decoded.src2_reg   // rd
            );

        case 223: // RotR32
            return jit_instruction::jit_emit_rot_r_32(
                assembler, target_arch,
                decoded.dest_reg,  // ra
                decoded.src1_reg,  // rb
                decoded.src2_reg   // rd
            );

        case 224: // AndInv
            return jit_instruction::jit_emit_and_inv(
                assembler, target_arch,
                decoded.dest_reg,
                decoded.src1_reg
            );

        case 225: // OrInv
            return jit_instruction::jit_emit_or_inv(
                assembler, target_arch,
                decoded.dest_reg,
                decoded.src1_reg
            );

        case 226: // Xnor
            return jit_instruction::jit_emit_xnor(
                assembler, target_arch,
                decoded.dest_reg,
                decoded.src1_reg
            );

        case 227: // Max
            return jit_instruction::jit_emit_max(
                assembler, target_arch,
                decoded.dest_reg,
                decoded.src1_reg
            );

        case 228: // MaxU
            return jit_instruction::jit_emit_max_u(
                assembler, target_arch,
                decoded.dest_reg,
                decoded.src1_reg
            );

        case 229: // Min
            return jit_instruction::jit_emit_min(
                assembler, target_arch,
                decoded.dest_reg,
                decoded.src1_reg
            );

        case 230: // MinU
            return jit_instruction::jit_emit_min_u(
                assembler, target_arch,
                decoded.dest_reg,
                decoded.src1_reg
            );

        default:
            // Unknown opcode - emit nop for now
            // TODO: Should return false or log error
            a->nop();
            return true;
    }
}

// Emit a basic block of instructions
bool emit_basic_block_instructions(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    const uint8_t* _Nonnull bytecode,
    uint32_t block_start_pc,
    uint32_t block_end_pc)
{
    uint32_t current_pc = block_start_pc;

    while (current_pc < block_end_pc) {
        DecodedInstruction decoded;

        // Decode instruction based on opcode
        uint8_t opcode = bytecode[current_pc];

        // Dispatch to appropriate decoder based on opcode
        bool decoded_ok = false;

        // Use switch for efficient opcode dispatch
        switch (opcode) {
            case static_cast<uint8_t>(Opcode::Trap):
                decoded_ok = decode_trap(bytecode, current_pc, decoded);
                break;

            case static_cast<uint8_t>(Opcode::Halt):
                decoded_ok = decode_fallthrough(bytecode, current_pc, decoded);
                break;

            case static_cast<uint8_t>(Opcode::LoadImmU64):
                decoded_ok = decode_load_imm_64(bytecode, current_pc, decoded);
                break;

            case static_cast<uint8_t>(Opcode::StoreImmU8):
                decoded_ok = decode_store_imm_u8(bytecode, current_pc, decoded);
                break;

            case static_cast<uint8_t>(Opcode::StoreImmU16):
                decoded_ok = decode_store_imm_u16(bytecode, current_pc, decoded);
                break;

            case static_cast<uint8_t>(Opcode::StoreImmU32):
                decoded_ok = decode_store_imm_u32(bytecode, current_pc, decoded);
                break;

            case static_cast<uint8_t>(Opcode::StoreImmU64):
                decoded_ok = decode_store_imm_u64(bytecode, current_pc, decoded);
                break;

            case static_cast<uint8_t>(Opcode::Jump):
                decoded_ok = decode_jump(bytecode, current_pc, decoded);
                break;

            case static_cast<uint8_t>(Opcode::JumpInd):
                decoded_ok = decode_jump_ind(bytecode, current_pc, decoded);
                break;

            case 2: // JumpInd (old opcode number for backwards compatibility)
                decoded_ok = decode_jump_ind(bytecode, current_pc, decoded);
                break;

            case static_cast<uint8_t>(Opcode::LoadImmJumpInd):
                decoded_ok = decode_load_imm_jump_ind(bytecode, current_pc, decoded);
                break;

            case static_cast<uint8_t>(Opcode::LoadImm):
                decoded_ok = decode_load_imm(bytecode, current_pc, decoded);
                break;

            case static_cast<uint8_t>(Opcode::LoadImmJump):
                decoded_ok = decode_load_imm_jump(bytecode, current_pc, decoded);
                break;

            case 100: // MoveReg - 2 register format (dest, src)
                decoded_ok = decode_2_reg(bytecode, current_pc, decoded);
                break;

            // Branch Immediate instructions (opcodes 81-90)
            // Format: [opcode][reg_index][value_64bit][offset_32bit]
            case static_cast<uint8_t>(Opcode::BranchEqImm):
                decoded_ok = decode_branch_eq_imm(bytecode, current_pc, decoded);
                break;

            case static_cast<uint8_t>(Opcode::BranchNeImm):
                decoded_ok = decode_branch_ne_imm(bytecode, current_pc, decoded);
                break;

            case static_cast<uint8_t>(Opcode::BranchLtUImm):
                decoded_ok = decode_branch_lt_u_imm(bytecode, current_pc, decoded);
                break;

            case static_cast<uint8_t>(Opcode::BranchLeUImm):
                decoded_ok = decode_branch_le_u_imm(bytecode, current_pc, decoded);
                break;

            case static_cast<uint8_t>(Opcode::BranchGeUImm):
                decoded_ok = decode_branch_ge_u_imm(bytecode, current_pc, decoded);
                break;

            case static_cast<uint8_t>(Opcode::BranchGtUImm):
                decoded_ok = decode_branch_gt_u_imm(bytecode, current_pc, decoded);
                break;

            case static_cast<uint8_t>(Opcode::BranchLtSImm):
                decoded_ok = decode_branch_lt_s_imm(bytecode, current_pc, decoded);
                break;

            case static_cast<uint8_t>(Opcode::BranchLeSImm):
                decoded_ok = decode_branch_le_s_imm(bytecode, current_pc, decoded);
                break;

            case static_cast<uint8_t>(Opcode::BranchGeSImm):
                decoded_ok = decode_branch_ge_s_imm(bytecode, current_pc, decoded);
                break;

            case static_cast<uint8_t>(Opcode::BranchGtSImm):
                decoded_ok = decode_branch_gt_s_imm(bytecode, current_pc, decoded);
                break;

            // 32-bit Immediate instructions (opcodes 131-148)
            // Format: [opcode][ra][rb][value_32bit]
            case static_cast<uint8_t>(Opcode::AddImm32):
                decoded_ok = decode_add_imm_32(bytecode, current_pc, decoded);
                break;

            case static_cast<uint8_t>(Opcode::AndImm):
                decoded_ok = decode_and_imm_32(bytecode, current_pc, decoded);
                break;

            case static_cast<uint8_t>(Opcode::XorImm):
                decoded_ok = decode_xor_imm_32(bytecode, current_pc, decoded);
                break;

            case static_cast<uint8_t>(Opcode::OrImm):
                decoded_ok = decode_or_imm_32(bytecode, current_pc, decoded);
                break;

            case static_cast<uint8_t>(Opcode::MulImm32):
                decoded_ok = decode_mul_imm_32(bytecode, current_pc, decoded);
                break;

            case static_cast<uint8_t>(Opcode::SetLtUImm):
                decoded_ok = decode_set_lt_u_imm(bytecode, current_pc, decoded);
                break;

            case static_cast<uint8_t>(Opcode::SetLtSImm):
                decoded_ok = decode_set_lt_s_imm(bytecode, current_pc, decoded);
                break;

            case static_cast<uint8_t>(Opcode::ShloLImm32):
                decoded_ok = decode_shlo_l_imm_32(bytecode, current_pc, decoded);
                break;

            case static_cast<uint8_t>(Opcode::ShloRImm32):
                decoded_ok = decode_shlo_r_imm_32(bytecode, current_pc, decoded);
                break;

            case static_cast<uint8_t>(Opcode::SharRImm32):
                decoded_ok = decode_shar_r_imm_32(bytecode, current_pc, decoded);
                break;

            case static_cast<uint8_t>(Opcode::NegAddImm32):
                decoded_ok = decode_neg_add_imm_32(bytecode, current_pc, decoded);
                break;

            case static_cast<uint8_t>(Opcode::SetGtUImm):
                decoded_ok = decode_set_gt_u_imm(bytecode, current_pc, decoded);
                break;

            case static_cast<uint8_t>(Opcode::SetGtSImm):
                decoded_ok = decode_set_gt_s_imm(bytecode, current_pc, decoded);
                break;

            case static_cast<uint8_t>(Opcode::ShloLImmAlt32):
                decoded_ok = decode_shlo_l_imm_alt_32(bytecode, current_pc, decoded);
                break;

            case static_cast<uint8_t>(Opcode::ShloRImmAlt32):
                decoded_ok = decode_shlo_r_imm_alt_32(bytecode, current_pc, decoded);
                break;

            case static_cast<uint8_t>(Opcode::SharRImmAlt32):
                decoded_ok = decode_shar_r_imm_alt_32(bytecode, current_pc, decoded);
                break;

            case static_cast<uint8_t>(Opcode::CmovIzImm):
                decoded_ok = decode_cmov_iz_imm(bytecode, current_pc, decoded);
                break;

            case static_cast<uint8_t>(Opcode::CmovNzImm):
                decoded_ok = decode_cmov_nz_imm(bytecode, current_pc, decoded);
                break;

            // 64-bit Immediate instructions (opcodes 149-161)
            // Format: [opcode][ra][rb][value_64bit]
            case static_cast<uint8_t>(Opcode::AddImm64):
                decoded_ok = decode_add_imm_64(bytecode, current_pc, decoded);
                break;

            case static_cast<uint8_t>(Opcode::MulImm64):
                decoded_ok = decode_mul_imm_64(bytecode, current_pc, decoded);
                break;

            case static_cast<uint8_t>(Opcode::ShloLImm64):
                decoded_ok = decode_shlo_l_imm_64(bytecode, current_pc, decoded);
                break;

            case static_cast<uint8_t>(Opcode::ShloRImm64):
                decoded_ok = decode_shlo_r_imm_64(bytecode, current_pc, decoded);
                break;

            case static_cast<uint8_t>(Opcode::SharRImm64):
                decoded_ok = decode_shar_r_imm_64(bytecode, current_pc, decoded);
                break;

            case static_cast<uint8_t>(Opcode::NegAddImm64):
                decoded_ok = decode_neg_add_imm_64(bytecode, current_pc, decoded);
                break;

            case static_cast<uint8_t>(Opcode::ShloLImmAlt64):
                decoded_ok = decode_shlo_l_imm_alt_64(bytecode, current_pc, decoded);
                break;

            case static_cast<uint8_t>(Opcode::ShloRImmAlt64):
                decoded_ok = decode_shlo_r_imm_alt_64(bytecode, current_pc, decoded);
                break;

            case static_cast<uint8_t>(Opcode::SharRImmAlt64):
                decoded_ok = decode_shar_r_imm_alt_64(bytecode, current_pc, decoded);
                break;

            case static_cast<uint8_t>(Opcode::RotR64Imm):
                decoded_ok = decode_rot_r_64_imm(bytecode, current_pc, decoded);
                break;

            case static_cast<uint8_t>(Opcode::RotR64ImmAlt):
                decoded_ok = decode_rot_r_64_imm_alt(bytecode, current_pc, decoded);
                break;

            case static_cast<uint8_t>(Opcode::RotR32Imm):
                decoded_ok = decode_rot_r_32_imm(bytecode, current_pc, decoded);
                break;

            case static_cast<uint8_t>(Opcode::RotR32ImmAlt):
                decoded_ok = decode_rot_r_32_imm_alt(bytecode, current_pc, decoded);
                break;

            case static_cast<uint8_t>(Opcode::LoadU8):
                decoded_ok = decode_load_u8(bytecode, current_pc, decoded);
                break;

            case static_cast<uint8_t>(Opcode::LoadI8):
                decoded_ok = decode_load_i8(bytecode, current_pc, decoded);
                break;

            case static_cast<uint8_t>(Opcode::LoadU16):
                decoded_ok = decode_load_u16(bytecode, current_pc, decoded);
                break;

            case static_cast<uint8_t>(Opcode::LoadI16):
                decoded_ok = decode_load_i16(bytecode, current_pc, decoded);
                break;

            case static_cast<uint8_t>(Opcode::LoadU32):
                decoded_ok = decode_load_u32(bytecode, current_pc, decoded);
                break;

            case static_cast<uint8_t>(Opcode::LoadI32):
                decoded_ok = decode_load_i32(bytecode, current_pc, decoded);
                break;

            case static_cast<uint8_t>(Opcode::LoadU64):
                decoded_ok = decode_load_u64(bytecode, current_pc, decoded);
                break;

            case static_cast<uint8_t>(Opcode::StoreU8):
                decoded_ok = decode_store_u8(bytecode, current_pc, decoded);
                break;

            case static_cast<uint8_t>(Opcode::StoreU16):
                decoded_ok = decode_store_u16(bytecode, current_pc, decoded);
                break;

            case static_cast<uint8_t>(Opcode::StoreU32):
                decoded_ok = decode_store_u32(bytecode, current_pc, decoded);
                break;

            case static_cast<uint8_t>(Opcode::StoreU64):
                decoded_ok = decode_store_u64(bytecode, current_pc, decoded);
                break;

            // Store Immediate Indirect instructions (opcodes 70-73)
            case static_cast<uint8_t>(Opcode::StoreImmIndU8):
                decoded_ok = decode_store_imm_ind_u8(bytecode, current_pc, decoded);
                break;

            case static_cast<uint8_t>(Opcode::StoreImmIndU16):
                decoded_ok = decode_store_imm_ind_u16(bytecode, current_pc, decoded);
                break;

            case static_cast<uint8_t>(Opcode::StoreImmIndU32):
                decoded_ok = decode_store_imm_ind_u32(bytecode, current_pc, decoded);
                break;

            case static_cast<uint8_t>(Opcode::StoreImmIndU64):
                decoded_ok = decode_store_imm_ind_u64(bytecode, current_pc, decoded);
                break;

            // Store Indirect instructions (opcodes 120-123)
            case static_cast<uint8_t>(Opcode::StoreIndU8):
                decoded_ok = decode_store_ind_u8(bytecode, current_pc, decoded);
                break;

            case static_cast<uint8_t>(Opcode::StoreIndU16):
                decoded_ok = decode_store_ind_u16(bytecode, current_pc, decoded);
                break;

            case static_cast<uint8_t>(Opcode::StoreIndU32):
                decoded_ok = decode_store_ind_u32(bytecode, current_pc, decoded);
                break;

            case static_cast<uint8_t>(Opcode::StoreIndU64):
                decoded_ok = decode_store_ind_u64(bytecode, current_pc, decoded);
                break;

            // Load Indirect instructions (opcodes 124-130)
            case static_cast<uint8_t>(Opcode::LoadIndU8):
                decoded_ok = decode_load_ind_u8(bytecode, current_pc, decoded);
                break;

            case static_cast<uint8_t>(Opcode::LoadIndI8):
                decoded_ok = decode_load_ind_i8(bytecode, current_pc, decoded);
                break;

            case static_cast<uint8_t>(Opcode::LoadIndU16):
                decoded_ok = decode_load_ind_u16(bytecode, current_pc, decoded);
                break;

            case static_cast<uint8_t>(Opcode::LoadIndI16):
                decoded_ok = decode_load_ind_i16(bytecode, current_pc, decoded);
                break;

            case static_cast<uint8_t>(Opcode::LoadIndU32):
                decoded_ok = decode_load_ind_u32(bytecode, current_pc, decoded);
                break;

            case static_cast<uint8_t>(Opcode::LoadIndI32):
                decoded_ok = decode_load_ind_i32(bytecode, current_pc, decoded);
                break;

            case static_cast<uint8_t>(Opcode::LoadIndU64):
                decoded_ok = decode_load_ind_u64(bytecode, current_pc, decoded);
                break;

            case static_cast<uint8_t>(Opcode::BranchEq):
                decoded_ok = decode_branch_eq(bytecode, current_pc, decoded);
                break;

            case static_cast<uint8_t>(Opcode::BranchNe):
                decoded_ok = decode_branch_ne(bytecode, current_pc, decoded);
                break;

            case static_cast<uint8_t>(Opcode::BranchLtU):
            case static_cast<uint8_t>(Opcode::BranchLtS):
            case static_cast<uint8_t>(Opcode::BranchGeU):
            case static_cast<uint8_t>(Opcode::BranchGeS):
                // Same format as BranchEq/BranchNe: [opcode][reg1][reg2][offset_32bit]
                decoded_ok = decode_branch_eq(bytecode, current_pc, decoded);
                break;

            case static_cast<uint8_t>(Opcode::Add32):
                decoded_ok = decode_add_32(bytecode, current_pc, decoded);
                break;

            case static_cast<uint8_t>(Opcode::Sub32):
                decoded_ok = decode_sub_32(bytecode, current_pc, decoded);
                break;

            case static_cast<uint8_t>(Opcode::Mul32):
                decoded_ok = decode_mul_32(bytecode, current_pc, decoded);
                break;

            case static_cast<uint8_t>(Opcode::DivU32):
                decoded_ok = decode_div_u32(bytecode, current_pc, decoded);
                break;

            case static_cast<uint8_t>(Opcode::DivS32):
                decoded_ok = decode_div_s32(bytecode, current_pc, decoded);
                break;

            case static_cast<uint8_t>(Opcode::RemU32):
                decoded_ok = decode_rem_u32(bytecode, current_pc, decoded);
                break;

            case static_cast<uint8_t>(Opcode::RemS32):
                decoded_ok = decode_rem_s32(bytecode, current_pc, decoded);
                break;

            case static_cast<uint8_t>(Opcode::ShloL32):
            case static_cast<uint8_t>(Opcode::ShloR32):
            case static_cast<uint8_t>(Opcode::SharR32):
                // Same 2-register format as arithmetic: [opcode][dest_reg][src_reg]
                decoded_ok = decode_add_32(bytecode, current_pc, decoded);
                break;

            case static_cast<uint8_t>(Opcode::Add64):
                decoded_ok = decode_add_64(bytecode, current_pc, decoded);
                break;

            case static_cast<uint8_t>(Opcode::Sub64):
                decoded_ok = decode_sub_64(bytecode, current_pc, decoded);
                break;

            case static_cast<uint8_t>(Opcode::Mul64):
                decoded_ok = decode_mul_64(bytecode, current_pc, decoded);
                break;

            case static_cast<uint8_t>(Opcode::And):
                decoded_ok = decode_and(bytecode, current_pc, decoded);
                break;

            case static_cast<uint8_t>(Opcode::Xor):
                decoded_ok = decode_xor(bytecode, current_pc, decoded);
                break;

            case static_cast<uint8_t>(Opcode::Or):
                decoded_ok = decode_or(bytecode, current_pc, decoded);
                break;

            case static_cast<uint8_t>(Opcode::ShloL64):
            case static_cast<uint8_t>(Opcode::ShloR64):
            case static_cast<uint8_t>(Opcode::SharR64):
                // Same 2-register format as arithmetic: [opcode][dest_reg][src_reg]
                decoded_ok = decode_add_64(bytecode, current_pc, decoded);
                break;

            case 213: // MulUpperSS
            case 214: // MulUpperUU
            case 215: // MulUpperSU
            case 216: // SetLtU
            case 217: // SetLtS
            case 218: // CmovIz
            case 219: // CmovNz
            case 220: // RotL64
            case 221: // RotL32
            case 222: // RotR64
            case 223: // RotR32
            case 224: // AndInv
            case 225: // OrInv
            case 226: // Xnor
            case 227: // Max
            case 228: // MaxU
            case 229: // Min
            case 230: // MinU
                decoded_ok = decode_3_reg(bytecode, current_pc, decoded);
                break;

            default:
                // Unknown opcode - fail compilation to prevent unsafe execution
                // Skipping bytes could land us in the middle of multi-byte instructions
                return false;
        }

        if (!decoded_ok) {
            // Failed to decode - fail compilation to prevent unsafe execution
            // Decode failure indicates we're misinterpreting the instruction stream
            return false;
        }

        // Emit the decoded instruction
        if (!emit_instruction_decoded(assembler, target_arch, decoded)) {
            return false;
        }

        // Move to next instruction
        current_pc += decoded.size;
    }

    return true;
}

} // namespace jit_emitter

// Extern "C" wrapper to allow calling from helper.cpp
// This function provides the main entry point for compiling a range of bytecode
extern "C" bool jit_emitter_emit_basic_block_instructions(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    const uint8_t* _Nonnull bytecode,
    uint32_t start_pc,
    uint32_t end_pc)
{
    return jit_emitter::emit_basic_block_instructions(assembler, target_arch, bytecode, start_pc, end_pc);
}
