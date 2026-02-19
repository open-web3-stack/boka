#include "jit_cfg_helper.hh"
#include "opcodes.hh"
#include "helper.hh"
#include <cstring>
#include <stdio.h>

using namespace PVM;

static inline uint32_t clamp_imm_len(uint32_t len) {
    return (len > 4) ? 4 : len;
}

static inline uint32_t second_immediate_len(uint32_t instr_size, uint32_t prefix_len, uint32_t first_immediate_len) {
    if (instr_size <= prefix_len + first_immediate_len) {
        return 0;
    }
    return clamp_imm_len(instr_size - prefix_len - first_immediate_len);
}

static inline int32_t decode_immediate_signed32(
    const uint8_t* bytecode,
    uint32_t offset,
    uint32_t len,
    uint32_t code_size)
{
    if (len == 0 || offset >= code_size || offset + len > code_size) {
        return 0;
    }
    uint32_t value = 0;
    for (uint32_t i = 0; i < len; ++i) {
        value |= uint32_t(bytecode[offset + i]) << (8 * i);
    }
    if (len < 4) {
        uint32_t signBit = 1U << (len * 8 - 1);
        if (value & signBit) {
            value |= (~0U) << (len * 8);
        }
    }
    return static_cast<int32_t>(value);
}

void ControlFlowGraph::build(
    const uint8_t* codeBuffer,
    uint32_t codeSize,
    const uint32_t* skipTable,
    uint32_t skipTableSize,
    const uint8_t* bitmask,
    uint32_t entryPC
) {
    clear();

    // Cache pointers
    this->codeBuffer = codeBuffer;
    this->codeSize = codeSize;
    this->skipTable = skipTable;
    this->skipTableSize = skipTableSize;
    this->bitmask = bitmask;

    // Start CFG analysis from entry point (usually PC=0)
    std::queue<uint32_t> worklist;
    worklist.push(entryPC);

    while (!worklist.empty()) {
        uint32_t pc = worklist.front();
        worklist.pop();

        // Skip if already processed
        if (reachablePCs.contains(pc)) {
            continue;
        }

        // Bounds check
        if (pc >= codeSize) {
            continue;
        }

        // Must be at instruction boundary
        if (!isInstructionBoundary(pc)) {
            fprintf(stderr, "[CFG] PC %u NOT at instruction boundary, skipping\n", pc);
            continue;
        }

        // Mark as reachable
        reachablePCs.insert(pc);
        fprintf(stderr, "[CFG] Marking PC %u as reachable (opcode=0x%02x)\n", pc, codeBuffer[pc]);

        // Process instruction and add successors
        processInstruction(pc, worklist);
    }
}

void ControlFlowGraph::processInstruction(uint32_t pc, std::queue<uint32_t>& worklist) {
    uint8_t opcode = codeBuffer[pc];
    uint32_t instrSize = getInstrSize(pc);

    fprintf(stderr, "[CFG] Processing PC %u (opcode=0x%02x), instrSize=%u\n", pc, opcode, instrSize);

    if (instrSize == 0) {
        // Invalid opcode, stop CFG traversal here
        fprintf(stderr, "[CFG] PC %u has instrSize=0, stopping traversal\n", pc);
        return;
    }

    // Check if this is a jump/branch instruction
    if (isJump(opcode)) {
        uint32_t targetPC = getJumpTarget(pc, instrSize);

        // Add jump target as successor if valid
        if (targetPC < codeSize && isInstructionBoundary(targetPC)) {
            jumpTargets.insert(targetPC);
            if (!reachablePCs.contains(targetPC)) {
                worklist.push(targetPC);
            }
        }

        // Jumps may also fall through if conditional
        // For conditional branches (Branch*), add fallthrough
        if (!isTerminator(opcode)) {
            uint32_t nextPC = pc + instrSize;
            fprintf(stderr, "[CFG] Jump instruction at PC %u, nextPC=%u\n", pc, nextPC);
            if (nextPC < codeSize && !reachablePCs.contains(nextPC)) {
                worklist.push(nextPC);
                fprintf(stderr, "[CFG] Adding nextPC %u to worklist (fallthrough from jump)\n", nextPC);
            }
        }
    } else {
        // Not a jump - add fallthrough successor if not terminator
        if (!isTerminator(opcode)) {
            uint32_t nextPC = pc + instrSize;

            // Check if next PC is valid
            if (nextPC < codeSize) {
                if (!reachablePCs.contains(nextPC)) {
                    worklist.push(nextPC);
                    fprintf(stderr, "[CFG] Adding nextPC %u to worklist (fallthrough)\n", nextPC);
                }
            }
        }
    }
}

