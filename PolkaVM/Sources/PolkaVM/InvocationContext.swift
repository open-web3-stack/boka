public protocol InvocationContext<ContextType>: Sendable {
    associatedtype ContextType

    /// Items required for the invocation, some items inside this context might be mutated after the host-call
    var context: ContextType { get set }

    /// host-call dispatch function
    func dispatch(index: UInt32, state: any VMState) async -> ExecOutcome
}
