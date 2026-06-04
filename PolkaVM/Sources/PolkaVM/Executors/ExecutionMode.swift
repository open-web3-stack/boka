public struct ExecutionMode: OptionSet, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    /// Determine if JIT or interpreter should be used
    public static let jit = ExecutionMode(rawValue: 1 << 0)
}
