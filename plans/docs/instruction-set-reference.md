# PolkaVM Instruction Set Reference

## Overview

PolkaVM uses a RISC-style instruction set with variable-length encoding. Instructions operate on 13 general-purpose registers and support both 32-bit and 64-bit modes.

## Registers

### Register File

| Name | Number | ABI Name | Description |
|------|--------|----------|-------------|
| RA   | 0      | r0       | Return address |
| SP   | 1      | r1       | Stack pointer |
| T0   | 2      | r2       | Temporary |
| T1   | 3      | r3       | Temporary |
| T2   | 4      | r4       | Temporary |
| S0   | 5      | r5       | Saved register |
| S1   | 6      | r6       | Saved register |
| A0   | 7      | r7       | Argument/Return value |
| A1   | 8      | r8       | Argument/Return value |
| A2   | 9      | r9       | Argument |
| A3   | 10     | r10      | Argument |
| A4   | 11     | r11      | Argument |
| A5   | 12     | r12      | Argument |

### Register Conventions

- **A0-A5**: Argument and return value registers
- **T0-T2**: Temporary registers (caller-saved)
- **S0-S1**: Saved registers (callee-saved)
- **RA**: Return address (implicitly used by calls)
- **SP**: Stack pointer (implicitly used by stack operations)

## Instruction Formats

### Format Types

1. **argless** - No operands
2. **reg** - Single register operand
3. **reg_imm** - Register + immediate
4. **reg_imm_offset** - Register + two immediates (second is PC offset)
5. **reg_imm_imm** - Register + two immediates
6. **reg_reg** - Two registers
7. **reg_reg_imm** - Two registers + immediate
8. **reg_reg_offset** - Two registers + offset
9. **reg_reg_reg** - Three registers
10. **offset** - Single PC-relative offset
11. **imm** - Single immediate
12. **imm_imm** - Two immediates
13. **reg_reg_imm_imm** - Two registers + two immediates
14. **reg_imm64** - Register + 64-bit immediate

## Instruction Categories

### 1. Control Flow

#### trap
**Format:** argless
**Opcode:** 0
**Description:** Trap to host. Terminates execution and returns to host with trap reason.

```
trap
```

#### ecalli
**Format:** imm
**Opcode:** 10
**Description:** Environment call with immediate. Invokes host function with immediate as argument.

```
ecalli imm
```
- `imm`: Host call identifier

#### jump (indirect)
**Format:** offset
**Opcode:** 40
**Description:** Indirect jump through jump table. Jumps to address specified by jump table entry.

```
jump offset
```
- `offset`: Index into jump table

### 2. Branch Instructions

Conditional branches compare values and jump if condition is met.

#### branch_eq
**Format:** reg_reg_offset
**Opcode:** 170
**Description:** Branch if registers are equal.

```
branch_eq reg1, reg2, offset
```

#### branch_not_eq
**Format:** reg_reg_offset
**Opcode:** 171
**Description:** Branch if registers are not equal.

```
branch_not_eq reg1, reg2, offset
```

#### branch_less_unsigned
**Format:** reg_reg_offset
**Opcode:** 172
**Description:** Branch if reg1 < reg2 (unsigned).

```
branch_less_unsigned reg1, reg2, offset
```

#### branch_less_signed
**Format:** reg_reg_offset
**Opcode:** 173
**Description:** Branch if reg1 < reg2 (signed).

```
branch_less_signed reg1, reg2, offset
```

#### branch_greater_or_equal_unsigned
**Format:** reg_reg_offset
**Opcode:** 174
**Description:** Branch if reg1 >= reg2 (unsigned).

```
branch_greater_or_equal_unsigned reg1, reg2, offset
```

#### branch_greater_or_equal_signed
**Format:** reg_reg_offset
**Opcode:** 175
**Description:** Branch if reg1 >= reg2 (signed).

```
branch_greater_or_equal_signed reg1, reg2, offset
```

### 3. Load/Store Instructions

#### load_imm_u8
**Format:** reg_imm
**Opcode:** 20
**Description:** Load zero-extended 8-bit immediate into register.

```
load_imm_u8 reg, imm
```

#### load_imm_u16
**Format:** reg_imm
**Opcode:** 21
**Description:** Load zero-extended 16-bit immediate into register.

