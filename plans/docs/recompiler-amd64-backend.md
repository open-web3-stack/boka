# AMD64 Backend Deep Dive

## Overview

The AMD64 backend implements instruction selection and emission for compiling PolkaVM's ISA to x86-64 machine code. It uses a small assembler domain-specific language (DSL) for efficient code generation and relies on a fixed register mapping from guest to host registers.

### Key Components

- **Assembler DSL**: Provides a fluent interface for x86-64 instruction emission
- **Register mapping**: Fixed mapping between PolkaVM registers and x86-64 registers
- **Sandbox abstraction**: Supports both Linux and Generic sandbox modes with different memory addressing schemes

### Temporary Registers

The backend uses two temporary x86-64 registers for internal operations:
- `rcx` (TMP_REG): Primary temporary for shift counts and intermediate values
- `r15` (AUX_TMP_REG): Auxiliary temporary for complex operations

## Key Building Blocks

### Label Resolution

Label resolution helpers automatically choose between short (8-bit) and near (32-bit) branch displacements to minimize code size:
- **calculate_label_offset**: Computes distance between current position and target label
- **branch_to_label**: Emits conditional branch with optimal displacement
- **jump_to_label**: Emits unconditional jump with optimal displacement

This optimization is applied during code generation to produce compact binaries.

### Memory Operand Abstraction

A memory operand macro abstracts addressing differences between Linux and Generic sandboxes:
- **Base + offset** mode: `[base + offset]` for simple addressing
- **Absolute addressing**: Direct absolute addresses for constant memory locations
- **RIP-relative addressing**: Position-independent code for Generic sandbox
- **Base + index** mode: `[base + index*scale]` for array access

The macro automatically selects the appropriate addressing mode based on the target sandbox.

### VmCtx Field Access

Helper functions compute operands for accessing VmCtx (VM context) fields:
- **vmctx_field**: Direct operand for VmCtx field access
- **load_vmctx_field_address**: Loads address of a VmCtx field into a register

These functions use sandbox-specific offsets to access the shared VM context structure.

## Instruction Patterns

### Arithmetic and Logical Operations

ALU operations (add, sub, and, or, xor) emit different forms based on operands:
- **Register form**: Both operands are registers (e.g., `add rax, rbx`)
- **Immediate form**: One operand is an immediate value (e.g., `add rax, 42`)
- **Sign/zero extension**: In 64-bit mode, 32-bit operations automatically zero-extend results to 64 bits

### Shift and Rotate Operations

Shifts and rotates use the x86-64 convention where `rcx` holds the shift count:
- Move shift count to `rcx` if not already there
- Perform shift/rotate operation
- Sign-extend or zero-extend result as needed

The backend automatically handles operand movement and result extension.

### Division and Remainder

Division preserves RISC-V semantics with special handling:
- **Divide-by-zero guards**: Check divisor and trap if zero
- **Overflow guards**: Check for INT_MIN/-1 case and trap
- **Register saving**: Save `rax` and `rdx` before division (they hold quotient/remainder)
- **Register restoration**: Restore clobbered registers after division

The backend uses the `rax:rdx` register pair for 128-bit division results.

### Bit Manipulation Operations

Bit counting operations map to CPU instruction extensions when available:
- **LZCNT** (leading zero count): BMI1 instruction
- **TZCNT** (trailing zero count): BMI1 instruction
- **POPCNT** (population count): POPCNT instruction

The backend detects CPU feature support and uses the appropriate instruction or falls back to software implementation.

### Load and Store Operations

Memory access helpers choose the proper addressing mode:
- **32-bit loads**: Zero-extend to 64 bits when appropriate (e.g., I32 vs U32)
- **Sign extension**: Apply sign extension for signed load variants
- **Address calculation**: Compute effective addresses using base + displacement

The backend optimizes for common patterns like sequential access and structure field access.

## Control Flow

### Direct Branches

Conditional branches compare values and jump based on the result:
- Emit comparison instruction (`cmp` or `test`)
- Fold immediate values into comparison when possible
- Emit conditional branch with optimal displacement

The backend optimizes branch targets to use short displacements when possible.

### Indirect Jumps

Indirect jumps through jump tables use different strategies per sandbox:
- **Linux sandbox**: Uses `gs:[target*8]` segment addressing for direct jump table access
- **Generic sandbox**: Builds RIP-relative address and loads pointer through memory

The jump table index is multiplied by the entry size (8 bytes) to access the target address.

### Trampoline Calls

Calls to trampolines use different mechanisms:
- **Ecall/step**: `call_label32` for environment calls and single-stepping
- **Trap**: Direct `jmp` to host trap handler address
- **Return**: Direct `jmp` to host return handler address

