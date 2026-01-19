Gas Metering, Trampolines, and Traps

Gas Metering

Gas metering limits guest execution by charging costs for operations. The recompiler inserts a stub at the beginning of each basic block that decrements the gas counter and checks for underflow.

Stub Structure (Synchronous Mode):
```swift
// Pseudocode: synchronous gas metering stub
func emitGasStubSync(vmctx: VmCtx, blockCost: UInt64) {
    // Load current gas counter
    mov [vmctx.gas] -> rax

    // Subtract block cost
    sub blockCost -> rax

    // Check for underflow (overflow flag set if rax went negative)
    jo gasTrapLabel

    // Store updated counter
    mov rax -> [vmctx.gas]

    // Continue with basic block
    // ... rest of block instructions ...

gasTrapLabel:
    // Gas exhausted: jump to trap handler
    jmp syscallTrap
}
```

Stub Structure (Asynchronous Mode):
```swift
// Pseudocode: asynchronous gas metering stub
func emitGasStubAsync(vmctx: VmCtx, blockCost: UInt64) {
    // Load and decrement without immediate check
    mov [vmctx.gas] -> rax
    sub blockCost -> rax
    mov rax -> [vmctx.gas]

    // Continue with basic block
    // Handler will check for negative gas later
}
```

Key Differences Between Modes:

Synchronous (Pre-Check):
- Detects gas exhaustion immediately via overflow flag
- Branches to trap path before executing any block instructions
- No risk of executing partial work with insufficient gas
- Slight overhead: branch instruction in fast path

Asynchronous (Post-Check):
- Executes block instructions regardless of gas state
- Handler detects negative gas after execution
- Better performance (no branch in stub)
- Risk: partial work may complete before gas exhaustion detected

Cost Computation:
```swift
// During parsing: accumulate costs per basic block
struct GasVisitor {
    var currentBlockCost: UInt64
    var instructionCosts: [Instruction: UInt64]
}

extension GasVisitor {
    mutating func visitInstruction(_ instruction: Instruction) {
        let cost = instructionCosts[instruction]!
        currentBlockCost += cost
    }

    mutating func finishBlock() -> UInt64 {
        let cost = currentBlockCost
        currentBlockCost = 0
        return cost
    }
}

// During finalization: patch the immediate operand
func patchGasImmediates(_ compiler: inout CompilerVisitor) {
    for (basicBlock, cost) in compiler.blockCosts {
        // Patch the subtract immediate with computed cost
        compiler.assembler.patchImmediate(
            basicBlock.gasStubLabel,
            cost
        )
    }
}
```

VmCtx Layout:
```swift
// Pseudocode: VmCtx structure
struct VmCtx {
    var gas: UInt64                      // Gas counter
    var programCounter: UInt32           // Current guest PC
    var nextNativeProgramCounter: UInt64 // Resume address after trap
    var registers: [UInt64]              // Guest register file (size: 32)
    // ... other fields ...
}
```

Memset Integration

Memset (memory initialization) requires special handling due to its variable-cost nature. The inline implementation uses `rep stosb`, which fills memory with a specified value for a specified count.

Inline Memset with Gas:
```swift
// Pseudocode: inline memset with synchronous gas
func emitMemsetSync(dest: UnsafeMutablePointer<UInt8>, value: UInt8, count: UInt64, vmctx: VmCtx) {
    // Pre-charge gas for full memset operation
    let totalCost = count * MEMSET_PER_BYTE_COST

    mov [vmctx.gas] -> rax
    sub totalCost -> rax
    jo memsetSlowPath  // Not enough gas: go to trampoline

    // Sufficient gas: execute inline memset
    mov rax -> [vmctx.gas]  // Save updated gas
    mov count -> rcx
    mov value -> al
    mov dest -> rdi
    rep stosb  // Fill [rdi] with al, rcx times
    ret

memsetSlowPath:
    // Trampoline: compute partial memset
    mov totalCost -> rdx  // Save original cost
    mov count -> rcx       // Save original count

    // Refund the pre-charged gas
    mov [vmctx.gas] -> rax
    add rdx -> rax
    mov rax -> [vmctx.gas]

    // Compute bytes possible with remaining gas
    mov [vmctx.gas] -> rax
    xor rdx -> rdx
    div MEMSET_PER_BYTE_COST  // rax = bytes possible

    // Execute partial memset
    mov rax -> rcx
    mov value -> al
    mov dest -> rdi
    rep stosb

    // Stash remaining count for later retry
    mov rcx -> [vmctx.memsetRemainingCount]

    // Invoke NotEnoughGas syscall to pause execution
    mov SYSCALL_NOT_ENOUGH_GAS -> rax
    call AddressTable[SYSCALL_NOT_ENOUGH_GAS]
}
```

