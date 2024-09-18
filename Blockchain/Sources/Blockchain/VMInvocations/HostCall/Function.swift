import PolkaVM

public protocol HostCallFunction {
    static var identifier: UInt8 { get }
    static var gasCost: UInt64 { get }

    /// Invocation context items that do not change after host-call
    associatedtype Invariant
    /// Invocation context items that mutates after host-call
    associatedtype Mutable

    static func call(state: VMState, invariant: Invariant) throws
    static func call(state: VMState, invariant: Invariant, mutable: inout Mutable) throws
}

extension HostCallFunction {
    public static func hasEnoughGas(state: VMState) -> Bool {
        state.getGas() >= gasCost
    }

    // this exists because for Gas host-call, we cannot pass in a void mutable value,
    // and all other host-calls do not need to implement this
    public static func call(state _: VMState, invariant _: Invariant) throws {
        fatalError("This should not be called")
    }
}