```
load_imm_u16 reg, imm
```

#### load_imm_u32
**Format:** reg_imm
**Opcode:** 22
**Description:** Load zero-extended 32-bit immediate into register.

```
load_imm_u32 reg, imm
```

#### load_imm_u64
**Format:** reg_imm64
**Opcode:** 23
**Description:** Load 64-bit immediate into register.

```
load_imm_u64 reg, imm
```

#### load_imm_s32
**Format:** reg_imm
**Opcode:** 24
**Description:** Load sign-extended 32-bit immediate into register.

```
load_imm_s32 reg, imm
```

#### load_8
**Format:** reg_reg_imm
**Opcode:** 50
**Description:** Load zero-extended byte from memory.

```
load_8 dest, base, offset
```
- Effective address: base + offset

#### load_8_signed
**Format:** reg_reg_imm
**Opcode:** 51
**Description:** Load sign-extended byte from memory.

```
load_8_signed dest, base, offset
```

#### load_16
**Format:** reg_reg_imm
**Opcode:** 52
**Description:** Load zero-extended 16-bit value from memory.

```
load_16 dest, base, offset
```

#### load_16_signed
**Format:** reg_reg_imm
**Opcode:** 53
**Description:** Load sign-extended 16-bit value from memory.

```
load_16_signed dest, base, offset
```

#### load_32
**Format:** reg_reg_imm
**Opcode:** 54
**Description:** Load zero-extended 32-bit value from memory.

```
load_32 dest, base, offset
```

#### load_32_signed
**Format:** reg_reg_imm
**Opcode:** 55
**Description:** Load sign-extended 32-bit value from memory.

```
load_32_signed dest, base, offset
```

#### load_64
**Format:** reg_reg_imm
**Opcode:** 56
**Description:** Load 64-bit value from memory.

```
load_64 dest, base, offset
```

#### store_imm_u8
**Format:** imm
**Opcode:** 30
**Description:** Store 8-bit immediate to address in A0.

```
store_imm_u8 imm
```
- Stores to address: A0 + imm

#### store_imm_u16
**Format:** imm
**Opcode:** 31
**Description:** Store 16-bit immediate to address in A0.

```
store_imm_u16 imm
```

#### store_imm_u32
**Format:** imm
**Opcode:** 32
**Description:** Store 32-bit immediate to address in A0.

```
store_imm_u32 imm
```

#### store_imm_u64
**Format:** imm
**Opcode:** 33
**Description:** Store 64-bit immediate to address in A0.

```
store_imm_u64 imm
```

#### store_8
**Format:** reg_reg_imm
**Opcode:** 60
**Description:** Store byte to memory.

```
store_8 src, base, offset
```

#### store_16
**Format:** reg_reg_imm
**Opcode:** 61
**Description:** Store 16-bit value to memory.

```
store_16 src, base, offset
```

#### store_32
**Format:** reg_reg_imm
**Opcode:** 62
**Description:** Store 32-bit value to memory.

```
store_32 src, base, offset
```

#### store_64
**Format:** reg_reg_imm
**Opcode:** 63
**Description:** Store 64-bit value to memory.

```
store_64 src, base, offset
```

### 4. Arithmetic Instructions

#### add_32 / add_64
**Format:** reg_reg_imm
**Opcode:** 190 (32-bit), 200 (64-bit)
**Description:** Add register, immediate, and carry.

```
add_32 dest, src, imm
add_64 dest, src, imm
```
- Operation: dest = src + imm

#### sub_32 / sub_64
**Format:** reg_reg_imm
**Opcode:** 191 (32-bit), 201 (64-bit)
**Description:** Subtract immediate from register.

```
sub_32 dest, src, imm
sub_64 dest, src, imm
```
- Operation: dest = src - imm

#### mul_32 / mul_64
**Format:** reg_reg_imm
**Opcode:** 192 (32-bit), 202 (64-bit)
**Description:** Multiply register by immediate.

```
mul_32 dest, src, imm
mul_64 dest, src, imm
```
- Operation: dest = src * imm

#### mul_upper_signed_signed
**Format:** reg_reg
**Opcode:** 213
**Description:** Multiply upper signed × signed. Returns high bits of multiplication.

```
mul_upper_signed_signed dest, src
```
- Operation: dest = (dest × src) >> width

