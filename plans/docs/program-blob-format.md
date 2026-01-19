# PolkaVM Program Blob Format

## Overview

A PolkaVM program blob is a binary container that holds all the information needed to execute a PolkaVM program. It contains code, data, jump tables, metadata, and debugging information.

## Binary Structure

The blob is a binary format with the following high-level structure:

```
[Header]
[RO Data Section]
[RW Data Section]
[Code Section]
[Jump Table]
[Bitmask]
[Import Offsets]
[Import Symbols]
[Exports]
[Debug Strings (optional)]
[Debug Line Programs (optional)]
```

## Header

The header contains metadata about the program:

| Field | Type | Description |
|-------|------|-------------|
| `isa` | u8 | Instruction set kind (0 = 32-bit, 1 = 64-bit) |
| `ro_data_size` | varint | Size of read-only data section |
| `rw_data_size` | varint | Size of read-write data section |
| `stack_size` | varint | Size of stack |
| `ro_data` | bytes | Read-only data (length = ro_data_size) |
| `rw_data` | bytes | Read-write data (length = rw_data_size) |
| `code` | bytes | Code section |
| `jump_table` | bytes | Jump table |
| `jump_table_entry_size` | u8 | Size in bytes of each jump table entry |
| `bitmask` | bytes | Valid instruction bitmask |
| `import_offsets` | bytes | Import offset table |
| `import_symbols` | bytes | Import symbol names |
| `exports` | bytes | Export table |
| `debug_strings` | bytes (optional) | Debug string table |
| `debug_line_program_ranges` | bytes (optional) | Debug line info ranges |
| `debug_line_programs` | bytes (optional) | Debug line program info |

### Varint Encoding

Variable-length integers are encoded using LEB128 format:

- Unsigned varint: Each byte uses 7 bits for data, MSB indicates continuation
- Example: `0x81 0x01` = 129 (0b10000001 << 0 | 0b00000001 << 7)

## Code Section

The code section contains a sequence of variable-length instructions. Each instruction consists of:

1. **Opcode byte** - Identifies the operation
2. **Arguments** - Variable-length, encoding-dependent on opcode

### Instruction Encoding

Instructions are encoded compactly using variable-length arguments. The encoding pattern depends on the instruction format:

#### Format: Argless
```
[opcode]
```
Example: `trap` instruction

#### Format: reg_imm
```
[opcode] [reg:4 | imm:varint]
```
- `reg` occupies 4 bits (lower nibble of first byte after opcode)
- `imm` is encoded as varint starting from the next byte

Example: `load_imm_u8 reg=5, imm=42` encodes as:
```
[opcode] [0x05] [0x2A]
```

#### Format: reg_reg
```
[opcode] [reg1:4 | reg2:4]
```
- Both registers packed into one byte (4 bits each)

Example: `move_reg reg1=5, reg2=7` encodes as:
```
[opcode] [0x57]
```

#### Format: reg_reg_imm
```
[opcode] [reg1:4 | reg2:4] [imm:varint]
```

#### Format: reg_reg_offset
```
[opcode] [reg1:4 | reg2:4] [offset:varint]
```

#### Format: reg_reg_reg
```
[opcode] [reg1:4 | reg2:4 | reg3:8]
```
- reg1 and reg2 in first byte, reg3 in second byte

#### Format: offset
```
[opcode] [offset:varint]
```
- Offset is relative to current instruction

#### Format: imm
```
[opcode] [imm:varint]
```

#### Format: imm_imm
```
[opcode] [imm1:varint] [imm2:varint]
```

#### Format: reg_imm_offset
```
[opcode] [reg:4] [imm1:varint] [imm2:varint]
```
- Second immediate is an offset

#### Format: reg_imm_imm
```
[opcode] [reg:4] [imm1:varint] [imm2:varint]
```

#### Format: reg_reg_imm_imm
```
[opcode] [reg1:4 | reg2:4] [imm1:varint] [imm2:varint]
```