Asynchronous Memset:
```swift
// Pseudocode: inline memset with asynchronous gas
func emitMemsetAsync(dest: UnsafeMutablePointer<UInt8>, value: UInt8, count: UInt64, vmctx: VmCtx) {
    // Simply subtract cost without check
    let totalCost = count * MEMSET_PER_BYTE_COST

    mov [vmctx.gas] -> rax
    sub totalCost -> rax
    mov rax -> [vmctx.gas]

    // Execute memset regardless of gas state
    mov count -> rcx
    mov value -> al
    mov dest -> rdi
    rep stosb
    ret

    // Handler will detect negative gas and handle it
}
```

Slow Path Trampoline Details:
- Computes how many bytes can be filled with remaining gas
- Executes partial memset for that many bytes
- Stores remaining count in VmCtx for retry
- Invokes NotEnoughGas syscall to yield to host
- On resume: gas has been replenished, retry remaining bytes

Trampolines

Trampolines are small stubs that transition from guest code execution to host runtime services. They save guest state and invoke appropriate handlers.

1. Trap Trampoline:
```swift
// Pseudocode: trap trampoline
func emitTrapTrampoline() {
    // Save all guest registers
    for reg in GUEST_REGISTERS {
        mov reg -> [vmctx.registers + regOffset(reg)]
    }

    // Clear nextNativeProgramCounter to prevent resume
    mov 0 -> [vmctx.nextNativeProgramCounter]

    // Jump to trap handler
    jmp AddressTable[SYSCALL_TRAP]
}
```

Triggered by:
- Out-of-gas (synchronous mode)
- Execution faults (invalid memory access, illegal instruction)
- Explicit trap instructions
- Assertion failures

2. Ecall Trampoline:
```swift
// Pseudocode: ecall (host call) trampoline
func emitEcallTrampoline() {
    // Save return address (next guest instruction)
    mov returnAddress -> [vmctx.nextNativeProgramCounter]

    // Save all guest registers
    for reg in GUEST_REGISTERS {
        mov reg -> [vmctx.registers + regOffset(reg)]
    }

    // Load syscall number from guest register
    mov SYSCALL_NUM_REG -> rax

    // Jump to hostcall handler
    jmp AddressTable[SYSCALL_HOSTCALL]
}
```

Used for:
- I/O operations (read, write, seek)
- Environment queries (get args, get env vars)
- Time queries (clock, sleep)
- Cryptographic operations
- Other host services

3. Sbrk Trampoline:
```swift
// Pseudocode: sbrk (memory allocation) trampoline
func emitSbrkTrampoline() {
    // Save minimal state (leaf function)
    push rax
    push rcx
    push rdx
    push r11

    // Move requested size to appropriate register
    mov ALLOCATION_SIZE_REG -> rdi

    // Invoke host allocator
    call AddressTable[SYSCALL_SBRK]

    // Restore and return
    pop r11
    pop rdx
    pop rcx
    pop rax
    ret
}
```

