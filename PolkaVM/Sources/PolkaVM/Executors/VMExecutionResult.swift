import Foundation
import Utils

/// Result of VM execution including exit reason, gas consumption, and output data
public struct VMExecutionResult: Sendable {
    public let exitReason: ExitReason
    public let gasUsed: Gas
    public let outputData: Data?
    public let fallbackState: (pc: UInt32, registers: [UInt64], gasUsed: UInt64)?

    public init(exitReason: ExitReason, gasUsed: Gas, outputData: Data?, fallbackState: (pc: UInt32, registers: [UInt64], gasUsed: UInt64)? = nil) {
        self.exitReason = exitReason
        self.gasUsed = gasUsed
        self.outputData = outputData
        self.fallbackState = fallbackState
    }
}
