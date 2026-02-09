import Foundation
@testable import JAMTests
import PolkaVM
import Testing
import TracingUtils
import Utils

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
    case panic
    case halt
    case pageFault = "page-fault"
}

struct PolkaVMTestcase: Codable, CustomStringConvertible {
    var name: String
    var initialRegs: [UInt64]
    var initialPC: UInt32
    var initialPageMap: [PageMap]
    var initialMemory: [MemoryChunk]
    var initialGas: Gas
    var program: [UInt8]
    var expectedStatus: Status
    var expectedRegs: [UInt64]
    var expectedPC: UInt32
    var expectedMemory: [MemoryChunk]
    var expectedGas: Gas
    var expectedPageFaultAddress: UInt32?

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
        case expectedPageFaultAddress = "expected-page-fault-address"
    }

    var description: String {
        name
    }
}

private let logger = Logger(label: "PVMTests")

struct PVMTests {
    // init() {
    //     setupTestLogger()
    // }

    static func loadTests() throws -> [Testcase] {
        try TestLoader.getTestcases(path: "pvm/programs", extension: "json")
    }

    @Test(arguments: try loadTests())
    func pVM(testCase: Testcase) async throws {
        let decoder = JSONDecoder()
        let testCase = try decoder.decode(PolkaVMTestcase.self, from: testCase.data)
        let program = try ProgramCode(Data(testCase.program))
        let memory = try GeneralMemory(
            pageMap: testCase.initialPageMap.map { (address: $0.address, length: $0.length, writable: $0.isWritable) },
            chunks: testCase.initialMemory.map { (address: $0.address, data: Data($0.contents)) },
        )
        let vmState = VMStateInterpreter(
            program: program,
            pc: testCase.initialPC,
            registers: Registers(testCase.initialRegs),
            gas: testCase.initialGas,
            memory: memory,
        )
        let engine = Engine(config: DefaultPvmConfig())
        let exitReason = await engine.execute(state: vmState)
        logger.debug("exit reason: \(exitReason)")
        var pageFaultAddress: UInt32?
        var status: Status
        switch exitReason {
        case .halt:
            status = .halt
        case let .pageFault(addr):
            pageFaultAddress = addr
            vmState.consumeGas(Gas(1)) // NOTE: somehow need to add this
            status = .pageFault
        default:
            status = .panic
        }

        #expect(status == testCase.expectedStatus)
        #expect(vmState.getRegisters() == Registers(testCase.expectedRegs))
        #expect(vmState.pc == testCase.expectedPC)
        #expect(pageFaultAddress == testCase.expectedPageFaultAddress)
        for chunk in testCase.expectedMemory {
            for (offset, byte) in chunk.contents.enumerated() {
                let value = try vmState.getMemory().read(address: chunk.address + UInt32(offset))
                #expect(value == byte)
            }
        }
        #expect(vmState.getGas().value == testCase.expectedGas.value)
    }
}
