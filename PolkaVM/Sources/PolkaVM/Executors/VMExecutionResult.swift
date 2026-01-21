import Foundation
import Utils

/// Result of VM execution including exit reason, gas consumption, and output data
public struct VMExecutionResult: Sendable {
    public let exitReason: ExitReason
    public let gasUsed: Gas
    public let outputData: Data?

    public init(exitReason: ExitReason, gasUsed: Gas, outputData: Data?) {
        self.exitReason = exitReason
        self.gasUsed = gasUsed
        self.outputData = outputData
    }
}
