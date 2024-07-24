import Foundation

public enum Instructions {
    static func decodeImmidate(data: Data) -> UInt32 {
        let len = min(data.count, 4)
        if len == 0 {
            return 0
        }
        var value: UInt32 = 0
        for i in 0 ..< len {
            value = value | (UInt32(data[i]) << (8 * i))
        }
        let shift = (4 - len) * 8
        // shift left so that the MSB is the sign bit
        // and then do signed shift right to fill the empty bits using the sign bit
        // and then convert back to UInt32
        return UInt32(bitPattern: Int32(bitPattern: value << shift) >> shift)
    }

    // MARK: Instructions without Arguments.

    public struct Trap: Instruction {
        public static var opcode: UInt8 { 0 }

        public init(data _: Data) {}

        public func executeImpl(state _: inout VMState) -> ExitReason? {
            .halt(.trap)
        }

        public func gasCost() -> UInt64 {
            1
        }
    }

    public struct Fallthrough: Instruction {
        public static var opcode: UInt8 { 1 }

        public init(data _: Data) {}

        public func executeImpl(state _: inout VMState) -> ExitReason? {
            nil
        }

        public func gasCost() -> UInt64 {
            1
        }
    }

    // MARK: Instructions with Arguments of One Immediate

    public struct Ecalli: Instruction {
        public static var opcode: UInt8 { 78 }

        public let callIndex: UInt32

        public init(data: Data) {
            callIndex = Instructions.decodeImmidate(data: data)
        }

        public func executeImpl(state _: inout VMState) -> ExitReason? {
            fatalError("Not implemented")
        }

        public func gasCost() -> UInt64 {
            1
        }
    }
}
