#!/usr/bin/env swift

import Foundation
import PolkaVM

// Test bytecode: LoadImm64 r1, 100; LoadImm64 r2, 42; Add64 r3, r1, r2; Halt
let code: [UInt8] = [
    0x14, 0x01, 0x64, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // LoadImm64 r1, 100
    0x14, 0x02, 0x2A, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // LoadImm64 r2, 42
    0xC8, 0x21, 0x03, // Add64 r3, r1, r2 (packed: ra=0x01, rb=0x02, rd=0x03)
    0x01, // Halt
]

print("Code bytes: \(code.map { String(format: "%02x", $0) }.joined(separator: " "))")
print("Code length: \(code.count) bytes")

let blob = ProgramBlobBuilder.createProgramCode(code)
print("Blob length: \(blob.count) bytes")

// Run interpreter
Task {
    let config = DefaultPvmConfig()
    let state = try VMStateInterpreter(
        standardProgramBlob: blob,
        pc: 0,
        gas: Gas(1_000_000),
        argumentData: nil
    )

    print("Initial registers:")
    print("  r1: \(state.getRegisters()[Registers.Index(raw: 1)])")
    print("  r2: \(state.getRegisters()[Registers.Index(raw: 2)])")
    print("  r3: \(state.getRegisters()[Registers.Index(raw: 3)])")

    let engine = Engine(config: config)
    let result = await engine.execute(state: state)

    print("\nAfter execution:")
    print("  Exit reason: \(result)")
    print("  r1: \(state.getRegisters()[Registers.Index(raw: 1)])")
    print("  r2: \(state.getRegisters()[Registers.Index(raw: 2)])")
    print("  r3: \(state.getRegisters()[Registers.Index(raw: 3)])")
    print("  PC: \(state.pc)")
}

RunLoop.main.run(until: Date(timeIntervalSinceNow: 2))
