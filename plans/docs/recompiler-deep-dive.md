PolkaVM Recompiler: Deep Dive with Code

Purpose: Explain, in one self-contained document, how the PolkaVM recompiler compiles bytecode to native code, executes it in a sandbox with strong isolation, meters gas, and handles traps/faults, including code snippets from core implementation points.

Sections
- Pipeline Overview
- Compiler Core
- Basic Blocks and Mapping
- Gas Metering
- Trampolines
- Indirect Jumps and Jump Table
- Memset and Gas Integration
- Trap and Fault Handling
- Sandboxing and VmCtx
- Register Mapping
- Memory Layout
- Optimizations

Pipeline Overview

At a high level, the engine chooses the compiled backend and sandbox, constructs a compilation driver (CompilerVisitor), visits the program instruction stream, and finalizes into a CompiledModule with native code and jump tables.

Example: backend selection and compilation process

The compilation macro expands to:
1. Define visitor type parameterized by sandbox kind, bitness, and gas mode
2. Create CompilerVisitor with:
   - Compiler cache reference
   - Configuration
   - Instruction set definition
   - Jump table from program blob
   - Code bytes from program blob
   - Bitmask from program blob
   - Exported functions
   - Step tracing flag (enabled if config.step_tracing or engine.crosscheck)
   - Code length as 32-bit value
   - Initialization data
   - Gas visitor with cost model
3. Visit the program blob with appropriate instruction set (with or without sbrk support)
4. Downcast global state for the sandbox
5. Finalize compilation to produce native module

Pseudocode:
```
func compileModule(engine: Engine, config: Config, blob: Blob,
                   exports: Exports, init: Init) -> CompiledModuleKind {
    let visitorType = CompilerVisitor<SandboxKind, Bitness, GasMode>.self

    let visitor = CompilerVisitor(
        compilerCache: engine.state.compilerCache,
        config: config,
        instructionSet: instructionSet,
        jumpTable: blob.jumpTable(),
        code: blob.code(),
        bitmask: blob.bitmask(),
        exports: exports,
        stepTracing: config.stepTracing || engine.crosscheck,
        codeLen: UInt32(blob.code().count),
        init: init,
        gasVisitor: GasVisitor(costModel: costModel.clone())
    )

    if config.allowSbrk {
        blob.visit(instructionSetWithSbrk, visitor)
    } else {
        blob.visit(instructionSetWithoutSbrk, visitor)
    }

    let globalState = downcastGlobalState(engine.state.sandboxGlobal)
    let module = visitor.finishCompilation(globalState: globalState,
                                          compilerCache: engine.state.compilerCache)

    return CompiledModuleKind(module)
}
```

Compiler Core

The CompilerVisitor orchestrates one compilation: it owns the assembler, labels, maps, gas visitor, and emits trampolines up front. It then starts the first basic block and records guest→native offset mapping as code is emitted.

Creation and trampoline emission

Initialize labels and emit trampolines:
- Declare forward labels for: ecall, trap, invalid_jump, step, jump_table, sbrk, memset
- Initialize visitor state fields
- Emit architecture-specific trampolines:
  * Trap trampoline
  * Ecall trampoline
  * Sbrk trampoline
  * Divrem trampoline (for division/remainder operations)
  * Memset trampoline (if gas metering enabled)
  * Step trampoline (if step tracing enabled)
- Record initial mapping: program counter 0 → current assembler offset
- Force start of first basic block at PC 0

Pseudocode:
```
init?(assembler: Assembler, config: Config, instructionSet: InstructionSet,
      jumpTable: JumpTable, code: Code, bitmask: Bitmask,
      exports: Exports, stepTracing: Bool, codeLen: UInt32,
      init: Init, gasVisitor: GasVisitor) {
    // Declare labels
    self.ecallLabel = assembler.forwardDeclareLabel()
    self.trapLabel = assembler.forwardDeclareLabel()
    self.invalidJumpLabel = assembler.forwardDeclareLabel()
    self.stepLabel = assembler.forwardDeclareLabel()
    self.jumpTableLabel = assembler.forwardDeclareLabel()
    self.sbrkLabel = assembler.forwardDeclareLabel()
    self.memsetLabel = assembler.forwardDeclareLabel()

    // Initialize visitor fields
    // ... (set up assembler, maps, gas visitor, etc.)

    // Emit trampolines
    ArchVisitor.emitTrapTrampoline(visitor: self)
    ArchVisitor.emitEcallTrampoline(visitor: self)
    ArchVisitor.emitSbrkTrampoline(visitor: self)

    if config.gasMetering != nil {
        self.memsetTrampolineStart = self.assembler.len()
        ArchVisitor.emitMemsetTrampoline(visitor: self)
        self.memsetTrampolineEnd = self.assembler.len()
    }

    if stepTracing {
        ArchVisitor.emitStepTrampoline(visitor: self)
    }

    // Record initial mapping
    self.programCounterToMachineCodeOffsetList.append(
        (PC(0), UInt32(self.assembler.len()))
    )

    // Start first basic block
    self.forceStartNewBasicBlock(0, self.isJumpTargetValid(0))
}
```

