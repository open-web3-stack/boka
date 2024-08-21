import Foundation
import Utils

public let BASIC_BLOCK_INSTRUCTIONS: Set<UInt8> = [
    Instructions.Trap.opcode,
    Instructions.Fallthrough.opcode,
    Instructions.Jump.opcode,
    Instructions.JumpInd.opcode,
    Instructions.LoadImmJump.opcode,
    // TODO: uncomment after add more
    // Instructions.LoadImmJumpInd.opcode,
    // Instructions.BranchEq.opcode,
    // Instructions.BranchNe.opcode,
    // Instructions.BranchGeU.opcode,
    // Instructions.BranchGeS.opcode,
    // Instructions.BranchLtU.opcode,
    // Instructions.BranchLtS.opcode,
    Instructions.BranchEqImm.opcode,
    Instructions.BranchNeImm.opcode,
    Instructions.BranchLtUImm.opcode,
    Instructions.BranchLtSImm.opcode,
    Instructions.BranchLeUImm.opcode,
    Instructions.BranchLeSImm.opcode,
    Instructions.BranchGeUImm.opcode,
    Instructions.BranchGeSImm.opcode,
    Instructions.BranchGtUImm.opcode,
    Instructions.BranchGtSImm.opcode,
]

protocol BranchInstruction: Instruction {
    var offset: UInt32 { get }
    func comparison(state: VMState, skip: UInt32) -> Bool
}

extension BranchInstruction {
    public func _executeImpl(state: VMState) -> ExitReason? {
        Instructions.checkBranch(state: state, offset: offset)
    }

    public func updatePC(state: VMState, skip: UInt32) {
        if comparison(state: state, skip: skip) {
            state.increasePC(offset)
        } else {
            state.increasePC(skip + 1)
        }
    }
}

public enum Instructions {
    static func decodeImmediate(_ data: Data) -> UInt32 {
        let len = min(data.count, 4)
        if len == 0 {
            return 0
        }
        var value: UInt32 = 0
        for i in 0 ..< len {
            value = value | (UInt32(data[relative: i]) << (8 * i))
        }
        let shift = (4 - len) * 8
        // shift left so that the MSB is the sign bit
        // and then do signed shift right to fill the empty bits using the sign bit
        // and then convert back to UInt32
        return UInt32(bitPattern: Int32(bitPattern: value << shift) >> shift)
    }

    static func decodeImmediate2(_ data: Data, divideBy: UInt8 = 1) -> (UInt32, UInt32)? {
        do {
            let lA = try Int((data.at(relative: 0) / divideBy) & 0b111)
            let lX = min(4, lA)
            let lY1 = min(4, max(0, data.count - Int(lA) - 1))
            let lY2 = min(lY1, 8 - lA)
            let vX = try decodeImmediate(data.at(relative: 1 ..< lX))
            let vY = try decodeImmediate(data.at(relative: (1 + lA) ..< lY2))
            return (vX, vY)
        } catch {
            return nil
        }
    }

    static func checkBranch(state: VMState, offset: UInt32) -> ExitReason? {
        let pc = state.pc
        let code = state.program.code
        let opcode = code[code.startIndex + Int(pc &+ offset)]
        if BASIC_BLOCK_INSTRUCTIONS.contains(opcode) {
            return nil
        }
        return .panic(.invalidBranch)
    }

    // MARK: Instructions without Arguments (5.1)

    public struct Trap: Instruction {
        public static var opcode: UInt8 { 0 }

        public init(data _: Data) {}

        public func _executeImpl(state _: VMState) -> ExitReason? {
            .panic(.trap)
        }
    }

    public struct Fallthrough: Instruction {
        public static var opcode: UInt8 { 17 }

        public init(data _: Data) {}

        public func _executeImpl(state _: VMState) -> ExitReason? {
            nil
        }
    }

    // MARK: Instructions with Arguments of One Immediate (5.2)

    public struct Ecalli: Instruction {
        public static var opcode: UInt8 { 78 }

