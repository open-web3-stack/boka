import PolkaVM

public protocol HostCallFunction {
    static var identifier: UInt8 { get }
    static var gasCost: UInt64 { get }

    associatedtype Input
    associatedtype Output

    static func call(state: VMState, input: Input) throws -> Output
}
