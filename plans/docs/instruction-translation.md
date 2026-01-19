# Instruction Translation Guide

## Overview

This document describes how to translate PolkaVM bytecode instructions into native machine code (specifically x86-64). Each instruction category includes translation patterns, implementation details, and optimization opportunities.

## General Principles

### 1. Register Mapping

PolkaVM registers map directly to x86-64 registers:

| PVM Reg | x86-64 Reg | Rationale |
|---------|-----------|-----------|
| A0      | rdi       | First argument (System V ABI) |
| A1      | rax       | Return value, compact encodings |
| A2      | rdx       | Third argument |
| A3      | rbp       | Fourth argument |
| SP      | rsi       | Stack pointer |
| RA      | rbx       | Callee-saved |
| S0      | r8        | Saved register |
| S1      | r9        | Saved register |
| A4      | r10       | Argument |
| A5      | r11       | Argument |
| T0      | r13       | Temporary |
| T1      | r14       | Temporary |
| T2      | r12       | Temporary |
| TMP     | rcx       | Temporary (shift counter) |
| AUX_TMP | r15       | Temporary (must save/restore) |

### 2. Immediate Encoding

- **Small immediates** (-128 to 127): Use sign-extended 8-bit
- **Medium immediates** (-2³¹ to 2³¹-1): Use 32-bit (sign-extended to 64)
- **Large immediates**: Use 64-bit

### 3. Memory Operands

Use efficient addressing modes:
- `[base + disp32]` - Base register + displacement
- `[base + index*scale + disp]` - Complex addressing
- `[rip + disp32]` - RIP-relative for globals

## Category 1: Control Flow

### trap

**Purpose:** Unconditionally trap to host

**Translation:**

```asm
; Save all registers to vmctx
push rax
push rbx
; ... (save all registers)

; Set next_native_pc = 0
mov qword [vmctx + offset_next_native_pc], 0

; Jump to trap handler
jmp [trap_handler_address]
```

**Swift Equivalent:**
```swift
func trap() -> Never {
    // Save all registers to vmctx
    // Set next_native_pc = 0
    // Jump to trap handler
    fatalError("Unconditional trap")
}
```

**Key Points:**
- Must save ALL registers
- Zero next_native_pc indicates trap (not return)
- Use absolute jump to handler address

### ecalli imm

**Purpose:** Host environment call

**Translation:**

```asm
; Store argument
mov dword [vmctx + offset_arg], imm

; Store current PC and next PC
mov dword [vmctx + offset_pc], current_pc
mov dword [vmctx + offset_next_pc], next_pc

; Save return address
push [return_address_register]

; Save all registers
; ... (save all)

; Jump to host call handler
jmp [hostcall_handler_address]
```

**Swift Equivalent:**
```swift
func ecalli(_ imm: Int32) {
    // Store argument to vmctx
    // Store current PC and next PC
    // Save return address
    // Save all registers
    // Jump to host call handler
    hostCall(argument: imm)
}
```

**Key Points:**
- Argument in vmctx.arg
- Save both PC and next PC
- Return to next instruction after host returns

### jump offset

**Purpose:** Indirect jump through jump table

**Translation (Linux sandbox):**

```asm
; Load jump table index into register
mov rax, [base_register + offset]

; Jump through table (gs: for Linux sandbox)
jmp qword [gs:rax * 8]
```

**Translation (Generic sandbox):**

```asm
; Materialize jump table address
lea r11, [rip + jump_table_label]

; Load index and scale
mov rax, [base_register + offset]
shl rax, 3  ; multiply by 8

; Load target and jump
add r11, rax
jmp qword [r11]
```

**Swift Equivalent:**
```swift
func jump(offset: Int) {
    let index = loadJumpTableIndex(offset: offset)
    let targetAddress = jumpTable[index]
    jumpTo(address: targetAddress)
}
```

**Key Points:**
- Linux uses gs: segment for fast access
- Invalid entries point to non-canonical address
- Index is PC offset aligned to VM_CODE_ADDRESS_ALIGNMENT

