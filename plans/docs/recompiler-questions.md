# Recompiler: Questions and Answers

## Q1: Where is the recompiler implemented and how is it invoked?

**Answer:** The architecture-agnostic core compiler logic is in the main compiler module. The x86-64 backend is in the architecture-specific compiler module. Compilation is invoked from the API layer, which creates a compiler visitor with the instruction set, code bitmask, exports, gas configuration, then visits the program blob instruction stream, and finally finishes compilation to produce a compiled module.

**Key Components:**
- Core compiler: Architecture-agnostic driver
- Backend: ISA-specific code generation (e.g., amd64)
- API layer: Entry point for compilation requests
- Program blob: Parsed bytecode and metadata

## Q2: What is the overall pipeline from bytecode to native code?

**Answer:** The compilation pipeline follows these steps:

1. **Engine initialization**: Selects backend and sandbox type
2. **Module loading**: Parses program blob from bytecode
3. **Compiler setup**: Creates compiler visitor with:
   - Instruction set kind (32-bit or 64-bit)
   - Code section and jump table
   - Valid code bitmask
   - Exported functions
   - Gas configuration and cost model
4. **Instruction visiting**: Iterates through instruction stream:
   - Each instruction invokes a visitor method
   - Accumulates gas costs
   - Emits native code
5. **Finalization**:
   - Patches gas immediates into basic block stubs
   - Emits sysenter/sysreturn trampolines
   - Allocates and initializes jump table
   - Returns compiled module with native code

## Q3: How are basic blocks formed and tracked?

**Answer:** Basic blocks are formed at:

**Start points:**
- Program entry point (PC = 0)
- Jump targets (validated against code bitmask)

**End points:**
- After terminating instructions (branches, jumps, traps)
- End of code section

**Tracking mechanism:**
1. When control flow instruction encountered, end current block
2. Mark next PC as potential block start
3. For valid jump targets, create labels
4. At block start:
   - Define label if this is a jump target
   - Optionally emit step tracing code
   - Emit gas metering stub (if enabled)
5. After each instruction, record PC → native offset mapping

## Q4: How is gas metering implemented?

**Answer:** Gas metering uses per-basic-block stubs:

**Emission phase:**
1. At start of each basic block, emit stub:
   ```
   subtract gas_counter, BLOCK_COST  ; cost patched later
   if gas_counter < 0: trap_to_handler  ; Sync mode only
   ```
2. Accumulate instruction costs while parsing
3. At block end, capture total cost

**Finalization phase:**
1. Patch actual block costs into stub immediates
2. Two metering modes:
   - **Sync**: Pre-check gas, trap before block if insufficient
   - **Async**: Execute block, trap after if gas negative

**Special case: memset**
- Pre-charge full gas for entire operation
- Fast path: Inline `rep stosb` if sufficient gas
- Slow path: Trampoline calculates bytes possible, refunds remainder

## Q5: How are dynamic jumps and jump tables handled?

**Answer:** Indirect jumps use a jump table for dispatch:

**Jump table structure:**
- Array of native code pointers
- Indexed by PC offset (aligned to VM_CODE_ADDRESS_ALIGNMENT)
- Each entry: 8 bytes (64-bit) or 4 bytes (32-bit)

**Invalid entry handling:**
- Invalid entries point to JUMP_TABLE_INVALID_ADDRESS
- Address chosen to exceed canonical width (causes CPU fault)
- Fault occurs without clobbering instruction pointer
- Enables safe recovery and trap handling

**Code generation differences:**
- **Linux sandbox**: Uses `gs:` segment addressing
  ```
  jmp [gs:jump_table + index*8]
  ```
- **Generic sandbox**: Materializes table address, loads pointer
  ```
  lea tmp, [rip + jump_table_label]
  jmp [tmp + index*8]
  ```

## Q6: What trampolines exist and what do they do?

**Answer:** Trampolines bridge guest and host execution:

**List of trampolines:**

1. **Trap trampoline**
   - Saves all registers to VM context
   - Sets next_native_pc = 0 (indicates trap)
   - Jumps to host trap handler

2. **Ecall trampoline**
   - Saves return address and registers
   - Jumps to host call handler
   - Argument already in vmctx.arg

3. **Sbrk trampoline**
   - Saves registers
   - Calls host sbrk function
   - Returns result to guest
   - Restores registers

4. **Step trampoline** (if tracing enabled)
   - Saves registers
   - Records program counter
   - Jumps to host step handler

5. **Sysenter**
   - Entry point from host to guest
   - Restores registers
   - Jumps to next_native_pc continuation

6. **Sysreturn**
   - Exit from guest to host
   - Saves registers
   - Sets next_native_pc = 0
   - Jumps to host return handler

## Q7: How are traps, page faults, and out-of-gas handled?

**Answer:** Signal/fault handlers classify and recover from exceptions:

**Trap classification (Linux sandbox):**

1. **Check execution context**:
   - Is fault in memset code? → Memset fault
   - Is gas negative? → Out of gas
   - Otherwise → Regular trap