Finalization: gas patching, sysenter/sysreturn, and jump table

Finalization steps:
1. If gas metering enabled:
   - Iterate over gas metering stub offsets paired with basic block costs
   - For each stub, emit the cost immediate at the correct offset
2. Emit sysenter and sysreturn sequences
3. Allocate and initialize jump table:
   - Calculate alignment and length
   - Allocate jump table memory through sandbox
   - Fill prefix and suffix with invalid address sentinel

Pseudocode:
```
func finishCompilation(globalState: GlobalState, compilerCache: CompilerCache) throws -> CompiledModule {
    // Patch gas metering stubs with actual costs
    if gasMetering != nil {
        for (nativeCodeOffset, cost) in zip(gasMeteringStubOffsets, gasCostForBasicBlock) {
            ArchVisitor.emitWeight(nativeCodeOffset, cost)
        }
    }

    // Emit system entry/return points
    let labelSysenter = ArchVisitor.emitSysenter()
    let labelSysreturn = ArchVisitor.emitSysreturn()

    // Allocate and initialize jump table
    let vmCodeAddressAlignment = VM_CODE_ADDRESS_ALIGNMENT
    let jumpTableLength = (jumpTable.count + 1) * vmCodeAddressAlignment
    let nativeJumpTable = Sandbox.allocateJumpTable(globalState, jumpTableLength)

    // Fill guard regions with invalid address
    nativeJumpTable[0..<vmCodeAddressAlignment].fill(JUMP_TABLE_INVALID_ADDRESS)
    nativeJumpTable[jumpTableLength...].fill(JUMP_TABLE_INVALID_ADDRESS)

    // ... finalize and return compiled module ...
}
```

Basic Blocks and Mapping

Blocks begin at entry and after every terminating control-flow instruction. At block head, optional step tracing and the gas stub are emitted. After each instruction, the guest→native mapping is appended. When a block ends, the accumulated gas cost is captured.

Starting a new basic block:
1. If valid jump target:
   - If label already exists for this PC, define it
   - Otherwise create new label and record in PC→label map
2. If step tracing enabled, emit step trace
3. If gas metering enabled:
   - Record current assembler offset
   - Emit gas metering stub

After instruction processing:
1. Calculate next program counter
2. Record mapping: next PC → current assembler offset
3. If instruction ends basic block:
   - If gas metering enabled, capture accumulated block cost
   - Determine if next PC is valid jump target
   - Force start new basic block
4. Otherwise if step tracing enabled, emit step trace

Pseudocode:
```
func forceStartNewBasicBlock(programCounter: UInt32, isValidJumpTarget: Bool) {
    if isValidJumpTarget {
        if let label = programCounterToLabel[programCounter] {
            assembler.defineLabel(label)
        } else {
            let label = assembler.createLabel()
            programCounterToLabel[programCounter] = label
        }
    }

    if stepTracing {
        emitStepTrace(programCounter)
    }

    if gasMetering != nil {
        gasMeteringStubOffsets.append(UInt32(assembler.len()))
        ArchVisitor.emitGasMeteringStub(gasMetering)
    }
}

func afterInstruction(programCounter: UInt32, argsLength: UInt32, kind: ControlFlowKind) {
    let nextProgramCounter = programCounter + argsLength + 1
    programCounterToMachineCodeOffsetList.append(
        (PC(nextProgramCounter), UInt32(assembler.len()))
    )

    if kind != .continue {
        if gasMetering != nil {
            let cost = gasVisitor.takeBlockCost()
            gasCostForBasicBlock.append(cost)
        }

        let canJump = (kind != .endBasicBlockInvalid) &&
                      (nextProgramCounter < UInt32(code.count))
        forceStartNewBasicBlock(nextProgramCounter, canJump)
    } else if stepTracing {
        emitStepTrace(nextProgramCounter)
    }
}
```

