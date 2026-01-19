// Instruction Emitter - Header file
// Provides the interface between Swift instruction decoding and C++ JIT emission

#ifndef INSTRUCTION_EMITTER_HH
#define INSTRUCTION_EMITTER_HH

#include <cstdint>
#include <cstddef>

namespace jit_emitter {

// Forward declaration
struct LabelManager;

/// Emit a single instruction to the assembler
/// - Parameters:
///   - assembler: The AsmJit assembler instance
///   - target_arch: Target architecture ("x86_64")
///   - opcode: The instruction opcode
///   - instruction_data: Pointer to instruction encoding data
///   - instruction_size: Size of the instruction in bytes
///   - current_pc: Current program counter
///   - label_manager: Optional label manager for fixups
/// - Returns: true if successful, false otherwise
bool emit_instruction(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t opcode,
    const uint8_t* _Nonnull instruction_data,
    size_t instruction_size,
    uint32_t current_pc,
    const LabelManager* _Nullable label_manager);

/// Emit all instructions from a basic block
/// - Parameters:
///   - assembler: The AsmJit assembler instance
///   - target_arch: Target architecture ("x86_64")
///   - code_buffer: Pointer to the code buffer
///   - code_size: Size of the code buffer
///   - block_start_pc: Starting PC of the basic block
///   - block_end_pc: Ending PC of the basic block
///   - label_manager: Optional label manager for fixups
/// - Returns: true if successful, false otherwise
bool emit_basic_block(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    const uint8_t* _Nonnull code_buffer,
    size_t code_size,
    uint32_t block_start_pc,
    uint32_t block_end_pc,
    const LabelManager* _Nullable label_manager);

} // namespace jit_emitter

#endif // INSTRUCTION_EMITTER_HH
