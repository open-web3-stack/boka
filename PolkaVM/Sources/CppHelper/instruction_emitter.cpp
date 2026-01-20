// Instruction Emitter - Dispatches to appropriate JIT instruction emitters
// This file provides the integration between Swift instruction decoding and C++ JIT emission

#include "instruction_emitter.hh"
#include "jit_instructions.hh"
#include <cstring>

namespace jit_emitter {

// Declare the extern C function from instruction_dispatcher.cpp
extern "C" bool jit_emitter_emit_basic_block_instructions(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    const uint8_t* _Nonnull bytecode,
    uint32_t start_pc,
    uint32_t end_pc
);

// Emit a single instruction to the assembler
// Returns true if successful, false if instruction is not supported
bool emit_instruction(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    uint8_t opcode,
    const uint8_t* _Nonnull instruction_data,
    size_t instruction_size,
    uint32_t current_pc,
    const LabelManager* _Nullable label_manager)
{
    // Call the comprehensive instruction dispatcher from instruction_dispatcher.cpp
    // This dispatcher handles all 194 implemented instructions
    return jit_emitter_emit_basic_block_instructions(assembler, target_arch, instruction_data, current_pc, current_pc + static_cast<uint32_t>(instruction_size));
}

// Emit all instructions from a basic block
bool emit_basic_block(
    void* _Nonnull assembler,
    const char* _Nonnull target_arch,
    const uint8_t* _Nonnull code_buffer,
    size_t code_size,
    uint32_t block_start_pc,
    uint32_t block_end_pc,
    const LabelManager* _Nullable label_manager)
{
    // Use the comprehensive instruction dispatcher
    return jit_emitter_emit_basic_block_instructions(assembler, target_arch, code_buffer, block_start_pc, block_end_pc);
}

} // namespace jit_emitter