Gas Metering

Each block starts with a stub that decrements `vmctx.gas` by a per-block immediate. In Sync mode the stub conditionally traps before the block executes. Costs are computed while visiting instructions and patched into the stub at finalization.

Codegen for gas stub and immediate patching

Gas metering stub generation:
- Emit subtraction instruction: `sub qword [vmctx.gas], 0x7fffffff`
- The immediate will be patched later with actual cost
- In Sync mode, emit conditional jump:
  * Linux sandbox: `jb -7` (jump back to invalid instruction to trap)
  * Generic sandbox: `jb -8` (similar trap mechanism)

Patching the immediate:
- Calculate length of the subtraction instruction
- Convert cost to little-endian bytes
- Overwrite the immediate bytes in the machine code

Assembly comments:
```
; Gas metering stub (initial form)
    sub qword [vmctx.gas], 0x7fffffff  ; immediate to be patched
    jb -7                             ; trap if underflow (Sync mode only)

; Patching process:
; 1. Calculate offset to immediate field
; 2. Write cost as 32-bit little-endian value
```

Pseudocode:
```
func emitGasMeteringStub(kind: GasMeteringKind) {
    let origin = assembler.len()

    // Emit: sub qword [vmctx.gas], 0x7fffffff
    // The immediate will be patched with actual cost later
    assembler.emitSubImm64(vmctxGasOffset, IMM32_MAX)

    if kind == .sync {
        if sandboxKind == .linux {
            // jb -7 (jump back into invalid instruction to trap)
            assembler.emitRawBytes([0x78, 0xf9])
        } else {
            // jb -8 (similar trap mechanism)
            assembler.emitRawBytes([0x78, 0xf6])
        }
    }
}

func emitWeight(offset: Int, cost: UInt32) {
    // Calculate where the immediate is in the subtraction instruction
    let instructionLength = lengthOfSubImm64Instruction()
    let immediateOffset = offset + instructionLength - 4

    // Patch the immediate with actual cost (little-endian)
    let costBytes = cost.littleEndianBytes
    assembler.codeMut()[immediateOffset..<immediateOffset+4] = costBytes
}
```

Naive gas visitor (accumulates cost per instruction and captures per-block totals)

Gas visitor structure:
- cost_model: reference to cost model with per-operation costs
- cost: accumulated cost for current basic block
- last_block_cost: captured cost for most recently completed block

Interface methods:
- take_block_cost(): return and clear last_block_cost
- is_at_start_of_basic_block(): check if cost == 0

Instruction visitor methods:
- For each instruction, add its cost from cost_model to accumulator
- After terminating instructions, call start_new_basic_block()
- This captures the accumulated cost in last_block_cost and resets accumulator

Pseudocode:
```
struct GasVisitor {
    let costModel: CostModel
    var cost: UInt32                    // accumulated for current block
    var lastBlockCost: UInt32?          // captured for completed block

    mutating func takeBlockCost() -> UInt32 {
        let result = lastBlockCost ?? 0
        lastBlockCost = nil
        return result
    }

    func isAtStartOfBasicBlock() -> Bool {
        return cost == 0
    }

    mutating func startNewBasicBlock() {
        lastBlockCost = cost
        cost = 0
    }

    // For each instruction type:
    mutating func visitInvalid() {
        cost += costModel.invalid
        startNewBasicBlock()
    }

    mutating func visitTrap() {
        cost += costModel.trap
        startNewBasicBlock()
    }

    mutating func visitFallthrough() {
        cost += costModel.fallthrough
        startNewBasicBlock()
    }

    mutating func visitMemset() {
        cost += costModel.memset
        // no block termination
    }

    mutating func visitEcalli(_ imm: UInt32) {
        cost += costModel.ecalli
        // no block termination
    }

    // ... similar for all other opcodes
}
```

Trampolines

These are the controlled host/guest boundaries. They save/restore registers to/from VmCtx and jump to fixed host entry points from the AddressTable.

sysenter/sysreturn

Sysenter (system entry - host to guest):
- Linux sandbox: load VMCTX register with fixed address
- Restore guest registers from VmCtx
- Jump to address in vmctx.next_native_program_counter

Assembly comments:
```
; Sysenter: enter guest code
    mov LINUX_SANDBOX_VMCTX_REG, VM_ADDR_VMCTX  ; Linux only
    restore_registers_from_vmctx()              ; load guest regs
    jmp [vmctx.next_native_program_counter]     ; jump to target
```

