Recompiler Architecture Overview

High-Level Flow

1. Backend Selection: The engine dynamically chooses between compiled and interpreter modes based on configuration and module capabilities. The compiled backend is selected when native code generation is available and beneficial for performance.

2. Compilation Initialization:
```swift
// Pseudocode: compilation setup
func compileModule(isa: ISA, codeBlob: CodeBlob, bitmask: Bitmask, exports: Exports, config: Config) -> CompiledModule {
    let compiler = CompilerVisitor(isa: isa, config: config)
    let gasVisitor = GasVisitor(gasMode: config.gasMode)

    for instruction in codeBlob {
        compiler.visit(instruction, gasVisitor)
    }

    return compiler.finish()
}
```

3. Instruction Dispatch: The program blob's instruction stream is dispatched to the CompilerVisitor, which implements a visitor pattern for parsing. This component:
   - Tracks gas consumption via GasVisitor
   - Delegates architecture-specific instruction lowering to ArchVisitor
   - Maintains mappings between guest program counters and native code offsets
   - Tracks basic block boundaries and labels

4. Finalization: The compilation process concludes by emitting function epilogues, generating trampolines for host/guest transitions, finalizing gas metering weights, constructing jump tables for indirect branches, and returning a CompiledModule containing the native code and metadata.

Core Components

1. CompilerVisitor (Architecture-Agnostic Driver):
   - Manages the entire compilation process for a single module
   - Maintains compilation state: basic blocks, labels, PC mappings
   - Orchestrates trampoline generation for system calls and traps
   - Coordinates with architecture-specific backends
   - Assembles final machine code from emitted instructions
   - Typical lifecycle: initialize → visit instructions → finalize

2. ArchVisitor (Architecture-Specific Backend):
   - Implements instruction selection for target ISA (e.g., x86-64)
   - Translates guest instructions to native machine code
   - Manages register allocation and instruction scheduling
   - Emits encoded instructions to the assembler buffer
   - Handles architecture-specific constraints (e.g., x86-64 RIP-relative addressing)

3. Assembler and Encoders:
   - Provides compact, type-safe instruction builders
   - Manages label resolution and backpatching
   - Encodes instructions according to ISA specifications
   - Handles complex addressing modes and immediates

4. Sandbox Abstraction:
   - Provides platform-specific syscall entry points
   - Defines VmCtx memory layout for guest state access
   - Linux backend: uses GS-segment addressing for fast VmCtx access
   - Generic backend: uses absolute addressing with explicit table materialization
   - Abstracts differences in fault handling and signal interception

5. GasVisitor:
   - Tracks per-instruction gas costs during parsing
   - Accumulates costs per basic block
   - Supports synchronous (pre-check) and asynchronous (post-check) modes
   - Emits gas metering stubs for each basic block

Key Data Flow

```
Guest Bytecode
    ↓
Program Blob Parser
    ↓
CompilerVisitor (implements ParsingVisitor)
    ├→ GasVisitor (track costs)
    ├→ ArchVisitor (lower to native)
    │      ↓
    │   Assembler Buffer
    │
    ├→ Label/Block Tracking
    └→ PC → Native Offset Mapping
```

At each basic block start:
1. Optional step tracing hook (if debugging enabled)
2. Gas metering stub (if gas metering active)
3. Native instructions for block body
4. After each instruction: record (guest_PC, native_offset) mapping

Finalization phase:
1. Patch gas immediates with computed costs
2. Allocate and populate jump table for indirect branches
3. Emit system call entry/exit trampolines
4. Finalize label resolution
5. Build metadata structures (exports, debug info)

Basic Blocks and Labels

Basic block boundaries occur at:
- Function entry points
- After control-flow instructions (branches, calls, returns)
- After conditional instructions that may divert execution
- Export function boundaries

Label management strategy:
```swift
// Pseudocode: lazy label creation and resolution
struct CompilerState {
    var programCounterToLabel: [PC: Label] = [:]
    var definedLabels: Set<Label> = []
}

// When a branch target is encountered
func getOrCreateLabel(_ pc: PC) -> Label {
    if !programCounterToLabel.keys.contains(pc) {
        let label = assembler.createLabel()
        programCounterToLabel[pc] = label
    }
    return programCounterToLabel[pc]!
}

// When reaching the actual target instruction
func defineLabel(_ pc: PC) {
    let label = programCounterToLabel[pc]!
    if !definedLabels.contains(label) {
        assembler.defineLabel(label)
        definedLabels.insert(label)
    }
}
```

Target validation:
- All potential branch targets are validated against the code mask during parsing
- Invalid targets result in compilation errors or trap generation
- Export functions are pre-validated for external calls

Trampolines (Host/Guest Boundary)

Trampolines bridge the gap between guest code execution and host runtime services. Each trampoline follows a standard pattern:

```swift
// Pseudocode: generic trampoline structure
func emitTrampoline(trampolineType: TrampolineType) {
    // 1. Save all guest registers to VmCtx
    for reg in guestRegisters {
        store reg -> vmctx.gasRegisters[reg]
    }

    // 2. Record guest state for resume
    store returnAddress -> vmctx.nextNativeProgramCounter

    // 3. Load syscall number or operation identifier
    mov syscallId -> specificRegister

    // 4. Jump to host handler
    jump AddressTable[syscallId]
}
```