Trampolines save all guest state and transition control to the host runtime.

## Memset and Gas Integration

### Fast Path Memset

The inline fast path for `memset` uses the x86-64 `rep stosb` instruction:
- **Guest register alignment**: A0→rdi (destination), A1→rax (value), A2→rcx (count)
- **Inline execution**: Runs fully in generated code without trampoline calls
- **Efficiency**: Single instruction for memory filling operation

### Gas Metering Integration

When gas metering is enabled, `memset` uses a slower path:
- **Pre-charge gas**: Deduct gas cost before operation
- **Restart address**: Store address to resume if interrupted
- **Fast/slow path**: Either continue inline or compute bytes possible and exit with NotEnoughGas error

The slow path handles partial operations when gas is insufficient.

## Gas Metering Stub

At the start of each basic block, a gas metering stub is emitted:
- **Decrement gas**: Subtract a patched immediate from `vmctx.gas`
- **Check negative**: Branch to trap if gas becomes negative
- **Trap offset**: Encoding is carefully sized to compute `GAS_METERING_TRAP_OFFSET`

The trap handler uses the offset to locate and refund the gas counter from the machine code bytes.

## Trap and Page Fault Handling

### Signal Trap Handler

The `on_signal_trap` function classifies and handles traps:
- **Classification**: Determine if trap is due to out-of-gas, memset fault, or other reasons
- **Update PCs**: Set `program_counter` and `next_native_program_counter` for recovery
- **Gas refund**: Refund gas using the patched immediate from the trap stub
- **Recoverability**: Indicate whether execution can safely continue

### Page Fault Handler

The `on_page_fault` function handles memory access violations:
- **Update PCs**: Set program counters for resume after paging
- **Memset recovery**: Complete interrupted memset operations
- **Next PC**: Set `next_native_program_counter` to resume execution

## Sandbox Differences

### Linux Sandbox

The Linux sandbox uses OS-level isolation with specific addressing:
- **VMCtx register**: `LINUX_SANDBOX_VMCTX_REG` holds the address of `VmCtx`
- **Fixed addresses**: VmCtx and jump tables at fixed high addresses unreachable to 32-bit guest code
- **GS segment**: Uses `gs:` segment for jump table addressing
- **Zygote model**: Worker processes forked from a template process for fast startup
- **Process isolation**: Separate process with restricted system call access

### Generic Sandbox

The Generic sandbox is an experimental implementation:
- **Local mapping**: VM memory mapped into host process address space
- **Computed addresses**: VmCtx and jump table addresses computed at runtime
- **No segments**: Does not use x86-64 segment registers
- **Not production-ready**: Intended for development and testing only

## Register Mapping

### Guest to Host Mapping

The backend uses a fixed mapping from PolkaVM registers to x86-64 registers:

| Guest Reg | Host Reg | Purpose |
|-----------|----------|---------|
| A0 | rdi | Argument/Return value 0 |
| A1 | rax | Argument/Return value 1 |
| SP | rsi | Stack pointer |
| RA | rbx | Return address |
| A2 | rdx | Argument 2 |
| A3 | rbp | Argument 3 |
| S0 | r8 | Saved register 0 |
| S1 | r9 | Saved register 1 |
| A4 | r10 | Argument 4 |
| A5 | r11 | Argument 5 |
| T0 | r13 | Temporary 0 |
| T1 | r14 | Temporary 1 |
| T2 | r12 | Temporary 2 |
| TMP_REG | rcx | Temporary (internal) |
| AUX_TMP_REG | r15 | Auxiliary temporary (internal) |

This mapping is designed to:
- Use argument registers for common operations (A0→rdi for first arg)
- Preserve caller-saved registers across calls (S0→r8, S1→r9)
- Minimize register moves for common instruction patterns

## Memory Layout

### Guest Address Space

The guest address space is 32-bit and partitioned with guard pages:

```
[guard] RO data [guard] RW data [guard] stack [guard] AUX [guard]
```

### Key Addresses

- **RO data start**: `0x10000` (page-aligned, `ro_data_address`)
- **RW data start**: After guard page and RO region
- **Stack**: High memory range below `0xffff0000`
- **Stack bounds**: `stack_address_low` and `stack_address_high` define limits
- **AUX region**: Above stack (`aux_data_address/range`)
- **Heap base**: Same as RW data start
- **Heap tracking**: Max heap size and growth tracked in `VmCtx.heap_info`

### Special Sentinel

Jumping to `0xffff0000` (`VM_ADDR_RETURN_TO_HOST`) signals normal termination and return to the host.

## Security Model

### Process Isolation (Linux Sandbox)