#### mul_upper_unsigned_unsigned
**Format:** reg_reg
**Opcode:** 214
**Description:** Multiply upper unsigned × unsigned.

```
mul_upper_unsigned_unsigned dest, src
```

#### mul_upper_signed_unsigned
**Format:** reg_reg
**Opcode:** 215
**Description:** Multiply upper signed × unsigned.

```
mul_upper_signed_unsigned dest, src
```

#### div_unsigned_32 / div_unsigned_64
**Format:** reg_reg
**Opcode:** 193 (32-bit), 203 (64-bit)
**Description:** Unsigned division.

```
div_unsigned_32 dest, src
div_unsigned_64 dest, src
```
- Operation: dest = dest / src
- Traps on division by zero

#### div_signed_32 / div_signed_64
**Format:** reg_reg
**Opcode:** 194 (32-bit), 204 (64-bit)
**Description:** Signed division.

```
div_signed_32 dest, src
div_signed_64 dest, src
```
- Traps on division by zero
- Traps on overflow (INT_MIN / -1)

#### rem_unsigned_32 / rem_unsigned_64
**Format:** reg_reg
**Opcode:** 195 (32-bit), 205 (64-bit)
**Description:** Unsigned remainder.

```
rem_unsigned_32 dest, src
rem_unsigned_64 dest, src
```
- Operation: dest = dest % src

#### rem_signed_32 / rem_signed_64
**Format:** reg_reg
**Opcode:** 196 (32-bit), 206 (64-bit)
**Description:** Signed remainder.

```
rem_signed_32 dest, src
rem_signed_64 dest, src
```

### 5. Logical Instructions

#### and
**Format:** reg_reg_imm
**Opcode:** 210
**Description:** Bitwise AND.

```
and dest, src, imm
```

#### or
**Format:** reg_reg_imm
**Opcode:** 212
**Description:** Bitwise OR.

```
or dest, src, imm
```

#### xor
**Format:** reg_reg_imm
**Opcode:** 211
**Description:** Bitwise XOR.

```
xor dest, src, imm
```

#### and_inverted
**Format:** reg_reg_imm
**Opcode:** 224
**Description:** Bitwise AND with inverted immediate.

```
and_inverted dest, src, imm
```
- Operation: dest = src & ~imm

#### or_inverted
**Format:** reg_reg_imm
**Opcode:** 225
**Description:** Bitwise OR with inverted immediate.

```
or_inverted dest, src, imm
```
- Operation: dest = src | ~imm

#### xnor
**Format:** reg_reg_imm
**Opcode:** 226
**Description:** Bitwise XNOR (XOR with NOT).

```
xnor dest, src, imm
```
- Operation: dest = ~(src ^ imm)

### 6. Comparison Instructions

#### set_less_than_unsigned
**Format:** reg_reg_imm
**Opcode:** 216
**Description:** Set register to 1 if src < imm (unsigned), else 0.

```
set_less_than_unsigned dest, src, imm
```

#### set_less_than_signed
**Format:** reg_reg_imm
**Opcode:** 217
**Description:** Set register to 1 if src < imm (signed), else 0.

```
set_less_than_signed dest, src, imm
```

#### set_less_than_unsigned_imm
**Format:** reg_imm_offset
**Opcode:** 140
**Description:** Set register to 1 if reg < imm (unsigned), else 0.

```
set_less_than_unsigned_imm reg, imm, unused_offset
```

#### set_greater_than_signed_imm
**Format:** reg_imm_offset
**Opcode:** 141
**Description:** Set register to 1 if reg > imm (signed), else 0.

```
set_greater_than_signed_imm reg, imm, unused_offset
```

### 7. Shift and Rotate Instructions

#### shift_logical_left_32 / shift_logical_left_64
**Format:** reg_reg
**Opcode:** 197 (32-bit), 207 (64-bit)
**Description:** Logical left shift.

```
shift_logical_left_32 dest, count
shift_logical_left_64 dest, count
```
- Operation: dest = dest << (count & 31/63)

#### shift_logical_right_32 / shift_logical_right_64
**Format:** reg_reg
**Opcode:** 198 (32-bit), 208 (64-bit)
**Description:** Logical right shift.

```
shift_logical_right_32 dest, count
shift_logical_right_64 dest, count
```