## Category 2: Conditional Branches

### branch_eq reg1, reg2, offset

**Purpose:** Branch if reg1 == reg2

**Translation:**

```asm
; Compare registers
cmp map(reg1), map(reg2)

; Conditional jump
je target_label
```

**Swift Equivalent:**
```swift
func branch_eq(reg1: Register, reg2: Register, offset: Int) {
    if registers[reg1] == registers[reg2] {
        jumpTo(offset: offset)
    }
}
```

**Label Handling:**
- If target already defined: emit direct branch
- If forward reference: create fixup, emit rel32 branch

**Optimization:**
- Use rel8 if displacement fits in 8-bit range
- Otherwise use rel32

### branch_less_unsigned reg1, reg2, offset

**Purpose:** Branch if reg1 < reg2 (unsigned)

**Translation:**

```asm
cmp map(reg1), map(reg2)
jb target_label
```

**Swift Equivalent:**
```swift
func branch_less_unsigned(reg1: Register, reg2: Register, offset: Int) {
    if UInt64(bitPattern: registers[reg1]) < UInt64(bitPattern: registers[reg2]) {
        jumpTo(offset: offset)
    }
}
```

**Condition Codes:**

| Instruction | Condition | x86-64 Condition |
|-------------|-----------|------------------|
| branch_eq | equal | je (ZF=1) |
| branch_not_eq | not equal | jne (ZF=0) |
| branch_less_unsigned | less (unsigned) | jb (CF=1) |
| branch_less_signed | less (signed) | jl (SF≠OF) |
| branch_ge_unsigned | greater or equal (unsigned) | jae (CF=0) |
| branch_ge_signed | greater or equal (signed) | jge (SF=OF) |

## Category 3: Load/Store Instructions

### load_8 dest, base, offset

**Purpose:** Load zero-extended byte

**Translation:**

```asm
movzx map(dest), byte [map(base) + offset]
```

**Swift Equivalent:**
```swift
func load_8(dest: Register, base: Register, offset: Int) {
    let address = registers[base] + offset
    let value = memory.loadUInt8(from: address)
    registers[dest] = UInt64(value)
}
```

**Size Variants:**

| Instruction | x86-64 Instruction |
|-------------|-------------------|
| load_8 | movzx r32, byte |
| load_8_signed | movsx r32, byte |
| load_16 | movzx r32, word |
| load_16_signed | movsx r32, word |
| load_32 | mov r32, dword (zero-extends in 64-bit mode) |
| load_32_signed | movs r64, dword |
| load_64 | mov r64, qword |

**Key Points:**
- Use movzx for zero-extension
- Use movsx for sign-extension
- In 64-bit mode, mov r32 zero-extends to r64

### store_8 src, base, offset

**Purpose:** Store byte to memory

**Translation:**

```asm
mov byte [map(base) + offset], map(src_low8)
```

**Swift Equivalent:**
```swift
func store_8(src: Register, base: Register, offset: Int) {
    let address = registers[base] + offset
    let value = UInt8(truncatingIfNeeded: registers[src])
    memory.store(value, to: address)
}
```

**Size Variants:**

| Instruction | x86-64 Instruction |
|-------------|-------------------|
| store_8 | mov byte |
| store_16 | mov word |
| store_32 | mov dword |
| store_64 | mov qword |

### load_imm_u32 reg, imm

**Purpose:** Load 32-bit immediate (zero-extended)

**Translation:**

```asm
mov map(reg), imm
```

**For 64-bit immediate:**

```asm
movabs map(reg), imm64  ; 10-byte instruction
```

**Swift Equivalent:**
```swift
func load_imm_u32(reg: Register, imm: UInt32) {
    registers[reg] = UInt64(imm)
}

func load_imm_u64(reg: Register, imm: UInt64) {
    registers[reg] = imm
}
```