        public let callIndex: UInt32

        public init(data: Data) {
            callIndex = Instructions.decodeImmediate(data)
        }

        public func _executeImpl(state _: VMState) -> ExitReason? {
            .hostCall(callIndex)
        }
    }

    // MARK: Instructions with Arguments of Two Immediates (5.3)

    public struct StoreImmU8: Instruction {
        public static var opcode: UInt8 { 62 }

        public let address: UInt32
        public let value: UInt8

        public init(data: Data) {
            let (x, y) = Instructions.decodeImmediate2(data)!
            address = x
            value = UInt8(truncatingIfNeeded: y)
        }

        public func _executeImpl(state: VMState) throws -> ExitReason? {
            try state.writeMemory(address: address, value: value)
            return nil
        }
    }

    public struct StoreImmU16: Instruction {
        public static var opcode: UInt8 { 79 }

        public let address: UInt32
        public let value: UInt16

        public init(data: Data) {
            let (x, y) = Instructions.decodeImmediate2(data)!
            address = x
            value = UInt16(truncatingIfNeeded: y)
        }

        public func _executeImpl(state: VMState) throws -> ExitReason? {
            try state.writeMemory(address: address, values: value.encode(method: .fixedWidth(2)))
            return nil
        }
    }

    public struct StoreImmU32: Instruction {
        public static var opcode: UInt8 { 38 }

        public let address: UInt32
        public let value: UInt32

        public init(data: Data) {
            let (x, y) = Instructions.decodeImmediate2(data)!
            address = x
            value = y
        }

        public func _executeImpl(state: VMState) -> ExitReason? {
            if (try? state.writeMemory(
                address: address, values: value.encode(method: .fixedWidth(4))
            )) != nil {
                return nil
            }
            return .pageFault(address)
        }
    }

    // MARK: Instructions with Arguments of One Offset (5.4)

    public struct Jump: Instruction {
        public static var opcode: UInt8 { 58 }

        public let offset: UInt32

        public init(data: Data) {
            // this should be a signed value
            // but because we use wrapped addition, it will work as expected
            offset = Instructions.decodeImmediate(data)
        }

        public func _executeImpl(state: VMState) -> ExitReason? {
            Instructions.checkBranch(state: state, offset: offset)
        }

        public func updatePC(state: VMState, skip _: UInt32) {
            state.increasePC(offset)
        }
    }

    // Instructions with Arguments of One Register & One Immediate (5.5)

    public struct JumpInd: Instruction {
        public static var opcode: UInt8 { 19 }

        public let register: Registers.Index
        public let offset: UInt32

        public init(data: Data) throws {
            register = try Registers.Index(data.at(relative: 0))
            offset = try Instructions.decodeImmediate(data.at(relative: 1...))
        }

        public func _executeImpl(state _: VMState) -> ExitReason? {
            nil
        }

        public func updatePC(state: VMState, skip _: UInt32) {
            let regVal = state.readRegister(register)
            state.updatePC(regVal &+ offset) // wrapped add
        }
    }

    public struct LoadImm: Instruction {
        public static var opcode: UInt8 { 4 }

        public let register: Registers.Index
        public let value: UInt32

        public init(data: Data) throws {
            register = try Registers.Index(data.at(relative: 0))
            value = try Instructions.decodeImmediate(data.at(relative: 1...))
        }

        public func _executeImpl(state: VMState) -> ExitReason? {
            state.writeRegister(register, value)
            return nil
        }
    }

    public struct LoadU8: Instruction {
        public static var opcode: UInt8 { 60 }

        public let register: Registers.Index
        public let address: UInt32

        public init(data: Data) throws {
            register = try Registers.Index(data.at(relative: 0))
            address = try Instructions.decodeImmediate(data.at(relative: 1...))
        }

        public func _executeImpl(state: VMState) throws -> ExitReason? {
            let value = try state.readMemory(address: address)
            state.writeRegister(register, UInt32(value))
            return nil
        }
    }

