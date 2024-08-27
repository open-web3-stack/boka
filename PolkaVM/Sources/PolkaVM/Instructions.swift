import Foundation
import Utils

public let BASIC_BLOCK_INSTRUCTIONS: Set<UInt8> = [
    Instructions.Trap.opcode,
    Instructions.Fallthrough.opcode,
    Instructions.Jump.opcode,
    Instructions.JumpInd.opcode,
    Instructions.LoadImmJump.opcode,
    Instructions.LoadImmJumpInd.opcode,
    Instructions.BranchEq.opcode,
    Instructions.BranchNe.opcode,
    Instructions.BranchGeU.opcode,
    Instructions.BranchGeS.opcode,
    Instructions.BranchLtU.opcode,
    Instructions.BranchLtS.opcode,
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

public enum Instructions {
    public enum Constants {
        public static let djumpHaltAddress: UInt32 = 0xFFFF_0000
        public static let djumpAddressAlignmentFactor: Int = 2
    }

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

    static func decodeImmediate2(_ data: Data, divideBy: UInt8 = 1, minus: Int = 1) throws -> (UInt32, UInt32) {
        let lX1 = try Int((data.at(relative: 0) / divideBy) & 0b111)
        let lX = min(4, lX1)
        let lY = min(4, max(0, data.count - Int(lX) - minus))

        let vX = try decodeImmediate(data.at(relative: 1 ..< 1 + lX))
        let vY = try decodeImmediate(data.at(relative: (1 + lX) ..< (1 + lX + lY)))
        return (vX, vY)
    }

    static func isBranchValid(state: VMState, offset: UInt32) -> Bool {
        state.program.basicBlockIndices.contains(state.pc &+ offset)
    }

    static func isDjumpValid(state: VMState, target a: UInt32, targetAligned: UInt32) -> Bool {
        let za = Constants.djumpAddressAlignmentFactor
        return a == 0 &&
            a > state.program.jumpTable.count * za &&
            Int(a) % za != 0 &&
            state.program.basicBlockIndices.contains(targetAligned)
    }

    static func djump(state: VMState, target: UInt32) -> ExecOutcome {
        guard target != Constants.djumpHaltAddress else {
            return .exit(.halt)
        }

        let entrySize = Int(state.program.jumpTableEntrySize)
        let start = ((Int(target) / Constants.djumpAddressAlignmentFactor) - 1) * entrySize
        let end = start + entrySize
        var targetAlignedData = state.program.jumpTable[relative: start ..< end]
        guard let targetAligned = targetAlignedData.decode() else {
            fatalError("unreachable: jump table entry should be valid")
        }

        guard isDjumpValid(state: state, target: target, targetAligned: UInt32(targetAligned)) else {
            return .exit(.panic(.invalidDynamicJump))
        }

        state.updatePC(UInt32(targetAligned))
        return .continued
    }

    // MARK: Instructions without Arguments (5.1)

    public struct Trap: Instruction {
        public static var opcode: UInt8 { 0 }

        public init(data _: Data) {}

        public func _executeImpl(state _: VMState) -> ExecOutcome {
            .exit(.panic(.trap))
        }
    }

    public struct Fallthrough: Instruction {
        public static var opcode: UInt8 { 17 }

        public init(data _: Data) {}

        public func _executeImpl(state _: VMState) -> ExecOutcome { .continued }
    }

    // MARK: Instructions with Arguments of One Immediate (5.2)

    public struct Ecalli: Instruction {
        public static var opcode: UInt8 { 78 }

        public let callIndex: UInt32

        public init(data: Data) {
            callIndex = Instructions.decodeImmediate(data)
        }

        public func _executeImpl(state _: VMState) -> ExecOutcome {
            .exit(.hostCall(callIndex))
        }
    }

    // MARK: Instructions with Arguments of Two Immediates (5.3)

    public struct StoreImmU8: Instruction {
        public static var opcode: UInt8 { 62 }

        public let address: UInt32
        public let value: UInt8

        public init(data: Data) throws {
            let (x, y) = try Instructions.decodeImmediate2(data)
            address = x
            value = UInt8(truncatingIfNeeded: y)
        }

        public func _executeImpl(state: VMState) throws -> ExecOutcome {
            try state.writeMemory(address: address, value: value)
            return .continued
        }
    }

    public struct StoreImmU16: Instruction {
        public static var opcode: UInt8 { 79 }

        public let address: UInt32
        public let value: UInt16

        public init(data: Data) throws {
            let (x, y) = try Instructions.decodeImmediate2(data)
            address = x
            value = UInt16(truncatingIfNeeded: y)
        }

        public func _executeImpl(state: VMState) throws -> ExecOutcome {
            try state.writeMemory(address: address, values: value.encode(method: .fixedWidth(2)))
            return .continued
        }
    }

    public struct StoreImmU32: Instruction {
        public static var opcode: UInt8 { 38 }

        public let address: UInt32
        public let value: UInt32

        public init(data: Data) throws {
            let (x, y) = try Instructions.decodeImmediate2(data)
            address = x
            value = y
        }

        public func _executeImpl(state: VMState) -> ExecOutcome {
            if (try? state.writeMemory(
                address: address, values: value.encode(method: .fixedWidth(4))
            )) != nil {
                return .continued
            }
            return .exit(.pageFault(address))
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

        public func _executeImpl(state _: VMState) -> ExecOutcome { .continued }

        public func updatePC(state: VMState, skip _: UInt32) -> ExecOutcome {
            guard Instructions.isBranchValid(state: state, offset: offset) else {
                return .exit(.panic(.invalidBranch))
            }
            state.increasePC(offset)
            return .continued
        }
    }

    // Instructions with Arguments of One Register & One Immediate (5.5)

    public struct JumpInd: Instruction {
        public static var opcode: UInt8 { 19 }

        public let register: Registers.Index
        public let offset: UInt32

        public init(data: Data) throws {
            register = try Registers.Index(ra: data.at(relative: 0))
            offset = try Instructions.decodeImmediate(data.at(relative: 1...))
        }

        public func _executeImpl(state _: VMState) -> ExecOutcome { .continued }

        public func updatePC(state: VMState, skip _: UInt32) -> ExecOutcome {
            let regVal = state.readRegister(register)
            return Instructions.djump(state: state, target: regVal &+ offset)
        }
    }

    public struct LoadImm: Instruction {
        public static var opcode: UInt8 { 4 }

        public let register: Registers.Index
        public let value: UInt32

        public init(data: Data) throws {
            register = try Registers.Index(ra: data.at(relative: 0))
            value = try Instructions.decodeImmediate(data.at(relative: 1...))
        }

        public func _executeImpl(state: VMState) -> ExecOutcome {
            state.writeRegister(register, value)
            return .continued
        }
    }

    public struct LoadU8: Instruction {
        public static var opcode: UInt8 { 60 }

        public let register: Registers.Index
        public let address: UInt32

        public init(data: Data) throws {
            register = try Registers.Index(ra: data.at(relative: 0))
            address = try Instructions.decodeImmediate(data.at(relative: 1...))
        }

        public func _executeImpl(state: VMState) throws -> ExecOutcome {
            let value = try state.readMemory(address: address)
            state.writeRegister(register, UInt32(value))
            return .continued
        }
    }

    public struct LoadI8: Instruction {
        public static var opcode: UInt8 { 74 }

        public let register: Registers.Index
        public let address: UInt32

        public init(data: Data) throws {
            register = try Registers.Index(ra: data.at(relative: 0))
            address = try Instructions.decodeImmediate(data.at(relative: 1...))
        }

        public func _executeImpl(state: VMState) throws -> ExecOutcome {
            let value = try state.readMemory(address: address)
            state.writeRegister(register, UInt32(bitPattern: Int32(Int8(bitPattern: value))))
            return .continued
        }
    }

    public struct LoadU16: Instruction {
        public static var opcode: UInt8 { 76 }

        public let register: Registers.Index
        public let address: UInt32

        public init(data: Data) throws {
            register = try Registers.Index(ra: data.at(relative: 0))
            address = try Instructions.decodeImmediate(data.at(relative: 1...))
        }

        public func _executeImpl(state: VMState) throws -> ExecOutcome {
            var data = try state.readMemory(address: address, length: 2)
            guard let value: UInt16 = data.decode(length: 2) else {
                fatalError("unreachable: value should be valid")
            }
            state.writeRegister(register, UInt32(value))
            return .continued
        }
    }

    public struct LoadI16: Instruction {
        public static var opcode: UInt8 { 66 }

        public let register: Registers.Index
        public let address: UInt32

        public init(data: Data) throws {
            register = try Registers.Index(ra: data.at(relative: 0))
            address = try Instructions.decodeImmediate(data.at(relative: 1...))
        }

        public func _executeImpl(state: VMState) throws -> ExecOutcome {
            var data = try state.readMemory(address: address, length: 2)
            guard let value: UInt16 = data.decode(length: 2) else {
                fatalError("unreachable: value should be valid")
            }
            state.writeRegister(register, UInt32(bitPattern: Int32(Int16(bitPattern: value))))
            return .continued
        }
    }

    public struct LoadU32: Instruction {
        public static var opcode: UInt8 { 10 }

        public let register: Registers.Index
        public let address: UInt32

        public init(data: Data) throws {
            register = try Registers.Index(ra: data.at(relative: 0))
            address = try Instructions.decodeImmediate(data.at(relative: 1...))
        }

        public func _executeImpl(state: VMState) throws -> ExecOutcome {
            var data = try state.readMemory(address: address, length: 4)
            guard let value: UInt32 = data.decode(length: 4) else {
                fatalError("unreachable: value should be valid")
            }
            state.writeRegister(register, value)
            return .continued
        }
    }

    public struct StoreU8: Instruction {
        public static var opcode: UInt8 { 71 }

        public let register: Registers.Index
        public let address: UInt32

        public init(data: Data) throws {
            register = try Registers.Index(ra: data.at(relative: 0))
            address = try Instructions.decodeImmediate(data.at(relative: 1...))
        }

        public func _executeImpl(state: VMState) throws -> ExecOutcome {
            let value = UInt8(truncatingIfNeeded: state.readRegister(register))
            try state.writeMemory(address: address, value: value)
            return .continued
        }
    }

    public struct StoreU16: Instruction {
        public static var opcode: UInt8 { 69 }

        public let register: Registers.Index
        public let address: UInt32

        public init(data: Data) throws {
            register = try Registers.Index(ra: data.at(relative: 0))
            address = try Instructions.decodeImmediate(data.at(relative: 1...))
        }

        public func _executeImpl(state: VMState) throws -> ExecOutcome {
            let value = UInt16(truncatingIfNeeded: state.readRegister(register))
            try state.writeMemory(address: address, values: value.encode(method: .fixedWidth(2)))
            return .continued
        }
    }

    public struct StoreU32: Instruction {
        public static var opcode: UInt8 { 22 }

        public let register: Registers.Index
        public let address: UInt32

        public init(data: Data) throws {
            register = try Registers.Index(ra: data.at(relative: 0))
            address = try Instructions.decodeImmediate(data.at(relative: 1...))
        }

        public func _executeImpl(state: VMState) throws -> ExecOutcome {
            let value = state.readRegister(register)
            try state.writeMemory(address: address, values: value.encode(method: .fixedWidth(4)))
            return .continued
        }
    }

    // MARK: Instructions with Arguments of One Register & Two Immediates (5.6)

    public struct StoreImmIndU8: Instruction {
        public static var opcode: UInt8 { 26 }

        public let register: Registers.Index
        public let address: UInt32
        public let value: UInt8

        public init(data: Data) throws {
            register = try Registers.Index(ra: data.at(relative: 0))
            let (x, y) = try Instructions.decodeImmediate2(data, divideBy: 16)
            address = x
            value = UInt8(truncatingIfNeeded: y)
        }

        public func _executeImpl(state: VMState) throws -> ExecOutcome {
            try state.writeMemory(address: state.readRegister(register) &+ address, value: value)
            return .continued
        }
    }

    public struct StoreImmIndU16: Instruction {
        public static var opcode: UInt8 { 54 }

        public let register: Registers.Index
        public let address: UInt32
        public let value: UInt16

        public init(data: Data) throws {
            register = try Registers.Index(ra: data.at(relative: 0))
            let (x, y) = try Instructions.decodeImmediate2(data, divideBy: 16)
            address = x
            value = UInt16(truncatingIfNeeded: y)
        }

        public func _executeImpl(state: VMState) throws -> ExecOutcome {
            try state.writeMemory(address: state.readRegister(register) &+ address, values: value.encode(method: .fixedWidth(2)))
            return .continued
        }
    }

    public struct StoreImmIndU32: Instruction {
        public static var opcode: UInt8 { 13 }

        public let register: Registers.Index
        public let address: UInt32
        public let value: UInt32

        public init(data: Data) throws {
            register = try Registers.Index(ra: data.at(relative: 0))
            let (x, y) = try Instructions.decodeImmediate2(data, divideBy: 16)
            address = x
            value = y
        }

        public func _executeImpl(state: VMState) throws -> ExecOutcome {
            try state.writeMemory(address: state.readRegister(register) &+ address, values: value.encode(method: .fixedWidth(4)))
            return .continued
        }
    }

    // MARK: Instructions with Arguments of One Register, One Immediate and One Offset (5.7)

    public struct LoadImmJump: Instruction {
        public static var opcode: UInt8 { 6 }

        public let register: Registers.Index
        public let value: UInt32
        public let offset: UInt32

        public init(data: Data) throws {
            register = try Registers.Index(ra: data.at(relative: 0))
            (value, offset) = try Instructions.decodeImmediate2(data, divideBy: 16)
        }

        public func _executeImpl(state: VMState) throws -> ExecOutcome {
            state.writeRegister(register, value)
            return .continued
        }

        public func updatePC(state: VMState, skip _: UInt32) -> ExecOutcome {
            guard Instructions.isBranchValid(state: state, offset: offset) else {
                return .exit(.panic(.invalidBranch))
            }
            state.increasePC(offset)
            return .continued
        }
    }

    public struct BranchEqImm: BranchInstructionBase {
        public static var opcode: UInt8 { 7 }
        typealias Compare = CompareEq

        var register: Registers.Index
        var value: UInt32
        var offset: UInt32
        public init(data: Data) throws { (register, value, offset) = try Self.parse(data: data) }
    }

    public struct BranchNeImm: BranchInstructionBase {
        public static var opcode: UInt8 { 15 }
        typealias Compare = CompareNe

        var register: Registers.Index
        var value: UInt32
        var offset: UInt32
        public init(data: Data) throws { (register, value, offset) = try Self.parse(data: data) }
    }

    public struct BranchLtUImm: BranchInstructionBase {
        public static var opcode: UInt8 { 44 }
        typealias Compare = CompareLt

        var register: Registers.Index
        var value: UInt32
        var offset: UInt32
        public init(data: Data) throws { (register, value, offset) = try Self.parse(data: data) }
    }

    public struct BranchLeUImm: BranchInstructionBase {
        public static var opcode: UInt8 { 59 }
        typealias Compare = CompareLe

        var register: Registers.Index
        var value: UInt32
        var offset: UInt32
        public init(data: Data) throws { (register, value, offset) = try Self.parse(data: data) }
    }

    public struct BranchGeUImm: BranchInstructionBase {
        public static var opcode: UInt8 { 52 }
        typealias Compare = CompareGe

        var register: Registers.Index
        var value: UInt32
        var offset: UInt32
        public init(data: Data) throws { (register, value, offset) = try Self.parse(data: data) }
    }

    public struct BranchGtUImm: BranchInstructionBase {
        public static var opcode: UInt8 { 50 }
        typealias Compare = CompareGt

        var register: Registers.Index
        var value: UInt32
        var offset: UInt32
        public init(data: Data) throws { (register, value, offset) = try Self.parse(data: data) }
    }

    public struct BranchLtSImm: BranchInstructionBase {
        public static var opcode: UInt8 { 32 }
        typealias Compare = CompareLt

        var register: Registers.Index
        var value: UInt32
        var offset: UInt32
        public init(data: Data) throws { (register, value, offset) = try Self.parse(data: data) }
    }

    public struct BranchLeSImm: BranchInstructionBase {
        public static var opcode: UInt8 { 46 }
        typealias Compare = CompareLe

        var register: Registers.Index
        var value: UInt32
        var offset: UInt32
        public init(data: Data) throws { (register, value, offset) = try Self.parse(data: data) }
    }

    public struct BranchGeSImm: BranchInstructionBase {
        public static var opcode: UInt8 { 45 }
        typealias Compare = CompareGe

        var register: Registers.Index
        var value: UInt32
        var offset: UInt32
        public init(data: Data) throws { (register, value, offset) = try Self.parse(data: data) }
    }

    public struct BranchGtSImm: BranchInstructionBase {
        public static var opcode: UInt8 { 53 }
        typealias Compare = CompareGt

        var register: Registers.Index
        var value: UInt32
        var offset: UInt32
        public init(data: Data) throws { (register, value, offset) = try Self.parse(data: data) }
    }

    // MARK: Instructions with Arguments of Two Registers (5.8)

    public struct MoveReg: Instruction {
        public static var opcode: UInt8 { 82 }

        public let src: Registers.Index
        public let dest: Registers.Index

        public init(data: Data) throws {
            dest = try Registers.Index(ra: data.at(relative: 0))
            src = try Registers.Index(rb: data.at(relative: 0))
        }

        public func _executeImpl(state: VMState) -> ExecOutcome {
            state.writeRegister(dest, state.readRegister(src))
            return .continued
        }
    }

    public struct Sbrk: Instruction {
        public static var opcode: UInt8 { 87 }

        public let src: Registers.Index
        public let dest: Registers.Index

        public init(data: Data) throws {
            dest = try Registers.Index(ra: data.at(relative: 0))
            src = try Registers.Index(rb: data.at(relative: 0))
        }

        public func _executeImpl(state: VMState) throws -> ExecOutcome {
            let increment = state.readRegister(src)
            let startAddr = try state.sbrk(increment)
            state.writeRegister(dest, startAddr)

            return .continued
        }
    }

    // MARK: Instructions with Arguments of Two Registers & One Immediate (5.9)

    public struct StoreIndU8: Instruction {
        public static var opcode: UInt8 { 16 }

        public let src: Registers.Index
        public let dest: Registers.Index
        public let offset: UInt32

        public init(data: Data) throws {
            src = try Registers.Index(ra: data.at(relative: 0))
            dest = try Registers.Index(rb: data.at(relative: 0))
            offset = try Instructions.decodeImmediate(data.at(relative: 1...))
        }

        public func _executeImpl(state: VMState) throws -> ExecOutcome {
            let value = UInt8(truncatingIfNeeded: state.readRegister(src))
            try state.writeMemory(address: state.readRegister(dest) &+ offset, value: value)
            return .continued
        }
    }

    public struct StoreIndU16: Instruction {
        public static var opcode: UInt8 { 29 }

        public let src: Registers.Index
        public let dest: Registers.Index
        public let offset: UInt32

        public init(data: Data) throws {
            src = try Registers.Index(ra: data.at(relative: 0))
            dest = try Registers.Index(rb: data.at(relative: 0))
            offset = try Instructions.decodeImmediate(data.at(relative: 1...))
        }

        public func _executeImpl(state: VMState) throws -> ExecOutcome {
            let value = UInt16(truncatingIfNeeded: state.readRegister(src))
            try state.writeMemory(address: state.readRegister(dest) &+ offset, values: value.encode(method: .fixedWidth(2)))
            return .continued
        }
    }

    public struct StoreIndU32: Instruction {
        public static var opcode: UInt8 { 3 }

        public let src: Registers.Index
        public let dest: Registers.Index
        public let offset: UInt32

        public init(data: Data) throws {
            src = try Registers.Index(ra: data.at(relative: 0))
            dest = try Registers.Index(rb: data.at(relative: 0))
            offset = try Instructions.decodeImmediate(data.at(relative: 1...))
        }

        public func _executeImpl(state: VMState) throws -> ExecOutcome {
            let value = state.readRegister(src)
            try state.writeMemory(address: state.readRegister(dest) &+ offset, values: value.encode(method: .fixedWidth(4)))
            return .continued
        }
    }

    public struct LoadIndU8: Instruction {
        public static var opcode: UInt8 { 11 }

        public let src: Registers.Index
        public let dest: Registers.Index
        public let offset: UInt32

        public init(data: Data) throws {
            dest = try Registers.Index(ra: data.at(relative: 0))
            src = try Registers.Index(rb: data.at(relative: 0))
            offset = try Instructions.decodeImmediate(data.at(relative: 1...))
        }

        public func _executeImpl(state: VMState) throws -> ExecOutcome {
            let value = try state.readMemory(address: state.readRegister(src) + offset)
            state.writeRegister(dest, UInt32(value))
            return .continued
        }
    }

    public struct LoadIndI8: Instruction {
        public static var opcode: UInt8 { 21 }

        public let src: Registers.Index
        public let dest: Registers.Index
        public let offset: UInt32

        public init(data: Data) throws {
            dest = try Registers.Index(ra: data.at(relative: 0))
            src = try Registers.Index(rb: data.at(relative: 0))
            offset = try Instructions.decodeImmediate(data.at(relative: 1...))
        }

        public func _executeImpl(state: VMState) throws -> ExecOutcome {
            let value = try state.readMemory(address: state.readRegister(src) + offset)
            state.writeRegister(dest, UInt32(bitPattern: Int32(Int8(bitPattern: value))))
            return .continued
        }
    }

    public struct LoadIndU16: Instruction {
        public static var opcode: UInt8 { 37 }

        public let src: Registers.Index
        public let dest: Registers.Index
        public let offset: UInt32

        public init(data: Data) throws {
            dest = try Registers.Index(ra: data.at(relative: 0))
            src = try Registers.Index(rb: data.at(relative: 0))
            offset = try Instructions.decodeImmediate(data.at(relative: 1...))
        }

        public func _executeImpl(state: VMState) throws -> ExecOutcome {
            var data = try state.readMemory(address: state.readRegister(src) &+ offset, length: 2)
            guard let value: UInt16 = data.decode(length: 2) else {
                fatalError("unreachable: value should be valid")
            }
            state.writeRegister(dest, UInt32(value))
            return .continued
        }
    }

    public struct LoadIndI16: Instruction {
        public static var opcode: UInt8 { 33 }

        public let src: Registers.Index
        public let dest: Registers.Index
        public let offset: UInt32

        public init(data: Data) throws {
            dest = try Registers.Index(ra: data.at(relative: 0))
            src = try Registers.Index(rb: data.at(relative: 0))
            offset = try Instructions.decodeImmediate(data.at(relative: 1...))
        }

        public func _executeImpl(state: VMState) throws -> ExecOutcome {
            var data = try state.readMemory(address: state.readRegister(src) &+ offset, length: 2)
            guard let value: UInt16 = data.decode(length: 2) else {
                fatalError("unreachable: value should be valid")
            }
            state.writeRegister(dest, UInt32(bitPattern: Int32(Int16(bitPattern: value))))
            return .continued
        }
    }

    public struct LoadIndU32: Instruction {
        public static var opcode: UInt8 { 1 }

        public let src: Registers.Index
        public let dest: Registers.Index
        public let offset: UInt32

        public init(data: Data) throws {
            dest = try Registers.Index(ra: data.at(relative: 0))
            src = try Registers.Index(rb: data.at(relative: 0))
            offset = try Instructions.decodeImmediate(data.at(relative: 1...))
        }

        public func _executeImpl(state: VMState) throws -> ExecOutcome {
            var data = try state.readMemory(address: state.readRegister(src) &+ offset, length: 4)
            guard let value: UInt32 = data.decode(length: 4) else {
                fatalError("unreachable: value should be valid")
            }
            state.writeRegister(dest, value)
            return .continued
        }
    }

    public struct AddImm: Instruction {
        public static var opcode: UInt8 { 2 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let value: UInt32

        public init(data: Data) throws {
            ra = try Registers.Index(ra: data.at(relative: 0))
            rb = try Registers.Index(rb: data.at(relative: 0))
            value = try Instructions.decodeImmediate(data.at(relative: 1...))
        }

        public func _executeImpl(state: VMState) -> ExecOutcome {
            let regVal = state.readRegister(rb)
            state.writeRegister(ra, regVal &+ value)
            return .continued
        }
    }

    public struct AndImm: Instruction {
        public static var opcode: UInt8 { 18 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let value: UInt32

        public init(data: Data) throws {
            ra = try Registers.Index(ra: data.at(relative: 0))
            rb = try Registers.Index(rb: data.at(relative: 0))
            value = try Instructions.decodeImmediate(data.at(relative: 1...))
        }

        public func _executeImpl(state: VMState) -> ExecOutcome {
            let regVal = state.readRegister(rb)
            state.writeRegister(ra, regVal & value)
            return .continued
        }
    }

    public struct XorImm: Instruction {
        public static var opcode: UInt8 { 31 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let value: UInt32

        public init(data: Data) throws {
            ra = try Registers.Index(ra: data.at(relative: 0))
            rb = try Registers.Index(rb: data.at(relative: 0))
            value = try Instructions.decodeImmediate(data.at(relative: 1...))
        }

        public func _executeImpl(state: VMState) -> ExecOutcome {
            let regVal = state.readRegister(rb)
            state.writeRegister(ra, regVal ^ value)
            return .continued
        }
    }

    public struct OrImm: Instruction {
        public static var opcode: UInt8 { 49 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let value: UInt32

        public init(data: Data) throws {
            ra = try Registers.Index(ra: data.at(relative: 0))
            rb = try Registers.Index(rb: data.at(relative: 0))
            value = try Instructions.decodeImmediate(data.at(relative: 1...))
        }

        public func _executeImpl(state: VMState) -> ExecOutcome {
            let regVal = state.readRegister(rb)
            state.writeRegister(ra, regVal | value)
            return .continued
        }
    }

    public struct MulImm: Instruction {
        public static var opcode: UInt8 { 35 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let value: UInt32

        public init(data: Data) throws {
            ra = try Registers.Index(ra: data.at(relative: 0))
            rb = try Registers.Index(rb: data.at(relative: 0))
            value = try Instructions.decodeImmediate(data.at(relative: 1...))
        }

        public func _executeImpl(state: VMState) -> ExecOutcome {
            let regVal = state.readRegister(rb)
            state.writeRegister(ra, regVal &* value)
            return .continued
        }
    }

    public struct MulUpperSSImm: Instruction {
        public static var opcode: UInt8 { 65 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let value: UInt32

        public init(data: Data) throws {
            ra = try Registers.Index(ra: data.at(relative: 0))
            rb = try Registers.Index(rb: data.at(relative: 0))
            value = try Instructions.decodeImmediate(data.at(relative: 1...))
        }

        public func _executeImpl(state: VMState) -> ExecOutcome {
            let regVal = state.readRegister(rb)
            state.writeRegister(ra, UInt32(bitPattern: Int32((Int64(Int32(bitPattern: regVal)) * Int64(Int32(bitPattern: value))) >> 32)))
            return .continued
        }
    }

    public struct MulUpperUUImm: Instruction {
        public static var opcode: UInt8 { 63 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let value: UInt32

        public init(data: Data) throws {
            ra = try Registers.Index(ra: data.at(relative: 0))
            rb = try Registers.Index(rb: data.at(relative: 0))
            value = try Instructions.decodeImmediate(data.at(relative: 1...))
        }

        public func _executeImpl(state: VMState) -> ExecOutcome {
            let regVal = state.readRegister(rb)
            state.writeRegister(ra, UInt32((UInt64(regVal) * UInt64(value)) >> 32))
            return .continued
        }
    }

    public struct SetLtUImm: Instruction {
        public static var opcode: UInt8 { 27 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let value: UInt32

        public init(data: Data) throws {
            ra = try Registers.Index(ra: data.at(relative: 0))
            rb = try Registers.Index(rb: data.at(relative: 0))
            value = try Instructions.decodeImmediate(data.at(relative: 1...))
        }

        public func _executeImpl(state: VMState) -> ExecOutcome {
            let regVal = state.readRegister(rb)
            state.writeRegister(ra, regVal < value ? 1 : 0)
            return .continued
        }
    }

    public struct SetLtSImm: Instruction {
        public static var opcode: UInt8 { 56 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let value: UInt32

        public init(data: Data) throws {
            ra = try Registers.Index(ra: data.at(relative: 0))
            rb = try Registers.Index(rb: data.at(relative: 0))
            value = try Instructions.decodeImmediate(data.at(relative: 1...))
        }

        public func _executeImpl(state: VMState) -> ExecOutcome {
            let regVal = state.readRegister(rb)
            state.writeRegister(ra, Int32(bitPattern: regVal) < Int32(bitPattern: value) ? 1 : 0)
            return .continued
        }
    }

    public struct ShloLImm: Instruction {
        public static var opcode: UInt8 { 9 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let value: UInt32

        public init(data: Data) throws {
            ra = try Registers.Index(ra: data.at(relative: 0))
            rb = try Registers.Index(rb: data.at(relative: 0))
            value = try Instructions.decodeImmediate(data.at(relative: 1...))
        }

        public func _executeImpl(state: VMState) -> ExecOutcome {
            let regVal = state.readRegister(rb)
            let shift = value & 0x1F
            state.writeRegister(ra, regVal << shift)
            return .continued
        }
    }

    public struct ShloRImm: Instruction {
        public static var opcode: UInt8 { 14 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let value: UInt32

        public init(data: Data) throws {
            ra = try Registers.Index(ra: data.at(relative: 0))
            rb = try Registers.Index(rb: data.at(relative: 0))
            value = try Instructions.decodeImmediate(data.at(relative: 1...))
        }

        public func _executeImpl(state: VMState) -> ExecOutcome {
            let regVal = state.readRegister(rb)
            let shift = value & 0x1F
            state.writeRegister(ra, regVal >> shift)
            return .continued
        }
    }

    public struct SharRImm: Instruction {
        public static var opcode: UInt8 { 25 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let value: UInt32

        public init(data: Data) throws {
            ra = try Registers.Index(ra: data.at(relative: 0))
            rb = try Registers.Index(rb: data.at(relative: 0))
            value = try Instructions.decodeImmediate(data.at(relative: 1...))
        }

        public func _executeImpl(state: VMState) -> ExecOutcome {
            let regVal = state.readRegister(rb)
            let shift = value & 0x1F
            state.writeRegister(ra, UInt32(bitPattern: Int32(bitPattern: regVal) >> shift))
            return .continued
        }
    }

    public struct NegAddImm: Instruction {
        public static var opcode: UInt8 { 40 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let value: UInt32

        public init(data: Data) throws {
            ra = try Registers.Index(ra: data.at(relative: 0))
            rb = try Registers.Index(rb: data.at(relative: 0))
            value = try Instructions.decodeImmediate(data.at(relative: 1...))
        }

        public func _executeImpl(state: VMState) -> ExecOutcome {
            let regVal = state.readRegister(rb)
            state.writeRegister(ra, regVal &- value)
            return .continued
        }
    }

    public struct SetGtUImm: Instruction {
        public static var opcode: UInt8 { 39 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let value: UInt32

        public init(data: Data) throws {
            ra = try Registers.Index(ra: data.at(relative: 0))
            rb = try Registers.Index(rb: data.at(relative: 0))
            value = try Instructions.decodeImmediate(data.at(relative: 1...))
        }

        public func _executeImpl(state: VMState) -> ExecOutcome {
            let regVal = state.readRegister(rb)
            state.writeRegister(ra, regVal > value ? 1 : 0)
            return .continued
        }
    }

    public struct SetGtSImm: Instruction {
        public static var opcode: UInt8 { 61 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let value: UInt32

        public init(data: Data) throws {
            ra = try Registers.Index(ra: data.at(relative: 0))
            rb = try Registers.Index(rb: data.at(relative: 0))
            value = try Instructions.decodeImmediate(data.at(relative: 1...))
        }

        public func _executeImpl(state: VMState) -> ExecOutcome {
            let regVal = state.readRegister(rb)
            state.writeRegister(ra, Int32(bitPattern: regVal) > Int32(bitPattern: value) ? 1 : 0)
            return .continued
        }
    }

    public struct ShloLImmAlt: Instruction {
        public static var opcode: UInt8 { 75 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let value: UInt32

        public init(data: Data) throws {
            ra = try Registers.Index(ra: data.at(relative: 0))
            rb = try Registers.Index(rb: data.at(relative: 0))
            value = try Instructions.decodeImmediate(data.at(relative: 1...))
        }

        public func _executeImpl(state: VMState) -> ExecOutcome {
            let regVal = state.readRegister(rb)
            let shift = regVal & 0x1F
            state.writeRegister(ra, value << shift)
            return .continued
        }
    }

    public struct ShloRImmAlt: Instruction {
        public static var opcode: UInt8 { 72 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let value: UInt32

        public init(data: Data) throws {
            ra = try Registers.Index(ra: data.at(relative: 0))
            rb = try Registers.Index(rb: data.at(relative: 0))
            value = try Instructions.decodeImmediate(data.at(relative: 1...))
        }

        public func _executeImpl(state: VMState) -> ExecOutcome {
            let regVal = state.readRegister(rb)
            let shift = regVal & 0x1F
            state.writeRegister(ra, value >> shift)
            return .continued
        }
    }

    public struct SharRImmAlt: Instruction {
        public static var opcode: UInt8 { 80 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let value: UInt32

        public init(data: Data) throws {
            ra = try Registers.Index(ra: data.at(relative: 0))
            rb = try Registers.Index(rb: data.at(relative: 0))
            value = try Instructions.decodeImmediate(data.at(relative: 1...))
        }

        public func _executeImpl(state: VMState) -> ExecOutcome {
            let regVal = state.readRegister(rb)
            let shift = regVal & 0x1F
            state.writeRegister(ra, UInt32(bitPattern: Int32(bitPattern: value) >> shift))
            return .continued
        }
    }

    public struct CmovIzImm: Instruction {
        public static var opcode: UInt8 { 81 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let value: UInt32

        public init(data: Data) throws {
            ra = try Registers.Index(ra: data.at(relative: 0))
            rb = try Registers.Index(rb: data.at(relative: 0))
            value = try Instructions.decodeImmediate(data.at(relative: 1...))
        }

        public func _executeImpl(state: VMState) -> ExecOutcome {
            let regVal = state.readRegister(rb)
            state.writeRegister(ra, regVal == 0 ? value : regVal)
            return .continued
        }
    }

    public struct CmovNzImm: Instruction {
        public static var opcode: UInt8 { 82 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let value: UInt32

        public init(data: Data) throws {
            ra = try Registers.Index(ra: data.at(relative: 0))
            rb = try Registers.Index(rb: data.at(relative: 0))
            value = try Instructions.decodeImmediate(data.at(relative: 1...))
        }

        public func _executeImpl(state: VMState) -> ExecOutcome {
            let regVal = state.readRegister(rb)
            state.writeRegister(ra, regVal != 0 ? value : regVal)
            return .continued
        }
    }

    // MARK: Instructions with Arguments of Two Registers & One Offset (5.10)

    public struct BranchEq: BranchInstructionBase2 {
        public static var opcode: UInt8 { 24 }
        typealias Compare = CompareEq

        var r1: Registers.Index
        var r2: Registers.Index
        var offset: UInt32
        public init(data: Data) throws { (r1, r2, offset) = try Self.parse(data: data) }
    }

    public struct BranchNe: BranchInstructionBase2 {
        public static var opcode: UInt8 { 30 }
        typealias Compare = CompareNe

        var r1: Registers.Index
        var r2: Registers.Index
        var offset: UInt32
        public init(data: Data) throws { (r1, r2, offset) = try Self.parse(data: data) }
    }

    public struct BranchLtU: BranchInstructionBase2 {
        public static var opcode: UInt8 { 47 }
        typealias Compare = CompareLt

        var r1: Registers.Index
        var r2: Registers.Index
        var offset: UInt32
        public init(data: Data) throws { (r1, r2, offset) = try Self.parse(data: data) }
    }

    public struct BranchLtS: BranchInstructionBase2 {
        public static var opcode: UInt8 { 48 }
        typealias Compare = CompareLt

        var r1: Registers.Index
        var r2: Registers.Index
        var offset: UInt32
        public init(data: Data) throws { (r1, r2, offset) = try Self.parse(data: data) }
    }

    public struct BranchGeU: BranchInstructionBase2 {
        public static var opcode: UInt8 { 41 }
        typealias Compare = CompareGe

        var r1: Registers.Index
        var r2: Registers.Index
        var offset: UInt32
        public init(data: Data) throws { (r1, r2, offset) = try Self.parse(data: data) }
    }

    public struct BranchGeS: BranchInstructionBase2 {
        public static var opcode: UInt8 { 43 }
        typealias Compare = CompareGe

        var r1: Registers.Index
        var r2: Registers.Index
        var offset: UInt32
        public init(data: Data) throws { (r1, r2, offset) = try Self.parse(data: data) }
    }

    // MARK: Instruction with Arguments of Two Registers and Two Immediates (5.11)

    public struct LoadImmJumpInd: Instruction {
        public static var opcode: UInt8 { 10 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let value: UInt32
        public let offset: UInt32

        public init(data: Data) throws {
            ra = try Registers.Index(ra: data.at(relative: 0))
            rb = try Registers.Index(rb: data.at(relative: 0))
            (value, offset) = try Instructions.decodeImmediate2(data[relative: 1...], divideBy: 1, minus: 2)
        }

        public func _executeImpl(state: VMState) throws -> ExecOutcome {
            state.writeRegister(ra, value)
            return .continued
        }

        public func updatePC(state: VMState, skip _: UInt32) -> ExecOutcome {
            let rbVal = state.readRegister(rb)
            return Instructions.djump(state: state, target: rbVal &+ offset)
        }
    }
}

// MARK: Branch Helpers

protocol BranchCompare {
    static func compare(a: UInt32, b: UInt32) -> Bool
}

// for branch in A.5.7
protocol BranchInstructionBase<Compare>: Instruction {
    associatedtype Compare: BranchCompare

    var register: Registers.Index { get set }
    var value: UInt32 { get set }
    var offset: UInt32 { get set }

    func _executeImpl(state _: VMState) throws -> ExecOutcome
    func updatePC(state: VMState, skip: UInt32) -> ExecOutcome
    func condition(state: VMState) -> Bool
}

extension BranchInstructionBase {
    public static func parse(data: Data) throws -> (Registers.Index, UInt32, UInt32) {
        let register = try Registers.Index(ra: data.at(relative: 0))
        let (value, offset) = try Instructions.decodeImmediate2(data, divideBy: 16)
        return (register, value, offset)
    }

    public func _executeImpl(state _: VMState) throws -> ExecOutcome { .continued }

    public func updatePC(state: VMState, skip: UInt32) -> ExecOutcome {
        guard Instructions.isBranchValid(state: state, offset: offset) else {
            return .exit(.panic(.invalidBranch))
        }
        if condition(state: state) {
            state.increasePC(offset)
        } else {
            state.increasePC(skip + 1)
        }
        return .continued
    }

    public func condition(state: VMState) -> Bool {
        let regVal = state.readRegister(register)
        return Compare.compare(a: regVal, b: value)
    }
}

// for branch in A.5.10
protocol BranchInstructionBase2<Compare>: Instruction {
    associatedtype Compare: BranchCompare

    var r1: Registers.Index { get set }
    var r2: Registers.Index { get set }
    var offset: UInt32 { get set }

    func _executeImpl(state _: VMState) throws -> ExecOutcome
    func updatePC(state: VMState, skip: UInt32) -> ExecOutcome
    func condition(state: VMState) -> Bool
}

extension BranchInstructionBase2 {
    public static func parse(data: Data) throws -> (Registers.Index, Registers.Index, UInt32) {
        let offset = try Instructions.decodeImmediate(data.at(relative: 1...))
        let r1 = try Registers.Index(ra: data.at(relative: 0))
        let r2 = try Registers.Index(rb: data.at(relative: 0))
        return (r1, r2, offset)
    }

    public func _executeImpl(state _: VMState) throws -> ExecOutcome { .continued }

    public func updatePC(state: VMState, skip: UInt32) -> ExecOutcome {
        guard Instructions.isBranchValid(state: state, offset: offset) else {
            return .exit(.panic(.invalidBranch))
        }
        if condition(state: state) {
            state.increasePC(offset)
        } else {
            state.increasePC(skip + 1)
        }
        return .continued
    }

    public func condition(state: VMState) -> Bool {
        let r1Val = state.readRegister(r1)
        let r2Val = state.readRegister(r2)
        return Compare.compare(a: r1Val, b: r2Val)
    }
}

public struct CompareEq: BranchCompare {
    public static func compare(a: UInt32, b: UInt32) -> Bool {
        Int32(bitPattern: a) == Int32(bitPattern: b)
    }
}

public struct CompareNe: BranchCompare {
    public static func compare(a: UInt32, b: UInt32) -> Bool {
        Int32(bitPattern: a) != Int32(bitPattern: b)
    }
}

public struct CompareLt: BranchCompare {
    public static func compare(a: UInt32, b: UInt32) -> Bool {
        a < b
    }
}

public struct CompareLe: BranchCompare {
    public static func compare(a: UInt32, b: UInt32) -> Bool {
        a <= b
    }
}

public struct CompareGe: BranchCompare {
    public static func compare(a: UInt32, b: UInt32) -> Bool {
        a >= b
    }
}

public struct CompareGt: BranchCompare {
    public static func compare(a: UInt32, b: UInt32) -> Bool {
        a > b
    }
}
