# PolkaVM Recompiler Documentation

This folder contains comprehensive documentation for understanding and implementing a high-performance PolkaVM recompiler. The documents provide enough detail to implement a recompiler from scratch using only the PVM specification and these docs.

## For Implementers

If you want to **implement a PolkaVM recompiler**, read in this order:

1. **[Implementation Guide](implementation-guide.md)** ⭐ START HERE
   - Step-by-step roadmap for building a recompiler
   - Architecture decisions and trade-offs
   - Phases of implementation with code examples
   - Testing strategies and common pitfalls

2. **[Program Blob Format](program-blob-format.md)**
   - Binary format specification
   - Instruction encoding details
   - Parsing varint and complex instructions
   - Understanding jump tables and bitmasks

3. **[Instruction Set Reference](instruction-set-reference.md)**
   - Complete list of all PVM opcodes
   - Instruction formats and semantics
   - Register set and conventions
   - Behavior details (overflow, sign-extension, etc.)

4. **[Instruction Translation Guide](instruction-translation.md)**
   - How to translate each PVM instruction to native code
   - x86-64 translation patterns
   - Optimization opportunities
   - Common implementation patterns

## For Understanding the Implementation

If you want to **understand the existing implementation**, read in this order:

1. **[Recompiler Architecture](recompiler-architecture.md)** - High-level overview
   - Compilation pipeline and data flow
   - Core components (CompilerVisitor, ArchVisitor, Assembler)
   - Basic blocks, labels, and mappings

2. **[Recompiler Deep Dive](recompiler-deep-dive.md)** - Implementation details with code
   - Pipeline overview with code examples
   - Compiler core, basic blocks, gas metering
   - Trampolines, jumps, memset, traps
   - Sandboxing, VmCtx, register mapping

3. **[AMD64 Backend](recompiler-amd64-backend.md)** - Architecture-specific details
   - Instruction patterns for x86-64
   - Control flow, memory operations
   - Gas metering and trap handling
   - Security model and optimizations

4. **[Gas Metering, Traps, and Trampolines](recompiler-gas-traps.md)** - Special topics
   - Gas accounting per basic block
   - Memset integration with gas
   - All trampolines (trap, ecall, sbrk, step, sysenter/sysreturn)
   - Fault handling and recovery

## Reference Materials

- **[Recompiler FAQ](recompiler-faq.md)** - Frequently asked questions ⭐ QUICK HELP
- **[Recompiler Questions](recompiler-questions.md)** - Technical Q&A with implementation details
- **[Recompiler Analysis Plan](recompiler-analysis-plan.md)** - Analysis methodology and scope

## Document Structure

### Core Documentation (Implementer-Focused)

| Document | Purpose | Audience |
|----------|---------|----------|
| [Implementation Guide](implementation-guide.md) | Step-by-step implementation roadmap | Implementers |
| [Program Blob Format](program-blob-format.md) | Binary format specification | Implementers |
| [Instruction Set Reference](instruction-set-reference.md) | Complete opcode reference | Implementers |
| [Instruction Translation](instruction-translation.md) | Translation patterns to native code | Implementers |

### Analysis Documentation (Understanding-Focused)

| Document | Purpose | Detail Level |
|----------|---------|--------------|
| [Recompiler Architecture](recompiler-architecture.md) | High-level architecture | Overview |
| [Recompiler Deep Dive](recompiler-deep-dive.md) | Detailed analysis with code | In-depth |
| [AMD64 Backend](recompiler-amd64-backend.md) | x86-64 implementation specifics | In-depth |
| [Gas Metering & Traps](recompiler-gas-traps.md) | Specialized mechanisms | In-depth |

### Supporting Documentation

| Document | Purpose |
|----------|---------|
| [FAQ](recompiler-faq.md) | Frequently asked questions (quick help) |
| [Questions](recompiler-questions.md) | Technical Q&A |
| [Analysis Plan](recompiler-analysis-plan.md) | Analysis methodology |

## Key Concepts

### Components

- **CompilerVisitor**: Architecture-agnostic compilation driver
- **ArchVisitor**: Architecture-specific instruction lowering
- **Assembler**: Machine code emission with label/fixup support
- **Sandbox**: Process isolation (Linux) or in-process (Generic)
- **GasVisitor**: Per-instruction cost tracking

### Mechanisms

- **Basic Blocks**: Gas metering and jump targets at block boundaries
- **Jump Tables**: Indirect jump dispatch via table lookup
- **Trampolines**: Host/guest boundary with register save/restore
- **Gas Metering**: Per-block stub with patched immediate
- **Fault Handling**: Signal/page fault classification and recovery

### Optimizations

- Compact branch encoding (rel8 vs rel32)
- Register mapping for compact encodings
- Efficient addressing modes
- Memset fast path with rep stosb
- Gas stub patching for low overhead

## Quick Reference

### Implementing from Scratch

```bash
# Read in order:
1. implementation-guide.md        # Plan your implementation
2. program-blob-format.md          # Parse programs
3. instruction-set-reference.md    # Understand instructions
4. instruction-translation.md      # Generate native code
```

### Understanding the Codebase

```bash
# Read in order:
1. recompiler-architecture.md      # Overview
2. recompiler-deep-dive.md         # Details
3. recompiler-amd64-backend.md     # x86-64 specifics
4. recompiler-gas-traps.md         # Special topics
```

## Documentation Format

All documentation uses **Swift syntax** for code examples, making it:
- Modern and readable
- Type-safe and expressive
- Easy to translate to other languages (C++, C, Go, Java, Rust, etc.)
- Follows best practices with clear error handling

All documents are **completely self-contained** with no external file references.

## Documentation Status

✅ **Complete**: All documentation is self-contained with comprehensive coverage of:
- Architecture and design
- Complete PVM instruction set (70+ opcodes)
- Program blob binary format
- Instruction translation patterns
- Implementation roadmap
- Gas metering and trap handling
- x86-64 backend specifics

**Language**: Swift syntax throughout (easy to translate to any language)
**Dependencies**: None (all code examples are inline)
**Last Updated**: 2025-01-19

## Contributing

When adding new documentation:
1. Update this README to include the new document
2. Cross-reference related documents
3. Use Swift syntax for all code examples
4. Keep all documentation self-contained (no external file references)
5. Mark as "Validated" after review

## License

This documentation is part of the PolkaVM project and follows the same license terms.