    public struct LoadI8: Instruction {
        public static var opcode: UInt8 { 74 }

        public let register: Registers.Index
        public let address: UInt32

        public init(data: Data) throws {
            register = try Registers.Index(data.at(relative: 0))
            address = try Instructions.decodeImmediate(data.at(relative: 1...))
        }

        public func _executeImpl(state: VMState) throws -> ExitReason? {
            let value = try state.readMemory(address: address)
            state.writeRegister(register, UInt32(bitPattern: Int32(Int8(bitPattern: value))))
            return nil
        }
    }

    public struct LoadU16: Instruction {
        public static var opcode: UInt8 { 76 }

        public let register: Registers.Index
        public let address: UInt32

        public init(data: Data) throws {
            register = try Registers.Index(data.at(relative: 0))
            address = try Instructions.decodeImmediate(data.at(relative: 1...))
        }

        public func _executeImpl(state: VMState) throws -> ExitReason? {
            var data = try state.readMemory(address: address, length: 2)
            guard let value: UInt16 = data.decode(length: 2) else {
                fatalError("unreachable: value should be valid")
            }
            state.writeRegister(register, UInt32(value))
            return nil
        }
    }

    public struct LoadI16: Instruction {
        public static var opcode: UInt8 { 66 }

        public let register: Registers.Index
        public let address: UInt32

        public init(data: Data) throws {
            register = try Registers.Index(data.at(relative: 0))
            address = try Instructions.decodeImmediate(data.at(relative: 1...))
        }

        public func _executeImpl(state: VMState) throws -> ExitReason? {
            var data = try state.readMemory(address: address, length: 2)
            guard let value: UInt16 = data.decode(length: 2) else {
                fatalError("unreachable: value should be valid")
            }
            state.writeRegister(register, UInt32(bitPattern: Int32(Int16(bitPattern: value))))
            return nil
        }
    }

    public struct LoadU32: Instruction {
        public static var opcode: UInt8 { 10 }

        public let register: Registers.Index
        public let address: UInt32

        public init(data: Data) throws {
            register = try Registers.Index(data.at(relative: 0))
            address = try Instructions.decodeImmediate(data.at(relative: 1...))
        }

        public func _executeImpl(state: VMState) throws -> ExitReason? {
            var data = try state.readMemory(address: address, length: 4)
            guard let value: UInt32 = data.decode(length: 4) else {
                fatalError("unreachable: value should be valid")
            }
            state.writeRegister(register, value)
            return nil
        }
    }

    public struct StoreU8: Instruction {
        public static var opcode: UInt8 { 71 }

        public let register: Registers.Index
        public let address: UInt32

        public init(data: Data) throws {
            register = try Registers.Index(data.at(relative: 0))
            address = try Instructions.decodeImmediate(data.at(relative: 1...))
        }

        public func _executeImpl(state: VMState) throws -> ExitReason? {
            let value = UInt8(truncatingIfNeeded: state.readRegister(register))
            try state.writeMemory(address: address, value: value)
            return nil
        }
    }

    public struct StoreU16: Instruction {
        public static var opcode: UInt8 { 69 }

        public let register: Registers.Index
        public let address: UInt32

        public init(data: Data) throws {
            register = try Registers.Index(data.at(relative: 0))
            address = try Instructions.decodeImmediate(data.at(relative: 1...))
        }

        public func _executeImpl(state: VMState) throws -> ExitReason? {
            let value = UInt16(truncatingIfNeeded: state.readRegister(register))
            try state.writeMemory(address: address, values: value.encode(method: .fixedWidth(2)))
            return nil
        }
    }

    public struct StoreU32: Instruction {
        public static var opcode: UInt8 { 22 }

        public let register: Registers.Index
        public let address: UInt32

        public init(data: Data) throws {
            register = try Registers.Index(data.at(relative: 0))
            address = try Instructions.decodeImmediate(data.at(relative: 1...))
        }

        public func _executeImpl(state: VMState) throws -> ExitReason? {
            let value = state.readRegister(register)
            try state.writeMemory(address: address, values: value.encode(method: .fixedWidth(4)))
            return nil
        }
    }