**Optimization:**
- Use mov with imm32 for values that fit in 32 bits
- Use movabs only for full 64-bit values

## Category 4: Arithmetic Instructions

### add_32 dest, src, imm

**Purpose:** Add with 32-bit operands

**Translation:**

```asm
; Load source
mov eax, map(src)

; Add immediate
add eax, imm

; Store result (implicit zero-extension to 64-bit in x86-64)
mov map(dest), eax
```

**add_64 variant:**

```asm
mov rax, map(src)
add rax, imm
mov map(dest), rax
```

**Swift Equivalent:**
```swift
func add_32(dest: Register, src: Register, imm: Int32) {
    let result = UInt32(truncatingIfNeeded: registers[src]) &+ UInt32(bitPattern: imm)
    registers[dest] = UInt64(result)  // Zero-extends to 64-bit
}

func add_64(dest: Register, src: Register, imm: Int64) {
    let result = registers[src] &+ UInt64(bitPattern: imm)
    registers[dest] = result
}
```

**Optimization:**
- If dest == src: single `add map(reg), imm`
- Use lea for certain patterns: `lea reg, [reg + imm]`

### sub_32 dest, src, imm

**Purpose:** Subtract with 32-bit operands

**Translation:**

```asm
mov eax, map(src)
sub eax, imm
mov map(dest), eax
```

**Swift Equivalent:**
```swift
func sub_32(dest: Register, src: Register, imm: Int32) {
    let result = UInt32(truncatingIfNeeded: registers[src]) &- UInt32(bitPattern: imm)
    registers[dest] = UInt64(result)
}
```

### mul_32 dest, src, imm

**Purpose:** Multiply with 32-bit operands

**Translation:**

```asm
mov eax, map(src)
imul eax, imm
mov map(dest), eax
```

**Swift Equivalent:**
```swift
func mul_32(dest: Register, src: Register, imm: Int32) {
    let result = Int32(truncatingIfNeeded: registers[src]) &* imm
    registers[dest] = UInt64(truncatingIfNeeded: result)
}
```

**Key Points:**
- imul sign-extends immediate
- Result truncated to operand width

### mul_upper_signed_signed dest, src

**Purpose:** Get high bits of signed multiplication

**Translation:**

```asm
movsxd rax, map(dest)  ; Sign-extend to 64-bit
movsxd rdx, map(src)
imul rax, rdx         ; rdx:rax = 128-bit result
mov map(dest), rdx    ; Store high bits
```

**For 32-bit:**

```asm
mov eax, map(dest)
mov ecx, map(src)
imul rax, rcx         ; rdx:rax = 64-bit result
shr rax, 32           ; Get high bits
mov map(dest), eax
```

**Swift Equivalent:**
```swift
func mul_upper_signed_signed_64(dest: Register, src: Register) {
    let a = Int64(bitPattern: registers[dest])
    let b = Int64(bitPattern: registers[src])
    let result = a.multipliedFullWidth(by: b)  // (high, low)
    registers[dest] = UInt64(bitPattern: result.high)
}

func mul_upper_signed_signed_32(dest: Register, src: Register) {
    let a = Int32(truncatingIfNeeded: registers[dest])
    let b = Int32(truncatingIfNeeded: registers[src])
    let result = a.multipliedFullWidth(by: b)
    registers[dest] = UInt64(truncatingIfNeeded: result.high)
}
```

### div_unsigned_32 dest, src

**Purpose:** Unsigned division

**Translation:**

```asm
mov eax, map(dest)
xor edx, edx          ; Zero-extend to edx:eax
mov ecx, map(src)

; Check for division by zero
test ecx, ecx
jz trap_handler

div ecx               ; eax = edx:eax / ecx, edx = edx:eax % ecx
mov map(dest), eax
```

**Swift Equivalent:**
```swift
func div_unsigned_32(dest: Register, src: Register) {
    guard registers[src] != 0 else {
        trap()
    }
    let dividend = UInt64(truncatingIfNeeded: registers[dest])
    let divisor = UInt64(truncatingIfNeeded: registers[src])
    registers[dest] = dividend / divisor
}
```