uint32_t ControlFlowGraph::getInstrSize(uint32_t pc) const {
    if (pc >= codeSize) {
        return 0;
    }

    uint8_t opcode = codeBuffer[pc];

    // Handle old opcode numbers for backwards compatibility
    // Old JumpInd = opcode 2 (2 bytes: [opcode][reg_index])
    if (opcode == 2) {
        return 2;
    }

    // Use bitmask to find the next instruction boundary.
    // This is more reliable than re-decoding compact immediates.
    if (!bitmask) {
        // Fall back to get_instruction_size if no bitmask available
        return get_instruction_size(codeBuffer, pc, codeSize);
    }

    // Scan forward from pc+1 to find the next instruction boundary
    // The current instruction size is the distance to the next boundary
    for (uint32_t nextPC = pc + 1; nextPC < codeSize; nextPC++) {
        if (isInstructionBoundary(nextPC)) {
            return nextPC - pc;
        }
    }

    // No more instruction boundaries found - size is to end of code
    return codeSize - pc;
}

uint32_t ControlFlowGraph::getJumpTarget(uint32_t pc, uint32_t instrSize) const {
    uint8_t opcode = codeBuffer[pc];

    // CRITICAL: Check opcode FIRST before checking instrSize
    // LoadImmJump and LoadImmJumpInd have variable sizes and must be handled
    // before the generic size-based handlers to avoid misclassification

    // LoadImmJump: [opcode][r_A | l_X][immed_X (l_X bytes)][immed_Y (l_Y bytes)]
    if (opcode_is(opcode, Opcode::LoadImmJump)) {
        if (pc + 1 >= codeSize) return pc + instrSize;

        uint8_t byte1 = codeBuffer[pc + 1];
        uint32_t l_X = (byte1 >> 4) & 0x07;
        if (l_X > 4) l_X = 4;

        uint32_t l_Y = instrSize - 2 - l_X;

        if (l_Y > 4 || (instrSize < 2 + l_X)) {
            return pc + instrSize;
        }

        uint32_t offsetPos = pc + 2 + l_X;
        if (offsetPos + l_Y > codeSize) {
            return pc + instrSize;
        }

        int32_t jumpOffset = decode_immediate_signed32(codeBuffer, offsetPos, l_Y, codeSize);
        uint32_t targetPC = pc + uint32_t(jumpOffset);
        return targetPC;
    }

    // LoadImmJumpInd: [opcode][packed_ra_rb][len][immed_X][immed_Y]
    if (opcode_is(opcode, Opcode::LoadImmJumpInd)) {
        // LoadImmJumpInd jumps through a register, not to a fixed PC
        // For CFG purposes, treat as fallthrough (we can't predict runtime register values)
        return pc + instrSize;
    }

    // Jump: [opcode][offset_32bit] = 5 bytes
    if (opcode_is(opcode, Opcode::Jump)) {
        if (pc + 5 > codeSize) {
            return pc + instrSize; // Fallthrough on error
        }
        uint32_t offset;
        memcpy(&offset, &codeBuffer[pc + 1], 4);
        return pc + int32_t(offset);
    }

    // Branch register instructions (7 bytes): [opcode][reg1][reg2][offset_32bit]
    if (instrSize == 7) {
        if (pc + 7 > codeSize) {
            return pc + instrSize;
        }
        uint32_t offset;
        memcpy(&offset, &codeBuffer[pc + 3], 4);
        return pc + int32_t(offset);
    }

    // Branch immediate instructions:
    // [opcode][packed_rA_lX][immed_X][immed_Y]
    if (opcode_is(opcode, Opcode::BranchEqImm) ||
        opcode_is(opcode, Opcode::BranchNeImm) ||
        opcode_is(opcode, Opcode::BranchLtUImm) ||
        opcode_is(opcode, Opcode::BranchLeUImm) ||
        opcode_is(opcode, Opcode::BranchGeUImm) ||
        opcode_is(opcode, Opcode::BranchGtUImm) ||
        opcode_is(opcode, Opcode::BranchLtSImm) ||
        opcode_is(opcode, Opcode::BranchLeSImm) ||
        opcode_is(opcode, Opcode::BranchGeSImm) ||
        opcode_is(opcode, Opcode::BranchGtSImm))
    {
        if (instrSize < 2 || pc + instrSize > codeSize) {
            return pc + instrSize;
        }

        uint8_t packed = codeBuffer[pc + 1];
        uint32_t l_X = clamp_imm_len((packed >> 4) & 0x07);
        if (instrSize < (2 + l_X)) {
            return pc + instrSize;
        }
        uint32_t l_Y = second_immediate_len(instrSize, 2, l_X);
        int32_t offset = decode_immediate_signed32(codeBuffer, pc + 2 + l_X, l_Y, codeSize);
        return pc + uint32_t(offset);
    }

    return pc + instrSize; // Fallthrough
}