    // MARK: Instructions with Arguments of One Register & Two Immediates (5.6)

    public struct StoreImmIndU8: Instruction {
        public static var opcode: UInt8 { 26 }

        public let register: Registers.Index
        public let address: UInt32
        public let value: UInt8

        public init(data: Data) throws {
            register = try Registers.Index(data.at(relative: 0))
            let (x, y) = Instructions.decodeImmediate2(data, divideBy: 16)!
            address = x
            value = UInt8(truncatingIfNeeded: y)
        }

        public func _executeImpl(state: VMState) throws -> ExitReason? {
            try state.writeMemory(address: state.readRegister(register) + address, value: value)
            return nil
        }
    }

    public struct StoreImmIndU16: Instruction {
        public static var opcode: UInt8 { 54 }

        public let register: Registers.Index
        public let address: UInt32
        public let value: UInt16

        public init(data: Data) throws {
            register = try Registers.Index(data.at(relative: 0))
            let (x, y) = Instructions.decodeImmediate2(data, divideBy: 16)!
            address = x
            value = UInt16(truncatingIfNeeded: y)
        }

        public func _executeImpl(state: VMState) throws -> ExitReason? {
            try state.writeMemory(address: state.readRegister(register) + address, values: value.encode(method: .fixedWidth(2)))
            return nil
        }
    }

    public struct StoreImmIndU32: Instruction {
        public static var opcode: UInt8 { 13 }

        public let register: Registers.Index
        public let address: UInt32
        public let value: UInt32

        public init(data: Data) throws {
            register = try Registers.Index(data.at(relative: 0))
            let (x, y) = Instructions.decodeImmediate2(data, divideBy: 16)!
            address = x
            value = y
        }

        public func _executeImpl(state: VMState) throws -> ExitReason? {
            try state.writeMemory(address: state.readRegister(register) + address, values: value.encode(method: .fixedWidth(4)))
            return nil
        }
    }

    // MARK: Instructions with Arguments of One Register, One Immediate and One Offset (5.7)

    public struct LoadImmJump: Instruction {
        public static var opcode: UInt8 { 6 }

        public let register: Registers.Index
        public let value: UInt32
        public let offset: UInt32

        public init(data: Data) throws {
            register = try Registers.Index(data.at(relative: 0))
            (value, offset) = Instructions.decodeImmediate2(data, divideBy: 16)!
        }

        public func _executeImpl(state: VMState) throws -> ExitReason? {
            state.writeRegister(register, value)
            return Instructions.checkBranch(state: state, offset: offset)
        }

        public func updatePC(state: VMState, skip _: UInt32) {
            state.increasePC(offset)
        }
    }

    public struct BranchEqImm: BranchInstruction {
        public static var opcode: UInt8 { 7 }

        public let register: Registers.Index
        public let value: UInt32
        public let offset: UInt32

        public init(data: Data) throws {
            register = try Registers.Index(data.at(relative: 0))
            (value, offset) = Instructions.decodeImmediate2(data, divideBy: 16)!
        }

        func comparison(state: VMState, skip _: UInt32) -> Bool {
            state.readRegister(register) == value
        }
    }

    public struct BranchNeImm: BranchInstruction {
        public static var opcode: UInt8 { 15 }

        public let register: Registers.Index
        public let value: UInt32
        public let offset: UInt32

        public init(data: Data) throws {
            register = try Registers.Index(data.at(relative: 0))
            (value, offset) = Instructions.decodeImmediate2(data, divideBy: 16)!
        }

        func comparison(state: VMState, skip _: UInt32) -> Bool {
            state.readRegister(register) != value
        }
    }

    public struct BranchLtUImm: BranchInstruction {
        public static var opcode: UInt8 { 44 }

        public let register: Registers.Index
        public let value: UInt32
        public let offset: UInt32