**Key Points:**
- Must check for division by zero
- Zero-extend dividend into edx:eax
- Use div for unsigned, idiv for signed

### div_signed_64 dest, src

**Purpose:** Signed division with overflow check

**Translation:**

```asm
mov rax, map(dest)
cqo                   ; Sign-extend into rdx:rax
mov rcx, map(src)

; Check for division by zero
test rcx, rcx
jz trap_handler

; Check for overflow (INT64_MIN / -1)
cmp rax, -9223372036854775808
jne do_div
cmp rcx, -1
jne do_div
; Overflow case - trap
jmp trap_handler

do_div:
idiv rcx              ; rax = rdx:rax / rcx, rdx = rdx:rax % rcx
mov map(dest), rax
```

**Swift Equivalent:**
```swift
func div_signed_64(dest: Register, src: Register) {
    guard registers[src] != 0 else {
        trap()
    }

    // Check for overflow (Int64.min / -1)
    let dividend = Int64(bitPattern: registers[dest])
    let divisor = Int64(bitPattern: registers[src])

    guard !(dividend == Int64.min && divisor == -1) else {
        trap()
    }

    registers[dest] = UInt64(bitPattern: dividend / divisor)
}
```

## Category 5: Logical Instructions

### and dest, src, imm

**Purpose:** Bitwise AND

**Translation:**

```asm
mov rax, map(src)
and rax, imm
mov map(dest), rax
```

**Swift Equivalent:**
```swift
func and(dest: Register, src: Register, imm: UInt64) {
    registers[dest] = registers[src] & imm
}
```

**Optimization:**
- If imm is 0xFF, can use and with zero-extended byte
- If imm is power of 2, consider test instruction for checking

### xor dest, src, imm

**Purpose:** Bitwise XOR

**Translation:**

```asm
mov rax, map(src)
xor rax, imm
mov map(dest), rax
```

**Swift Equivalent:**
```swift
func xor(dest: Register, src: Register, imm: UInt64) {
    registers[dest] = registers[src] ^ imm
}

// Special case - zero register
func zero_register(reg: Register) {
    registers[reg] = 0
}
```

**Special Case - Zero Register:**

```asm
xor rax, rax  ; Faster than: mov rax, 0
```

### or dest, src, imm

**Purpose:** Bitwise OR

**Translation:**

```asm
mov rax, map(src)
or rax, imm
mov map(dest), rax
```

**Swift Equivalent:**
```swift
func or(dest: Register, src: Register, imm: UInt64) {
    registers[dest] = registers[src] | imm
}
```

## Category 6: Shift and Rotate

### shift_logical_left_32 dest, count

**Purpose:** Left shift

**Translation:**

```asm
mov eax, map(dest)
mov ecx, map(count)
shl eax, cl          ; Masks count to 5 bits (0-31)
mov map(dest), eax
```

**shift_logical_left_64 variant:**

```asm
mov rax, map(dest)
mov ecx, map(count)
shl rax, cl          ; Masks count to 6 bits (0-63)
mov map(dest), rax
```

**Swift Equivalent:**
```swift
func shift_logical_left_32(dest: Register, count: Register) {
    let shiftAmount = UInt32(truncatingIfNeeded: registers[count]) & 0x1F
    let result = UInt32(truncatingIfNeeded: registers[dest]) << shiftAmount
    registers[dest] = UInt64(result)
}

func shift_logical_left_64(dest: Register, count: Register) {
    let shiftAmount = registers[count] & 0x3F
    registers[dest] = registers[dest] << shiftAmount
}
```

**Key Points:**
- Shift count must be in cl (rcx low byte)
- Hardware automatically masks count
- Left shift different: shl (logical) vs. sal (same as shl)

### shift_arithmetic_right_64 dest, count

**Purpose:** Arithmetic right shift (sign-extended)

**Translation:**