Specific trampoline types:

1. Trap Trampoline:
   - Triggered by: execution faults, out-of-gas, invalid operations
   - Action: Save state, zero next_native_program_counter (prevents resume), jump to trap handler
   - Handler classifies trap type and possibly panics

2. Ecall Trampoline:
   - Triggered by: guest explicit system call instruction
   - Action: Save return address, preserve registers, jump to hostcall handler
   - Used for: I/O, environment queries, host services

3. Sbrk Trampoline:
   - Triggered by: guest memory allocation requests
   - Action: Save registers, invoke host allocator, restore and return
   - Optimized: leaf function with minimal overhead

4. Step Trampoline:
   - Triggered by: single-stepping debug mode
   - Action: Save state, invoke step handler for breakpoint/inspection
   - Used for: debugging, instrumentation, execution tracing

5. Sysenter/Sysreturn Bridge:
   - Sysenter: Entry point for host→guest transitions
     - Restore saved registers
     - Load continuation address from next_native_program_counter
     - Jump to resumed guest code
   - Sysreturn: Exit point for guest→host returns
     - Save current registers
     - Store return address in next_native_program_counter
     - Jump to syscall return handler

Jump Tables and Dynamic Jumps

Indirect jumps (computed goto, jump tables) use a host-provided jump table for safety and control flow verification.

```swift
// Pseudocode: indirect jump handling
struct JumpTable {
    var entries: [NativeAddress] // Size: MAX_CODE_SIZE
}

// Invalid entries point to a special trap address
let JUMP_TABLE_INVALID_ADDRESS: NativeAddress = 0xFFFFFFFFFFFFFFFF

// At compile time: populate valid targets
func compileIndirectJump(guestTargetPC: PC) {
    if isValidTarget(guestTargetPC) {
        jumpTable[guestTargetPC] = labelForPC(guestTargetPC)
    } else {
        jumpTable[guestTargetPC] = JUMP_TABLE_INVALID_ADDRESS
    }
}

// At runtime: indirect jump sequence
// Linux backend (using GS segment):
mov guestTarget -> rax
mov gs:[JumpTable + rax * 8] -> rax
jmp rax

// Generic backend (materialize table address):
lea jumpTableBase -> r11
mov [r11 + guestTarget * 8] -> rax
jmp rax
```

Invalid jump handling:
- Invalid targets point to a deliberately out-of-range address
- The chosen address exceeds canonical address width (e.g., all bits set in 64-bit)
- CPU faults immediately on jump attempt without clobbering RIP
- Fault handler identifies and recovers from invalid jump

Gas Metering

Gas metering limits guest execution by charging costs for operations. Two primary modes exist:

1. Synchronous (Pre-Check):
```swift
// Pseudocode: synchronous gas stub
func emitGasStub(blockCost: Immediate) {
    let startLabel = assembler.createLabel()
    let trapLabel = getTrapLabel()

    // Load gas counter
    mov vmctx.gas -> rax
    sub blockCost -> rax

    // Check if underflowed
    jo trapLabel  // Jump if overflow (gas went negative)

    // Store updated counter
    mov rax -> vmctx.gas
}
```

2. Asynchronous (Post-Check):
```swift
// Pseudocode: asynchronous gas stub
func emitGasStubAsync(blockCost: Immediate) {
    // Simply decrement without check
    mov vmctx.gas -> rax
    sub blockCost -> rax
    mov rax -> vmctx.gas

    // Handler checks for negative gas later
}
```

Computation and patching:
```swift
// During parsing: track costs
var blockGasCost = 0
for instruction in basicBlock {
    blockGasCost += gasVisitor.costOf(instruction)
}

// During finalization: patch the immediate
assembler.patchImmediate(gasStubLabel, blockGasCost)
```

Special case: memset
- Inline memset uses `rep stosb` for bulk memory initialization
- With synchronous gas: pre-charge full cost, branch to slow path if insufficient
- With asynchronous gas: execute and allow handler to detect underflow
- Slow path trampoline: computes bytes possible with remaining gas, stashes remainder, invokes NotEnoughGas syscall

PC/Offset Mapping and Caching

The recompiler maintains detailed mappings between guest program counters and native code locations:

```swift
struct CompiledModule {
    // Mapping after each instruction
    var pcToNativeOffset: [(PC, NativeOffset)]

    // Direct entry points for exported functions
    var exportOffsets: [ExportName: NativeOffset]

    // Native code buffer
    var codeBuffer: [UInt8]

    // Jump table for indirect branches
    var jumpTable: JumpTable
}

// Lookup helpers for runtime use
extension CompiledModule {
    func nativeOffsetForPC(_ pc: PC) -> NativeOffset? {
        // Binary search through sorted pcToNativeOffset
    }

    func exportOffset(_ export: String) -> NativeOffset? {
        exportOffsets[export]
    }
}
```

Mapping collection during compilation:
- After each instruction is emitted: append (current_guest_PC, current_native_offset)
- For exported functions: record label resolution result
- Enables: stack unwinding, debugging, exception handling, garbage collection

Caching strategy:
- Reuse allocations across compilations (Vec, HashMap capacity)
- Pool assembler buffers and label instances
- Cache architecture-specific encoders
- Reduces allocation overhead in JIT scenarios