        public init(data: Data) throws {
            register = try Registers.Index(data.at(relative: 0))
            (value, offset) = Instructions.decodeImmediate2(data, divideBy: 16)!
        }

        func comparison(state: VMState, skip _: UInt32) -> Bool {
            state.readRegister(register) < value
        }
    }

    public struct BranchLeUImm: BranchInstruction {
        public static var opcode: UInt8 { 59 }

        public let register: Registers.Index
        public let value: UInt32
        public let offset: UInt32

        public init(data: Data) throws {
            register = try Registers.Index(data.at(relative: 0))
            (value, offset) = Instructions.decodeImmediate2(data, divideBy: 16)!
        }

        func comparison(state: VMState, skip _: UInt32) -> Bool {
            state.readRegister(register) <= value
        }
    }

    public struct BranchGeUImm: BranchInstruction {
        public static var opcode: UInt8 { 52 }

        public let register: Registers.Index
        public let value: UInt32
        public let offset: UInt32

        public init(data: Data) throws {
            register = try Registers.Index(data.at(relative: 0))
            (value, offset) = Instructions.decodeImmediate2(data, divideBy: 16)!
        }

        func comparison(state: VMState, skip _: UInt32) -> Bool {
            state.readRegister(register) >= value
        }
    }

    public struct BranchGtUImm: BranchInstruction {
        public static var opcode: UInt8 { 50 }

        public let register: Registers.Index
        public let value: UInt32
        public let offset: UInt32

        public init(data: Data) throws {
            register = try Registers.Index(data.at(relative: 0))
            (value, offset) = Instructions.decodeImmediate2(data, divideBy: 16)!
        }

        func comparison(state: VMState, skip _: UInt32) -> Bool {
            state.readRegister(register) > value
        }
    }

    public struct BranchLtSImm: BranchInstruction {
        public static var opcode: UInt8 { 32 }

        public let register: Registers.Index
        public let value: UInt32
        public let offset: UInt32

        public init(data: Data) throws {
            register = try Registers.Index(data.at(relative: 0))
            (value, offset) = Instructions.decodeImmediate2(data, divideBy: 16)!
        }

        func comparison(state: VMState, skip _: UInt32) -> Bool {
            let regVal = state.readRegister(register)
            return Int32(bitPattern: regVal) < Int32(bitPattern: value)
        }
    }

    public struct BranchLeSImm: BranchInstruction {
        public static var opcode: UInt8 { 46 }

        public let register: Registers.Index
        public let value: UInt32
        public let offset: UInt32

        public init(data: Data) throws {
            register = try Registers.Index(data.at(relative: 0))
            (value, offset) = Instructions.decodeImmediate2(data, divideBy: 16)!
        }

        func comparison(state: VMState, skip _: UInt32) -> Bool {
            let regVal = state.readRegister(register)
            return Int32(bitPattern: regVal) <= Int32(bitPattern: value)
        }
    }

    public struct BranchGeSImm: BranchInstruction {
        public static var opcode: UInt8 { 45 }

        public let register: Registers.Index
        public let value: UInt32
        public let offset: UInt32

        public init(data: Data) throws {
            register = try Registers.Index(data.at(relative: 0))
            (value, offset) = Instructions.decodeImmediate2(data, divideBy: 16)!
        }

        func comparison(state: VMState, skip _: UInt32) -> Bool {
            let regVal = state.readRegister(register)
            return Int32(bitPattern: regVal) >= Int32(bitPattern: value)
        }
    }

    public struct BranchGtSImm: BranchInstruction {
        public static var opcode: UInt8 { 53 }

        public let register: Registers.Index
        public let value: UInt32
        public let offset: UInt32

        public init(data: Data) throws {
            register = try Registers.Index(data.at(relative: 0))
            (value, offset) = Instructions.decodeImmediate2(data, divideBy: 16)!
        }

        func comparison(state: VMState, skip _: UInt32) -> Bool {
            let regVal = state.readRegister(register)
            return Int32(bitPattern: regVal) > Int32(bitPattern: value)
        }
    }
}