Sysreturn (system return - re-enter guest after host call):
- Clear vmctx.next_native_program_counter (set to 0)
- Save all registers to VmCtx
- Load syscall_return address from address table into temporary register
- Jump to syscall return handler

Assembly comments:
```
; Sysreturn: return to guest after host call
    mov [vmctx.next_native_program_counter], 0
    save_registers_to_vmctx()
    mov TMP_REG, AddressTable.syscall_return
    jmp TMP_REG
```

Actual implementation (simplified for ecall, trap, sbrk, step):

Ecall trampoline (guest makes system call):
- Save return address to VmCtx
- Save all registers to VmCtx
- Load syscall_hostcall address from address table
- Jump to host call handler

Assembly comments:
```
; Ecall trampoline
    save_return_address_to_vmctx()
    save_registers_to_vmctx()
    mov TMP_REG, AddressTable.syscall_hostcall
    jmp TMP_REG
```

Trap trampoline (guest traps):
- Save all registers to VmCtx
- Clear vmctx.next_native_program_counter
- Load syscall_trap address from address table
- Jump to trap handler

Assembly comments:
```
; Trap trampoline
    save_registers_to_vmctx()
    mov [vmctx.next_native_program_counter], 0
    mov TMP_REG, AddressTable.syscall_trap
    jmp TMP_REG
```

Sbrk trampoline (guest requests memory growth):
- Push temporary register to preserve it
- Save all registers to VmCtx
- Load syscall_sbrk address from address table
- Pop desired size into RDI (first argument register)
- Call sbrk handler
- Push result (RAX) to preserve it
- Restore guest registers from VmCtx
- Pop result into temporary register
- Return to guest

Assembly comments:
```
; Sbrk trampoline
    push TMP_REG
    save_registers_to_vmctx()
    mov TMP_REG, AddressTable.syscall_sbrk
    pop RDI              ; size argument
    call TMP_REG         ; returns new heap end in RAX
    push RAX             ; preserve result
    restore_registers_from_vmctx()
    pop TMP_REG          ; restore result
    ret
```

Step trampoline (tracing single instruction execution):
- Store current code offset in vmctx.program_counter
- Store current code offset in vmctx.next_program_counter
- Call step handler
- Uses reserved assembler space (exactly 3 instructions)

Assembly comments:
```
; Step trampoline (trace execution)
    mov [vmctx.program_counter], code_offset
    mov [vmctx.next_program_counter], code_offset
    call step_label
```

Pseudocode:
```
func emitEcallTrampoline() {
    saveReturnAddressToVmctx()
    saveRegistersToVmctx()
    emitMovImm64(TMP_REG, AddressTable.syscallHostcall)
    emitJmp(TMP_REG)
}

func emitTrapTrampoline() {
    saveRegistersToVmctx()
    emitMovImm(vmctx.nextNativeProgramCounter, 0)
    emitMovImm64(TMP_REG, AddressTable.syscallTrap)
    emitJmp(TMP_REG)
}

func emitSbrkTrampoline() {
    emitPush(TMP_REG)
    saveRegistersToVmctx()
    emitMovImm64(TMP_REG, AddressTable.syscallSbrk)
    emitPop(RDI)
    emitCall(TMP_REG)
    emitPush(RAX)
    restoreRegistersFromVmctx()
    emitPop(TMP_REG)
    emitRet()
}

func traceExecution(codeOffset: UInt32?) {
    // Reserve exactly 3 instructions
    let asm = assembler.reserve(3)
    asm.emitMovImm(vmctx.programCounter, codeOffset ?? 0)
    asm.emitMovImm(vmctx.nextProgramCounter, codeOffset ?? 0)
    asm.emitCallLabel32(stepLabel)
    asm.assertReservedExactly(3)
}
```

Indirect Jumps and Jump Table

Indirect jumps index a per-module native jump table. Linux uses `gs:` segment-based addressing; Generic materializes the table address and loads the target pointer.

Linux sandbox path (segment-based addressing):
1. Calculate target register (may need LEA if offset != 0)
2. Optionally restore return address
3. Emit indexed jump: `jmp [gs:target*8]`

Generic sandbox path (absolute addressing):
1. Load jump table address into temporary register using RIP-relative LEA
2. Push base register to preserve it
3. Shift base left by 3 (multiply by 8 for pointer size)
4. Add offset if needed
5. Add temporary register (table base) to base register
6. Restore base register
7. Load target pointer from table
8. Jump to target

