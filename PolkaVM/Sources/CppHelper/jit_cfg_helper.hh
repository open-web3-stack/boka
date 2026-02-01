#pragma once

#include <cstdint>
#include <vector>
#include <unordered_set>
#include <queue>

/**
 * ControlFlowGraph - Analyzes bytecode to determine reachable code paths
 *
 * Uses a worklist-based algorithm to perform control flow analysis starting
 * from an entry point (typically PC=0). This ensures the JIT compiler only
 * compiles code that would actually be executed by the interpreter.
 */
class ControlFlowGraph {
public:
    /**
     * Build control flow graph starting from entryPC
     *
     * @param codeBuffer Pointer to bytecode buffer
     * @param codeSize Size of bytecode in bytes
     * @param skipTable Skip table for variable-length instructions (can be null)
     * @param skipTableSize Size of skip table
     * @param bitmask Bitmask indicating instruction boundaries (can be null)
     * @param entryPC Starting point for CFG analysis (usually 0)
     */
    void build(
        const uint8_t* codeBuffer,
        uint32_t codeSize,
        const uint32_t* skipTable,
        uint32_t skipTableSize,
        const uint8_t* bitmask,
        uint32_t entryPC
    );

    /**
     * Check if a PC is reachable from the entry point
     *
     * @param pc Program counter to check
     * @return true if PC is reachable, false otherwise
     */
    bool isReachable(uint32_t pc) const;

    /**
     * Check if a PC is a jump target (has incoming edge)
     *
     * @param pc Program counter to check
     * @return true if PC is a jump target, false otherwise
     */
    bool isJumpTarget(uint32_t pc) const;

    /**
     * Get all reachable PCs
     *
     * @return Set of reachable program counters
     */
    const std::unordered_set<uint32_t>& getReachablePCs() const;

    /**
     * Clear the CFG and reset state
     */
    void clear();

private:
    std::unordered_set<uint32_t> reachablePCs;
    std::unordered_set<uint32_t> jumpTargets;

    // Cached pointers to code data
    const uint8_t* codeBuffer = nullptr;
    uint32_t codeSize = 0;
    const uint32_t* skipTable = nullptr;
    uint32_t skipTableSize = 0;
    const uint8_t* bitmask = nullptr;

    /**
     * Process instruction at PC, add successors to worklist
     *
     * @param pc Current program counter
     * @param worklist Worklist for BFS traversal
     */
    void processInstruction(uint32_t pc, std::queue<uint32_t>& worklist);

    /**
     * Get instruction size at PC
     *
     * @param pc Program counter
     * @return Instruction size in bytes, or 0 if invalid
     */
    uint32_t getInstrSize(uint32_t pc) const;

    /**
     * Get jump target for branch instructions
     *
     * @param pc Program counter of jump instruction
     * @param instrSize Instruction size
     * @return Target PC, or pc + instrSize (fallthrough) if invalid
     */
    uint32_t getJumpTarget(uint32_t pc, uint32_t instrSize) const;

    /**
     * Check if PC is at instruction boundary
     *
     * @param pc Program counter to check
     * @return true if PC is at instruction boundary
     */
    bool isInstructionBoundary(uint32_t pc) const;

    /**
     * Check if opcode is a jump/branch instruction
     *
     * @param opcode Opcode byte
     * @return true if instruction is a jump or branch
     */
    static bool isJump(uint8_t opcode);

    /**
     * Check if opcode is a terminator (doesn't fall through)
     *
     * @param opcode Opcode byte
     * @return true if instruction terminates basic block
     */
    static bool isTerminator(uint8_t opcode);
};
