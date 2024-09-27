import PolkaVM

public protocol HostCallFunction {
    static var identifier: UInt8 { get }
    static var gasCost: UInt64 { get }

    /// Input items other than VMState
    associatedtype Input

    /// Output items other than VMState
    ///
    /// Usually parts of input items that are mutated after `call`
    associatedtype Output

    static func call(state: VMState, input: Input) throws -> Output
}
