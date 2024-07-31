import Foundation
import PolkaVM
import Testing
import Utils

@testable import JAMTests

struct PageMap: Codable {
    var address: UInt32
    var length: UInt32
    var isWritable: Bool

    enum CodingKeys: String, CodingKey {
        case address
        case length
        case isWritable = "is-writable"
    }
}

struct MemoryChunk: Codable {
    var address: UInt32
    var contents: [UInt8]
}

enum Status: String, Codable {
    case trap
    case halt
}

struct PolkaVMTestcase: Codable, CustomStringConvertible {
    var name: String
    var initialRegs: [UInt32]
    var initialPC: UInt32
    var initialPageMap: [PageMap]
    var initialMemory: [MemoryChunk]
    var initialGas: Int64
    var program: [UInt8]
    var expectedStatus: Status
    var expectedRegs: [UInt32]
    var expectedPC: UInt32
    var expectedMemory: [MemoryChunk]
    var expectedGas: Int64

    enum CodingKeys: String, CodingKey {
        case name
        case initialRegs = "initial-regs"
        case initialPC = "initial-pc"
        case initialPageMap = "initial-page-map"
        case initialMemory = "initial-memory"
        case initialGas = "initial-gas"
        case program
        case expectedStatus = "expected-status"
        case expectedRegs = "expected-regs"
        case expectedPC = "expected-pc"
        case expectedMemory = "expected-memory"
        case expectedGas = "expected-gas"
    }

    var description: String {
        name
    }
}

struct PVMTests {
    static func loadTests() throws -> [PolkaVMTestcase] {
        let tests = try TestLoader.getTestFiles(path: "pvm/programs", extension: "json")
        return try tests.map {
            let data = try Data(contentsOf: URL(fileURLWithPath: $0.path))
            let decoder = JSONDecoder()
            return try decoder.decode(PolkaVMTestcase.self, from: data)
        }
    }

    @Test(arguments: try loadTests())
    func testPVM(testCase: PolkaVMTestcase) throws {
        let program = try ProgramCode(Data(testCase.program))
        let memory = Memory(
            pageMap: testCase.initialPageMap.map { (address: $0.address, length: $0.length, writable: $0.isWritable) },
            chunks: testCase.initialMemory.map { (address: $0.address, data: Data($0.contents)) }
        )
        let vmState = VMState(
            program: program,
            pc: testCase.initialPC,
            registers: Registers(testCase.initialRegs),
            gas: UInt64(testCase.initialGas),
            memory: memory
        )
        let engine = Engine()
        let exitReason = engine.execute(program: program, state: vmState)
        let exitReason2: Status = switch exitReason {
        case .halt:
            .halt
        default:
            .trap
        }

        withKnownIssue("not yet implemented", isIntermittent: true) {
            #expect(exitReason2 == testCase.expectedStatus)
            #expect(vmState.registers == Registers(testCase.expectedRegs))
            #expect(vmState.pc == testCase.expectedPC)
            for chunk in testCase.expectedMemory {
                for (offset, byte) in chunk.contents.enumerated() {
                    let value = try vmState.memory.read(chunk.address + UInt32(offset))
                    #expect(value == byte)
                }
            }
            #expect(vmState.gas == testCase.expectedGas)
        }
    }
}