```asm
mov rax, map(dest)
mov ecx, map(count)
sar rax, cl          ; Sign-filling shift
mov map(dest), rax
```

**shift_logical_right_64 variant:**

```asm
shr rax, cl          ; Zero-filling shift
```

**Swift Equivalent:**
```swift
func shift_arithmetic_right_64(dest: Register, count: Register) {
    let shiftAmount = registers[count] & 0x3F
    let value = Int64(bitPattern: registers[dest])
    registers[dest] = UInt64(bitPattern: value >> shiftAmount)
}

func shift_logical_right_64(dest: Register, count: Register) {
    let shiftAmount = registers[count] & 0x3F
    registers[dest] = registers[dest] >> shiftAmount
}
```

### rotate_right_32 dest, count

**Purpose:** Rotate right

**Translation:**

```asm
mov eax, map(dest)
mov ecx, map(count)
ror eax, cl          ; Masks count to 5 bits
mov map(dest), eax
```

**rotate_left_32 variant:**

```asm
rol eax, cl
```

**Swift Equivalent:**
```swift
func rotate_right_32(dest: Register, count: Register) {
    var value = UInt32(truncatingIfNeeded: registers[dest])
    let shiftAmount = UInt32(truncatingIfNeeded: registers[count]) & 0x1F
    value = (value >> shiftAmount) | (value << (32 - shiftAmount))
    registers[dest] = UInt64(value)
}

func rotate_left_32(dest: Register, count: Register) {
    var value = UInt32(truncatingIfNeeded: registers[dest])
    let shiftAmount = UInt32(truncatingIfNeeded: registers[count]) & 0x1F
    value = (value << shiftAmount) | (value >> (32 - shiftAmount))
    registers[dest] = UInt64(value)
}
```

## Category 7: Comparison

### set_less_than_unsigned dest, src, imm

**Purpose:** Set dest to 1 if src < imm (unsigned), else 0

**Translation:**

```asm
mov eax, map(src)
cmp eax, imm
setb al              ; al = 1 if CF=1 (less, unsigned)
movzx eax, al        ; Zero-extend to full register
mov map(dest), eax
```

**set_less_than_signed variant:**

```asm
cmp eax, imm
setl al              ; al = 1 if SF≠OF (less, signed)
movzx eax, al
```

**Swift Equivalent:**
```swift
func set_less_than_unsigned(dest: Register, src: Register, imm: UInt32) {
    let value = UInt32(truncatingIfNeeded: registers[src])
    registers[dest] = value < imm ? 1 : 0
}

func set_less_than_signed(dest: Register, src: Register, imm: Int32) {
    let value = Int32(truncatingIfNeeded: registers[src])
    registers[dest] = value < imm ? 1 : 0
}
```

**Optimization:**
- Use setcc + movzx for boolean results
- Avoid branching for boolean operations

## Category 8: Conditional Move

### cmov_if_zero dest, src, value

**Purpose:** dest = value if src == 0

**Translation:**

```asm
test map(src), map(src)
cmovz map(dest), value
```

**cmov_if_not_zero variant:**

```asm
test map(src), map(src)
cmovnz map(dest), value
```

**Swift Equivalent:**
```swift
func cmov_if_zero(dest: Register, src: Register, value: UInt64) {
    if registers[src] == 0 {
        registers[dest] = value
    }
}

func cmov_if_not_zero(dest: Register, src: Register, value: UInt64) {
    if registers[src] != 0 {
        registers[dest] = value
    }
}
```

**Key Points:**
- x86-64 has conditional move for all conditions
- Avoids branch prediction penalties
- Requires value in register

## Category 9: Bit Manipulation

### count_leading_zero_bits_32 reg

**Purpose:** Count leading zeros

**Translation:**

```asm
mov eax, map(reg)
lzcnt eax, eax        ; BMI1 instruction
mov map(reg), eax
```

**Fallback (without BMI1):**

