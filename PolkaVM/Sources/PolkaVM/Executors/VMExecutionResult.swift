import Foundation
import Utils

/// Result of VM execution including exit reason, gas consumption, output data, and final register state
public struct VMExecutionResult: Sendable {
    public let exitReason: ExitReason
    public let gasUsed: Gas
    public let outputData: Data?
    public let finalRegisters: Registers
    public let finalPC: UInt32

    public init(
        exitReason: ExitReason,
        gasUsed: Gas,
        outputData: Data? = nil,
        finalRegisters: Registers = Registers(),
        finalPC: UInt32 = 0
    ) {
        self.exitReason = exitReason
        self.gasUsed = gasUsed
        self.outputData = outputData
        self.finalRegisters = finalRegisters
        self.finalPC = finalPC
    }
}