2. **Memset fault handling**:
   - Calculate bytes already processed
   - Update remaining count in A2
   - Refund gas for unprocessed bytes
   - Set next_native_pc for recovery

3. **Out-of-gas handling**:
   - Locate gas stub that caused trap
   - Read gas cost from machine code immediate
   - Refund cost to gas counter
   - Set program_counter to trapped instruction
   - Set next_native_pc to retry after gas added

4. **Regular trap**:
   - Set program_counter to faulting instruction
   - Set next_native_pc = 0 (return to host)
   - Trap type indicates reason (division by zero, etc.)

**Page fault handling:**
- Similar classification as traps
- May indicate invalid memory access or memset in progress
- Updates PCs for recovery or terminates with error

## Q8: How are guest registers mapped to native registers?

**Answer:** Fixed mapping optimized for code density:

**x86-64 mapping example:**

| PVM Register | x86-64 Register | Purpose |
|--------------|-----------------|---------|
| A0 | rdi | First argument (System V ABI) |
| A1 | rax | Return value, compact encodings |
| A2 | rdx | Third argument |
| A3 | rbp | Fourth argument |
| SP | rsi | Stack pointer |
| RA | rbx | Return address (callee-saved) |
| S0 | r8 | Saved register |
| S1 | r9 | Saved register |
| A4 | r10 | Argument |
| A5 | r11 | Argument |
| T0 | r13 | Temporary |
| T1 | r14 | Temporary |
| T2 | r12 | Temporary |
| TMP | rcx | Temporary (shift counter) |
| AUX_TMP | r15 | Temporary (must save/restore) |

**Rationale:**
- A0→rdi matches calling convention
- A1→rax enables compact encodings
- Minimizes register shuffling
- Temporaries in non-pressure registers

## Q9: How does 32-bit vs 64-bit mode affect codegen?

**Answer:** Bitness affects code generation in several ways:

**Register width:**
- 32-bit mode: Operates on 32-bit values
- 64-bit mode: Operates on 64-bit values

**Sign extension:**
- 32-bit loads in 64-bit mode zero-extend automatically
- Explicit sign-extension needed for signed values
- Different handling for arithmetic results

**Instruction selection:**
- Some instructions have _32 and _64 variants
- Shift count masking differs (5 bits vs. 6 bits)
- Immediate sizes may vary

**Memory operations:**
- Address calculation width differs
- May need to truncate or extend addresses

**Overflow handling:**
- Division overflow checks differ
- 64-bit mode has larger overflow edge cases

## Q10: How are per-instruction costs and maximum instruction length handled?

**Answer:** Gas costs accumulated during instruction visit:

**Cost accumulation:**
1. Start new basic block with zero cost
2. For each instruction, add cost to running total
3. At block end, store total cost for patching

**Cost model types:**
- **Naive**: Fixed cost per instruction type (simple but accurate enough)
- **Custom**: Hooks for more sophisticated models (future)

**Instruction length limits:**
- Debug builds check maximum native code length per PVM instruction
- Catches pathological encodings early
- Typical limit: ~30 bytes per instruction
- Helps identify code generation bugs

## Q11: How are guest PC ↔ native offset mappings maintained?

**Answer:** Mapping tracked during compilation:

**Data structures:**
- Sorted list of (PC, native_offset) pairs
- Map from export PC to native entry point
- Reverse lookup for trap recovery

**Recording:**
1. Before compilation: Initialize with (PC=0, native_offset=start)
2. After each instruction: Append (next_pc, current_native_length)
3. For exports: Store entry point in separate map

**Usage:**
- **Debugging**: Translate native crash address to PVM PC
- **Trap recovery**: Find PVM instruction that caused trap
- **Profiling**: Map execution back to source
- **Validation**: Verify jump targets are valid

## Q12: What sandbox differences matter for codegen?

**Answer:** Sandbox type affects addressing and memory layout:

**Linux sandbox:**
- Fixed virtual addresses (VM_ADDR_VMCTX, VM_ADDR_NATIVE_CODE, VM_ADDR_JUMP_TABLE)
- Segment-based addressing (gs:) for jump table
- Process isolation for security
- Separate PID, can use signals

**Generic sandbox:**
- Mapped memory addresses (not fixed)
- RIP-relative addressing for jump table
- In-process execution (no process isolation)
- No PID, signals handled differently

**Portability mechanisms:**
- Both expose AddressTable (host function addresses)
- Both expose OffsetTable (VM context field offsets)
- Code generation abstracts addressing differences
- Backend selects appropriate addressing mode

**Impact:**
- Same code works for both sandboxes
- Run-time selects sandbox implementation
- Compilation is sandbox-agnostic

## Open Questions

**Future possibilities:**
- Are there planned non-x86 backends? Currently only amd64 exists. ARM64 would be a natural next step.
- Any planned optimized cost models? Hooks exist for custom cost models. Could implement static analysis or profiling-based costs.