Assembly comments:
```
; Linux sandbox: indirect jump via gs segment
    lea TMP_REG, [base_reg + offset]   ; if offset needed
    jmp [gs:TMP_REG*8]                 ; indexed jump through table

; Generic sandbox: indirect jump via absolute address
    lea TMP_REG, [rip + jump_table_label]
    push base_reg
    shl base_reg, 3                    ; multiply by 8
    add base_reg, offset*8             ; if offset > 0
    add TMP_REG, base_reg
    pop base_reg
    mov TMP_REG, [TMP_REG]             ; load target
    jmp TMP_REG
```

The invalid entry sentinel forces a CPU fault without clobbering RIP, simplifying recovery.

```
JUMP_TABLE_INVALID_ADDRESS = 0xfa6f29540376ba8a
```

This magic address is chosen to:
- Be in canonical address space (will fault on access)
- Not be a valid code address
- Be easily identifiable in crash dumps

Pseudocode:
```
func emitIndirectJump(baseReg: Register, offset: UInt32, loadImm: (Register, UInt32)?) {
    switch sandboxKind {
    case .linux:
        // Calculate target register
        if offset != 0 || loadImm?.0 == baseReg {
            emitLea(TMP_REG, [baseReg + offset])
            let targetReg = TMP_REG
        } else if bitness == .sixtyFour {
            emitMov(TMP_REG, baseReg)
            let targetReg = TMP_REG
        } else {
            let targetReg = baseReg
        }

        // Set return address if needed
        if let loadImm = loadImm {
            // ... restore return address ...
        }

        // Emit indexed jump
        emitJmpMemIndexed(Segment.GS, targetReg, scale: 8, offset: 0)

    case .generic:
        // Materialize table address
        emitLeaRipLabel(TMP_REG, jumpTableLabel)

        // Calculate index * 8
        emitPush(baseReg)
        emitShlImm(baseReg, 3)
        if offset > 0 {
            emitAdd(baseReg, offset * 8)
        }

        // Add table base and load target
        emitAdd(TMP_REG, baseReg)
        emitPop(baseReg)
        emitLoadU64(TMP_REG, [TMP_REG])
        emitJmp(TMP_REG)
    }
}
```

Memset and Gas Integration

Inline memset uses `rep stosb`; with gas metering, Sync mode pre-charges gas and branches to a slow trampoline if insufficient, Async subtracts and runs then lets the handler classify.

Fast path memset with gas metering:
1. Store resume address (RCX) in next_native_program_counter for safe recovery
2. Zero-extend count to 32 bits
3. Three modes:

No gas metering:
- Move count to RCX (rep stosb counter)
- Emit `rep stosb` (repeat store byte)
- Restore count register

Sync gas metering:
- Subtract count from gas
- Compare gas to 0
- Branch to slow trampoline if negative
- Execute fast `rep stosb`
- Restore count register

Async gas metering:
- Subtract count from gas
- Execute fast `rep stosb`
- Restore count register
- Handler will classify out-of-gas later

Assembly comments:
```
; Memset with gas metering (fast path)
    mov [vmctx.next_native_program_counter], rcx  ; save resume address
    mov count_reg, count_reg                      ; zero-extend

    ; Sync mode: pre-check gas
    sub [vmctx.gas], count
    cmp [vmctx.gas], 0
    jb memset_slow_trampoline

    ; Fast memset
    mov rcx, count
    rep stosb                    ; [rdi] = al, repeat rcx times
    mov count_reg, rcx
```

Slow trampoline (used when gas insufficient in Sync mode):
- Zero RCX
- Exchange RCX with gas (gets negative gas, sets gas to 0)
- Add negative gas to count (now has remaining allowed bytes)
- Subtract allowed bytes from count (now has overflow bytes)
- Store remaining allowed bytes in vmctx.arg
- Execute `rep stosb` with partial count
- Save registers and trap to not_enough_gas

Assembly comments:
```
; Memset slow trampoline (insufficient gas)
    xor rcx, rcx
    xchg rcx, [vmctx.gas]        ; rcx = -gas, gas = 0
    add rcx, count               ; rcx = count - gas (remaining allowed)
    sub count, rcx               ; count = overflow bytes
    mov [vmctx.arg], rcx         ; store remaining for handler
    rep stosb                    ; fill allowed bytes
    save_registers_to_vmctx()
    mov TMP_REG, AddressTable.syscall_not_enough_gas
    jmp TMP_REG
```

