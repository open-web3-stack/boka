// JIT Instruction Emitters - Header file
// Declares all JIT instruction emission functions to match implementations in instructions.cpp

#pragma once

#include <cstdint>

namespace jit_instruction {

// Basic instructions
bool jit_emit_trap(void* _Nonnull assembler, const char* _Nonnull target_arch);
bool jit_emit_nop(void* _Nonnull assembler, const char* _Nonnull target_arch);
bool jit_emit_ecalli(void* _Nonnull assembler, const char* _Nonnull target_arch, uint32_t call_index);
bool jit_emit_fallthrough(void* _Nonnull assembler, const char* _Nonnull target_arch);
bool jit_emit_break(void* _Nonnull assembler, const char* _Nonnull target_arch);
bool jit_emit_unimp(void* _Nonnull assembler, const char* _Nonnull target_arch);

// Load immediate instructions
bool jit_emit_load_imm_u8(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t immediate);
bool jit_emit_load_imm_u16(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint16_t immediate);
bool jit_emit_load_imm_u32(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint32_t immediate);
bool jit_emit_load_imm_u64(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint64_t immediate);
bool jit_emit_load_imm_s32(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, int32_t immediate);
bool jit_emit_load_imm_32(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint32_t immediate);
bool jit_emit_load_imm_32_hi(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint32_t immediate);
bool jit_emit_load_imm_64(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint64_t immediate);
bool jit_emit_load_imm_jump(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint32_t value, uint32_t target_pc);
bool jit_emit_load_imm_jump_ind(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg, uint32_t value, uint32_t offset);

// Load from memory instructions
bool jit_emit_load_u8(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t ptr_reg, int32_t offset);
bool jit_emit_load_i8(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t ptr_reg, int32_t offset);
bool jit_emit_load_u16(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t ptr_reg, int32_t offset);
bool jit_emit_load_i16(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t ptr_reg, int32_t offset);
bool jit_emit_load_u32(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t ptr_reg, int32_t offset);
bool jit_emit_load_i32(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t ptr_reg, int32_t offset);
bool jit_emit_load_u64(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t ptr_reg, int32_t offset);
bool jit_emit_load_reserved(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t ptr_reg);

// Load from memory instructions (direct addressing)
bool jit_emit_load_u8_direct(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint32_t address);
bool jit_emit_load_i8_direct(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint32_t address);
bool jit_emit_load_u16_direct(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint32_t address);
bool jit_emit_load_i16_direct(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint32_t address);
bool jit_emit_load_u32_direct(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint32_t address);
bool jit_emit_load_i32_direct(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint32_t address);
bool jit_emit_load_u64_direct(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint32_t address);

// Store instructions (register to memory)
bool jit_emit_store_8(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t ptr_reg, uint8_t src_reg, int32_t offset);
bool jit_emit_store_16(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t ptr_reg, uint8_t src_reg, int32_t offset);
bool jit_emit_store_32(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t ptr_reg, uint8_t src_reg, int32_t offset);
bool jit_emit_store_64(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t ptr_reg, uint8_t src_reg, int32_t offset);
bool jit_emit_store_u8(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t ptr_reg, int16_t offset, uint8_t src_reg);
bool jit_emit_store_u16(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t ptr_reg, int16_t offset, uint8_t src_reg);
bool jit_emit_store_u32(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t ptr_reg, int16_t offset, uint8_t src_reg);
bool jit_emit_store_u64(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t ptr_reg, int16_t offset, uint8_t src_reg);
bool jit_emit_store_conditional(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t ptr_reg, uint8_t src_reg);

// Store instructions (register to memory, direct addressing)
bool jit_emit_store_u8_direct(void* _Nonnull assembler, const char* _Nonnull target_arch, uint32_t address, uint8_t src_reg);
bool jit_emit_store_u16_direct(void* _Nonnull assembler, const char* _Nonnull target_arch, uint32_t address, uint8_t src_reg);
bool jit_emit_store_u32_direct(void* _Nonnull assembler, const char* _Nonnull target_arch, uint32_t address, uint8_t src_reg);
bool jit_emit_store_u64_direct(void* _Nonnull assembler, const char* _Nonnull target_arch, uint32_t address, uint8_t src_reg);

// Store immediate instructions - Use *_direct variants instead
// NOTE: StoreImm* instructions handled via *_direct functions which support full 32-bit addresses
// Legacy dispatcher doesn't implement these - use labeled JIT instead

// 32-bit arithmetic instructions
bool jit_emit_add_32(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg);
bool jit_emit_sub_32(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg);
bool jit_emit_mul_32(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg);
bool jit_emit_div_u32(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg);
bool jit_emit_div_s32(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg);
bool jit_emit_rem_u32(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg);
bool jit_emit_rem_s32(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg);

// 64-bit arithmetic instructions
bool jit_emit_add_64(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg);
bool jit_emit_sub_64(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg);
bool jit_emit_mul_64(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg);
bool jit_emit_mul_u_64(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg);
bool jit_emit_div_u_64(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg);
bool jit_emit_div_s_64(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg);
bool jit_emit_rem_u_64(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg);
bool jit_emit_rem_s_64(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg);

// Bitwise operations (32-bit and 64-bit)
bool jit_emit_and(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg);
bool jit_emit_or(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg);
bool jit_emit_xor(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg);
bool jit_emit_and_64(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg);
bool jit_emit_or_64(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg);
bool jit_emit_xor_64(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg);

// Inverse bitwise operations
bool jit_emit_and_inv(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg);
bool jit_emit_or_inv(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg);
bool jit_emit_xnor(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg);

// Immediate arithmetic operations
bool jit_emit_add_imm_32(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg, int32_t immediate);
bool jit_emit_add_imm_64(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg, uint64_t immediate);
bool jit_emit_add_carry(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg);
bool jit_emit_add_64_carry(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg);

bool jit_emit_neg_add_imm_32(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg, int32_t immediate);
bool jit_emit_neg_add_imm_64(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg, uint64_t immediate);
bool jit_emit_sub_borrow(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg);
bool jit_emit_sub_64_borrow(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg);
bool jit_emit_mul_imm_32(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg, int32_t immediate);
bool jit_emit_mul_imm_64(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg, int64_t immediate);

bool jit_emit_div_u32_imm(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg, uint32_t immediate);
bool jit_emit_div_s32_imm(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg, int32_t immediate);
bool jit_emit_rem_u32_imm(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg, uint32_t immediate);
bool jit_emit_rem_s32_imm(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg, int32_t immediate);
bool jit_emit_and_imm(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg, uint64_t immediate);
bool jit_emit_and_imm_32(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg, uint32_t immediate);
bool jit_emit_or_imm(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg, uint64_t immediate);
bool jit_emit_or_imm_32(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg, uint32_t immediate);
bool jit_emit_xor_imm(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg, uint64_t immediate);
bool jit_emit_xor_imm_32(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg, uint32_t immediate);

// Shift operations
bool jit_emit_shlo_l_32(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg);
bool jit_emit_shlo_r_32(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg);
bool jit_emit_shar_r_32(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg);
bool jit_emit_shlo_l_64(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg);
bool jit_emit_shlo_r_64(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg);
bool jit_emit_shar_r_64(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg);
bool jit_emit_shlo_l_64_3reg(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t ra, uint8_t rb, uint8_t rd);
bool jit_emit_shlo_r_64_3reg(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t ra, uint8_t rb, uint8_t rd);
bool jit_emit_shar_r_64_3reg(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t ra, uint8_t rb, uint8_t rd);
bool jit_emit_shl_imm_32(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg, uint8_t immediate);
bool jit_emit_shl_imm_64(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg, uint8_t immediate);
bool jit_emit_shr_imm_32(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg, uint8_t immediate);
bool jit_emit_shr_imm_64(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg, uint8_t immediate);
bool jit_emit_sar_imm_32(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg, uint8_t immediate);
bool jit_emit_sar_imm_64(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg, uint8_t immediate);

// Rotate operations
bool jit_emit_rol_64(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg);
bool jit_emit_ror_64(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg);
bool jit_emit_rot_l_32(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t ra, uint8_t rb, uint8_t rd);
bool jit_emit_rot_l_imm_32(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg, uint8_t immediate);
bool jit_emit_rot_l_imm_64(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg, uint8_t immediate);
bool jit_emit_rot_r_32(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t ra, uint8_t rb, uint8_t rd);
bool jit_emit_rot_r_imm_32(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg, uint8_t immediate);
bool jit_emit_rot_r_imm_64(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg, uint8_t immediate);

// Comparison operations
bool jit_emit_eq(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg);
bool jit_emit_ne(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg);
bool jit_emit_lt_32(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg);
bool jit_emit_lt_u_32(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg);
bool jit_emit_gt_32(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg);
bool jit_emit_gt_u_32(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg);
bool jit_emit_eq_imm(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg, uint64_t immediate);
bool jit_emit_ne_imm(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg, uint64_t immediate);
bool jit_emit_lt_imm(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg, int64_t immediate);
bool jit_emit_lt_imm_u(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg, uint64_t immediate);
bool jit_emit_gt_imm(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg, int64_t immediate);
bool jit_emit_gt_imm_u(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg, uint64_t immediate);

// Conditional operations
bool jit_emit_select(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t test_reg, uint8_t src_reg);
bool jit_emit_merge(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t test_reg, uint8_t src_reg);
bool jit_emit_c_zero(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t test_reg, uint8_t src_reg);
bool jit_emit_c_not(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t test_reg, uint8_t src_reg);

// Min/Max operations
bool jit_emit_max(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg);
bool jit_emit_max_u(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg);
bool jit_emit_min(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg);
bool jit_emit_min_u(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg);

// Bit manipulation
bool jit_emit_clz(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg);
bool jit_emit_clz_64(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg);
bool jit_emit_ctz(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg);
bool jit_emit_ctz_64(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg);
bool jit_emit_pop_count(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg);
bool jit_emit_leading_zeros(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg);
bool jit_emit_trailing_zeros(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg);
bool jit_emit_bswap(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg);
bool jit_emit_bswap_32(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg);

// Extension operations
bool jit_emit_sext_8(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg);
bool jit_emit_sext_16(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg);
bool jit_emit_zext_8(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg);
bool jit_emit_zext_16(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg);
bool jit_emit_sign_extend_8(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg);
bool jit_emit_sign_extend_16(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg);
bool jit_emit_sign_extend_32(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg);
bool jit_emit_zero_extend_8(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg);
bool jit_emit_zero_extend_16(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg);
bool jit_emit_zero_extend_32(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg);

// Unary operations
bool jit_emit_neg(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg);
bool jit_emit_not(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg);
bool jit_emit_abs(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg);
bool jit_emit_inc(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg);
bool jit_emit_dec(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg);

// Control flow
bool jit_emit_jump(void* _Nonnull assembler, const char* _Nonnull target_arch, uint32_t target_pc);
bool jit_emit_jump_ind(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t ptr_reg, uint32_t offset);
bool jit_emit_call(void* _Nonnull assembler, const char* _Nonnull target_arch, int32_t offset);
bool jit_emit_ret(void* _Nonnull assembler, const char* _Nonnull target_arch);

// Branch instructions
bool jit_emit_branch_eq(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t src1_reg, uint8_t src2_reg, uint32_t target_pc);
bool jit_emit_branch_ne(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t src1_reg, uint8_t src2_reg, uint32_t target_pc);
bool jit_emit_branch_lt(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t reg1, uint8_t reg2, uint32_t target_pc);
bool jit_emit_branch_lt_u(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t reg1, uint8_t reg2, uint32_t target_pc);
bool jit_emit_branch_gt(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t reg1, uint8_t reg2, uint32_t target_pc);
bool jit_emit_branch_gt_u(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t reg1, uint8_t reg2, uint32_t target_pc);
bool jit_emit_branch_eq_imm(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t reg, uint64_t value, uint32_t target_pc);
bool jit_emit_branch_ne_imm(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t reg, uint64_t value, uint32_t target_pc);
bool jit_emit_branch_lt_imm(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t reg, uint64_t value, uint32_t target_pc);
bool jit_emit_branch_lt_u_imm(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t reg, uint64_t value, uint32_t target_pc);
bool jit_emit_branch_le_imm(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t reg, uint64_t value, uint32_t target_pc);
bool jit_emit_branch_le_u_imm(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t reg, uint64_t value, uint32_t target_pc);
bool jit_emit_branch_gt_imm(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t reg, uint64_t value, uint32_t target_pc);
bool jit_emit_branch_gt_u_imm(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t reg, uint64_t value, uint32_t target_pc);
bool jit_emit_branch_ge_imm(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t reg, uint64_t value, uint32_t target_pc);
bool jit_emit_branch_ge_u_imm(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t reg, uint64_t value, uint32_t target_pc);

// Memory operations
bool jit_emit_memcpy(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg, uint8_t count_reg);
bool jit_emit_memset(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t value_reg, uint8_t count_reg);

// Load-Effective-Address
bool jit_emit_lea(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t ptr_reg, int32_t offset);

// Register operations
bool jit_emit_copy(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg);

// Test operations
bool jit_emit_test(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t reg1, uint8_t reg2);
bool jit_emit_test_imm(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg, uint64_t immediate);

// System instructions
bool jit_emit_syscall(void* _Nonnull assembler, const char* _Nonnull target_arch);
bool jit_emit_sbrk(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg);
bool jit_emit_fence(void* _Nonnull assembler, const char* _Nonnull target_arch);

// 64-bit shift operations (alternate names)
bool jit_emit_sll_64(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg);
bool jit_emit_srl_64(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg);
bool jit_emit_sra_64(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg);

// 3-register instructions (MulUpper, SetLt, Cmov, Rot)
// Format: [ra][rb][rd] - all registers are passed as parameters
bool jit_emit_mul_upper_uu(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t ra, uint8_t rb, uint8_t rd);
bool jit_emit_mul_upper_su(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t ra, uint8_t rb, uint8_t rd);
bool jit_emit_mul_upper_s_s(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t ra, uint8_t rb, uint8_t rd);
bool jit_emit_set_lt_u(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t ra, uint8_t rb, uint8_t rd);
bool jit_emit_set_lt_s(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t ra, uint8_t rb, uint8_t rd);
bool jit_emit_cmov_iz(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t ra, uint8_t rb, uint8_t rd);
bool jit_emit_cmov_nz(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t ra, uint8_t rb, uint8_t rd);
bool jit_emit_cmov_iz_imm(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg, uint32_t immediate);
bool jit_emit_cmov_nz_imm(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t dest_reg, uint8_t src_reg, uint32_t immediate);
bool jit_emit_rol_64(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t ra, uint8_t rb, uint8_t rd);
bool jit_emit_ror_64(void* _Nonnull assembler, const char* _Nonnull target_arch, uint8_t ra, uint8_t rb, uint8_t rd);

} // namespace jit_instruction
