import PolkaVM

public protocol HostCallFunction {
    static var identifier: UInt8 { get }
    static var gasCost: UInt64 { get }

    /// For invocation context items other than VMState. Item properties may be mutated if it is mutable
    associatedtype Input

    /// For output items other than VMState. Usually it's parts of input items (as a whole) that should
    /// be mutated after `call`, or items that need to be further processed
    ///
    /// NOTE: Not using inout on entire input or parts of input items to avoid making code more
    /// complex and less generic for invocation use cases
    associatedtype Output

    static func call(state: VMState, input: Input) throws -> Output
}