Optimized as leaf function because:
- No need to save full guest state (doesn't trap)
- Returns directly to guest code
- Minimal register saving for ABI compliance

4. Step Trampoline:
```swift
// Pseudocode: step (single-step debug) trampoline
func emitStepTrampoline() {
    // Save return address (next guest instruction)
    mov returnAddress -> [vmctx.nextNativeProgramCounter]

    // Save all guest registers
    for reg in GUEST_REGISTERS {
        mov reg -> [vmctx.registers + regOffset(reg)]
    }

    // Jump to step handler
    jmp AddressTable[SYSCALL_STEP]
}
```

Used for:
- Single-stepping debuggers
- Breakpoint handling
- Instruction-level tracing
- Performance profiling

5. Sysenter Bridge (Host → Guest Entry):
```swift
// Pseudocode: sysenter (resume guest execution)
func emitSysenter() {
    // Restore guest registers
    for reg in GUEST_REGISTERS {
        mov [vmctx.registers + regOffset(reg)] -> reg
    }

    // Load continuation address
    mov [vmctx.nextNativeProgramCounter] -> rax

    // Jump back to guest code
    jmp rax
}
```

Used when:
- Hostcall completes and execution should resume
- After gas replenishment
- After memory allocation succeeds
- Resuming from breakpoint

6. Sysreturn Bridge (Guest → Host Exit):
```swift
// Pseudocode: sysreturn (exit to host)
func emitSysreturn() {
    // Save guest registers
    for reg in GUEST_REGISTERS {
        mov reg -> [vmctx.registers + regOffset(reg)]
    }

    // Save return address (next guest instruction)
    mov returnAddress -> [vmctx.nextNativeProgramCounter]

    // Jump to syscall return handler
    jmp AddressTable[SYSCALL_RETURN]
}
```

Used when:
- Guest explicitly returns from main function
- Guest requests termination
- Fatal error requiring host intervention

Trap and Fault Handling (Linux)

The Linux sandbox uses signal handlers to intercept and recover from execution faults. Two primary hooks handle different scenarios.

1. Signal Trap Handler:
```swift
// Pseudocode: signal trap handler
func onSignalTrap(signal: SignalInfo, vmctx: inout VmCtx) -> Bool {
    let faultAddress = signal.faultAddress
    let faultInstruction = signal.faultInstruction

    // Determine trap cause by inspecting fault site
    if isMemsetInstruction(faultInstruction) {
        // Fault in inline memset: gas exhausted mid-operation
        handleMemsetTrap(signal, &vmctx)
        return true  // Recoverable
    }

    if isMemsetTrampoline(faultInstruction) {
        // Fault in memset trampoline: not enough gas for partial memset
        handleMemsetTrampolineTrap(signal, &vmctx)
        return true  // Recoverable
    }

    if isGasStub(faultInstruction) {
        // Fault in gas metering stub: out-of-gas
        handleGasTrap(signal, &vmctx)
        return true  // Recoverable (refunds and retries)
    }

    // Unknown fault: not recoverable
    vmctx.nextNativeProgramCounter = 0  // Prevent resume
    return false
}

func handleGasTrap(signal: SignalInfo, vmctx: inout VmCtx) {
    // Refund the block cost that was just subtracted
    let faultInstruction = signal.faultInstruction
    let blockCost = readImmediateAt(faultInstruction)

    // Read current (negative) gas
    let currentGas = vmctx.gas

    // Refund the block cost
    vmctx.gas = currentGas + blockCost

    // Set PC to current instruction for retry
    vmctx.programCounter = signal.guestPC

    // Set nextNativeProgramCounter to retry after replenishment
    vmctx.nextNativeProgramCounter = signal.nativeAddress
}
```

Recoverable traps:
- Out-of-gas (synchronous)
- Memset with insufficient gas
- Recoverable page faults (see below)

Non-recoverable traps:
- Division by zero
- Invalid memory access (not page fault)
- Illegal instruction
- Stack overflow

2. Page Fault Handler:
```swift
// Pseudocode: page fault handler
func onPageFault(fault: PageFaultInfo, vmctx: inout VmCtx) {
    let faultAddress = fault.address
    let faultInstruction = fault.instruction

    // Special case: memset page fault
    if isMemsetInstruction(faultInstruction) {
        // Memset crossed page boundary into unmapped page
        handleMemsetPageFault(fault, &vmctx)
        return
    }

    // Standard page fault: request memory from host
    // Save state for retry after mapping
    vmctx.programCounter = fault.guestPC
    vmctx.nextNativeProgramCounter = fault.nativeAddress

    // Request page mapping from host
    invokeSyscall(SYSCALL_MAP_PAGE, faultAddress)
}

func handleMemsetPageFault(fault: PageFaultInfo, vmctx: inout VmCtx) {
    // Memset faulted: compute bytes already set
    let destReg = readDestRegister(fault.instruction)
    let countReg = readCountRegister(fault.instruction)

    let bytesCompleted = fault.address - destReg
    let remainingBytes = countReg - bytesCompleted

    // Update memset state for retry
    vmctx.memsetRemainingCount = remainingBytes
    vmctx.memsetDest = fault.address

    // Request page mapping
    invokeSyscall(SYSCALL_MAP_PAGE, faultAddress)
}
```

Address Table and Offset Table:
```swift
// Pseudocode: sandbox-provided tables
struct AddressTable {
    var syscallTrap: NativeAddress
    var syscallHostcall: NativeAddress
    var syscallSbrk: NativeAddress
    var syscallStep: NativeAddress
    var syscallReturn: NativeAddress
    var syscallMapPage: NativeAddress
    var syscallNotEnoughGas: NativeAddress
    // ... more syscalls ...
}

struct OffsetTable {
    var vmctxGas: UInt32
    var vmctxProgramCounter: UInt32
    var vmctxNextNativeProgramCounter: UInt32
    var vmctxRegisters: UInt32
    // ... more offsets ...
}

// Code generation uses these to access VmCtx
// Linux backend (GS segment):
mov gs:[OffsetTable.vmctxGas] -> rax

// Generic backend (absolute address):
mov [VmCtxBase + OffsetTable.vmctxGas] -> rax
```

Invalid Dynamic Jumps

Indirect jumps (computed goto, jump tables) use a host-provided jump table. Invalid entries point to a special trap address that causes an immediate, recoverable fault.

```swift
// Pseudocode: jump table setup
let JUMP_TABLE_INVALID_ADDRESS: UInt64 = 0xFFFFFFFFFFFFFFFF

// At compile time: populate jump table
func setupJumpTable(_ jumpTable: inout JumpTable, codeMask: Bitmask) {
    for pc in 0..<MAX_CODE_SIZE {
        if codeMask.isValid(pc) {
            // Valid target: use actual native address
            jumpTable[pc] = resolveLabel(pc)
        } else {
            // Invalid target: use trap address
            jumpTable[pc] = JUMP_TABLE_INVALID_ADDRESS
        }
    }
}
```

Why this address is special:
- Exceeds canonical address width on x86-64 (only 48 bits used)
- CPU faults immediately when attempting to jump to it
- Fault occurs before instruction execution, preserving register state
- RIP is not clobbered, making recovery straightforward
- Signal handler can identify and handle the fault

Runtime execution:
```swift
// Pseudocode: indirect jump execution
// Guest code computes target PC
mov guestTargetPC -> rax

// Load native address from jump table
// Linux backend:
mov gs:[JumpTable + rax * 8] -> rax

// Generic backend:
lea jumpTableBase -> r11
mov [r11 + rax * 8] -> rax

// Jump to target (or fault if invalid)
jmp rax
```

Fault recovery:
```swift
// Signal handler detects invalid jump
func onInvalidJumpFault(fault: FaultInfo, vmctx: inout VmCtx) {
    // Check if fault address is the invalid jump marker
    if fault.targetAddress == JUMP_TABLE_INVALID_ADDRESS {
        // Invalid jump: trap guest
        vmctx.nextNativeProgramCounter = 0
        vmctx.trapReason = TrapReason.invalidJump
        return
    }

    // Other fault type: handle normally
    handleOtherFault(fault, &vmctx)
}
```

This design provides:
- Safety: invalid jumps cannot jump to arbitrary host code
- Performance: valid jumps are direct table lookups
- Debuggability: invalid jumps cause immediate, identifiable faults
- Simplicity: no need for explicit bounds checking in fast path