```asm
bsr eax, map(reg)     ; Find highest set bit (index)
jnz got_result
mov eax, 31           ; All zeros
jmp done
got_result:
xor eax, 31           ; Convert to leading zero count
done:
mov map(reg), eax
```

**Swift Equivalent:**
```swift
func count_leading_zero_bits_32(reg: Register) {
    let value = UInt32(truncatingIfNeeded: registers[reg])
    registers[reg] = UInt64(value.leadingZeroBitCount)
}
```

### count_ones reg

**Purpose:** Population count

**Translation:**

```asm
mov rax, map(reg)
popcnt rax, rax       ; POPCNT instruction
mov map(reg), rax
```

**Fallback (without POPCNT):**

```asm
; Software implementation using shifts and adds
; (omitted for brevity - see reference implementation)
```

**Swift Equivalent:**
```swift
func count_ones(reg: Register) {
    registers[reg] = UInt64(registers[reg].nonzeroBitCount)
}
```

### swap_bytes reg

**Purpose:** Reverse byte order

**Translation:**

```asm
mov rax, map(reg)
bswap rax
mov map(reg), rax
```

**For 32-bit:**

```asm
mov eax, map(reg)
bswap eax
mov map(reg), eax
```

**Swift Equivalent:**
```swift
func swap_bytes_64(reg: Register) {
    registers[reg] = registers[reg].byteSwapped
}

func swap_bytes_32(reg: Register) {
    var value = UInt32(truncatingIfNeeded: registers[reg])
    value = value.byteSwapped
    registers[reg] = UInt64(value)
}
```

## Category 10: Min/Max

### minimum dest, src, imm

**Purpose:** dest = min(src, imm) signed

**Translation:**

```asm
mov eax, map(src)
cmp eax, imm
cmovl eax, imm        ; Move if less
mov map(dest), eax
```

**maximum_unsigned variant:**

```asm
mov eax, map(src)
cmp eax, imm
cmova eax, imm        ; Move if above (unsigned greater)
mov map(dest), eax
```

**Swift Equivalent:**
```swift
func minimum(dest: Register, src: Register, imm: Int64) {
    let value = Int64(bitPattern: registers[src])
    registers[dest] = UInt64(bitPattern: min(value, imm))
}

func maximum_unsigned(dest: Register, src: Register, imm: UInt64) {
    registers[dest] = max(registers[src], imm)
}
```

## Category 11: Special Instructions

### move_reg dest, src

**Purpose:** Copy register

**Translation:**

```asm
mov map(dest), map(src)
```

**Swift Equivalent:**
```swift
func move_reg(dest: Register, src: Register) {
    registers[dest] = registers[src]
}
```

**Optimization:**
- Eliminated by register allocation if possible
- Use xor reg, reg instead of mov reg, 0

### memcpy

**Purpose:** Copy memory block

**Translation (uses A2 as count):**

```asm
; Arguments: src in reg, dest in A0, count in A2
mov rsi, map(src)     ; Source
mov rdi, map(A0)      ; Destination
mov rcx, map(A2)      ; Count
rep movsb            ; Copy rcx bytes from [rsi] to [rdi]
```

**Swift Equivalent:**
```swift
func memcpy(src: Register, dest: Register, count: Int) {
    let source = registers[src]
    let destination = registers[dest]
    memory.copy(from: source, to: destination, count: count)
}
```

**Key Points:**
- Uses x86-64 string instructions
- Direction flag should be cleared (forward copy)
- Count in rcx

### memset

**Purpose:** Fill memory with value

**Fast Path (no gas metering):**

```asm
; A0=dest, A1=value, A2=count
mov rdi, map(A0)
mov rax, map(A1)
mov rcx, map(A2)
rep stosb            ; Fill rcx bytes at [rdi] with al
```

**Swift Equivalent:**
```swift
func memset(dest: Register, value: UInt8, count: Int) {
    let destination = registers[dest]
    memory.set(value: value, at: destination, count: count)
}
```

**With Gas Metering (Sync mode):**