bool ControlFlowGraph::isInstructionBoundary(uint32_t pc) const {
    if (!bitmask || pc >= codeSize) {
        return false;
    }
    uint32_t byteIndex = pc / 8;
    uint32_t bitIndex = pc % 8;
    return (bitmask[byteIndex] & (1 << bitIndex)) != 0;
}

bool ControlFlowGraph::isJump(uint8_t opcode) {
    return
        opcode_is(opcode, Opcode::Jump) ||
        opcode_is(opcode, Opcode::JumpInd) ||
        opcode_is(opcode, Opcode::LoadImmJump) ||
        opcode_is(opcode, Opcode::LoadImmJumpInd) ||
        opcode_is(opcode, Opcode::BranchEq) ||
        opcode_is(opcode, Opcode::BranchNe) ||
        opcode_is(opcode, Opcode::BranchLtU) ||
        opcode_is(opcode, Opcode::BranchLtS) ||
        opcode_is(opcode, Opcode::BranchGeU) ||
        opcode_is(opcode, Opcode::BranchGeS) ||
        opcode_is(opcode, Opcode::BranchEqImm) ||
        opcode_is(opcode, Opcode::BranchNeImm) ||
        opcode_is(opcode, Opcode::BranchLtUImm) ||
        opcode_is(opcode, Opcode::BranchLeUImm) ||
        opcode_is(opcode, Opcode::BranchGeUImm) ||
        opcode_is(opcode, Opcode::BranchGtUImm) ||
        opcode_is(opcode, Opcode::BranchLtSImm) ||
        opcode_is(opcode, Opcode::BranchLeSImm) ||
        opcode_is(opcode, Opcode::BranchGeSImm) ||
        opcode_is(opcode, Opcode::BranchGtSImm);
}

bool ControlFlowGraph::isTerminator(uint8_t opcode) {
    // Terminators are instructions that never fall through:
    // - Trap: Unconditional trap
    // - Halt: Normal termination
    // - Jump: Unconditional jump
    // - JumpInd: Indirect jump
    // - LoadImmJump: Load and unconditional jump
    // - LoadImmJumpInd: Load and indirect jump
    // - Ecalli: Environment call (may or may not return, treat as terminator for safety)
    return
        opcode_is(opcode, Opcode::Trap) ||
        opcode_is(opcode, Opcode::Halt) ||
        opcode_is(opcode, Opcode::Jump) ||
        opcode_is(opcode, Opcode::JumpInd) ||
        opcode_is(opcode, Opcode::LoadImmJump) ||
        opcode_is(opcode, Opcode::LoadImmJumpInd) ||
        opcode_is(opcode, Opcode::Ecalli);
}

bool ControlFlowGraph::isReachable(uint32_t pc) const {
    return reachablePCs.contains(pc);
}

bool ControlFlowGraph::isJumpTarget(uint32_t pc) const {
    return jumpTargets.contains(pc);
}

const std::unordered_set<uint32_t>& ControlFlowGraph::getReachablePCs() const {
    return reachablePCs;
}

void ControlFlowGraph::clear() {
    reachablePCs.clear();
    jumpTargets.clear();
    codeBuffer = nullptr;
    codeSize = 0;
    skipTable = nullptr;
    skipTableSize = 0;
    bitmask = nullptr;
}