#### shift_arithmetic_right_32 / shift_arithmetic_right_64
**Format:** reg_reg
**Opcode:** 199 (32-bit), 209 (64-bit)
**Description:** Arithmetic right shift (sign-extended).

```
shift_arithmetic_right_32 dest, count
shift_arithmetic_right_64 dest, count
```

#### shift_logical_left_imm_alt_32 / shift_logical_left_imm_alt_64
**Format:** reg_imm_offset
**Opcode:** 144 (32-bit), 155 (64-bit)
**Description:** Logical left shift by immediate.

```
shift_logical_left_imm_alt_32 reg, shift, unused
```

#### shift_logical_right_imm_alt_32 / shift_logical_right_imm_alt_64
**Format:** reg_imm_offset
**Opcode:** 145 (32-bit), 156 (64-bit)
**Description:** Logical right shift by immediate.

```
shift_logical_right_imm_alt_32 reg, shift, unused
```

#### shift_arithmetic_right_imm_alt_32 / shift_arithmetic_right_imm_alt_64
**Format:** reg_imm_offset
**Opcode:** 146 (32-bit), 157 (64-bit)
**Description:** Arithmetic right shift by immediate.

```
shift_arithmetic_right_imm_alt_32 reg, shift, unused
```

#### rotate_left_32 / rotate_left_64
**Format:** reg_reg
**Opcode:** 221 (32-bit), 220 (64-bit)
**Description:** Rotate left.

```
rotate_left_32 dest, count
rotate_left_64 dest, count
```

#### rotate_right_32 / rotate_right_64
**Format:** reg_reg
**Opcode:** 223 (32-bit), 222 (64-bit)
**Description:** Rotate right.

```
rotate_right_32 dest, count
rotate_right_64 dest, count
```

#### rotate_right_imm_32 / rotate_right_imm_64
**Format:** reg_imm_offset
**Opcode:** 160 (32-bit), 158 (64-bit)
**Description:** Rotate right by immediate.

```
rotate_right_imm_32 reg, shift, unused
```

#### rotate_right_imm_alt_32 / rotate_right_imm_alt_64
**Format:** reg_imm_offset
**Opcode:** 161 (32-bit), 159 (64-bit)
**Description:** Alternate rotate right by immediate.

```
rotate_right_imm_alt_32 reg, shift, unused
```

### 8. Conditional Move Instructions

#### cmov_if_zero
**Format:** reg_reg_imm
**Opcode:** 218
**Description:** Conditional move if source is zero.

```
cmov_if_zero dest, src, value
```
- Operation: if src == 0 then dest = value

#### cmov_if_not_zero
**Format:** reg_reg_imm
**Opcode:** 219
**Description:** Conditional move if source is non-zero.

```
cmov_if_not_zero dest, src, value
```
- Operation: if src != 0 then dest = value

#### cmov_if_zero_imm
**Format:** reg_imm_offset
**Opcode:** 147
**Description:** Conditional move if register is zero (immediate form).

```
cmov_if_zero_imm reg, value, unused
```

#### cmov_if_not_zero_imm
**Format:** reg_imm_offset
**Opcode:** 148
**Description:** Conditional move if register is non-zero (immediate form).

```
cmov_if_not_zero_imm reg, value, unused
```

### 9. Min/Max Instructions

#### maximum
**Format:** reg_reg_imm
**Opcode:** 227
**Description:** Signed maximum.

```
maximum dest, src, imm
```
- Operation: dest = max(src, imm) (signed)

#### maximum_unsigned
**Format:** reg_reg_imm
**Opcode:** 228
**Description:** Unsigned maximum.

```
maximum_unsigned dest, src, imm
```

#### minimum
**Format:** reg_reg_imm
**Opcode:** 229
**Description:** Signed minimum.

```
minimum dest, src, imm
```

#### minimum_unsigned
**Format:** reg_reg_imm
**Opcode:** 230
**Description:** Unsigned minimum.

```
minimum_unsigned dest, src, imm
```

### 10. Bit Manipulation Instructions

#### count_leading_zero_bits_32 / count_leading_zero_bits_64
**Format:** reg
**Opcode:** 104 (32-bit), 105 (64-bit)
**Description:** Count leading zero bits.