Pseudocode:
```
func emitMemset() {
    // Stash resume address for safe recovery
    emitStore(vmctx.nextNativeProgramCounter, rcx)

    let count = convReg(A2)
    emitMov(count, count)  // zero-extend

    switch gasMetering {
    case nil:
        emitMov(rcx, count)
        emitRepStosb()  // fills [rdi] with al, rcx times
        emitMov(count, rcx)

    case .sync:
        // Pre-charge gas
        emitSub(vmctx.gas, count)
        emitCmp(vmctx.gas, 0)
        emitBranchIfLess(memsetLabel)

        // Fast path
        emitMov(rcx, count)
        emitRepStosb()
        emitMov(count, rcx)

    case .async:
        // Subtract gas, run anyway
        emitSub(vmctx.gas, count)
        emitMov(rcx, count)
        emitRepStosb()
        emitMov(count, rcx)
    }
}

func emitMemsetTrampoline() {
    // RCX = negative gas budget
    emitXor(rcx, rcx)
    emitXchg(rcx, [vmctx.gas])  // rcx = -gas, gas = 0

    // Compute allowed bytes
    emitAdd(rcx, A2)            // remaining = A2 - gas
    emitSub(A2, rcx)            // A2 = overflow

    // Store remaining for handler
    emitStore(vmctx.arg, rcx)

    // Fill allowed bytes
    emitRepStosb()

    // Trap
    saveRegistersToVmctx()
    emitMovImm64(TMP_REG, AddressTable.syscallNotEnoughGas)
    emitJmp(TMP_REG)
}
```

Trap and Fault Handling

Linux sandbox signal handlers classify traps (memset, out-of-gas, regular), set guest and native PCs for recovery, and refund pre-charged gas by reading the stub immediate from machine code.

Signal trap handler classification:
1. Determine trap kind:
   - If executing memset: classify as memset trap
   - Else if gas metering enabled and gas < 0: not enough gas
   - Else: regular trap