```asm
; Pre-charge gas
sub qword [vmctx + offset_gas], map(A2)
jb memset_slow_path  ; Not enough gas

; Fast path
mov rdi, map(A0)
mov rax, map(A1)
mov rcx, map(A2)
rep stosb
jmp memset_done

memset_slow_path:
; Call memset trampoline
call memset_trampoline

memset_done:
```

**Slow Path (trampoline):**

```asm
; Compute bytes possible with remaining gas
xor ecx, ecx
xchg rcx, [vmctx + offset_gas]  ; Get remaining gas, zero gas counter
add rcx, map(A2)                ; Bytes we want to fill
sub map(A2), rcx                ; Bytes we can actually fill
mov [vmctx + offset_arg], rcx   ; Stash remaining count

; Do partial memset
mov rdi, map(A0)
mov rax, map(A1)
mov rcx, map(A2)                ; Bytes we can fill
rep stosb

; Save registers and trap
; ... (save all registers)
jmp [not_enough_gas_handler]
```

**Swift Equivalent (with gas metering):**
```swift
func memset_with_gas(dest: Register, value: UInt8, count: Int) {
    if gas_remaining >= count {
        // Fast path
        gas_remaining -= count
        memset(dest: dest, value: value, count: count)
    } else {
        // Slow path - partial fill then trap
        let bytes_to_fill = gas_remaining
        gas_remaining = 0
        memset(dest: dest, value: value, count: bytes_to_fill)
        trap()
    }
}
```

## Optimization Patterns

### 1. Immediate Selection

Choose smallest immediate encoding:

```asm
; Bad: mov eax, 1          (5 bytes)
; Good: xor eax, eax       (2 bytes)
;        inc eax           (2 bytes, total 4 bytes)
; Or: mov eax, 1          (5 bytes - simpler)
```

**Swift Equivalent:**
```swift
// Swift handles this automatically
let x: UInt64 = 1  // Compiler chooses optimal encoding
```

### 2. Register to Register Moves

```asm
; Bad: mov rax, rbx; mov rbx, rax (xchg without lock prefix)
; Good: xchg rax, rbx      (single instruction, but can be slow)
; Better: use different registers if possible
```

**Swift Equivalent:**
```swift
// Swift compiler optimizes register allocation
func swap(_ a: inout UInt64, _ b: inout UInt64) {
    swap(&a, &b)  // Compiler chooses optimal approach
}
```

### 3. Test vs. Compare

```asm
; For comparing against zero:
; Bad: cmp rax, 0
; Good: test rax, rax       (same encoding, but clearer intent)

; For checking if value is 1:
; Bad: cmp rax, 1
; Good: lea rcx, [rax - 1]; test rcx, rcx  (avoided branch on some CPUs)
```

**Swift Equivalent:**
```swift
// Swift optimizes these patterns
func is_zero(_ value: UInt64) -> Bool {
    return value == 0  // Compiler uses optimal instruction
}

func is_one(_ value: UInt64) -> Bool {
    return value == 1
}
```

### 4. Zero Extension

```asm
; In 64-bit mode, mov r32 zero-extends:
; mov eax, ecx   ; Zero-extends to rax
; Same as: mov eax, ecx; and rax, 0xFFFFFFFF
```

**Swift Equivalent:**
```swift
// Swift handles zero-extension automatically
let value32: UInt32 = /* ... */
let value64: UInt64 = UInt64(value32)  // Zero-extends
```

### 5. Load Effective Address (lea)

```asm
; Instead of: add rax, 8
; Use: lea rax, [rax + 8]  ; Same effect, no flags affected

; For complex address calculations:
lea rax, [rbx + rcx*8 + 16]  ; Single instruction
```

**Swift Equivalent:**
```swift
// Swift compiler optimizes address calculations
func array_access(base: UnsafeRawPointer, index: Int, stride: Int) -> UnsafeRawPointer {
    return base.advanced(by: index * stride + 16)  // Compiler uses lea
}
```