```
count_leading_zero_bits_32 reg
count_leading_zero_bits_64 reg
```
- Returns number of leading zeros in reg

#### count_trailing_zero_bits_32 / count_trailing_zero_bits_64
**Format:** reg
**Opcode:** 106 (32-bit), 107 (64-bit)
**Description:** Count trailing zero bits.

```
count_trailing_zero_bits_32 reg
count_trailing_zero_bits_64 reg
```

#### count_ones
**Format:** reg
**Opcode:** 108
**Description:** Count set bits (population count).

```
count_ones reg
```

#### swap_bytes
**Format:** reg
**Opcode:** 109
**Description:** Reverse byte order.

```
swap_bytes reg
```

### 11. Special Instructions

#### move_reg
**Format:** reg_reg
**Opcode:** 100
**Description:** Move value between registers.

```
move_reg dest, src
```

#### memcpy
**Format:** reg_reg
**Opcode:** 110
**Description:** Copy memory block.

```
memcpy src, dest
```
- Uses A2 as count register
- Copies A2 bytes from src to dest

#### memset
**Format:** argless
**Opcode:** 120
**Description:** Fill memory block.

```
memset
```
- Uses A0 as destination, A1 as value, A2 as count
- Fills A2 bytes at A0 with value A1

#### unlikely
**Format:** argless
**Opcode:** 150
**Description:** Hint that execution path is unlikely (for optimization).

```
unlikely
```

#### fallthrough
**Format:** argless
**Opcode:** 151
**Description:** Fall through to next instruction.

```
fallthrough
```

## Semantics and Behavior

### Register Width

- **32-bit mode**: Operations work on 32-bit values, results are zero-extended or sign-extended
- **64-bit mode**: Operations work on 64-bit values
- Some instructions have explicit _32 or _64 variants

### Immediate Sign Extension

- `load_*_signed` instructions sign-extend to full register width
- `load_*` (without _signed) zero-extend
- Immediate values in arithmetic are sign-extended as needed

### Memory Alignment

- No alignment requirement for loads/stores
- Unaligned access is supported but may be slower

### Overflow Behavior

- Signed overflow wraps (two's complement)
- Unsigned overflow wraps
- Division overflow (INT_MIN / -1) traps
- Division by zero traps

### Branch Behavior

- Branch offsets are relative to current PC
- Taken branches skip to target
- Fall-through continues to next instruction
- Conditional branches use full register comparison

## Instruction Encoding Details

See [program-blob-format.md](program-blob-format.md) for binary encoding details.

## Opcode Summary Table

| Category | Instructions |
|----------|--------------|
| Control Flow | trap (0), ecalli (10), jump (40) |
| Branch | branch_eq (170-175) |
| Load Immediate | load_imm_* (20-24) |
| Load from Memory | load_* (50-56) |
| Store Immediate | store_imm_* (30-33) |
| Store to Memory | store_* (60-63) |
| Arithmetic | add_* (190, 200), sub_* (191, 201), mul_* (192, 202, 213-215), div_* (193-194, 203-204), rem_* (195-196, 205-206) |
| Logical | and (210), or (212), xor (211), and_inverted (224), or_inverted (225), xnor (226) |
| Comparison | set_less_than_* (216-217), set_*_imm (140-141) |
| Shift/Rotate | shift_*_left (197, 207), shift_*_right (198-199, 208-209), shift_*_imm_alt (144-146, 155-157), rotate_* (220-223), rotate_*_imm (158-161) |
| Conditional Move | cmov_* (218-219), cmov_*_imm (147-148) |
| Min/Max | maximum (227-228), minimum (229-230) |
| Bit Manipulation | count_leading_zero_bits_* (104-105), count_trailing_zero_bits_* (106-107), count_ones (108), swap_bytes (109) |
| Special | move_reg (100), memcpy (110), memset (120), unlikely (150), fallthrough (151) |

## Implementation Notes

The instruction set is implemented in the core PolkaVM compiler with:
- A comprehensive instruction definition system with visitor pattern for code generation
- Backend-specific implementations for each supported architecture (e.g., AMD64/x86-64)
- Optimized encoding and decoding routines for fast program execution

For detailed implementation examples and architecture-specific code generation patterns, refer to the compiler implementation guides and architecture backend documentation.
