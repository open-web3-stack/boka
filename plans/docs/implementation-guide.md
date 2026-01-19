# PolkaVM Recompiler Implementation Guide

## Overview

This guide provides a comprehensive roadmap for implementing a high-performance PolkaVM recompiler from scratch. It covers architecture, data structures, algorithms, and practical implementation details in a language-agnostic way.

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Prerequisites](#prerequisites)
3. [Phase 1: Foundation](#phase-1-foundation)
4. [Phase 2: Program Parsing](#phase-2-program-parsing)
5. [Phase 3: Basic Code Generation](#phase-3-basic-code-generation)
6. [Phase 4: Control Flow](#phase-4-control-flow)
7. [Phase 5: Memory Operations](#phase-5-memory-operations)
8. [Phase 6: Gas Metering](#phase-6-gas-metering)
9. [Phase 7: Trampolines and Host Calls](#phase-7-trampolines-and-host-calls)
10. [Phase 8: Execution and Fault Handling](#phase-8-execution-and-fault-handling)
11. [Phase 9: Optimization](#phase-9-optimization)
12. [Testing Strategy](#testing-strategy)
13. [Common Pitfalls](#common-pitfalls)

## Architecture Overview

### High-Level Design

A PolkaVM recompiler transforms PolkaVM bytecode into native machine code. The key components are:

```
┌─────────────────┐
│  Program Blob   │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Program Parser  │ → Decodes instructions
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Compiler Visitor│ → Visits each instruction
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Architecture   │ → Lowers to native code
│    Visitor      │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│   Assembler     │ → Emits machine code
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Compiled Module │ → Native code + metadata
└─────────────────┘
```

### Key Design Decisions

**1. Single-Pass Compilation**
- Parse and generate code in one pass
- Use forward-declared labels for backpatching
- Trade-off: Simplicity vs. optimization opportunities

**2. Basic Block Granularity**
- Gas metering at basic block boundaries
- Jump targets mark basic block starts
- Enables precise gas accounting

**3. Fixed Register Mapping**
- Map VM registers to native registers statically
- Eliminates need for register allocation
- Optimization: Map common operands to compactly-encodable registers

**4. Trampoline-Based Host Calls**
- Separate trampolines for each host operation
- Saves/restores full VM state
- Enables secure host/guest boundary

## Prerequisites

### Required Knowledge

- **Target ISA**: x86-64 (or your chosen architecture)
- **Assembly language**: Your target's instruction set
- **Calling conventions**: System V ABI or similar
- **Memory management**: Virtual memory, memory protection
- **Compiler basics**: Instruction selection, code generation

### Required Components

1. **Assembler** - Emit machine code for your target
2. **Memory allocator** - Manage code and data buffers
3. **Program parser** - Decode PolkaVM bytecode
4. **VM context** - Shared state between host and guest
5. **Sandbox** - Isolate guest execution (optional but recommended)

## Phase 1: Foundation

### 1.1 Define Core Types

You'll need to define these core data structures:

**Guest Register Set:**
- Enumeration of VM registers: RA, SP, T0, T1, T2, S0, S1, A0, A1, A2, A3, A4, A5

**Program Counter (PC):**
- Represents an offset into the bytecode (32-bit unsigned integer)

**Native Code Offset:**
- Represents an offset into generated native code (32-bit unsigned integer)

**Label:**
- Represents a forward-declared jump target (32-bit unsigned integer ID)
- Used for backpatching jumps before the target is known

### 1.2 Create Assembler

Your assembler needs these components:

**Data Structures:**
- Code buffer: A growable byte array to hold emitted machine code
- Label table: A mapping from label ID to code offset (optional if not yet defined)
- Fixup list: A list of pending jump targets to be resolved later

**Core Operations:**
- `new()` - Create an empty assembler
- `emit(bytes)` - Write raw bytes to code buffer
- `create_label()` - Allocate a new label ID
- `define_label(label_id)` - Mark current position as the label's target
- `emit_jump(label_id)` - Emit jump instruction (creates fixup if label undefined)
- `finalize()` - Resolve all fixups and return completed code

**Pseudocode Example:**

```swift
func emitJump(assembler: Assembler, labelId: UInt32) {
    let currentOffset = assembler.code.count

    if let targetOffset = assembler.labelTable[labelId] {
        // Label already defined - compute displacement
        let displacement = targetOffset - currentOffset
        emitJumpWithDisplacement(assembler, displacement)
    } else {
        // Forward reference - emit placeholder, create fixup
        emitJumpPlaceholder(assembler)
        assembler.fixups.append(Fixup(
            type: .jump,
            labelId: labelId,
            patchOffset: currentOffset
        ))
    }
}

func finalize(assembler: Assembler) -> [UInt8] {
    // Resolve all fixups
    for fixup in assembler.fixups {
        guard let targetOffset = assembler.labelTable[fixup.labelId] else {
            fatalError("Undefined label reference")
        }

        let displacement = targetOffset - fixup.patchOffset
        patchJumpInstruction(assembler.code, fixup.patchOffset, displacement)
    }

    return assembler.code
}
```

### 1.3 Define VM Context

The VM context holds all execution state shared between host and guest:

**Structure Fields:**

**Registers:**
- Array of 13 64-bit atomic integers (one per VM register)
- Atomics needed for concurrent access from signal handlers

**Program Counters:**
- Current PC: 32-bit atomic (current bytecode position)
- Next PC: 32-bit atomic (next bytecode position for continuation)
- Next native PC: 64-bit atomic (native code address for continuation)

**Gas Metering:**
- Gas counter: 64-bit signed atomic integer
- Can go negative temporarily (trapped later)

**Memory:**
- Memory pointer: Pointer to byte array (guest memory)
- Memory size: Size in bytes
- Stack pointer: Pointer to current stack location
- Stack base: Pointer to stack bottom

**Host Communication:**
- Futex: 32-bit atomic (for synchronization)
- Argument: 32-bit atomic (argument for host calls)

## Phase 2: Program Parsing

### 2.1 Parse Program Blob

The program blob contains all code and data sections. Implement parsing according to the program blob format specification.

**Program Blob Structure:**

Sections to extract:
- Code section: Bytecode instructions
- Read-only data: Constants, jump tables
- Read-write data: Global variables
- Jump table: For indirect branches
- Bitmask: For valid PC ranges
- Exports: Public function entries

**Parsing Algorithm:**

```swift
func parseProgramBlob(_ data: [UInt8]) -> ProgramBlob {
    // 1. Read and validate header
    let header = readHeader(data)
    validateHeader(header)

    // 2. Parse variable-length integer fields
    var position = 0
    let codeOffset = readVarint(data, &position)
    let codeSize = readVarint(data, &position)
    let roDataOffset = readVarint(data, &position)
    let roDataSize = readVarint(data, &position)
    // ... etc for all sections

    // 3. Extract sections
    let code = extractSlice(data, codeOffset, codeSize)
    let roData = extractSlice(data, roDataOffset, roDataSize)
    // ... etc

    // 4. Validate consistency
    validateSections(code, roData, ...)

    return ProgramBlob(
        code: code,
        roData: roData
        // ... other fields
    )
}
```

### 2.2 Instruction Decoder

Create a decoder that reads instructions sequentially from bytecode.

**Decoder Structure:**

```swift
struct InstructionDecoder {
    let code: [UInt8]      // Bytecode to decode
    var pc: Int            // Current position in bytecode

    mutating func next() -> Instruction? {
        // 1. Read opcode at current PC
        let opcode = code[pc]

        // 2. Decode based on opcode
        let instruction = decodeOpcode(opcode, code, pc)

        // 3. Advance PC
        pc += instruction.size

        return instruction
    }
}
```

**Instruction Types:**

Examples of instructions to decode:
- Trap - halt execution
- Ecalli { imm } - host call with immediate argument
- LoadImmU8 { reg, imm } - load 8-bit immediate into register
- BranchEq { reg1, reg2, offset } - conditional branch
- And many more (see instruction set reference)

**Key Parsing Functions:**

- `read_varint(data, position)` - Decode variable-length integer
- `read_args_reg_imm(code, pc)` - Decode register + immediate encoding
- `read_args_reg_reg(code, pc)` - Decode two-register encoding

See the program blob format specification for detailed encoding rules.

## Phase 3: Basic Code Generation

### 3.1 Compiler Visitor

Create the main compilation driver that walks through instructions and generates code.

**Compiler Visitor Structure:**

```swift
struct CompilerVisitor {
    // Input
    let blob: ProgramBlob
    let config: CompilerConfiguration

    // Output
    var assembler: Assembler
    var pcToNativeOffset: [(UInt32, UInt32)] = []

    // State
    var labels: [UInt32: Label] = [:]
    var currentBlockLabel: Label?
}
```

**Compilation Algorithm:**

```swift
func compile(_ blob: ProgramBlob) -> CompiledModule {
    // 1. Create visitor
    var visitor = createVisitor(blob)

    // 2. Visit all instructions
    var decoder = createInstructionDecoder(blob.code)
    while let instruction = decoder.next() {
        visitInstruction(&visitor, instruction)
    }

    // 3. Finalize (resolve fixups, etc)
    return finalize(&visitor)
}
```

### 3.2 Visit Instructions

Implement the instruction visitor pattern:

```swift
func visitInstruction(_ visitor: inout CompilerVisitor, _ instruction: Instruction) {
    // Dispatch based on instruction type
    switch instruction.type {
    case .trap:
        emitTrap(&visitor)

    case .loadImmU8:
        emitLoadImmU8(&visitor, instruction.reg, instruction.imm)

    case .branchEq:
        emitBranchEq(&visitor, instruction.reg1, instruction.reg2, instruction.target)

    // ... handle all instruction types
    }

    // Record PC mapping after each instruction
    let nativeOffset = visitor.assembler.code.count
    visitor.pcToNativeOffset.append((visitor.pc, nativeOffset))
}
```

### 3.3 Register Mapping

Define how VM registers map to native registers. This is critical for performance.

**For x86-64:**

```
VM Register → Native Register Mapping:
    RA → rbx
    SP → rsi
    A0 → rdi
    A1 → rax
    A2 → rdx
    A3 → rbp
    S0 → r8
    S1 → r9
    A4 → r10
    A5 → r11
    T0 → r13
    T1 → r14
    T2 → r12
```

**Why this mapping?**

- A0 → rdi: First argument register in System V ABI calling convention
- A1 → rax: Compact encoding for many operations (special encodings available)
- Minimizes register shuffling in hot paths
- Avoids callee-saved registers where possible

## Phase 4: Control Flow

### 4.1 Basic Block Formation

Mark basic block boundaries for gas metering and jump targets.

**Basic Block Start Algorithm:**

```swift
func startBasicBlock(_ visitor: inout CompilerVisitor, _ pc: UInt32) {
    // Create label if this is a jump target
    if isJumpTarget(visitor, pc) {
        let label = visitor.assembler.createLabel()
        visitor.labels[pc] = label
        visitor.assembler.defineLabel(label)
        visitor.currentBlockLabel = label
    }
}

func endBasicBlock(_ visitor: inout CompilerVisitor) {
    visitor.currentBlockLabel = nil
}
```

**When to start new blocks:**

- At program entry point
- After any branch instruction
- At jump targets ( destinations of branches)
- After trap instructions

### 4.2 Direct Branches

Emit conditional branch instructions.

**Example: Branch if Equal**

```swift
func emitBranchEq(_ visitor: inout CompilerVisitor, _ reg1: Register, _ reg2: Register, _ targetPc: UInt32) {
    // Get or create label for target
    let targetLabel = getOrCreateLabel(&visitor, targetPc)

    // Compare the two registers (x86-64 assembly)
    // cmp reg1, reg2
    visitor.assembler.emitCmp(
        mapRegister(reg1),
        mapRegister(reg2)
    )

    // Conditional jump if equal (x86-64 assembly)
    // je target_label
    visitor.assembler.emitJcc(.equal, targetLabel)
}
```

### 4.3 Indirect Jumps

Use a jump table for dynamic jumps (computed goto).

**Indirect Jump Algorithm:**

```swift
func emitIndirectJump(_ visitor: inout CompilerVisitor, _ indexReg: Register) {
    // Load jump table base address into a register
    visitor.assembler.emitLoadJumpTableAddress()

    // Jump through table (x86-64 assembly)
    // jmp [table_base + index * 8]
    let nativeReg = mapRegister(indexReg)
    visitor.assembler.emitJmpMemoryScaled(
        tableBaseRegister,
        nativeReg,
        8  // 8 bytes per entry (64-bit pointer)
    )
}
```

**Jump Table Format:**

- Array of 64-bit native code pointers
- Indexed by VM PC offset
- Invalid entries use a special non-canonical address
- Causes trap if jumped to (safe fallback)

## Phase 5: Memory Operations

### 5.1 Load Instructions

Emit instructions to load from memory.

**Example: 32-bit Load**

```swift
func emitLoad32(_ visitor: inout CompilerVisitor, _ destReg: Register, _ baseReg: Register, _ offset: Int32) {
    let nativeDest = mapRegister(destReg)
    let nativeBase = mapRegister(baseReg)

    // Emit: mov dest, [base + offset]
    // x86-64 assembly: mov r32, [r64 + imm32]
    visitor.assembler.emitLoad32(
        nativeDest,
        nativeBase,
        offset
    )
}
```

**Memory Access Pattern:**

- Base register + immediate offset
- Sign-extend or zero-extend based on instruction size
- Validate memory access (or rely on page faults for sandboxing)

### 5.2 Store Instructions

Emit instructions to store to memory.

**Example: 32-bit Store**

```swift
func emitStore32(_ visitor: inout CompilerVisitor, _ srcReg: Register, _ baseReg: Register, _ offset: Int32) {
    let nativeSrc = mapRegister(srcReg)
    let nativeBase = mapRegister(baseReg)

    // Emit: mov [base + offset], src
    // x86-64 assembly: mov [r64 + imm32], r32
    visitor.assembler.emitStore32(
        nativeBase,
        offset,
        nativeSrc
    )
}
```

### 5.3 Memset Implementation

Special handling for memset (critical performance path).

**Fast Path Memset:**

```swift
func emitMemset(_ visitor: inout CompilerVisitor) {
    // Inputs: A0=destination, A1=value, A2=count
    // Uses: RDI, RAX, RCX (memset calling convention)

    // Move VM registers to memset argument registers
    visitor.assembler.emitMov(rdi, mapRegister(.a0))
    visitor.assembler.emitMov(rax, mapRegister(.a1))
    visitor.assembler.emitMov(rcx, mapRegister(.a2))

    // Emit: rep stosb (repeat store byte)
    // x86-64 assembly: F3 AA
    visitor.assembler.emitRaw([0xF3, 0xAA])
}
```

**With Gas Metering:**

- Pre-charge gas: `gas -= count`
- Branch to slow path if insufficient gas
- Slow path: compute bytes possible, execute partial, trap

## Phase 6: Gas Metering

### 6.1 Gas Accounting

Track gas costs per basic block.

**Gas Visitor Structure:**

```swift
struct GasVisitor {
    let costModel: CostModel
    var blockCost: Int = 0   // Current block's accumulated cost
    var totalCost: Int = 0   // Total program cost
}
```

**Gas Accounting Algorithm:**

```swift
func startBlock(_ visitor: inout GasVisitor) {
    visitor.blockCost = 0
}

func accountInstruction(_ visitor: inout GasVisitor, _ instruction: Instruction) {
    let cost = visitor.costModel.cost(instruction)
    visitor.blockCost += cost
}

func endBlock(_ visitor: inout GasVisitor) -> Int {
    let cost = visitor.blockCost
    visitor.totalCost += cost
    visitor.blockCost = 0
    return cost
}
```

### 6.2 Emit Gas Stub

At the start of each basic block, emit gas checking code.

**Gas Stub Format:**

```swift
func emitGasStub(_ visitor: inout CompilerVisitor, _ blockCost: Int) {
    // Stub format (x86-64 assembly):
    // sub qword [vmctx.gas], IMMEDIATE
    // jb trap_handler    // jump if gas < 0

    let stubOffset = visitor.assembler.code.count

    // Emit subtraction with placeholder cost
    visitor.assembler.emitSubImm64(
        vmctxGasOffset(),
        PLACEHOLDER_COST  // Will be patched later
    )

    // Emit conditional jump to trap handler
    if visitor.config.gasMeteringSync {
        visitor.assembler.emitJcc(.below, visitor.trapLabel)
    }

    // Record for later patching
    visitor.gasStubs.append((stubOffset, blockCost))
}
```

### 6.3 Patch Gas Costs

After compilation completes, patch in actual costs.

**Patching Algorithm:**

```swift
func patchGasCosts(_ visitor: inout CompilerVisitor) {
    for (stubOffset, cost) in visitor.gasStubs {
        // Calculate offset of immediate field
        // For x86-64 sub instruction, immediate is at offset + 4
        let immOffset = stubOffset + IMMEDIATE_OFFSET

        // Patch the 32-bit immediate value (little-endian)
        let costBytes = encodeLE32(cost)
        visitor.assembler.code[immOffset..<immOffset+4] = costBytes[0..<4]
    }
}
```

## Phase 7: Trampolines and Host Calls

### 7.1 Trap Trampoline

Save state and jump to trap handler in host code.

**Trap Trampoline Code:**

```swift
func emitTrapTrampoline(_ visitor: inout CompilerVisitor) -> Label {
    let trapLabel = visitor.assembler.createLabel()
    visitor.assembler.defineLabel(trapLabel)

    // Save all VM registers to vmctx
    saveAllRegisters(&visitor)

    // Set next_native_pc = 0 (indicates trap)
    visitor.assembler.emitMovImm64(
        vmctxNextNativePcOffset(),
        0
    )

    // Jump to host trap handler
    visitor.assembler.emitJmpAddress(HOST_TRAP_HANDLER_ADDRESS)

    return trapLabel
}
```

**Save All Registers:**

```swift
func saveAllRegisters(_ visitor: inout CompilerVisitor) {
    for vmReg in [Register.ra, .sp, .t0, .t1, .t2, .s0, .s1, .a0, .a1, .a2, .a3, .a4, .a5] {
        let nativeReg = mapRegister(vmReg)
        let offset = vmctxRegisterOffset(vmReg)

        // Emit: mov [vmctx + offset], native_reg
        visitor.assembler.emitStore64(
            vmctxBaseRegister,
            offset,
            nativeReg
        )
    }
}
```

### 7.2 Ecall Trampoline

Host call with argument.

**Ecall Trampoline:**

```swift
func emitEcallTrampoline(_ visitor: inout CompilerVisitor) -> Label {
    let ecallLabel = visitor.assembler.createLabel()
    visitor.assembler.defineLabel(ecallLabel)

    // Save return address
    saveReturnAddress(&visitor)

    // Save all registers
    saveAllRegisters(&visitor)

    // Jump to host handler
    visitor.assembler.emitJmpAddress(HOST_ECALL_HANDLER_ADDRESS)

    return ecallLabel
}
```

**Ecall Implementation:**

```swift
func emitEcalli(_ visitor: inout CompilerVisitor, _ imm: UInt32) {
    // Store argument for host
    visitor.assembler.emitMovImm32(
        vmctxArgOffset(),
        imm
    )

    // Store program counters
    visitor.assembler.emitMovImm32(
        vmctxPcOffset(),
        visitor.currentPc
    )
    visitor.assembler.emitMovImm32(
        vmctxNextPcOffset(),
        visitor.nextPc
    )

    // Call ecall trampoline
    visitor.assembler.emitCall(visitor.ecallLabel)
}
```

### 7.3 Sysenter/Sysreturn

Host ↔ guest transition points.

**Sysenter (Entry from Host):**

```swift
func emitSysenter(_ visitor: inout CompilerVisitor) {
    // Entry point from host code
    visitor.sysenterLabel = visitor.assembler.createLabel()
    visitor.assembler.defineLabel(visitor.sysenterLabel)

    // Restore all registers from vmctx
    restoreAllRegisters(&visitor)

    // Jump to continuation point
    // Emit: jmp [vmctx.next_native_pc]
    visitor.assembler.emitJmpMemory(vmctxNextNativePcOffset())
}
```

**Sysreturn (Exit to Host):**

```swift
func emitSysreturn(_ visitor: inout CompilerVisitor) {
    // Exit point to return to host
    visitor.sysreturnLabel = visitor.assembler.createLabel()
    visitor.assembler.defineLabel(visitor.sysreturnLabel)

    // Save all registers
    saveAllRegisters(&visitor)

    // Set next_pc = 0 (signals return to host)
    visitor.assembler.emitMovImm64(
        vmctxNextNativePcOffset(),
        0
    )

    // Jump to host return handler
    visitor.assembler.emitJmpAddress(HOST_RETURN_HANDLER_ADDRESS)
}
```

## Phase 8: Execution and Fault Handling

### 8.1 Module Structure

Compiled module contains:

**Compiled Module Components:**

- Machine code: Byte array of native instructions
- Jump table: Array of 64-bit code pointers
- PC to native offset mapping: List of (bytecode_offset, native_offset) pairs
- Native code origin: Base address for trap recovery

### 8.2 Execute Compiled Code

**Execution Algorithm:**

```swift
func execute(_ module: CompiledModule, _ vmctx: VMContext) {
    // 1. Map code into executable memory
    let codePtr = mapCodeExecutable(module.machineCode)

    // 2. Set up jump table in memory
    setupJumpTable(module.jumpTable)

    // 3. Enter at sysenter point
    let entryOffset = module.sysenterOffset
    let entryAddress = codePtr + entryOffset

    // Cast to function pointer and call
    let entryFn = unsafeBitCast(entryAddress, to: (@convention(c) () -> Void).self)

    // This never returns normally (traps or sysreturns out)
    entryFn()

    // Unreachable
    fatalError("Should not return")
}
```

### 8.3 Signal Handler (Linux Sandbox)

Handle traps and page faults for sandboxing.

**Signal Handler Algorithm:**

```swift
func signalHandler(_ signal: Int32, _ siginfo: UnsafeMutablePointer<siginfo_t>, _ context: UnsafeMutablePointer<ucontext_t>) {
    let faultAddr = getFaultAddress(context)
    let faultPc = getProgramCounter(context)

    // Classify fault type
    if isMemsetFault(faultPc) {
        handleMemsetFault(context)
    } else if isGasTrap(faultPc) {
        handleGasTrap(context)
    } else {
        handleTrap(context)
    }
}
```

**Gas Trap Handler:**

```swift
func handleGasTrap(_ context: UnsafeMutablePointer<ucontext_t>, _ vmctx: VMContext, _ machineCode: [UInt8]) {
    // 1. Get the faulting program counter
    let pc = getProgramCounter(context)

    // 2. Find gas stub location (trap occurs after sub instruction)
    let stubOffset = pc - GAS_METERING_TRAP_OFFSET

    // 3. Read gas cost from machine code
    let costBytes = machineCode[stubOffset + COST_OFFSET..<stubOffset + COST_OFFSET + 4]
    let cost = decodeLE32(costBytes)

    // 4. Refund the gas (since instruction didn't complete)
    vmctx.gas += cost

    // 5. Set recovery PC (retry after gas is added)
    vmctx.nextNativePc = stubOffset

    // 6. Find and set guest PC for recovery
    let guestPc = findGuestPc(stubOffset)
    vmctx.programCounter = guestPc
}
```

### 8.4 Page Fault Handler

Handle memory access violations.

**Page Fault Algorithm:**

```swift
func pageFaultHandler(_ faultAddr: UInt64, _ faultPc: UInt64) {
    if isInMemset(faultPc) {
        // Partial memset - complete remaining bytes
        completeMemset(faultPc, faultAddr)
    } else {
        // Invalid memory access - trap
        trapWithInvalidMemory(faultAddr)
    }
}
```

## Phase 9: Optimization

### 9.1 Compact Branch Encoding

Choose the shortest branch displacement encoding.

**Smart Jump Emission:**

```swift
func emitJump(_ visitor: inout CompilerVisitor, _ label: Label) {
    let currentOffset = visitor.assembler.code.count

    if let targetOffset = visitor.labelOffsets[label] {
        // Label already defined - can optimize
        let displacement = targetOffset - currentOffset

        // Use 8-bit relative jump if possible
        if displacement >= -128 && displacement <= 127 {
            // Emit: jmp rel8
            visitor.assembler.emitJmpRel8(Int8(displacement))
        } else {
            // Emit: jmp rel32
            visitor.assembler.emitJmpRel32(Int32(displacement))
        }
    } else {
        // Forward reference - must use rel32, create fixup
        visitor.assembler.emitJmpRel32Placeholder()
        visitor.fixups.append(Fixup(
            type: .jump,
            label: label,
            offset: currentOffset
        ))
    }
}
```

### 9.2 Memory Operand Optimization

Use efficient addressing modes.

**Optimization Guidelines:**

- Prefer RIP-relative addressing for global data access
- Use base + displacement for stack and structure access
- Avoid complex lea (load effective address) chains
- Leverage addressing mode: `[base + index*scale + displacement]`

### 9.3 Instruction Selection

Choose minimal instruction sequences.

**Example: Zero Register**

```
Better: xor reg, reg     # 2 bytes
Worse:  mov reg, 0       # 5-7 bytes
```

**Example: Load Immediate**

```
Small immediate: mov reg, imm32     # 5 bytes
Large immediate: mov reg, imm64     # 10 bytes
```

### 9.4 Caching

Reuse allocations across compilations to reduce overhead.

**Compiler Cache Structure:**

```swift
struct CompilerCache {
    var assemblerBuffer: [UInt8] = []       // Reused for code emission
    var labelMap: [UInt32: Label] = [:]    // Reused for labels
    var pcMapping: [(UInt32, UInt32)] = [] // Reused for mappings

    mutating func recycle() {
        assemblerBuffer.removeAll()
        labelMap.removeAll()
        pcMapping.removeAll()
    }
}
```

## Testing Strategy

### 1. Unit Tests

Test individual components in isolation:
- Instruction encoding/decoding
- Assembler emission
- Label resolution and fixup patching
- Gas calculation accuracy

### 2. Integration Tests

Test full compilation pipeline:
- Compile simple programs
- Verify native code correctness
- Check gas accounting accuracy

### 3. Comparison Tests

Compare against reference interpreter:

```swift
func testConsistency(_ blob: ProgramBlob) {
    // Run in interpreter
    let interpreterResult = interpretProgram(blob)

    // Run compiled code
    let compiledResult = executeCompiled(blob)

    // Should match
    assert(interpreterResult == compiledResult)
}
```

### 4. Fuzzing

Fuzz with random programs to find edge cases:
- Generate random valid programs
- Compare interpreter vs recompiler results
- Find discrepancies and fix bugs

### 5. Performance Tests

Benchmark and optimize:
- Compilation time
- Generated code size
- Execution speed
- Gas metering overhead

## Common Pitfalls

### 1. Sign Extension Errors

**Problem:** Incorrect sign-extension of immediates or loads
**Solution:** Use proper load instructions (load signed vs. unsigned) and check your encoding

### 2. PC Mapping Errors

**Problem:** Wrong PC → native offset mapping breaks trap recovery
**Solution:** Update mapping after EACH instruction, not just at block boundaries

### 3. Gas Stub Patching

**Problem:** Patching wrong offset in gas stub
**Solution:** Calculate offset carefully: instruction base + immediate displacement field offset

### 4. Register Clobbering

**Problem:** Trampolines clobber caller-save registers
**Solution:** Save/restore ALL VM registers in trampolines, not just callee-saved ones

### 5. Fault Recovery

**Problem:** Can't recover from gas trap properly
**Solution:** Ensure trap handler can identify faulting instruction location and refund gas correctly

### 6. Memory Alignment

**Problem:** Misaligned jumps cause crashes on some architectures
**Solution:** Align jump table entries to 8-byte boundaries

### 7. Forward Branches

**Problem:** Forward branch to undefined label fails
**Solution:** Always create fixup for forward references, resolve when label is defined

### 8. Indirect Jump Safety

**Problem:** Jump to invalid address corrupts state
**Solution:** Use non-canonical address (e.g., 0xFFFFFFFFFFFFFFFF) for invalid jump table entries

### 9. Memset Gas Accounting

**Problem:** Gas charged but memset only partially completed due to page fault
**Solution:** Slow path calculates bytes actually written, refunds remainder

### 10. Sandbox Violations

**Problem:** Guest code escapes sandbox boundaries
**Solution:** Use process isolation, fixed addresses, memory protection, and signal handling

## Performance Checklist

- [ ] Use compact branch encodings (rel8 when possible)
- [ ] Map common registers to compact instruction encodings
- [ ] Minimize register shuffling between operations
- [ ] Use efficient addressing modes (RIP-relative, etc.)
- [ ] Inline critical paths (memset, gas stubs)
- [ ] Cache and reuse allocations across compilations
- [ ] Minimize fixups by defining labels early when possible
- [ ] Batch gas cost patching
- [ ] Profile and optimize hot paths
- [ ] Use zero-register idiom (xor reg, reg)

## References

- [Architecture Overview](recompiler-architecture.md)
- [Deep Dive](recompiler-deep-dive.md)
- [AMD64 Backend](recompiler-amd64-backend.md)
- [Program Blob Format](program-blob-format.md)
- [Instruction Set](instruction-set-reference.md)
- [Gas Metering](recompiler-gas-traps.md)

## Example: Minimal Implementation

This guide provides complete information for implementing a PolkaVM recompiler. For additional details on specific topics, see:

- [Architecture Overview](recompiler-architecture.md) - High-level design
- [Deep Dive](recompiler-deep-dive.md) - Detailed implementation analysis
- [AMD64 Backend](recompiler-amd64-backend.md) - x86-64 specifics
- [Program Blob Format](program-blob-format.md) - Binary format
- [Instruction Set](instruction-set-reference.md) - Complete opcode reference
- [Gas Metering](recompiler-gas-traps.md) - Gas and trap handling

## Next Steps

1. Implement basic assembler with label support
2. Parse program blob format
3. Generate code for simple instructions (load_imm, add)
4. Add control flow (branches, jumps)
5. Implement memory operations
6. Add gas metering
7. Implement trampolines
8. Add fault handling
9. Optimize hot paths
10. Test thoroughly

Good luck with your implementation!