#### Format: reg_imm64
```
[opcode] [reg:4] [imm:u64]
```
- 64-bit immediate is encoded as little-endian bytes

### Argument Parsing

Arguments are parsed using lookup tables optimized for fast decoding:

1. **Skip value** - Number of bytes to skip after opcode
2. **Aux value** - Helps determine argument layout
3. **Sign extension** - Applied based on instruction format

The parser uses pre-computed lookup tables to determine:
- How many bytes to read for each immediate
- Where to apply sign extension
- How to unpack registers

## Jump Table

The jump table maps PC offsets to native code addresses. Each entry is:

**Format (32-bit mode):** 4 bytes per entry
**Format (64-bit mode):** 8 bytes per entry (but stored with alignment padding)

Entries are indexed by PC offset aligned to `VM_CODE_ADDRESS_ALIGNMENT`.

**Invalid entries** are marked with `JUMP_TABLE_INVALID_ADDRESS` (0xfa6f29540376ba8a), chosen to exceed canonical address width, causing immediate CPU fault.

## Bitmask

The bitmask identifies valid jump targets in the code section:

- Each bit represents whether the corresponding PC offset is a valid jump target
- Bit N = 1 means PC offset N is reachable
- Used to validate dynamic jumps before execution
- Length: `(code_length + 7) / 8` bytes

Example: If code is 10 bytes, bitmask is 2 bytes covering bits 0-15.

## Imports

### Import Offsets
Array of PC offsets where imports (external function calls) occur.

Format: `[offset:varint, ...]`

### Import Symbols
Array of symbol names for imported functions.

Format: `[length:varint, name:bytes, ...]`

## Exports

Export table defines publicly accessible entry points:

Format for each export:
```
[name_length:varint] [name:bytes] [pc_offset:varint]
```

## Debug Information (Optional)

### Debug Strings
String table for debug symbols and names.

### Debug Line Programs
DWARF-like line number information for source-level debugging.

**Line program ranges:**
- Maps code regions to line programs

**Line programs:**
- Encoded line number information

## Instruction Set Kind

The `isa` field determines the instruction set variant:

| Value | Name | Description |
|-------|------|-------------|
| 0 | Latest32 | 32-bit instruction set |
| 1 | Latest64 | 64-bit instruction set |

This affects:
- How registers are interpreted (32-bit vs 64-bit operations)
- Sign extension behavior
- Immediate value ranges

## Memory Layout Implications

The blob defines the guest memory layout:

- **RO data starts at:** 0x10000 (page-aligned)
- **RW data starts at:** ro_data_end + guard page
- **Heap base:** Same as RW data start
- **Stack:** High memory address range
- **AUX region:** Special auxiliary data area

Sizes are specified in the header, and the runtime allocates memory accordingly with guard pages between regions.

## Validation

When parsing a program blob, verify:

1. **Header integrity** - All required fields present
2. **Section lengths** - Match expected sizes
3. **Jump table alignment** - Entries properly aligned
4. **Bitmask length** - Covers entire code section
5. **Export PC offsets** - Within valid code range
6. **Import symbols** - Valid UTF-8 strings
7. **ISA compatibility** - Supported instruction set

## Example: Minimal Program

A minimal "trap" program:

```
Header:
  isa = 1 (64-bit)
  ro_data_size = 0
  rw_data_size = 0
  stack_size = 4096

Sections:
  ro_data = []
  rw_data = []
  code = [0x00]  # opcode for 'trap'
  jump_table = [0xfa, 0x6f, 0x29, 0x54, 0x03, 0x76, 0xba, 0x8a]  # invalid address
  jump_table_entry_size = 8
  bitmask = [0x01]  # PC 0 is valid
  import_offsets = []
  import_symbols = []
  exports = []
  debug_strings = []
  debug_line_program_ranges = []
  debug_line_programs = []
```

## Parsing Example (Swift)