## Common Patterns

### Pattern: Load Immediate and Use

```asm
; Instead of:
mov rax, 42
add rbx, rax

; Use:
add rbx, 42        ; If rbx != rax
```

**Swift Equivalent:**
```swift
// Swift compiler automatically optimizes this
var x: UInt64 = 100
x += 42  // Compiler folds immediate into add instruction
```

### Pattern: Compare and Branch

```asm
; Instead of:
cmp rax, rbx
jne .Lnot_equal
; ... equal case ...
jmp .Ldone
.Lnot_equal:
; ... not equal case ...
.Ldone:

; Use:
cmp rax, rbx
jne .Lnot_equal
; ... equal case ...
.Lnot_equal:
; ... not equal case ...
```

**Swift Equivalent:**
```swift
// Swift compiler generates optimal control flow
func compare_and_branch(_ a: UInt64, _ b: UInt64) {
    if a == b {
        // equal case
    } else {
        // not equal case
    }
}
```

### Pattern: Boolean Operations

```asm
; Instead of:
cmp rax, 0
setne al
movzx eax, al

; For just testing condition:
test rax, rax
setne al   ; If you need boolean result
```

**Swift Equivalent:**
```swift
// Swift naturally expresses boolean operations
func is_nonzero(_ value: UInt64) -> Bool {
    return value != 0  // Compiler uses optimal test/setcc
}

func to_boolean(_ value: UInt64) -> UInt64 {
    return value != 0 ? 1 : 0
}
```

## Performance Considerations

### 1. Code Size

- Prefer short encodings (rel8 vs rel32, imm8 vs imm32)
- Use xor reg, reg instead of mov reg, 0
- Minimize immediate sizes

**Swift Perspective:**
```swift
// Swift compiler automatically optimizes for code size
// Use appropriate integer types
let small: UInt8 = 255    // Uses smaller encoding
let large: UInt64 = 1000  // Full 64-bit when needed
```

### 2. Branch Prediction

- Arrange likely path as fallthrough
- Use conditional moves for simple boolean selects
- Avoid complex condition calculations

**Swift Perspective:**
```swift
// Swift compiler optimizes branch prediction
// Use likely/unlikely hints when available
@inline(__always)
func conditional_branch(_ condition: Bool) {
    if condition {
        // Likely path - compiler optimizes for fallthrough
    } else {
        // Unlikely path
    }
}
```

### 3. Cache Efficiency

- Keep hot paths compact
- Align loop entries to 16/32-byte boundaries
- Minimize cross-branch jumps

**Swift Perspective:**
```swift
// Swift compiler optimizes instruction cache usage
// Keep frequently called code simple and inlineable
@inline(__always)
func hot_path(_ value: UInt64) -> UInt64 {
    return value + 1  // Simple, compact code
}
```

### 4. Register Pressure

- Reuse registers when possible
- Minimize spills to stack
- Use caller-saved registers for temporaries

**Swift Perspective:**
```swift
// Swift compiler manages register allocation
// Break complex expressions to reduce pressure
func calculate(_ a: UInt64, _ b: UInt64, _ c: UInt64) -> UInt64 {
    let temp1 = a &+ b  // Break into steps
    let temp2 = temp1 &* c
    return temp2
}
```

## Implementation Checklist

For each instruction category:
- [ ] Basic translation working
- [ ] Correct for edge cases (overflow, division by zero)
- [ ] Sign/zero-extension correct
- [ ] Gas accounting accurate
- [ ] Optimization opportunities identified
- [ ] Tested against interpreter

## References

- [Instruction Set Reference](instruction-set-reference.md) - Complete PVM opcode documentation
- [AMD64 Backend Details](recompiler-amd64-backend.md) - x86-64 specific implementation
- [Implementation Guide](implementation-guide.md) - Step-by-step implementation roadmap
- [Recompiler Deep Dive](recompiler-deep-dive.md) - Detailed implementation analysis