Compiled execution runs in a separate sandboxed worker process using a zygote model:
- **Shared VmCtx**: Host and sandbox communicate via a shared memory region
- **Futex synchronization**: Efficient signaling between host and sandbox
- **Fixed addresses**: Code and jump tables at 64-bit addresses unreachable to 32-bit guest code
- **System call filtering**: Restricted system call access via seccomp

### Memory Protections

Memory regions are protected with OS-level security:
- **RO region**: Read-only, any write attempt triggers fault
- **RW region**: Read-write for guest data and heap
- **Stack**: Read-write with guard pages for overflow detection
- **AUX region**: Read-write for auxiliary data

### Dynamic Paging

When dynamic paging is enabled:
- **userfaultfd**: Mediates page faults for on-demand memory allocation
- **Lazy allocation**: Pages allocated on first access
- **Growth tracking**: Heap growth monitored and limited

Without dynamic paging, invalid accesses trap and terminate execution.

### Host API Gating

Host APIs validate memory access:
- **Layout checks**: Verify access is within valid guest memory regions
- **Bounds checking**: Prevent out-of-bounds reads and writes
- **Type checking**: Ensure operations match region types (RO vs RW)

### Non-Canonical Jumps

Indirect jumps through jump tables use safe addressing:
- **Invalid entries**: Point to `JUMP_TABLE_INVALID_ADDRESS` (non-canonical address)
- **CPU fault**: Non-canonical addresses fault immediately without updating RIP
- **State preservation**: Fault occurs before state change, enabling safe recovery
- **Validation**: Bitmask validates jump targets before execution

### Host Boundary Hardening

Trampolines ensure controlled transitions between guest and host:
- **Save state**: All guest registers saved to VmCtx before host transition
- **Next PC**: Set `next_native_program_counter` for resume after host call
- **Controlled addresses**: Jump to host addresses from sandbox AddressTable (not guest-controlled)
- **Zygote isolation**: Host calls handled in separate process for additional isolation

### Security Default

The Linux sandbox is the secure, production-ready option. The Generic sandbox is experimental and not suitable for production use.

## Host Calls (ecalli)

### Call Sequence

When guest issues `ecalli imm`:
1. **Write args**: Store `VmCtx.arg = imm`
2. **Set PCs**: `program_counter = pc`, `next_program_counter = pc + len`
3. **Call trampoline**: Jump to ecall trampoline

### Trampoline Operation

The ecall trampoline:
1. **Save state**: Save return address and all guest registers
2. **Jump to host**: Transfer control to `AddressTable.syscall_hostcall`
3. **Change state**: Switch to hostcall state
4. **Signal host**: Wake host via futex
5. **Return**: Surface `InterruptKind::Ecalli(imm)` to user

### Return to Guest

Returning uses sysenter/sysreturn trampolines:
- **Restore state**: Restore all guest registers from VmCtx
- **Resume**: Continue execution at `next_native_program_counter`

## Performance Optimizations

### Compact Encodings

The backend optimizes instruction encoding:
- **Label distance analysis**: Choose 8-bit vs 32-bit branch displacements
- **Addressing modes**: Select direct vs RIP-relative vs absolute forms
- **Size minimization**: Reduce instruction bytes for better cache utilization

### Register Mapping

The fixed guest-to-host mapping optimizes for common patterns:
- **Argument registers**: Map to x86-64 ABI registers (A0→rdi, A1→rax)
- **Reduced moves**: Minimize register shuffling for common operations
- **Short encodings**: Use registers that enable short instruction forms

### Indirect Jump Optimization

Different strategies per sandbox:
- **Linux**: Use `gs:` indexed addressing to avoid materializing table address
- **Generic**: Use short sequence to compute jump table pointer

### Memset Fast Path

Optimized memset implementation:
- **rep stosb**: Single x86-64 instruction for memory fill
- **Register alignment**: A2/A0/A1 map directly to rcx/rdi/rax
- **No shuffles**: Eliminate register moves for inline execution

### Gas Stub Patching

Optimized gas metering:
- **Emit once**: Generate stub templates during compilation
- **Bulk patch**: Patch immediates in bulk at end of compilation
- **Low overhead**: Minimal per-instruction cost
- **Refund support**: Extract gas value from machine code for refund

### Reserved Assembler

Space-efficient emission:
- **Reserve space**: Pre-allocate exact space for instructions
- **Avoid churn**: Minimize relocations and backpatching
- **Inlining**: Aggressive inlining for throughput
- **Small wrappers**: Minimal abstraction overhead

### Caching

Compiler cache reduces allocation overhead:
- **Buffer recycling**: Reuse assembler buffers across compilations
- **Label maps**: Preserve label mappings for reuse
- **PC mappings**: Cache PC-to-native address translations

These optimizations combine to produce fast, compact native code with low compilation overhead.
