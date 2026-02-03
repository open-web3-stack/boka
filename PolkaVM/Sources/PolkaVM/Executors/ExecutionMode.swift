public struct ExecutionMode: OptionSet, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    /// Determine if JIT or interpreter should be used
    public static let jit = ExecutionMode(rawValue: 1 << 0)

    /// Determine if the program should be sandboxed
    public static let sandboxed = ExecutionMode(rawValue: 1 << 1)
}

/// Enumeration of PVM execution modes for testing
public enum PVMExecutionMode: String, CaseIterable, Sendable {
    case interpreter
    case sandbox

    /// Convert to PolkaVM ExecutionMode
    public var executionMode: ExecutionMode {
        switch self {
        case .interpreter:
            [] // Empty = interpreter mode
        case .sandbox:
            .sandboxed
        }
    }

    /// Human-readable description
    public var description: String {
        rawValue
    }
}
