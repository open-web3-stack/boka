import Foundation
@testable import PolkaVM
import Testing
import Utils

@Suite(.serialized)
struct JITGasCostsTests {
    static func program(size: Int, blockSize: Int, jumpWidth: Int = 4) throws -> ProgramCode {
        var code = Data(repeating: 2, count: size)
        var mask = Data(repeating: 255, count: (size + 7) / 8)
        for end in stride(from: blockSize, to: size, by: blockSize) {
            code[end - jumpWidth - 1] = 40 // jump to the next block
            code[end - jumpWidth] = UInt8(jumpWidth + 1)
            for offset in (end - jumpWidth + 1) ..< end {
                code[offset] = 0
            }
            for offset in (end - jumpWidth) ..< end {
                mask[offset / 8] &= ~(1 << (offset % 8))
            }
        }
        code[size - 1] = 0
        return try ProgramCode(Data([0, 0]) + Data(UInt64(size).encode(method: .variableWidth)) + code + mask)
    }

    @Test
    func selectsRepresentationAtDensityBoundary() throws {
        for (span, sparse) in [(64, true), (8, true), (6, false)] {
            let program = try Self.program(size: 128, blockSize: span)
            let table = JITGasCosts(program: program)
            #expect(table.starts.isEmpty != sparse)
            if sparse {
                #expect(table.starts == program.basicBlockIndices.sorted())
                #expect(table.values.count * 8 + table.starts.count * 4 <= program.code.count * 2)
            } else {
                #expect(table.values.count == program.code.count)
            }
        }
    }

    @Test(arguments: [1, 2, 3, 4])
    func denseAndSparseCompileAndExecuteIdentically(jumpWidth: Int) throws {
        let program = try Self.program(size: 128, blockSize: 64, jumpWidth: jumpWidth)
        let skips = program.skipValues
        let total = program.basicBlockIndices.reduce(Gas(0)) { $0 + program.getBlockGasCosts(pc: $1) }
        for representation in [JITGasCosts.Representation.dense, .sparse] {
            for pc: UInt32 in [0, 1, 64, 65] {
                let compiler = JITCompiler()
                defer { withExtendedLifetime(compiler) {} }
                let function = try compiler.compile(
                    blob: program.code, initialPC: pc, config: DefaultPvmConfig(),
                    targetArchitecture: JITPlatform.getCurrentTargetArchitecture(), jitMemorySize: 4096,
                    skipTable: skips, bitmask: program.bitmask,
                    blockGasCosts: JITGasCosts(program: program, representation: representation),
                )
                var registers = Registers()
                var gas = pc < 64 ? total : program.getBlockGasCosts(pc: 64)
                let (exit, memory) = try JITExecutor().execute(
                    functionPtr: function, registers: &registers, jitMemorySize: 4096,
                    gas: &gas, initialPC: pc, invocationContext: nil,
                )
                memory.deallocate()
                #expect(exit == .panic(.trap))
                #expect(gas == Gas(0))
            }
        }
    }
}
