public protocol HostCallContext<ContextType> {
    associatedtype ContextType

    var context: ContextType { get set }

    /// host-call dispatch function
    func dispatch(index: UInt32, state: VMState) -> ExecOutcome
}
