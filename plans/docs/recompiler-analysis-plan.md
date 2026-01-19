# Recompiler Analysis Plan

## Goals

- Understand the recompiler backend architecture and its flow
- Map core data structures and their responsibilities
- Explain instruction translation, basic blocks, and code emission
- Document gas metering, trampolines, traps, and sandbox interactions
- Capture differences between Linux and Generic sandboxes and 32/64-bit modes

## Scope

**Core Components:**
- Architecture-agnostic compiler driver
- Architecture-specific backend (e.g., x86-64)
- Assembler for machine code emission
- Program blob parser
- Gas metering system
- Sandbox implementation (Linux and Generic)
- Trampoline implementations

**Focus Areas:**
- Instruction translation patterns
- Basic block formation and gas metering
- Jump tables and indirect jumps
- Trap handling and fault recovery
- Host/guest boundary (trampolines)
- Memory operations (memset fast path)
- Register mapping and calling conventions

**Exclude:**
- Interpreter internals (except where behavior contrasts are relevant)
- Frontend language details
- Build system and tooling

## Deliverables

- Architecture overview and pipeline description
- Backend-specific (amd64) translation patterns
- Gas metering and instrumentation documentation
- Trap handling, page faults, and memset behavior
- Q&A documenting key findings and open questions

## Milestones

1. **Inventory and entry points**
   - Identify main compilation pipeline components
   - Document API surface and invocation points

2. **Pipeline analysis**
   - Trace instruction visiting through compiler
   - Document per-instruction code generation

3. **Trampolines and host interaction**
   - sysenter/sysreturn mechanism
   - ecall, sbrk, step trampolines
   - Host/guest boundary

4. **Gas metering**
   - Stub emission and patching
   - Per-basic-block accounting
   - Out-of-gas handling

5. **Dynamic jumps**
   - Jump table structure
   - Indirect jump dispatch
   - Invalid address faulting

6. **Fault/trap handling**
   - PC mapping and recovery
   - Out-of-gas classification
   - Memset edge cases

7. **Registers and bitness**
   - Fixed register mapping strategy
   - 32-bit vs 64-bit differences
   - Sandbox addressing differences

8. **Caching and mappings**
   - PC to native offset mapping
   - Export table
   - Reverse lookup for debugging

9. **Documentation and Q&A**
   - Compile findings into comprehensive docs
   - Create FAQ for common questions
   - Final validation

## Approach

- Use architectural analysis for understanding the system design
- Validate flows by tracing execution paths
- Confirm gas and trap flows by examining signal/fault handling
- Document implementation patterns and trade-offs

## Related Documentation

- [Architecture Overview](recompiler-architecture.md) - High-level system design
- [Deep Dive](recompiler-deep-dive.md) - Detailed implementation analysis
- [Implementation Guide](implementation-guide.md) - Step-by-step roadmap
- [FAQ](recompiler-faq.md) - Common questions and answers
