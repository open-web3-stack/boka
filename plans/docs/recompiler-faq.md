# PolkaVM Recompiler FAQ

Frequently asked questions about implementing, understanding, and optimizing the PolkaVM recompiler.

## Table of Contents

- [Architecture and Design](#architecture-and-design)
- [Implementation](#implementation)
- [Performance](#performance)
- [Gas Metering](#gas-metering)
- [Traps and Faults](#traps-and-faults)
- [Testing and Validation](#testing-and-validation)
- [Porting and Extensions](#porting-and-extensions)

---

## Architecture and Design

### Q1: Why use a recompiler instead of an interpreter?

**A:** A recompiler (JIT compiler) provides significant performance advantages:

- **10-100x faster execution**: Native code runs at native speed vs. interpreted dispatch overhead
- **Better CPU utilization**: Eliminates interpreter dispatch loops and instruction decoding
- **Optimization opportunities**: Native code benefits from CPU branch prediction, caching, pipelining
- **Lower overhead**: No per-instruction dispatch cost, better register utilization

**Trade-offs:**
- Higher memory usage (native code + bytecode)
- Compilation startup cost
- More complex implementation

The reference PolkaVM implementation uses the recompiler for production workloads and falls back to the interpreter only for debugging or when compilation isn't available.

### Q2: Why single-pass compilation instead of multi-pass with optimization?

**A:** Single-pass design was chosen for:

- **Simplicity**: Easier to implement correctly
- **Fast compilation**: Minimizes JIT compilation overhead
- **Predictable performance**: No optimization phase variability
- **Lower memory usage**: No need to store IR for multiple passes

**Limitations:**
- Can't perform global optimizations
- Can't eliminate redundant code across basic blocks
- Register mapping is fixed (no allocation)

For most workloads, the simplicity wins outweigh the optimization losses. The critical paths (memset, gas stubs) are hand-optimized.

### Q3: Why use fixed register mapping instead of dynamic register allocation?

**A:** Fixed mapping provides:

- **Zero allocation cost**: No graph coloring or interference analysis
- **Predictable code generation**: Same instruction always uses same registers
- **Faster compilation**: Eliminates expensive register allocation pass
- **Compact encodings**: Common operands in compactly-encodable registers

**The mapping is carefully chosen:**
- A0→rdi: First argument in System V ABI
- A1→rax: Return value, compact encodings
- Minimizes register shuffling in hot paths

**Downside:** May cause spills for complex expressions, but this is rare in practice due to RISC-style instruction set.

### Q4: Why use basic blocks for gas metering instead of per-instruction?

**A:** Per-basic-block gas metering provides:

- **Lower overhead**: One decrement per block vs. one per instruction
- **Better branch prediction**: Fewer conditional jumps
- **Simpler implementation**: Fewer gas stubs to manage
- **Sufficient precision**: Blocks are short (1-5 instructions typically)

**Alternative considered**: Per-instruction metering
- 10-100x more overhead
- More complex implementation
- Better precision but rarely needed

The block granularity is a good balance: precise enough for fair metering while being fast enough for production use.

### Q5: Why use jump tables for indirect jumps instead of computed gotos?

**A:** Jump tables provide:

- **Safety**: Invalid entries fault immediately (non-canonical address)
- **Simplicity**: Single table lookup vs. complex computed goto logic
- **Predictability**: All indirect jumps use same mechanism
- **Debugging**: Easier to inspect and validate

**Why not computed gotos?**
- Not portable across architectures
- More complex to implement correctly
- Harder to secure against invalid jumps
- Similar performance in practice

The jump table approach with `JUMP_TABLE_INVALID_ADDRESS` ensures invalid jumps fault without clobbering RIP, enabling safe recovery.

### Q6: What's the purpose of the bitmask in the program blob?

**A:** The bitmask serves two critical purposes:

1. **Validation before execution**: Quickly check if a target is valid without parsing
2. **Security**: Prevent jumps to middle of instructions

**How it works:**
- Each bit represents whether the corresponding PC offset is a valid jump target
- Set during program creation by the linker
- Checked before indirect jumps

**Example:**
```
PC:     0  1  2  3  4  5  6  7  8  9 10
Code:   [add][...][...][label][sub][...]
Bitmask:1  0  0  0  1  0  0  0  0  0  0
```

Only PC 0 (entry) and PC 4 (label) are valid jump targets.

---

## Implementation

### Q7: How do I get started implementing a recompiler?

**A:** Follow this step-by-step approach:

**Phase 1: Foundation**
1. Implement a basic assembler for your target ISA
2. Implement program blob parsing
3. Create data structures (VM context, labels, fixups)

**Phase 2: Basic Codegen**
4. Implement instruction decoder
5. Generate code for simple instructions (load_imm, add, sub)
6. Add register mapping for your ISA

**Phase 3: Control Flow**
7. Implement label and fixup mechanism
8. Add direct branches (conditional/unconditional)
9. Implement basic block formation

**Phase 4: Advanced Features**
10. Add memory operations (load/store)
11. Implement jump table for indirect jumps
12. Add gas metering (optional but recommended)

**Phase 5: Integration**
13. Implement trampolines (trap, ecall)
14. Add execution engine
15. Test against reference implementation

See [implementation-guide.md](implementation-guide.md) for detailed instructions.

### Q8: How do I handle forward branches to undefined labels?

**A:** Use a two-phase approach with fixups:

**Emission phase (pseudocode):**
```swift
func emitJumpToLabel(label: Label) {
    let currentOffset = assembler.currentPosition()

    if label.isDefined() {
        // Label already defined - emit direct jump
        let target = label.getTarget()
        let displacement = target - currentOffset
        assembler.emitJump(displacement)
    } else {
        // Forward reference - emit placeholder, create fixup
        assembler.emitJumpPlaceholder()
        fixups.add(Fixup(
            offset: currentOffset,
            label: label,
            kind: FixupKind.jump
        ))
    }
}
```

**Resolution phase (pseudocode):**
```swift
func resolveFixups() {
    for fixup in fixups {
        if fixup.label.isDefined() {
            let target = fixup.label.getTarget()
            let displacement = target - fixup.offset
            patchDisplacement(fixup.offset, displacement)
        } else {
            fatalError("Undefined label: \(fixup.label)")
        }
    }
}
```

**Assembly output example:**
```asm
; During emission - placeholder for forward jump
    jmp .L_target     ; Offset: 0x10, will be patched later
; ... more code ...
.L_target:
    add eax, 1

; During resolution - patch the jump displacement
; jmp at offset 0x10 gets displacement = (target - 0x10)
```

### Q9: How do I choose between 8-bit and 32-bit branch displacements?

**A:** Calculate the displacement and choose the shortest encoding:

**Algorithm (pseudocode):**
```swift
func emitConditionalJump(condition: Condition, label: Label) {
    let currentOffset = assembler.currentPosition()

    if label.isDefined() {
        let targetOffset = label.getTarget()
        var displacement = targetOffset - (currentOffset + 2)

        // Try rel8 first (shorter encoding: 2 bytes total)
        if displacement >= -128 && displacement <= 127 {
            assembler.emitJccRel8(condition, displacement)
            return
        }

        // Fall back to rel32 (longer encoding: 6 bytes total)
        displacement = targetOffset - (currentOffset + 6)
        assembler.emitJccRel32(condition, displacement)
    } else {
        // Forward reference - must use rel32
        assembler.emitJccRel32Placeholder(condition)
        fixups.add(Fixup(
            offset: currentOffset,
            condition: condition,
            label: label
        ))
    }
}
```

**Assembly encoding comparison:**
```asm
; Short encoding (rel8): 2 bytes
    jne .L_target    ; 0x75 0x10  (opcode + rel8)

; Long encoding (rel32): 6 bytes
    jne .L_target    ; 0x0f 0x85 0x10 0x00 0x00 0x00  (opcode + rel32)
```

**Note**: For forward references, you must emit rel32 since you don't know the distance yet. You can optimize backward references.

### Q10: How do I implement varint parsing efficiently?

**A:** Use unaligned loads and bit manipulation for speed:

**Algorithm (pseudocode):**
```swift
func readVarint(data: [UInt8], offset: Int) -> (value: UInt32, bytesRead: Int)? {
    if offset >= data.count {
        return nil  // Out of bounds
    }

    let firstByte = data[offset]

    // Decode length from top 2 bits
    let lengthEncoding = (firstByte & 0xC0) >> 6
    let length: Int
    switch lengthEncoding {
    case 0: length = 1
    case 1: length = 2
    case 2: length = 4
    case 3: length = 8
    default: fatalError("Invalid length encoding")
    }

    // Check bounds
    if offset + length > data.count {
        return nil
    }

    // Extract value based on length
    let valueLow = UInt32(firstByte & 0x3F)  // Low 6 bits

    let value: UInt32
    let bytesRead: Int

    switch length {
    case 1:
        value = valueLow
        bytesRead = 1

    case 2:
        value = valueLow | (UInt32(data[offset + 1]) << 6)
        bytesRead = 2

    case 4:
        value = valueLow |
                (UInt32(data[offset + 1]) << 6) |
                (UInt32(data[offset + 2]) << 14) |
                (UInt32(data[offset + 3]) << 22)
        bytesRead = 4

    case 8:
        // Read as 64-bit, truncate to 32-bit
        let value64 = UInt64(valueLow) |
                      (UInt64(data[offset + 1]) << 6) |
                      (UInt64(data[offset + 2]) << 14) |
                      (UInt64(data[offset + 3]) << 22) |
                      (UInt64(data[offset + 4]) << 30) |
                      (UInt64(data[offset + 5]) << 38) |
                      (UInt64(data[offset + 6]) << 46) |
                      (UInt64(data[offset + 7]) << 54)
        value = UInt32(truncatingIfNeeded: value64)
        bytesRead = 8

    default:
        fatalError("Invalid length")
    }

    return (value, bytesRead)
}
```

**Assembly implementation approach:**
```asm
; Input: rsi = data pointer, rcx = offset
; Output: eax = value, edx = bytes_read

    movzx eax, byte [rsi + rcx]    ; Load first byte
    movzx edx, al                   ; Copy for length check
    shr edx, 6                      ; Extract length encoding (top 2 bits)

    ; Jump table based on length
    jmp [jump_table + rdx * 8]

; Case 1: 1-byte encoding
parse_1byte:
    and eax, 0x3F                   ; Mask to 6 bits
    mov edx, 1                      ; bytes_read = 1
    jmp parse_done

; Case 2: 2-byte encoding
parse_2byte:
    and eax, 0x3F                   ; Mask low 6 bits
    movzx edx, byte [rsi + rcx + 1] ; Load second byte
    shl edx, 6                      ; Shift into position
    or eax, edx                     ; Combine
    mov edx, 2                      ; bytes_read = 2
    jmp parse_done

; ... (similar for 4 and 8-byte cases)
```

**Key optimization**: Use unaligned loads (safe on x86-64) instead of byte-by-byte reading. This allows loading multiple bytes at once and using bit operations.

### Q11: How do I handle sign extension of immediates properly?

**A:** Sign extension depends on the instruction format and immediate size:

**For reg_imm instructions (pseudocode):**
```swift
func decodeRegImm(instructionChunk: UInt64) -> (register: Register, immediate: Int64) {
    // Extract register from low 4 bits
    let regId = instructionChunk & 0x0F
    let register = decodeRegister(regId)

    // Extract immediate and sign-extend
    let immRaw = UInt32((instructionChunk >> 8) & 0xFFFFFFFF)
    let immediate = Int64(bitPattern: UInt64(immRaw).signExtend())

    return (register, immediate)
}

func signExtend32To64(_ value32: UInt32) -> Int64 {
    return Int64(bitPattern: UInt64(value32) | (value32 & 0x80000000 != 0 ? 0xFFFFFFFF00000000 : 0))
}
```

**For loading immediates:**
- `load_imm_u8`: Zero-extend to 32/64 bits
- `load_imm_u16`: Zero-extend to 32/64 bits
- `load_imm_u32`: Zero-extend to 64 bits
- `load_imm_s32`: Sign-extend to 64 bits

**In code generation:**
```asm
; Zero-extension (automatic in x86-64 when writing to 32-bit register)
mov eax, imm32        ; Zero-extends to rax (writes to eax, clears upper rax)

; Sign-extension (explicit instructions needed)
movsxd rax, eax       ; Sign-extends eax to rax (MOVe SiGn-eXtend Double)
movsx eax, byte [mem] ; Sign-extends byte to eax (MOVe SiGn-eXtend)
movzx eax, byte [mem] ; Zero-extends byte to eax (MOVe Zero-eXtend)

; Practical example
mov eax, -1           ; eax = 0xFFFFFFFF
; rax is now 0x00000000FFFFFFFF (zero-extended)

movsxd rax, eax       ; rax = 0xFFFFFFFFFFFFFFFF (sign-extended)
```

### Q12: How do I implement the memset fast path correctly?

**A:** The key is understanding x86-64's `rep stosb` instruction:

**Fast path (no gas metering):**
```asm
; A0=dest (rdi), A1=value (rax), A2=count (rcx)
mov rdi, [vmctx + offset_regs + A0*8]
mov rax, [vmctx + offset_regs + A1*8]
mov rcx, [vmctx + offset_regs + A2*8]
rep stosb    ; Fills [rdi] with eax, rcx times
```

**With gas metering (Sync mode):**
```asm
; Pre-charge gas
mov rcx, [vmctx + offset_regs + A2*8]
sub qword [vmctx + offset_gas], rcx
jb memset_slow_path

; Fast path - safe to execute
mov rdi, [vmctx + offset_regs + A0*8]
mov rax, [vmctx + offset_regs + A1*8]
mov rcx, [vmctx + offset_regs + A2*8]
rep stosb
jmp memset_done

memset_slow_path:
; Compute bytes possible with remaining gas
xor ecx, ecx
xchg rcx, [vmctx + offset_gas]  ; Get remaining gas
add rcx, [vmctx + offset_regs + A2*8]  ; Bytes wanted
sub [vmctx + offset_regs + A2*8], rcx  ; Bytes possible
mov [vmctx + offset_arg], rcx    ; Stash remaining count

; Do partial memset
mov rdi, [vmctx + offset_regs + A0*8]
mov rax, [vmctx + offset_regs + A1*8]
mov rcx, [vmctx + offset_regs + A2*8]
rep stosb

; Save registers and trap
call save_all_registers
jmp [syscall_not_enough_gas]

memset_done:
```

**Critical points:**
- rdi, rax, rcx are used by `rep stosb` (matches A0, A1, A2)
- Direction flag must be cleared (cld) - normally true
- Gas pre-charging allows early detection of out-of-gas

---

## Performance

### Q13: What are the most important optimizations for a recompiler?

**A:** In order of impact:

**1. Compact code generation (High Impact)**
- Use rel8 instead of rel32 when possible
- Use shortest immediate encoding (imm8 vs imm32)
- Use xor reg, reg instead of mov reg, 0
- Minimize instruction count

**2. Register mapping (High Impact)**
- Map common operands to compactly-encodable registers
- Minimize register shuffling
- Use fixed mapping to avoid allocation overhead

**3. Efficient gas metering (Medium Impact)**
- Per-block instead of per-instruction
- Patch immediates in bulk
- Use conditional moves for gas checks

**4. Memory access patterns (Medium Impact)**
- Use efficient addressing modes
- Prefer RIP-relative for globals
- Use string instructions for bulk operations

**5. Caching and reuse (Low-Medium Impact)**
- Reuse assembler buffers
- Recycle label mappings
- Cache VM context access

**6. Branch prediction (Low Impact)**
- Arrange likely path as fallthrough
- Use conditional moves instead of branches

See [recompiler-amd64-backend.md](recompiler-amd64-backend.md) for specific optimizations.

### Q14: Why is compilation speed important in a JIT compiler?

**A:** Fast compilation matters because:

1. **Startup time**: Programs must be compiled before execution
2. **Dynamic loading**: WebAssembly modules load dynamically
3. **Memory constraints**: Slow compilation consumes more resources
4. **Development iteration**: Faster compile/test cycles

**PolkaVM compilation performance:**
- Typical program: ~10-50ms to compile
- ~1-5MB/s compilation throughput
- Linear in program size

**Optimization trade-off:**
- Complex optimizations (register allocation, instruction scheduling) would 10-100x slow compilation
- For many workloads, compilation time > execution time
- Better to have fast "good enough" code than slow "perfect" code

### Q15: How does the recompiler achieve such high performance?

**A:** Several factors contribute:

**1. Native execution speed**
- No interpreter dispatch overhead (~5-10 cycles per instruction saved)
- Native CPU features (branch prediction, out-of-order execution)
- Efficient use of CPU registers and pipelines

**2. Optimized hot paths**
- Hand-optimized memset using `rep stosb`
- Inline gas stubs with patched immediates
- Compact branch encodings

**3. Minimal overhead**
- Single-pass compilation
- Fixed register mapping (no allocation)
- Per-block gas instead of per-instruction

**4. Architecture-aware optimizations**
- Register mapping for x86-64 encoding efficiency
- Efficient addressing modes
- Special instructions (lzcnt, tzcnt, popcnt, bswap)

**5. Caching**
- Reuse allocations across compilations
- Recycle label and fixup structures

**Result**: 10-100x faster than interpretation depending on workload.

---

## Gas Metering

### Q16: How does gas metering work without killing performance?

**A:** Gas metering is designed for minimal overhead:

**Per-basic-block approach:**
```asm
; At start of each basic block
sub qword [vmctx + offset_gas], BLOCK_GAS_COST
jb trap_handler    ; Only taken if out of gas
; ... block body ...
```

**Why it's fast:**
- One decrement per block (not per instruction)
- Conditional branch is highly predictable (almost never taken)
- Block cost is an immediate (patched during compilation)
- No loop or iteration overhead

**Sync vs Async metering:**

| Mode | When to Trap | Overhead |
|------|--------------|----------|
| Sync | Before block if gas < 0 | Slightly higher (conditional branch) |
| Async | After execution if gas < 0 | Lower (no conditional branch) |

**Cost calculation:**
- During compilation: accumulate instruction costs
- At block end: emit stub with placeholder immediate
- After compilation: patch in actual costs
- ~1-2% overhead in practice

### Q17: How does the trap handler know how much gas to refund?

**A:** The trap reads the gas cost directly from the machine code:

**Algorithm (pseudocode):**
```swift
func onGasTrap(machineCode: [UInt8], faultPc: Int, vmctx: VMContext) {
    // Calculate stub location
    // fault_pc points after the 'sub' instruction
    let stubOffset = faultPc - GAS_METERING_TRAP_OFFSET

    // Read the immediate from the sub instruction
    // The instruction is: sub qword [vmctx + offset_gas], imm32
    let costOffset = stubOffset + IMMEDIATE_OFFSET  // Usually 3 bytes after stub start
    let cost = readLittleEndianU32(machineCode, costOffset)

    // Refund the cost
    vmctx.gas = vmctx.gas + cost
}
```

**Why this works:**
- The stub has a known format: `sub [vmctx.gas], imm32`
- The immediate is at a fixed offset from the stub start
- Reading from machine code is safe (code is in read-only memory)
- Enables precise gas accounting without extra metadata

**Assembly layout:**
```asm
; Gas stub at offset X:
; X+0: 48 2b              ; REX.W sub
; X+2: 0d                 ; ModR/M for [rip+disp32]
; X+3: <gas_offset>       ; RIP-relative displacement to vmctx.gas (4 bytes)
; X+7: <immediate>        ; The gas cost (4 bytes) - THIS IS WHAT WE READ
; X+11: 0f 82             ; jb trap
; X+13: <disp32>          ; Jump to trap handler

; So if fault_pc = X+11, we read at X+7
```

### Q18: What about gas for instructions that trap partway through (like memset)?

**A:** Special handling for partially-completed instructions:

**memset example:**
1. Pre-charge full gas: `gas -= count`
2. Execute `rep stosb`
3. If page fault or out-of-gas:
   - Calculate bytes actually processed
   - Refund gas for unprocessed bytes
   - Store remaining count in vmctx.arg
   - Trap with NotEnoughGas

**Recovery algorithm (pseudocode):**
```swift
// After trap, vmctx.arg contains remaining count
let remaining = vmctx.arg
let totalRequested = registerA2  // Original count from register
let processed = totalRequested - remaining

// Refund gas for remaining bytes
vmctx.gas = vmctx.gas + remaining
```

**Implementation in assembly (slow path):**
```asm
; When memset traps, rcx still contains remaining count

; Save remaining count to vmctx.arg
mov [vmctx + offset_arg], rcx

; Calculate gas refund (rcx already has remaining bytes)
; Gas is 1 per byte for memset
mov [vmctx + offset_gas], rcx  // Actually need to ADD, not replace
; Better: add [vmctx + offset_gas], rcx

; Save registers and trap
call save_all_registers
jmp [syscall_not_enough_gas]
```

This ensures precise gas accounting even for interrupts.

---

## Traps and Faults

### Q19: How does the reclassifier distinguish between different trap types?

**A:** The signal handler uses heuristics to classify traps:

**Classification algorithm (pseudocode):**
```swift
func classifyTrap(machineCode: [UInt8], faultPc: Int, vmctx: VMContext) -> TrapKind {
    // 1. Check if we're in memset
    if isInMemsetRange(machineCode, faultPc) {
        return .memset
    }

    // 2. Check if gas is negative
    if vmctx.gas < 0 {
        return .outOfGas
    }

    // 3. Otherwise, it's a regular trap
    return .trap
}
```

**Detection methods:**

**Memset detection:**
```swift
func isInMemsetRange(machineCode: MachineCode, faultPc: Int) -> Bool {
    // Check if PC is within memset code range
    // Each compiled module tracks memset regions
    for region in machineCode.memsetRegions {
        if faultPc >= region.start && faultPc < region.end {
            return true
        }
    }
    return false
}
```

**Gas trap detection:**
```swift
func isGasTrap(machineCode: [UInt8], faultPc: Int, vmctx: VMContext) -> Bool {
    // Check gas counter in vmctx
    if vmctx.gas >= 0 {
        return false
    }

    // Verify faulting instruction is gas stub
    // Gas stubs have pattern: sub [vmctx.gas], imm32
    let instruction = readInstructionAt(machineCode, faultPc)
    return instruction.matchesGasStubPattern()
}
```

**Regular trap:**
- Explicit `trap` instruction
- Invalid memory access
- Division by zero, etc.

### Q20: Why use JUMP_TABLE_INVALID_ADDRESS instead of trapping?

**A:** Using a non-canonical address (0xfa6f29540376ba8a) provides:

**1. Immediate fault without state corruption:**
```
CPU checks: "Is this address canonical?"
If no: Generate page fault WITHOUT updating RIP
Result: RIP points to the jmp instruction, not the fault target
```

**2. Safe recovery:**
- Instruction pointer is preserved
- Can identify the faulting jump
- Can classify and handle appropriately

**3. Better than trapping:**
```
; Bad: Jump to trap handler
jmp trap_trampoline
; Problem: Need to identify which jump caused this

; Good: Jump to invalid address
jmp [invalid_address]
; CPU faults, RIP preserved, easy to recover
```

**Why 0xfa6f29540376ba8a?**
- High bit set (MSB = 1)
- Exceeds 48-bit canonical address space
- Future-proof for 57-bit addressing
- Unlikely to conflict with real addresses

### Q21: How do I handle page faults in compiled code?

**A:** Page fault handler needs to:

**1. Identify fault type (pseudocode):**
```swift
func pageFaultHandler(faultAddr: UInt64, faultPc: Int) {
    // Check if we're in memset
    if isInMemset(faultPc) {
        handleMemsetPageFault(faultAddr: faultAddr, faultPc: faultPc)
    } else {
        // Invalid memory access - trap
        trapWithInvalidMemory(faultAddr)
    }
}
```

**2. For memset faults (pseudocode):**
```swift
func handleMemsetPageFault(faultAddr: UInt64, faultPc: Int) {
    // Determine how many bytes were written
    // rdi (destination) is at fault_addr
    // Original start was: fault_addr - bytes_written
    let memsetStartAddress = getMemsetStartFromContext(faultPc)
    let bytesWritten = faultAddr - memsetStartAddress

    // Calculate remaining bytes
    let totalBytes = vmctx.registers[A2]  // Original count from register A2
    let remaining = totalBytes - bytesWritten

    // Update A2 to remaining count
    vmctx.registers[A2] = remaining

    // Refund gas for remaining bytes
    vmctx.gas = vmctx.gas + remaining

    // Set up to resume after memset
    vmctx.nextNativePc = faultPc
}
```

**Assembly implementation:**
```asm
; Page fault handler entry
; rdi = fault_addr, rsi = fault_pc

; Check if in memset range
cmp rsi, memset_code_start
jb .invalid_access
cmp rsi, memset_code_end
jae .invalid_access

; Handle memset fault
mov rax, [vmctx + offset_regs + A2*8]  ; Get original count
sub rax, rdi                            ; Calculate remaining
mov [vmctx + offset_regs + A2*8], rax  ; Store remaining

; Refund gas
add [vmctx + offset_gas], rax

; Resume after memset
mov [vmctx + offset_native_pc], rsi
jmp fault_return_path

.invalid_access:
; This is a program error - trap to host
mov qword [vmctx + offset_native_pc], 0
mov [vmctx + offset_fault_addr], rdi
jmp trap_handler
```

**3. For invalid access (pseudocode):**
```swift
func trapWithInvalidMemory(faultAddr: UInt64) {
    // This is a program error - trap to host
    vmctx.nextNativePc = 0  // Signal to stop execution

    // Store fault address for debugging
    vmctx.faultAddress = faultAddr

    // Jump to trap handler
    executeTrapHandler()
}
```

---

## Testing and Validation

### Q22: How do I verify my recompiler is correct?

**A:** Use a multi-pronged testing strategy:

**1. Unit Tests**
- Test individual instruction encoding/decoding
- Test assembler emission
- Test label resolution
- Test gas calculation

**2. Differential Testing (Most Important)**

**Algorithm (pseudocode):**
```swift
// Run same program through both implementations
let interpreterResult = interpretProgram(blob)
let recompilerResult = executeCompiled(blob)

// Compare final state
assert(interpreterResult.registers == recompilerResult.registers)
assert(interpreterResult.memory == recompilerResult.memory)
assert(interpreterResult.pc == recompilerResult.pc)
```

**3. Property-Based Testing**

**Algorithm (pseudocode):**
```swift
// Generate random valid programs
for i in 1...10000 {
    let program = generateRandomProgram()
    let blob = compileToBlob(program)

    // Test both implementations
    let interpResult = interpret(blob)
    let recompResult = execute(blob)

    // Verify match
    assertResultsMatch(interpResult, recompResult)
}
```

**Test harness example:**
```swift
func testRandomPrograms(numTests: Int) -> Bool {
    for i in 0..<numTests {
        // Generate random program
        let program = randomProgramGenerator.generate(
            maxInstructions: 100,
            maxRegisters: 32,
            maxMemory: 4096
        )

        // Compile to blob
        let blob = linker.link(program)

        // Run both implementations
        let interpState = interpreter.execute(blob)
        let recompState = recompiler.execute(blob)

        // Compare states
        if interpState != recompState {
            print("Mismatch found!")
            print("Program:", program)
            print("Interpreter:", interpState)
            print("Recompiler:", recompState)
            saveFailureCase(program, interpState, recompState)
            return false
        }
    }

    return true
}
```

**4. Edge Case Testing**
- Division by zero
- Overflow edge cases (INT_MIN / -1)
- Maximum/minimum immediates
- All shift amounts (0-63)
- All branch conditions

**5. Real-World Programs**
- Compile actual guest programs
- Compare execution results
- Benchmark performance

### Q23: How do I test gas metering accuracy?

**A:** Validate gas accounting at multiple levels:

**1. Per-instruction costs (pseudocode):**
```swift
// Execute single instruction, verify gas consumed
let initialGas = 1000
vmctx.gas = initialGas

executeSingleInstruction(blob, pc)

let expectedGas = initialGas - instructionCost(opcode)
assert(vmctx.gas == expectedGas)
```

**2. Per-block costs (pseudocode):**
```swift
// Execute basic block, verify gas consumed
let block = parseBasicBlock(blob, startPc: startPc)
let expectedCost = calculateBlockGas(block)

let initialGas = 10000
vmctx.gas = initialGas

executeBlock(blob, startPc: startPc)

assert(vmctx.gas == initialGas - expectedCost)
```

**3. Trap and refund (pseudocode):**
```swift
// Force out-of-gas trap
vmctx.gas = 5  // Low gas
executeInstruction(blob, expensivePc)

// Should have trapped and refunded
assert(trapOccurred == true)
let refundedGas = readGasStubImmediate(machineCode, faultPc)
assert(vmctx.gas == 5 + refundedGas)
```

**4. Comparison with interpreter (pseudocode):**
```swift
// Run same program, compare total gas used
let interpGas = interpretWithGas(blob)
let recompGas = executeWithGas(blob)

assert(interpGas == recompGas)
```

**Test automation example:**
```swift
func testGasMetering() {
    let testCases = [
        TestCase(instruction: "add_32", expectedCost: 1),
        TestCase(instruction: "load_imm_u32", expectedCost: 1),
        TestCase(instruction: "memset", expectedCost: "variable"),
        // ... more test cases
    ]

    for test in testCases {
        let blob = compileSingleInstruction(test.instruction)

        // Test with sufficient gas
        vmctx.gas = 1000
        let initial = vmctx.gas
        execute(blob)
        let consumed = initial - vmctx.gas

        if test.expectedCost != "variable" {
            assert(consumed == test.expectedCost)
        }

        // Test with insufficient gas
        vmctx.gas = 1
        execute(blob)
        assert(trapOccurred == true)
        assert(vmctx.gas > 1)  // Should have refunded
    }
}
```

### Q24: How do I debug my recompiler implementation?

**A:** Use these debugging strategies:

**1. Tracing execution (pseudocode):**
```swift
// Enable step tracing
config.stepTracing = true

// Each instruction will call into host
func stepHandler(vmctx: VMContext) {
    let pc = vmctx.programCounter
    let nativePc = vmctx.nextNativeProgramCounter
    print("PC: \(pc), Native: 0x\(String(nativePc, radix: 16))")
}
```

**Assembly trace hook:**
```asm
; At the start of each basic block
; Register vmctx is already in a known register
push rax
push rcx
push rdx
push rdi
push rsi

mov rdi, [vmctx + offset_pc]
mov rsi, [vmctx + offset_native_pc]
call step_trace_handler

pop rsi
pop rdi
pop rdx
pop rcx
pop rax
```

**2. Disassembly (pseudocode):**
```swift
// Disassemble generated code
let disasm = disassembleNativeCode(compiledModule.machineCode)
print("Generated code:\n\(disasm)")
```

**3. Instruction-level comparison (pseudocode):**
```swift
// Trace both implementations
var interpreterTrace: [TraceEntry] = []
var recompilerTrace: [TraceEntry] = []

interpretWithTrace(blob, &interpreterTrace)
executeWithTrace(blob, &recompilerTrace)

// Compare traces
for i in 0..<min(interpreterTrace.count, recompilerTrace.count) {
    let interpStep = interpreterTrace[i]
    let recompStep = recompilerTrace[i]

    if interpStep != recompStep {
        print("Mismatch at step \(i): \(interpStep)")
        print("  Interpreter: \(interpStep)")
        print("  Recompiler:  \(recompStep)")
    }
}
```

**4. Memory dumps (pseudocode):**
```swift
// Dump VM state at specific points
func dumpVMState(_ vmctx: VMContext) {
    print("Registers:")
    for i in 0..<NUM_REGISTERS {
        let regValue = vmctx.registers[i]
        print("  r\(i): 0x\(String(regValue, radix: 16))")
    }

    print("PC: \(vmctx.programCounter)")
    print("Gas: \(vmctx.gas)")

    // Dump memory around specific address
    let address = vmctx.registers[A0]
    print("Memory at 0x\(String(address, radix: 16)):")
    for i in 0..<16 {
        let byte = vmctx.memory[address + UInt64(i)]
        print("  \(String(address + UInt64(i), radix: 16)): \(String(byte, radix: 16))")
    }
}
```

**Assembly dump helper:**
```asm
; Inline code to dump register state
; Call this at any point to see current state
push rax
push rdi
push rsi

mov rdi, vmctx
lea rsi, [rsp + 24]  ; Address of saved rax
call dump_registers_to_log

pop rsi
pop rdi
pop rax
```

**5. Signal handling (pseudocode):**
```swift
// Add logging to signal handlers
func signalHandler(signal: Int, info: SignalInfo, context: Context) {
    let pc = getProgramCounter(context)
    let faultAddr = getFaultAddress(context)
    errorLog("Signal \(signal) at PC 0x\(String(pc, radix: 16)), fault 0x\(String(faultAddr, radix: 16))")

    // Dump state
    dumpVMState(getVmctxFromContext(context))

    // ... handle signal ...
}
```

---

## Porting and Extensions

### Q25: Can I port the recompiler to other architectures (ARM, RISC-V)?

**A:** Yes! The architecture is ISA-agnostic. To port:

**1. Implement architecture-specific backend (pseudocode):**
```swift
// Create new file: compiler/arm64_backend
class Arm64Visitor: CompilerVisitor {
    // Implement all instruction lowering methods

    func emitAdd32(dest: Register, src: Register, imm: Int32) {
        // Emit ARM64 instruction
        // Format: add wXd, wXn, #imm
        // wXd = 32-bit destination register
        // wXn = 32-bit source register
        let arm32Dest = mapToArm32Register(dest)
        let arm32Src = mapToArm32Register(src)
        assembler.emitAdd32(arm32Dest, arm32Src, imm)
    }

    func emitJump(label: Label) {
        // Emit ARM64 unconditional branch
        let target = label.getTarget()
        assembler.emitB(target)
    }
}
```

**2. Define register mapping (pseudocode):**
```swift
func mapRegister(_ pvmReg: PVMRegister) -> ARM64Register {
    // Map PVM registers to ARM64 registers
    switch pvmReg {
    case .A0: return .x0   // First argument
    case .A1: return .x1   // Second argument / return
    case .A2: return .x2   // Third argument
    case .A3: return .x3   // Fourth argument
    case .A4: return .x4   // Fifth argument
    // ... and so on
    }
}
```

**ARM64 assembly example:**
```asm
; PVM: add_32 A0, A1, 42
; ARM64 translation:

; Map A0->w0, A1->w1
    add w0, w1, #42    ; w0 = w1 + 42

; PVM: load_imm_u32 A0, 0x12345678
; ARM64 translation:

    mov w0, #0x12345678  ; Load 32-bit immediate
```

**3. Adapt trampolines:**
```swift
// Save/restore all registers per ARM64 calling convention
func emitTrampoline(trampolineType: TrampolineType) {
    // Prologue: save all PVM registers
    for i in 0..<NUM_REGISTERS {
        let reg = mapRegister(i)
        assembler.emitStoreToStack(reg, offset: i * 8)
    }

    // Call handler based on type
    assembler.emitCall(trampolineType)

    // Epilogue: restore all PVM registers
    for i in 0..<NUM_REGISTERS {
        let reg = mapRegister(i)
        assembler.emitLoadFromStack(reg, offset: i * 8)
    }

    assembler.emitReturn()
}
```

**4. Adjust gas metering:**
```swift
// ARM64 gas stub format
func emitGasStub(cost: Int64) {
    // ARM64 uses different instruction encoding
    // sub x0, x0, #imm (subtract immediate)
    assembler.emitSubImmediate(GAS_REG, cost)

    // Conditional branch: b.lo label (branch if lower/unsigned less)
    assembler.emitBranchIfLessThanZero(trapHandler)
}
```

**Key differences to handle:**
- Instruction encoding (fixed 32-bit vs. variable length)
- Conditional execution (ARM64 has conditional select: csel)
- Memory addressing modes (register+offset vs. complex addressing)
- Special instructions (may need emulation)

**Estimated effort:** 2-4 weeks for a basic ARM64 backend.

### Q26: Can I add custom instructions to the instruction set?

**A:** Yes, but requires coordination:

**1. Add opcode to program format (pseudocode):**
```swift
// In instruction definitions
let instructionDefinitions: [InstructionDefinition] = [
    // ... existing instructions ...
    InstructionDefinition(name: "custom_op", opcode: 0xFF, format: "reg_imm"),
    // Add your custom opcode definition
]
```

**2. Implement in interpreter (pseudocode):**
```swift
// In interpreter instruction handler
func handleCustomOp(instruction: Instruction) {
    let arg = extractArgFromInstruction(instruction)

    // Your implementation here
    let result = performCustomOperation(arg)

    // Store result
    let destinationReg = extractDestination(instruction)
    registers[destinationReg] = result
}
```

**3. Implement in recompiler (pseudocode):**
```swift
// In compiler backend (x86-64 or ARM64)
func emitCustomOp(instruction: Instruction) {
    let dest = extractDestination(instruction)
    let src = extractSource(instruction)
    let arg = extractArg(instruction)

    // Emit native code for your instruction
    let nativeDest = mapRegister(dest)
    let nativeSrc = mapRegister(src)

    // Example: custom operation that adds and multiplies
    assembler.emitMov(nativeDest, nativeSrc)
    assembler.emitImmediateAdd(nativeDest, arg)
    assembler.emitShiftLeft(nativeDest, 2)  // Multiply by 4
}
```

**4. Update gas costs (pseudocode):**
```swift
// In gas cost model
let gasCosts: [String: Int] = [
    // ... existing instructions ...
    "custom_op": 10,  // Set gas cost for custom instruction
]
```

**Considerations:**
- Breaks compatibility with existing toolchains
- Requires updated linker
- All implementations must support it
- Better to work upstream if possible

**Example implementation flow:**
```
1. Define opcode format in spec
2. Update linker to recognize new opcode
3. Add interpreter handler
4. Add recompiler code generation
5. Update gas cost table
6. Add tests for new instruction
7. Document the new instruction
```

### Q27: Can I use the recompiler for other bytecode formats (WASM, etc.)?

**A:** The architecture is reusable, but you'd need to:

**1. Define mapping from your format to PVM:**
- Map your bytecode instructions to PVM instructions
- Handle semantic differences
- May need preprocessing passes

**2. Or implement custom frontend:**
- Keep the backend (assembler, codegen)
- Replace instruction decoder
- Replace instruction visitor

**Example architecture:**
```
WASM Module
    ↓ (decode)
WASM Instructions
    ↓ (translate)
PVM Instructions  ← OR: Custom IR here
    ↓ (compile)
Native Code
```

**Challenges:**
- Different semantics (e.g., WASM has a stack machine)
- Different memory model (WASM linear memory vs. PVM regions)
- Different control flow (WASM structured vs. PVM branches)

**Recommendation:** Use WASM→PVM transpiler if possible, or implement WASM-specific frontend.

### Q28: How do I add optimization passes to the recompiler?

**A:** You can insert optimization passes between parsing and codegen:

**Current architecture:**
```
Parse → Visit → Codegen → Native
```

**With optimizations:**
```
Parse → Visit → Optimize → Codegen → Native
```

**Example optimization passes:**

**1. Constant folding (pseudocode):**
```swift
func optimizeConstantFolding(_ block: BasicBlock) {
    for i in 0..<block.instructions.count {
        var instr = block.instructions[i]
        if instr.type == .ADD_32 && isConstant(instr.src) {
            let constVal = getConstantValue(instr.src)
            // Replace: add_32 dest, const_src, imm
            // With: load_imm_u32 dest, (const_val + imm)
            let newImm = constVal + instr.immediate
            block.instructions[i] = loadImmU32(dest: instr.dest, imm: newImm)
        }

        // ... other patterns ...
    }
}
```

**2. Dead code elimination (pseudocode):**
```swift
func eliminateDeadCode(_ block: BasicBlock) {
    // Calculate liveness analysis
    let live = calculateLiveness(block)

    // Remove instructions whose results are never used
    block.instructions = block.instructions.filter { instr in
        return isLive(instr, live)
    }
}
```

**3. Peephole optimization (pseudocode):**
```swift
func peepholeOptimize(_ instructions: inout [Instruction]) {
    for i in 0..<(instructions.count - 1) {
        let current = instructions[i]
        let next = instructions[i + 1]

        // Pattern: load_imm 0; add
        if current.type == .LOAD_IMM_U32 &&
           current.immediate == 0 &&
           next.type == .ADD_32 &&
           next.src == current.reg &&
           next.dest == current.reg {

            // Replace with just load_imm
            instructions[i] = loadImmU32(dest: next.dest, imm: next.immediate)
            instructions[i + 1] = nop()
        }

        // ... other patterns ...
    }
}
```

**Architecture for optimization passes (pseudocode):**
```swift
protocol OptimizationPass {
    func optimize(_ block: BasicBlock)
}

class ConstantFolding: OptimizationPass {
    func optimize(_ block: BasicBlock) {
        // Constant folding implementation
    }
}

class DeadCodeElimination: OptimizationPass {
    func optimize(_ block: BasicBlock) {
        // Dead code elimination implementation
    }
}

class PeepholeOptimizer: OptimizationPass {
    func optimize(_ block: BasicBlock) {
        // Peephole optimization implementation
    }
}

// Pipeline
func runOptimizationPasses(_ block: BasicBlock) {
    let passes: [OptimizationPass] = [
        ConstantFolding(),
        DeadCodeElimination(),
        PeepholeOptimizer()
    ]

    for pass in passes {
        pass.optimize(block)
    }
}
```

**Trade-offs:**
- Slower compilation (extra passes)
- More complex implementation
- May not improve runtime much for most workloads

**Recommendation:** Profile first, optimize hot paths manually before adding general optimization passes.

---

## Common Issues

### Q29: My recompiler generates correct code but is slow. What should I do?

**A:** Profile before optimizing:

**1. Identify bottlenecks:**
```bash
# Profile compilation time
perf record ./your_recompiler program.blob
perf report

# Profile execution time
perf record ./execute compiled_program
perf report
```

**2. Common performance killers:**

| Issue | Symptom | Fix |
|-------|---------|-----|
| Large code size | Slow I-Cache misses | Use compact encodings |
| Too many branches | Poor prediction | Use conditional moves |
| Register spills | Stack operations | Better register mapping |
| Slow gas stubs | Gas overhead | Use per-block metering |
| Inefficient jumps | Large jump table | Fix table alignment |

**3. Optimization priority:**
1. Code size (compact encodings) - usually #1 issue
2. Hot paths (memset, gas) - hand-optimize
3. Register pressure - improve mapping
4. Branch layout - arrange fallthrough

**4. Don't optimize:**
- Cold paths (error handling)
- One-time setup code
- Already-fast paths

### Q30: How do I handle differences between 32-bit and 64-bit modes?

**A:** The recompiler handles bitness through configuration parameters:

**In code generation (pseudocode):**
```swift
func emitAdd(dest: Register, src: Register, imm: Int64, bitnessMode: BitnessMode) {
    if bitnessMode == .mode32bit {
        // Emit 32-bit add
        let asmDest = mapRegister(dest, width: .width32)
        let asmSrc = mapRegister(src, width: .width32)
        assembler.emitAdd32(asmDest, asmSrc, imm)
    } else {  // MODE_64BIT
        // Emit 64-bit add
        let asmDest = mapRegister(dest, width: .width64)
        let asmSrc = mapRegister(src, width: .width64)
        assembler.emitAdd64(asmDest, asmSrc, signExtend(imm))
    }
}
```

**Assembly examples:**
```asm
; 32-bit mode: add_32 A0, A1, 42
; A0->eax, A1->ebx
    add eax, ebx       ; eax = eax + ebx (32-bit)
    add eax, 42        ; eax = eax + 42

; 64-bit mode: add_32 A0, A1, 42
; A0->rax, A1->rbx
    add eax, ebx       ; eax = eax + ebx (32-bit, clears upper rax)
    add eax, 42        ; eax = eax + 42

; 64-bit mode: add_64 A0, A1, 42
; A0->rax, A1->rbx
    add rax, rbx       ; rax = rax + rbx (64-bit)
    add rax, 42        ; rax = rax + 42
```

**Key differences:**

| Aspect | 32-bit | 64-bit |
|--------|--------|--------|
| Register width | 32 bits | 64 bits |
| Address size | 32 bits | 64 bits |
| Immediate size | Up to 32-bit | Up to 64-bit |
| Sign extension | Explicit needed | Automatic (mov r32) |
| Memory ops | 4-byte granularity | 8-byte granularity |

**Special handling (pseudocode):**
```swift
// Loads: Zero-extend or sign-extend appropriately
func emitLoad(dest: Register, address: UInt64, width: MemWidth, bitnessMode: BitnessMode) {
    switch width {
    case .width8:
        assembler.emitMovzx(dest, bytePtr(address))
    case .width16:
        assembler.emitMovzx(dest, wordPtr(address))
    case .width32:
        if bitnessMode == .mode64bit {
            // Zero-extend to 64 bits
            assembler.emitMov(destDword, dwordPtr(address))
        } else {
            assembler.emitMov(dest, dwordPtr(address))
    }
}

// Stores: Truncate to correct width
func emitStore(src: Register, address: UInt64, width: MemWidth) {
    switch width {
    case .width8:
        assembler.emitMov(bytePtr(address), srcByte)
    case .width16:
        assembler.emitMov(wordPtr(address), srcWord)
    case .width32:
        assembler.emitMov(dwordPtr(address), srcDword)
    }
}

// Memory addresses: Sign-extend 32-bit addresses in 64-bit mode
func emitAddressCalc(addressReg: Register, baseReg: Register, offset: Int64, bitnessMode: BitnessMode) {
    if bitnessMode == .mode64bit {
        // Sign-extend 32-bit address to 64-bit
        assembler.emitMovsx(addressReg, baseReg)
    } else {
        assembler.emitMov(addressReg, baseReg)
    }
}
```

**Implementation strategy:**
```swift
// Compiler configuration
struct CompilerConfig {
    let bitness: BitnessMode  // .mode64bit or .mode32bit
    let registerWidth: Int     // bytes
    let addressWidth: Int      // bytes
}

let config = CompilerConfig(
    bitness: .mode64bit,
    registerWidth: 8,
    addressWidth: 8
)

// During code generation
for instruction in program {
    emitInstruction(instruction, config.bitness)
}
```

---

## Additional Resources

**Still have questions?**

- [Implementation Guide](implementation-guide.md) - Step-by-step implementation
- [Instruction Translation](instruction-translation.md) - How to translate instructions
- [Recompiler Architecture](recompiler-architecture.md) - How it works
- [Recompiler Deep Dive](recompiler-deep-dive.md) - Detailed analysis

**Found a bug or have a feature request?**
- Open an issue on the PolkaVM GitHub repository
- Include minimal reproducer for bugs
- Provide use case for feature requests

**Want to contribute?**
- Pull requests welcome!
- See [CONTRIBUTING.md](../CONTRIBUTING.md) (if exists) for guidelines
- Add tests for new features
- Update documentation for changes

---

**Last Updated:** 2025-01-19

**Document Version:** 1.0
