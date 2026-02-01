#include "jit_cfg_helper.hh"
#include "opcodes.hh"
#include "helper.hh"
#include <cstring>
#include <stdio.h>

using namespace PVM;

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
            continue;
        }

        // Mark as reachable
        reachablePCs.insert(pc);

        // Process instruction and add successors
        processInstruction(pc, worklist);
    }
}

void ControlFlowGraph::processInstruction(uint32_t pc, std::queue<uint32_t>& worklist) {
    uint8_t opcode = codeBuffer[pc];
    uint32_t instrSize = getInstrSize(pc);

    if (instrSize == 0) {
        // Invalid opcode, stop CFG traversal here
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
            if (nextPC < codeSize && !reachablePCs.contains(nextPC)) {
                worklist.push(nextPC);
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

    return get_instruction_size(codeBuffer, pc, codeSize);
}

uint32_t ControlFlowGraph::getJumpTarget(uint32_t pc, uint32_t instrSize) const {
    uint8_t opcode = codeBuffer[pc];

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

    // Branch immediate instructions (14 bytes): [opcode][reg_index][value_64bit][offset_32bit]
    if (instrSize == 14) {
        if (pc + 14 > codeSize) {
            return pc + instrSize;
        }
        uint32_t offset;
        memcpy(&offset, &codeBuffer[pc + 10], 4);
        return pc + int32_t(offset);
    }

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

        int64_t jumpOffset = 0;
        if (l_Y > 0) {
            uint64_t rawValue = 0;
            for (uint32_t i = 0; i < l_Y; i++) {
                rawValue |= uint64_t(codeBuffer[offsetPos + i]) << (i * 8);
            }

            uint64_t signBit = 1ULL << (l_Y * 8 - 1);
            jumpOffset = (rawValue & signBit) ? (rawValue | (~((1ULL << (l_Y * 8)) - 1))) : rawValue;
        }

        return pc + uint32_t(jumpOffset);
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