2. Handle each kind:
   NotEnoughGas:
   - Calculate gas stub offset (subtract trap offset from machine code offset)
   - Set next_native_program_counter to stub location (for resume)
   - Find guest program counter using binary search in PC→native mapping
   - Extract gas cost immediate from machine code (4 bytes at specific offset)
   - Refund gas by adding cost back to gas counter
   - Return true (will resume execution)

   Trap:
   - Find guest program counter
   - Set next_native_program_counter to 0 (won't resume)
   - Return false (terminated)

   Memset:
   - Handle memset interruption with partial fill
   - Set next_native_program_counter to 0
   - Return false (terminated)

Page fault handler:
1. Check if executing memset
   - If yes: handle memset interruption
   - If no: set PC for recovery, set next_native_program_counter to fault address

Pseudocode:
```
func onSignalTrap(compiledModule: CompiledModule,
                  isGasMeteringEnabled: Bool,
                  machineCodeOffset: UInt64,
                  vmctx: VmCtx) throws -> Bool {
    // Classify trap kind
    let trapKind: TrapKind
    if isExecutingMemset(compiledModule, machineCodeOffset) {
        trapKind = .memset(kind)
    } else if isGasMeteringEnabled && vmctx.gas < 0 {
        trapKind = .notEnoughGas
    } else {
        trapKind = .trap
    }

    switch trapKind {
    case .notEnoughGas:
        // Calculate where gas stub is
        let offset = machineCodeOffset &- GAS_METERING_TRAP_OFFSET
        if offset &> machineCodeOffset {
            throw Error.addressUnderflow
        }

        // Set resume point to gas stub
        vmctx.nextNativeProgramCounter =
            compiledModule.nativeCodeOrigin + offset

        // Find guest PC
        let programCounter =
            setProgramCounterAfterInterruption(
                compiledModule, machineCodeOffset, vmctx
            )

        // Refund gas: read immediate from machine code
        let costOffset = offset + GAS_COST_LINUX_SANDBOX_OFFSET
        let gasCostBytes = compiledModule.machineCode()[costOffset..<costOffset+4]
        let gasCost = UInt32(littleEndian: gasCostBytes)

        vmctx.gas += Int64(gasCost)
        return true  // will resume

    case .trap:
        setProgramCounterAfterInterruption(
            compiledModule, machineCodeOffset, vmctx
        )
        vmctx.nextNativeProgramCounter = 0
        return false  // terminated

    case .memset:
        handleInterruptionDuringMemset(
            kind, compiledModule, isGasMeteringEnabled,
            machineCodeOffset, vmctx
        )
        vmctx.nextNativeProgramCounter = 0
        return false  // terminated
    }
}

func onPageFault(compiledModule: CompiledModule,
                 isGasMeteringEnabled: Bool,
                 machineCodeAddress: UInt64,
                 machineCodeOffset: UInt64,
                 vmctx: VmCtx) throws -> Success {
    if isExecutingMemset(compiledModule, machineCodeOffset) {
        handleInterruptionDuringMemset(
            kind, compiledModule, isGasMeteringEnabled,
            machineCodeOffset, vmctx
        )
    } else {
        setProgramCounterAfterInterruption(
            compiledModule, machineCodeOffset, vmctx
        )
        vmctx.nextNativeProgramCounter = machineCodeAddress
    }
    return .success
}
```

Sandboxing and VmCtx

The Linux sandbox runs compiled code in a separate worker process (zygote model) with shared VmCtx and fixed 64‑bit addresses for code and data structures unreachable to 32‑bit guest code. Codegen uses an AddressTable and OffsetTable for portable field access and host calls.

Address table and fixed virtual addresses

Address table contains function pointers to host handlers:
- syscall_hostcall: guest makes system call
- syscall_trap: guest traps
- syscall_return: return to guest after host call
- syscall_step: single-step tracing
- syscall_sbrk: request memory growth
- syscall_not_enough_gas: gas exhausted handler

Fixed virtual addresses:
```
VM_ADDR_NATIVE_CODE = 0x100000000  (4 GB)
VM_ADDR_JUMP_TABLE = 0x800000000   (32 GB)
VM_ADDR_VMCTX = 0x400000000       (16 GB)
VM_ADDR_SIGSTACK = 0x500000000    (signal stack)
```

These addresses:
- Are in 64-bit range unreachable to 32-bit guest code
- Allow direct addressing without register loading
- Are consistent across all sandbox instances

Offset table (Linux sandbox)

Offset table contains byte offsets of VmCtx fields for portable access:
- arg: offset of arg field
- gas: offset of gas field
- heap_info: offset of heap_info field
- next_native_program_counter: offset of next native PC
- next_program_counter: offset of next guest PC
- program_counter: offset of current guest PC
- regs: offset of registers array

Key VmCtx fields used by codegen and handlers

VmCtx structure fields:
- futex: atomic u32 - for synchronization
- program_counter: atomic u32 - current guest PC
- jump_into: atomic u64 - indirect jump target
- next_native_program_counter: atomic u64 - where to resume after trap
- tmp_reg: atomic u64 - temporary register storage
- rip: atomic u64 - instruction pointer (for signal recovery)
- next_program_counter: atomic u32 - next guest PC to execute
- arg: atomic u32 - argument register for host calls
- gas: atomic i64 - gas remaining (signed for underflow detection)
- regs: array of atomic u64 - guest registers
- heap_info: VmCtxHeapInfo - heap bounds and growth info
- sysreturn_address: atomic u64 - sysreturn trampoline address
- Plus: mapping metadata, counters, initialization data, message buffer

Register Mapping

Guest registers are mapped to host registers to minimize encoding size for common operations. Temps use rcx/r15.

Register mapping (guest → x86-64):
```
A0 → rdi    (first argument)
A1 → rax    (return value)
SP → rsi    (stack pointer)
RA → rbx    (return address)
A2 → rdx    (second argument)
A3 → rbp    (third argument)
S0 → r8     (saved register 0)
S1 → r9     (saved register 1)
A4 → r10    (fourth argument)
A5 → r11    (fifth argument)
T0 → r13    (temporary 0)
T1 → r14    (temporary 1)
T2 → r12    (temporary 2)
```

Temporary registers:
```
TMP_REG = rcx      // free temporary, doesn't need saving
AUX_TMP_REG = r15  // must save/restore around calls
```

This mapping optimizes for:
- Common instructions have short encodings (RAX, RCX, RDX, RBP, RSI, RDI)
- Arguments in standard calling convention registers
- Return value in RAX
- Stack pointer in RSI

Actual implementation:

Memory Layout

The VM exposes a 32‑bit guest address space with RO/RW regions, heap, stack, and an AUX region, separated by guard pages. A sentinel address returns to host when jumped to.

```
VM_ADDR_RETURN_TO_HOST = 0xffff0000  // jump here to return to host
```

Memory map (laid out by MemoryMapBuilder):
```
[guard] [ro_data] [guard] [rw_data] [guard] [stack] [guard] [aux] [guard]
```

Regions:
- Guard pages: unmapped pages that trap on access
- RO data: read-only code and constants
- RW data: read-write data segment
- Stack: guest stack (grows downward)
- AUX: auxiliary region for metadata

MemoryMapBuilder computes:
- heap_base: start of heap region
- stack bounds: valid stack range
- aux region: location and size
- Guard page placement between regions

Optimizations

Compact branches: Codegen analyzes label distances to pick 8‑bit vs. 32‑bit displacements.

Branch displacement calculation:
1. Calculate offset for 8-bit relative: target - (current_position + 1_byte_opcode + 1_byte_displacement)
2. Check if offset fits in signed 8-bit range (-128 to +127)
3. If yes, use 8-bit displacement (shorter encoding)
4. If no, use 32-bit displacement

For jumps:
1. Try to use 8-bit displacement
2. If label not yet resolved or out of range:
   - For conditional branch: emit safe self-trap
   - For unconditional jump: emit 32-bit label fixup

Pseudocode:
```
func calculateLabelOffset(asmLen: Int, rel8Len: Int, rel32Len: Int,
                          offset: Int) -> Result<Int8, Int32> {
    // Calculate offset for 8-bit displacement
    let offsetNear = offset - (asmLen + rel8Len)

    // Check if fits in i8 range
    if offsetNear >= -128 && offsetNear <= 127 {
        return .success(Int8(offsetNear))
    } else {
        // Calculate offset for 32-bit displacement
        let offsetFar = offset - (asmLen + rel32Len)
        return .error(Int32(offsetFar))
    }
}

func branchToLabel(assembler: Assembler, condition: Condition, label: Label) {
    // Try to use 8-bit displacement
    if label.isResolved() {
        let displacement = label.offset - assembler.len() - 2
        if displacement >= -128 && displacement <= 127 {
            emitBranchShort(condition, displacement)
        } else {
            emitBranchNear(condition, displacement)
        }
    } else {
        // Label not resolved - emit safe trap that will be patched
        emitSelfTrap()
        // ... add fixup record for later patching ...
    }
}

func jumpToLabel(assembler: Assembler, label: Label) {
    // Similar logic for unconditional jumps
    if label.isResolved() {
        let displacement = label.offset - assembler.len() - 5
        if displacement >= -128 && displacement <= 127 {
            emitJumpShort(displacement)
        } else {
            emitJumpNear(displacement)
        }
    } else {
        // Emit 32-bit fixup
        emitJumpNearPlaceholder()
        // ... add fixup record ...
    }
}
```

Additional optimizations:

1. Addressing forms:
   - Linux sandbox uses `gs:` segment for jump table access
   - Avoids materializing table address in register
   - Generic sandbox must materialize address

2. Register mapping:
   - Places frequently-used operands in registers with compact encodings
   - Arguments in standard calling convention registers
   - Minimizes REX prefix usage

3. Gas stub patching:
   - Emit identical stub at each block start
   - Record offsets in vector
   - Patch all immediates in bulk at finalization
   - Reduces code size and enables precise gas refunds

4. Memset fast path:
   - Uses `rep stosb` for optimal performance
   - Single instruction fills arbitrary length
   - Minimizes register pressure
   - Slow path only triggered on gas exhaustion

5. Caching:
   - Reuse assembler buffers across compilations
   - Reuse label and mapping data structures
   - Reduces allocation overhead

End-to-End Summary

1) Engine selects compiled backend and sandbox, builds CompilerVisitor with a GasVisitor and arch backend.

2) Program is visited:
   - Instructions are lowered to native code
   - Guest→native mapping is recorded after each instruction
   - Block heads emit gas stubs (if gas metering enabled)
   - Block terminations capture accumulated gas cost

3) Finalization:
   - Gas immediates are patched into stubs
   - Trampolines are bound to labels
   - Jump table is allocated and initialized with invalid sentinel

4) Execution:
   - Sysenter restores guest registers and jumps into native code
   - Hostcalls/traps/page faults cross via trampolines to host
   - Signal handlers classify fault and either:
     * Resume execution (for out-of-gas with refund)
     * Terminate execution (for traps or page faults)
   - Sync gas stubs refund pre-charged gas precisely by reading immediates