```swift
struct ProgramBlob {
    let isa: UInt8
    let roData: Data
    let rwData: Data
    let stackSize: Int
    let code: Data
    let jumpTable: Data
    let jumpTableEntrySize: UInt8
    let bitmask: Data
    let imports: [Import]
    let exports: [Export]
}

struct Import {
    let offset: UInt32
    let symbol: String
}

struct Export {
    let name: String
    let pcOffset: UInt32
}

class ProgramBlobParser {
    private var data: Data
    private var position: Int = 0

    init(data: Data) {
        self.data = data
    }

    func parse() throws -> ProgramBlob {
        // Read header
        let isa = try readByte()
        let roDataSize = try readVarint()
        let rwDataSize = try readVarint()
        let stackSize = try readVarint()

        // Read sections
        let roData = try readBytes(count: Int(roDataSize))
        let rwData = try readBytes(count: Int(rwDataSize))

        let codeLength = try readVarint()
        let code = try readBytes(count: Int(codeLength))

        let jumpTableLength = try readVarint()
        let jumpTable = try readBytes(count: Int(jumpTableLength))

        let jumpTableEntrySize = try readByte()

        let bitmaskLength = try readVarint()
        let bitmask = try readBytes(count: Int(bitmaskLength))

        // Read imports
        let imports = try readImports()

        // Read exports
        let exports = try readExports()

        return ProgramBlob(
            isa: isa,
            roData: roData,
            rwData: rwData,
            stackSize: Int(stackSize),
            code: code,
            jumpTable: jumpTable,
            jumpTableEntrySize: jumpTableEntrySize,
            bitmask: bitmask,
            imports: imports,
            exports: exports
        )
    }

    private func readByte() throws -> UInt8 {
        guard position < data.count else {
            throw ParseError.unexpectedEnd
        }
        let byte = data[position]
        position += 1
        return byte
    }

    private func readVarint() throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0

        while true {
            let byte = try readByte()
            result |= UInt64(byte & 0x7F) << shift
            if (byte & 0x80) == 0 {
                break
            }
            shift += 7
        }

        return result
    }

    private func readBytes(count: Int) throws -> Data {
        guard position + count <= data.count else {
            throw ParseError.unexpectedEnd
        }
        let slice = data[data.startIndex.advanced(by: position)..<data.startIndex.advanced(by: position + count)]
        position += count
        return Data(slice)
    }

    private func readImports() throws -> [Import] {
        var imports: [Import] = []
        // Implementation depends on import format
        return imports
    }

    private func readExports() throws -> [Export] {
        var exports: [Export] = []
        // Read export entries until end of section
        while position < data.count {
            let nameLength = try readVarint()
            if nameLength == 0 { break }
            let nameData = try readBytes(count: Int(nameLength))
            let name = String(data: nameData, encoding: .utf8) ?? ""
            let pcOffset = try readVarint()
            exports.append(Export(name: name, pcOffset: UInt32(pcOffset)))
        }
        return exports
    }

    enum ParseError: Error {
        case unexpectedEnd
        case invalidData
    }
}
```

## Optimization Notes

The format is designed for:

1. **Fast parsing** - Varint encoding minimizes size for small values
2. **Efficient execution** - Jump table enables O(1) indirect jumps
3. **Safety** - Bitmask allows validation without parsing
4. **Debuggability** - Optional debug info doesn't affect runtime
5. **Compactness** - Variable-length encoding reduces binary size

## Security Considerations

1. **Bounds checking** - All offsets must be validated before use
2. **Invalid jumps** - Non-canonical addresses fault immediately
3. **Memory isolation** - Guard pages between regions prevent accidental corruption
4. **Import validation** - Symbol names should be validated and sanitized

## Implementation Details

The program blob format is implemented with:
- A robust parser that validates all sections and maintains backward compatibility
- Efficient instruction decoding using lookup tables optimized for common operations
- Varint encoding/decoding utilities for compact binary representation
- Memory layout builders that ensure proper alignment and guard page placement

For specific implementation examples, parsing strategies, and integration patterns, refer to the runtime loader implementation documentation.
