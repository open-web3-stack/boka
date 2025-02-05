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
    // MARK: Instructions without Arguments (5.1)

    public struct Trap: Instruction {
        public static var opcode: UInt8 { 0 }

        public init(data _: Data = .init()) {}
        public func _executeImpl(context _: ExecutionContext) -> ExecOutcome {
            .exit(.panic(.trap))
        }
    }

    public struct Fallthrough: Instruction {
        public static var opcode: UInt8 { 1 }

        public init(data _: Data) {}

        public func _executeImpl(context _: ExecutionContext) -> ExecOutcome { .continued }
    }

    // MARK: Instructions with Arguments of One Immediate (5.2)

    public struct Ecalli: Instruction {
        public static var opcode: UInt8 { 10 }

        public let callIndex: UInt32

        public init(data: Data) {
            callIndex = Instructions.decodeImmediate(data)
        }

        public func _executeImpl(context _: ExecutionContext) -> ExecOutcome {
            .exit(.hostCall(callIndex))
        }
    }

    // MARK: Instructions with Arguments of One Register and One Extended Width Immediate (5.3)

    public struct LoadImm64: Instruction {
        public static var opcode: UInt8 { 20 }

        public let register: Registers.Index
        public let value: UInt64

        public init(data: Data) throws {
            register = try Registers.Index(r1: data.at(relative: 0))
            value = try data.at(relative: 1 ..< 9).decode(UInt64.self)
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            context.state.writeRegister(register, value)
            return .continued
        }
    }

    // MARK: Instructions with Arguments of Two Immediates (5.4)

    public struct StoreImmU8: Instruction {
        public static var opcode: UInt8 { 30 }

        public let address: UInt32
        public let value: UInt8

        public init(data: Data) throws {
            (address, value) = try Instructions.decodeImmediate2(data)
        }

        public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
            try context.state.writeMemory(address: address, value: value)
            return .continued
        }
    }

    public struct StoreImmU16: Instruction {
        public static var opcode: UInt8 { 31 }

        public let address: UInt32
        public let value: UInt16

        public init(data: Data) throws {
            (address, value) = try Instructions.decodeImmediate2(data)
        }

        public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
            try context.state.writeMemory(address: address, values: value.encode(method: .fixedWidth(2)))
            return .continued
        }
    }

    public struct StoreImmU32: Instruction {
        public static var opcode: UInt8 { 32 }

        public let address: UInt32
        public let value: UInt32

        public init(data: Data) throws {
            (address, value) = try Instructions.decodeImmediate2(data)
        }

        public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
            try context.state.writeMemory(address: address, values: value.encode(method: .fixedWidth(4)))
            return .continued
        }
    }

    public struct StoreImmU64: Instruction {
        public static var opcode: UInt8 { 33 }

        public let address: UInt32
        public let value: UInt32

        public init(data: Data) throws {
            (address, value) = try Instructions.decodeImmediate2(data)
        }

        public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
            try context.state.writeMemory(address: address, values: value.encode(method: .fixedWidth(8)))
            return .continued
        }
    }

    // MARK: Instructions with Arguments of One Offset (5.5)

    public struct Jump: Instruction {
        public static var opcode: UInt8 { 40 }

        public let offset: UInt32

        public init(data: Data) {
            // this should be a signed value
            // but because we use wrapped addition, it will work as expected
            offset = Instructions.decodeImmediate(data)
        }

        public func _executeImpl(context _: ExecutionContext) -> ExecOutcome { .continued }

        public func updatePC(context: ExecutionContext, skip _: UInt32) -> ExecOutcome {
            guard Instructions.isBranchValid(context: context, offset: offset) else {
                return .exit(.panic(.invalidBranch))
            }
            context.state.increasePC(offset)
            return .continued
        }
    }

    // MARK: Instructions with Arguments of One Register & One Immediate (5.6)

    public struct JumpInd: Instruction {
        public static var opcode: UInt8 { 50 }

        public let register: Registers.Index
        public let offset: UInt32

        public init(data: Data) throws {
            register = try Registers.Index(r1: data.at(relative: 0))
            offset = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        }

        public func _executeImpl(context _: ExecutionContext) -> ExecOutcome { .continued }

        public func updatePC(context: ExecutionContext, skip _: UInt32) -> ExecOutcome {
            let regVal: UInt32 = context.state.readRegister(register)
            return Instructions.djump(context: context, target: regVal &+ offset)
        }
    }

    public struct LoadImm: Instruction {
        public static var opcode: UInt8 { 51 }

        public let register: Registers.Index
        public let value: UInt32

        public init(data: Data) throws {
            register = try Registers.Index(r1: data.at(relative: 0))
            value = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            context.state.writeRegister(register, Int32(bitPattern: value))
            return .continued
        }
    }

    public struct LoadU8: Instruction {
        public static var opcode: UInt8 { 52 }

        public let register: Registers.Index
        public let address: UInt32

        public init(data: Data) throws {
            register = try Registers.Index(r1: data.at(relative: 0))
            address = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        }

        public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
            let value = try context.state.readMemory(address: address)
            context.state.writeRegister(register, value)
            return .continued
        }
    }

    public struct LoadI8: Instruction {
        public static var opcode: UInt8 { 53 }

        public let register: Registers.Index
        public let address: UInt32

        public init(data: Data) throws {
            register = try Registers.Index(r1: data.at(relative: 0))
            address = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        }

        public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
            let value = try context.state.readMemory(address: address)
            context.state.writeRegister(register, Int8(bitPattern: value))
            return .continued
        }
    }

    public struct LoadU16: Instruction {
        public static var opcode: UInt8 { 54 }

        public let register: Registers.Index
        public let address: UInt32

        public init(data: Data) throws {
            register = try Registers.Index(r1: data.at(relative: 0))
            address = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        }

        public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
            let data = try context.state.readMemory(address: address, length: 2)
            let value = data.decode(UInt16.self)
            context.state.writeRegister(register, value)
            return .continued
        }
    }

    public struct LoadI16: Instruction {
        public static var opcode: UInt8 { 55 }

        public let register: Registers.Index
        public let address: UInt32

        public init(data: Data) throws {
            register = try Registers.Index(r1: data.at(relative: 0))
            address = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        }

        public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
            let data = try context.state.readMemory(address: address, length: 2)
            let value = data.decode(UInt16.self)
            context.state.writeRegister(register, Int16(bitPattern: value))
            return .continued
        }
    }

    public struct LoadU32: Instruction {
        public static var opcode: UInt8 { 56 }

        public let register: Registers.Index
        public let address: UInt32

        public init(data: Data) throws {
            register = try Registers.Index(r1: data.at(relative: 0))
            address = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        }

        public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
            let data = try context.state.readMemory(address: address, length: 4)
            let value = data.decode(UInt32.self)
            context.state.writeRegister(register, value)
            return .continued
        }
    }

    public struct LoadI32: Instruction {
        public static var opcode: UInt8 { 57 }

        public let register: Registers.Index
        public let address: UInt32

        public init(data: Data) throws {
            register = try Registers.Index(r1: data.at(relative: 0))
            address = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        }

        public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
            let data = try context.state.readMemory(address: address, length: 4)
            let value = data.decode(UInt32.self)
            context.state.writeRegister(register, Int32(bitPattern: value))
            return .continued
        }
    }

    public struct LoadU64: Instruction {
        public static var opcode: UInt8 { 58 }

        public let register: Registers.Index
        public let address: UInt32

        public init(data: Data) throws {
            register = try Registers.Index(r1: data.at(relative: 0))
            address = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        }

        public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
            let data = try context.state.readMemory(address: address, length: 8)
            let value = data.decode(UInt64.self)
            context.state.writeRegister(register, value)
            return .continued
        }
    }

    public struct StoreU8: Instruction {
        public static var opcode: UInt8 { 59 }

        public let register: Registers.Index
        public let address: UInt32

        public init(data: Data) throws {
            register = try Registers.Index(r1: data.at(relative: 0))
            address = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        }

        public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
            let value: UInt8 = context.state.readRegister(register)
            try context.state.writeMemory(address: address, value: value)
            return .continued
        }
    }

    public struct StoreU16: Instruction {
        public static var opcode: UInt8 { 60 }

        public let register: Registers.Index
        public let address: UInt32

        public init(data: Data) throws {
            register = try Registers.Index(r1: data.at(relative: 0))
            address = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        }

        public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
            let value: UInt16 = context.state.readRegister(register)
            try context.state.writeMemory(address: address, values: value.encode(method: .fixedWidth(2)))
            return .continued
        }
    }

    public struct StoreU32: Instruction {
        public static var opcode: UInt8 { 61 }

        public let register: Registers.Index
        public let address: UInt32

        public init(data: Data) throws {
            register = try Registers.Index(r1: data.at(relative: 0))
            address = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        }

        public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
            let value: UInt32 = context.state.readRegister(register)
            try context.state.writeMemory(address: address, values: value.encode(method: .fixedWidth(4)))
            return .continued
        }
    }

    public struct StoreU64: Instruction {
        public static var opcode: UInt8 { 62 }

        public let register: Registers.Index
        public let address: UInt32

        public init(data: Data) throws {
            register = try Registers.Index(r1: data.at(relative: 0))
            address = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        }

        public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
            let value: UInt64 = context.state.readRegister(register)
            try context.state.writeMemory(address: address, values: value.encode(method: .fixedWidth(8)))
            return .continued
        }
    }

    // MARK: Instructions with Arguments of One Register & Two Immediates (5.7)

    public struct StoreImmIndU8: Instruction {
        public static var opcode: UInt8 { 70 }

        public let register: Registers.Index
        public let address: UInt32
        public let value: UInt8

        public init(data: Data) throws {
            register = try Registers.Index(r1: data.at(relative: 0))
            (address, value) = try Instructions.decodeImmediate2(data, divideBy: 16)
        }

        public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
            try context.state.writeMemory(address: context.state.readRegister(register) &+ address, value: value)
            return .continued
        }
    }

    public struct StoreImmIndU16: Instruction {
        public static var opcode: UInt8 { 71 }

        public let register: Registers.Index
        public let address: UInt32
        public let value: UInt16

        public init(data: Data) throws {
            register = try Registers.Index(r1: data.at(relative: 0))
            (address, value) = try Instructions.decodeImmediate2(data, divideBy: 16)
        }

        public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
            try context.state.writeMemory(
                address: context.state.readRegister(register) &+ address,
                values: value.encode(method: .fixedWidth(2))
            )
            return .continued
        }
    }

    public struct StoreImmIndU32: Instruction {
        public static var opcode: UInt8 { 72 }

        public let register: Registers.Index
        public let address: UInt32
        public let value: UInt32

        public init(data: Data) throws {
            register = try Registers.Index(r1: data.at(relative: 0))
            (address, value) = try Instructions.decodeImmediate2(data, divideBy: 16)
        }

        public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
            try context.state.writeMemory(
                address: context.state.readRegister(register) &+ address,
                values: value.encode(method: .fixedWidth(4))
            )
            return .continued
        }
    }

    public struct StoreImmIndU64: Instruction {
        public static var opcode: UInt8 { 73 }

        public let register: Registers.Index
        public let address: UInt32
        public let value: UInt32

        public init(data: Data) throws {
            register = try Registers.Index(r1: data.at(relative: 0))
            (address, value) = try Instructions.decodeImmediate2(data, divideBy: 16)
        }

        public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
            try context.state.writeMemory(
                address: context.state.readRegister(register) &+ address,
                values: value.encode(method: .fixedWidth(8))
            )
            return .continued
        }
    }

    // MARK: Instructions with Arguments of One Register, One Immediate and One Offset (5.8)

    public struct LoadImmJump: Instruction {
        public static var opcode: UInt8 { 80 }

        public let register: Registers.Index
        public let value: UInt32
        public let offset: UInt32

        public init(data: Data) throws {
            register = try Registers.Index(r1: data.at(relative: 0))
            (value, offset) = try Instructions.decodeImmediate2(data, divideBy: 16)
        }

        public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
            context.state.writeRegister(register, value)
            return .continued
        }

        public func updatePC(context: ExecutionContext, skip _: UInt32) -> ExecOutcome {
            guard Instructions.isBranchValid(context: context, offset: offset) else {
                return .exit(.panic(.invalidBranch))
            }
            context.state.increasePC(offset)
            return .continued
        }
    }

    public struct BranchEqImm: BranchInstructionBase {
        public static var opcode: UInt8 { 81 }
        typealias Compare = CompareEq

        var register: Registers.Index
        var value: UInt64
        var offset: UInt32
        public init(data: Data) throws { (register, value, offset) = try Self.parse(data: data) }
    }

    public struct BranchNeImm: BranchInstructionBase {
        public static var opcode: UInt8 { 82 }
        typealias Compare = CompareNe

        var register: Registers.Index
        var value: UInt64
        var offset: UInt32
        public init(data: Data) throws { (register, value, offset) = try Self.parse(data: data) }
    }

    public struct BranchLtUImm: BranchInstructionBase {
        public static var opcode: UInt8 { 83 }
        typealias Compare = CompareLtU

        var register: Registers.Index
        var value: UInt64
        var offset: UInt32
        public init(data: Data) throws { (register, value, offset) = try Self.parse(data: data) }
    }

    public struct BranchLeUImm: BranchInstructionBase {
        public static var opcode: UInt8 { 84 }
        typealias Compare = CompareLeU

        var register: Registers.Index
        var value: UInt64
        var offset: UInt32
        public init(data: Data) throws { (register, value, offset) = try Self.parse(data: data) }
    }

    public struct BranchGeUImm: BranchInstructionBase {
        public static var opcode: UInt8 { 85 }
        typealias Compare = CompareGeU

        var register: Registers.Index
        var value: UInt64
        var offset: UInt32
        public init(data: Data) throws { (register, value, offset) = try Self.parse(data: data) }
    }

    public struct BranchGtUImm: BranchInstructionBase {
        public static var opcode: UInt8 { 86 }
        typealias Compare = CompareGtU

        var register: Registers.Index
        var value: UInt64
        var offset: UInt32
        public init(data: Data) throws { (register, value, offset) = try Self.parse(data: data) }
    }

    public struct BranchLtSImm: BranchInstructionBase {
        public static var opcode: UInt8 { 87 }
        typealias Compare = CompareLtS

        var register: Registers.Index
        var value: UInt64
        var offset: UInt32
        public init(data: Data) throws { (register, value, offset) = try Self.parse(data: data) }
    }

    public struct BranchLeSImm: BranchInstructionBase {
        public static var opcode: UInt8 { 88 }
        typealias Compare = CompareLeS

        var register: Registers.Index
        var value: UInt64
        var offset: UInt32
        public init(data: Data) throws { (register, value, offset) = try Self.parse(data: data) }
    }

    public struct BranchGeSImm: BranchInstructionBase {
        public static var opcode: UInt8 { 89 }
        typealias Compare = CompareGeS

        var register: Registers.Index
        var value: UInt64
        var offset: UInt32
        public init(data: Data) throws { (register, value, offset) = try Self.parse(data: data) }
    }

    public struct BranchGtSImm: BranchInstructionBase {
        public static var opcode: UInt8 { 90 }
        typealias Compare = CompareGtS

        var register: Registers.Index
        var value: UInt64
        var offset: UInt32
        public init(data: Data) throws { (register, value, offset) = try Self.parse(data: data) }
    }

    // MARK: Instructions with Arguments of Two Registers (5.9)

    public struct MoveReg: Instruction {
        public static var opcode: UInt8 { 100 }

        public let src: Registers.Index
        public let dest: Registers.Index

        public init(data: Data) throws {
            (dest, src) = try Instructions.deocdeRegisters(data)
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            context.state.writeRegister(dest, context.state.readRegister(src) as UInt64)
            return .continued
        }
    }

    public struct Sbrk: Instruction {
        public static var opcode: UInt8 { 101 }

        public let src: Registers.Index
        public let dest: Registers.Index

        public init(data: Data) throws {
            (dest, src) = try Instructions.deocdeRegisters(data)
        }

        public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
            let increment: UInt32 = context.state.readRegister(src)
            let startAddr = try context.state.sbrk(increment)
            context.state.writeRegister(dest, startAddr)

            return .continued
        }
    }

    public struct CountSetBits64: Instruction {
        public static var opcode: UInt8 { 102 }

        public let ra: Registers.Index
        public let dest: Registers.Index

        public init(data: Data) throws {
            (ra, dest) = try Instructions.deocdeRegisters(data)
        }

        public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
            let regVal: UInt64 = context.state.readRegister(ra)
            context.state.writeRegister(dest, regVal.nonzeroBitCount)
            return .continued
        }
    }

    public struct CountSetBits32: Instruction {
        public static var opcode: UInt8 { 103 }

        public let ra: Registers.Index
        public let dest: Registers.Index

        public init(data: Data) throws {
            (ra, dest) = try Instructions.deocdeRegisters(data)
        }

        public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
            let regVal: UInt32 = context.state.readRegister(ra)
            context.state.writeRegister(dest, regVal.nonzeroBitCount)
            return .continued
        }
    }

    public struct LeadingZeroBits64: Instruction {
        public static var opcode: UInt8 { 104 }

        public let ra: Registers.Index
        public let dest: Registers.Index

        public init(data: Data) throws {
            (ra, dest) = try Instructions.deocdeRegisters(data)
        }

        public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
            let regVal: UInt64 = context.state.readRegister(ra)
            context.state.writeRegister(dest, regVal.leadingZeroBitCount)
            return .continued
        }
    }

    public struct LeadingZeroBits32: Instruction {
        public static var opcode: UInt8 { 105 }

        public let ra: Registers.Index
        public let dest: Registers.Index

        public init(data: Data) throws {
            (ra, dest) = try Instructions.deocdeRegisters(data)
        }

        public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
            let regVal: UInt32 = context.state.readRegister(ra)
            context.state.writeRegister(dest, regVal.leadingZeroBitCount)
            return .continued
        }
    }

    public struct TrailingZeroBits64: Instruction {
        public static var opcode: UInt8 { 106 }

        public let ra: Registers.Index
        public let dest: Registers.Index

        public init(data: Data) throws {
            (ra, dest) = try Instructions.deocdeRegisters(data)
        }

        public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
            let regVal: UInt64 = context.state.readRegister(ra)
            context.state.writeRegister(dest, regVal.trailingZeroBitCount)
            return .continued
        }
    }

    public struct TrailingZeroBits32: Instruction {
        public static var opcode: UInt8 { 107 }

        public let ra: Registers.Index
        public let dest: Registers.Index

        public init(data: Data) throws {
            (ra, dest) = try Instructions.deocdeRegisters(data)
        }

        public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
            let regVal: UInt32 = context.state.readRegister(ra)
            context.state.writeRegister(dest, regVal.trailingZeroBitCount)
            return .continued
        }
    }

    public struct SignExtend8: Instruction {
        public static var opcode: UInt8 { 108 }

        public let ra: Registers.Index
        public let dest: Registers.Index

        public init(data: Data) throws {
            (ra, dest) = try Instructions.deocdeRegisters(data)
        }

        public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
            let regVal: UInt8 = context.state.readRegister(ra)
            context.state.writeRegister(dest, Int8(bitPattern: regVal))
            return .continued
        }
    }

    public struct SignExtend16: Instruction {
        public static var opcode: UInt8 { 109 }

        public let ra: Registers.Index
        public let dest: Registers.Index

        public init(data: Data) throws {
            (ra, dest) = try Instructions.deocdeRegisters(data)
        }

        public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
            let regVal: UInt16 = context.state.readRegister(ra)
            context.state.writeRegister(dest, Int16(bitPattern: regVal))
            return .continued
        }
    }

    public struct ZeroExtend16: Instruction {
        public static var opcode: UInt8 { 110 }

        public let ra: Registers.Index
        public let dest: Registers.Index

        public init(data: Data) throws {
            (ra, dest) = try Instructions.deocdeRegisters(data)
        }

        public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
            let regVal: UInt16 = context.state.readRegister(ra)
            context.state.writeRegister(dest, regVal)
            return .continued
        }
    }

    public struct ReverseBytes: Instruction {
        public static var opcode: UInt8 { 111 }

        public let ra: Registers.Index
        public let dest: Registers.Index

        public init(data: Data) throws {
            (ra, dest) = try Instructions.deocdeRegisters(data)
        }

        public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
            let regVal: UInt64 = context.state.readRegister(ra)
            context.state.writeRegister(dest, regVal.byteSwapped)
            return .continued
        }
    }

    // MARK: Instructions with Arguments of Two Registers & One Immediate (5.10)

    public struct StoreIndU8: Instruction {
        public static var opcode: UInt8 { 120 }

        public let src: Registers.Index
        public let dest: Registers.Index
        public let offset: UInt32

        public init(data: Data) throws {
            (src, dest) = try Instructions.deocdeRegisters(data)
            offset = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        }

        public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
            let value: UInt8 = context.state.readRegister(src)
            try context.state.writeMemory(address: context.state.readRegister(dest) &+ offset, value: value)
            return .continued
        }
    }

    public struct StoreIndU16: Instruction {
        public static var opcode: UInt8 { 121 }

        public let src: Registers.Index
        public let dest: Registers.Index
        public let offset: UInt32

        public init(data: Data) throws {
            (src, dest) = try Instructions.deocdeRegisters(data)
            offset = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        }

        public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
            let value: UInt16 = context.state.readRegister(src)
            try context.state.writeMemory(address: context.state.readRegister(dest) &+ offset, values: value.encode(method: .fixedWidth(2)))
            return .continued
        }
    }

    public struct StoreIndU32: Instruction {
        public static var opcode: UInt8 { 122 }

        public let src: Registers.Index
        public let dest: Registers.Index
        public let offset: UInt32

        public init(data: Data) throws {
            (src, dest) = try Instructions.deocdeRegisters(data)
            offset = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        }

        public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
            let value: UInt32 = context.state.readRegister(src)
            try context.state.writeMemory(address: context.state.readRegister(dest) &+ offset, values: value.encode(method: .fixedWidth(4)))
            return .continued
        }
    }

    public struct StoreIndU64: Instruction {
        public static var opcode: UInt8 { 123 }

        public let src: Registers.Index
        public let dest: Registers.Index
        public let offset: UInt32

        public init(data: Data) throws {
            (src, dest) = try Instructions.deocdeRegisters(data)
            offset = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        }

        public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
            let value: UInt64 = context.state.readRegister(src)
            try context.state.writeMemory(address: context.state.readRegister(dest) &+ offset, values: value.encode(method: .fixedWidth(8)))
            return .continued
        }
    }

    public struct LoadIndU8: Instruction {
        public static var opcode: UInt8 { 124 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let offset: UInt32

        public init(data: Data) throws {
            (ra, rb) = try Instructions.deocdeRegisters(data)
            offset = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        }

        public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
            let value = try context.state.readMemory(address: context.state.readRegister(rb) + offset)
            context.state.writeRegister(ra, value)
            return .continued
        }
    }

    public struct LoadIndI8: Instruction {
        public static var opcode: UInt8 { 125 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let offset: UInt32

        public init(data: Data) throws {
            (ra, rb) = try Instructions.deocdeRegisters(data)
            offset = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        }

        public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
            let value = try context.state.readMemory(address: context.state.readRegister(rb) + offset)
            context.state.writeRegister(ra, Int8(bitPattern: value))
            return .continued
        }
    }

    public struct LoadIndU16: Instruction {
        public static var opcode: UInt8 { 126 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let offset: UInt32

        public init(data: Data) throws {
            (ra, rb) = try Instructions.deocdeRegisters(data)
            offset = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        }

        public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
            let data = try context.state.readMemory(address: context.state.readRegister(rb) &+ offset, length: 2)
            let value = data.decode(UInt16.self)
            context.state.writeRegister(ra, value)
            return .continued
        }
    }

    public struct LoadIndI16: Instruction {
        public static var opcode: UInt8 { 127 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let offset: UInt32

        public init(data: Data) throws {
            (ra, rb) = try Instructions.deocdeRegisters(data)
            offset = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        }

        public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
            let data = try context.state.readMemory(address: context.state.readRegister(rb) &+ offset, length: 2)
            let value = data.decode(UInt16.self)
            context.state.writeRegister(ra, Int16(bitPattern: value))
            return .continued
        }
    }

    public struct LoadIndU32: Instruction {
        public static var opcode: UInt8 { 128 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let offset: UInt32

        public init(data: Data) throws {
            (ra, rb) = try Instructions.deocdeRegisters(data)
            offset = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        }

        public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
            let data = try context.state.readMemory(address: context.state.readRegister(rb) &+ offset, length: 4)
            let value = data.decode(UInt32.self)
            context.state.writeRegister(ra, value)
            return .continued
        }
    }

    public struct LoadIndI32: Instruction {
        public static var opcode: UInt8 { 129 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let offset: UInt32

        public init(data: Data) throws {
            (ra, rb) = try Instructions.deocdeRegisters(data)
            offset = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        }

        public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
            let data = try context.state.readMemory(address: context.state.readRegister(rb) &+ offset, length: 4)
            let value = data.decode(UInt32.self)
            context.state.writeRegister(ra, Int32(bitPattern: value))
            return .continued
        }
    }

    public struct LoadIndU64: Instruction {
        public static var opcode: UInt8 { 130 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let offset: UInt32

        public init(data: Data) throws {
            (ra, rb) = try Instructions.deocdeRegisters(data)
            offset = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        }

        public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
            let data = try context.state.readMemory(address: context.state.readRegister(rb) &+ offset, length: 8)
            let value = data.decode(UInt64.self)
            context.state.writeRegister(ra, value)
            return .continued
        }
    }

    public struct AddImm32: Instruction {
        public static var opcode: UInt8 { 131 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let value: UInt32

        public init(data: Data) throws {
            (ra, rb) = try Instructions.deocdeRegisters(data)
            value = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let regVal: UInt32 = context.state.readRegister(rb)
            context.state.writeRegister(ra, Int32(bitPattern: regVal &+ value))
            return .continued
        }
    }

    public struct AndImm: Instruction {
        public static var opcode: UInt8 { 132 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let value: UInt64

        public init(data: Data) throws {
            (ra, rb) = try Instructions.deocdeRegisters(data)
            value = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let regVal: UInt64 = context.state.readRegister(rb)
            context.state.writeRegister(ra, regVal & value)
            return .continued
        }
    }

    public struct XorImm: Instruction {
        public static var opcode: UInt8 { 133 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let value: UInt64

        public init(data: Data) throws {
            (ra, rb) = try Instructions.deocdeRegisters(data)
            value = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let regVal: UInt64 = context.state.readRegister(rb)
            context.state.writeRegister(ra, regVal ^ value)
            return .continued
        }
    }

    public struct OrImm: Instruction {
        public static var opcode: UInt8 { 134 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let value: UInt64

        public init(data: Data) throws {
            (ra, rb) = try Instructions.deocdeRegisters(data)
            value = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let regVal: UInt64 = context.state.readRegister(rb)
            context.state.writeRegister(ra, regVal | value)
            return .continued
        }
    }

    public struct MulImm32: Instruction {
        public static var opcode: UInt8 { 135 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let value: UInt32

        public init(data: Data) throws {
            (ra, rb) = try Instructions.deocdeRegisters(data)
            value = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let regVal: UInt32 = context.state.readRegister(rb)
            context.state.writeRegister(ra, Int32(bitPattern: regVal &* value))
            return .continued
        }
    }

    public struct SetLtUImm: Instruction {
        public static var opcode: UInt8 { 136 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let value: UInt64

        public init(data: Data) throws {
            (ra, rb) = try Instructions.deocdeRegisters(data)
            value = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let regVal: UInt64 = context.state.readRegister(rb)
            context.state.writeRegister(ra, regVal < value ? 1 : 0)
            return .continued
        }
    }

    public struct SetLtSImm: Instruction {
        public static var opcode: UInt8 { 137 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let value: UInt64

        public init(data: Data) throws {
            (ra, rb) = try Instructions.deocdeRegisters(data)
            value = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let regVal: UInt64 = context.state.readRegister(rb)
            context.state.writeRegister(ra, Int64(bitPattern: regVal) < Int64(bitPattern: value) ? 1 : 0)
            return .continued
        }
    }

    public struct ShloLImm32: Instruction {
        public static var opcode: UInt8 { 138 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let value: UInt32

        public init(data: Data) throws {
            (ra, rb) = try Instructions.deocdeRegisters(data)
            value = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let regVal: UInt32 = context.state.readRegister(rb)
            let shift = value & 0x1F
            context.state.writeRegister(ra, Int32(bitPattern: regVal << shift))
            return .continued
        }
    }

    public struct ShloRImm32: Instruction {
        public static var opcode: UInt8 { 139 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let value: UInt32

        public init(data: Data) throws {
            (ra, rb) = try Instructions.deocdeRegisters(data)
            value = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let regVal: UInt32 = context.state.readRegister(rb)
            let shift = value & 0x1F
            context.state.writeRegister(ra, Int32(bitPattern: regVal >> shift))
            return .continued
        }
    }

    public struct SharRImm32: Instruction {
        public static var opcode: UInt8 { 140 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let value: UInt32

        public init(data: Data) throws {
            (ra, rb) = try Instructions.deocdeRegisters(data)
            value = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let regVal: UInt32 = context.state.readRegister(rb)
            let shift = value & 0x1F
            context.state.writeRegister(ra, Int32(bitPattern: regVal) >> shift)
            return .continued
        }
    }

    public struct NegAddImm32: Instruction {
        public static var opcode: UInt8 { 141 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let value: UInt32

        public init(data: Data) throws {
            (ra, rb) = try Instructions.deocdeRegisters(data)
            value = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let regVal: UInt32 = context.state.readRegister(rb)
            context.state.writeRegister(ra, Int32(bitPattern: value &- regVal))
            return .continued
        }
    }

    public struct SetGtUImm: Instruction {
        public static var opcode: UInt8 { 142 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let value: UInt64

        public init(data: Data) throws {
            (ra, rb) = try Instructions.deocdeRegisters(data)
            value = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let regVal: UInt64 = context.state.readRegister(rb)
            context.state.writeRegister(ra, regVal > value ? 1 : 0)
            return .continued
        }
    }

    public struct SetGtSImm: Instruction {
        public static var opcode: UInt8 { 143 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let value: UInt64

        public init(data: Data) throws {
            (ra, rb) = try Instructions.deocdeRegisters(data)
            value = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let regVal: UInt64 = context.state.readRegister(rb)
            context.state.writeRegister(ra, Int64(bitPattern: regVal) > Int64(bitPattern: value) ? 1 : 0)
            return .continued
        }
    }

    public struct ShloLImmAlt32: Instruction {
        public static var opcode: UInt8 { 144 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let value: UInt32

        public init(data: Data) throws {
            (ra, rb) = try Instructions.deocdeRegisters(data)
            value = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let regVal: UInt32 = context.state.readRegister(rb)
            let shift = regVal & 0x1F
            context.state.writeRegister(ra, Int32(bitPattern: value << shift))
            return .continued
        }
    }

    public struct ShloRImmAlt32: Instruction {
        public static var opcode: UInt8 { 145 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let value: UInt32

        public init(data: Data) throws {
            (ra, rb) = try Instructions.deocdeRegisters(data)
            value = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let regVal: UInt32 = context.state.readRegister(rb)
            let shift = regVal & 0x1F
            context.state.writeRegister(ra, Int32(bitPattern: value >> shift))
            return .continued
        }
    }

    public struct SharRImmAlt32: Instruction {
        public static var opcode: UInt8 { 146 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let value: UInt32

        public init(data: Data) throws {
            (ra, rb) = try Instructions.deocdeRegisters(data)
            value = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let regVal: UInt32 = context.state.readRegister(rb)
            let shift = regVal & 0x1F
            context.state.writeRegister(ra, Int32(bitPattern: value) >> shift)
            return .continued
        }
    }

    public struct CmovIzImm: Instruction {
        public static var opcode: UInt8 { 147 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let value: UInt64

        public init(data: Data) throws {
            (ra, rb) = try Instructions.deocdeRegisters(data)
            value = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let rbVal: UInt64 = context.state.readRegister(rb)
            if rbVal == 0 {
                context.state.writeRegister(ra, value)
            }
            return .continued
        }
    }

    public struct CmovNzImm: Instruction {
        public static var opcode: UInt8 { 148 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let value: UInt64

        public init(data: Data) throws {
            (ra, rb) = try Instructions.deocdeRegisters(data)
            value = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let regVal: UInt64 = context.state.readRegister(rb)
            context.state.writeRegister(ra, regVal != 0 ? value : regVal)
            return .continued
        }
    }

    public struct AddImm64: Instruction {
        public static var opcode: UInt8 { 149 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let value: UInt64

        public init(data: Data) throws {
            (ra, rb) = try Instructions.deocdeRegisters(data)
            value = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let regVal: UInt64 = context.state.readRegister(rb)
            context.state.writeRegister(ra, regVal &+ value)
            return .continued
        }
    }

    public struct MulImm64: Instruction {
        public static var opcode: UInt8 { 150 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let value: UInt64

        public init(data: Data) throws {
            (ra, rb) = try Instructions.deocdeRegisters(data)
            value = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let regVal: UInt64 = context.state.readRegister(rb)
            context.state.writeRegister(ra, regVal &* value)
            return .continued
        }
    }

    public struct ShloLImm64: Instruction {
        public static var opcode: UInt8 { 151 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let value: UInt64

        public init(data: Data) throws {
            (ra, rb) = try Instructions.deocdeRegisters(data)
            value = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let regVal: UInt64 = context.state.readRegister(rb)
            let shift = value & 0x1F
            context.state.writeRegister(ra, Int64(bitPattern: regVal << shift))
            return .continued
        }
    }

    public struct ShloRImm64: Instruction {
        public static var opcode: UInt8 { 152 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let value: UInt64

        public init(data: Data) throws {
            (ra, rb) = try Instructions.deocdeRegisters(data)
            value = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let regVal: UInt64 = context.state.readRegister(rb)
            let shift = value & 0x1F
            context.state.writeRegister(ra, Int64(bitPattern: regVal >> shift))
            return .continued
        }
    }

    public struct SharRImm64: Instruction {
        public static var opcode: UInt8 { 153 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let value: UInt64

        public init(data: Data) throws {
            (ra, rb) = try Instructions.deocdeRegisters(data)
            value = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let regVal: UInt64 = context.state.readRegister(rb)
            let shift = value & 0x1F
            context.state.writeRegister(ra, Int64(bitPattern: regVal) >> shift)
            return .continued
        }
    }

    public struct NegAddImm64: Instruction {
        public static var opcode: UInt8 { 154 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let value: UInt64

        public init(data: Data) throws {
            (ra, rb) = try Instructions.deocdeRegisters(data)
            value = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let regVal: UInt64 = context.state.readRegister(rb)
            context.state.writeRegister(ra, value &- regVal)
            return .continued
        }
    }

    public struct ShloLImmAlt64: Instruction {
        public static var opcode: UInt8 { 155 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let value: UInt64

        public init(data: Data) throws {
            (ra, rb) = try Instructions.deocdeRegisters(data)
            value = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let regVal: UInt64 = context.state.readRegister(rb)
            let shift = regVal & 0x1F
            context.state.writeRegister(ra, UInt64(truncatingIfNeeded: value << shift))
            return .continued
        }
    }

    public struct ShloRImmAlt64: Instruction {
        public static var opcode: UInt8 { 156 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let value: UInt64

        public init(data: Data) throws {
            (ra, rb) = try Instructions.deocdeRegisters(data)
            value = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let regVal: UInt64 = context.state.readRegister(rb)
            let shift = regVal & 0x1F
            context.state.writeRegister(ra, value >> shift)
            return .continued
        }
    }

    public struct SharRImmAlt64: Instruction {
        public static var opcode: UInt8 { 157 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let value: UInt64

        public init(data: Data) throws {
            (ra, rb) = try Instructions.deocdeRegisters(data)
            value = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let regVal: UInt64 = context.state.readRegister(rb)
            let shift = regVal & 0x1F
            context.state.writeRegister(ra, Int64(bitPattern: value) >> shift)
            return .continued
        }
    }

    public struct RotR64Imm: Instruction {
        public static var opcode: UInt8 { 158 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let value: UInt64

        public init(data: Data) throws {
            (ra, rb) = try Instructions.deocdeRegisters(data)
            value = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let rbVal: UInt64 = context.state.readRegister(rb)
            context.state.writeRegister(ra, rbVal.rotated(right: value))
            return .continued
        }
    }

    public struct RotR64ImmAlt: Instruction {
        public static var opcode: UInt8 { 159 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let value: UInt64

        public init(data: Data) throws {
            (ra, rb) = try Instructions.deocdeRegisters(data)
            value = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let rbVal: UInt64 = context.state.readRegister(rb)
            context.state.writeRegister(ra, value.rotated(right: rbVal))
            return .continued
        }
    }

    public struct RotR32Imm: Instruction {
        public static var opcode: UInt8 { 160 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let value: UInt32

        public init(data: Data) throws {
            (ra, rb) = try Instructions.deocdeRegisters(data)
            value = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let rbVal: UInt32 = context.state.readRegister(rb)
            context.state.writeRegister(ra, Int32(bitPattern: rbVal.rotated(right: value)))
            return .continued
        }
    }

    public struct RotR32ImmAlt: Instruction {
        public static var opcode: UInt8 { 161 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let value: UInt32

        public init(data: Data) throws {
            (ra, rb) = try Instructions.deocdeRegisters(data)
            value = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let rbVal: UInt32 = context.state.readRegister(rb)
            context.state.writeRegister(ra, Int32(bitPattern: value.rotated(right: rbVal)))
            return .continued
        }
    }

    // MARK: Instructions with Arguments of Two Registers & One Offset (5.11)

    public struct BranchEq: BranchInstructionBase2 {
        public static var opcode: UInt8 { 170 }
        typealias Compare = CompareEq

        var r1: Registers.Index
        var r2: Registers.Index
        var offset: UInt32
        public init(data: Data) throws { (r1, r2, offset) = try Self.parse(data: data) }
    }

    public struct BranchNe: BranchInstructionBase2 {
        public static var opcode: UInt8 { 171 }
        typealias Compare = CompareNe

        var r1: Registers.Index
        var r2: Registers.Index
        var offset: UInt32
        public init(data: Data) throws { (r1, r2, offset) = try Self.parse(data: data) }
    }

    public struct BranchLtU: BranchInstructionBase2 {
        public static var opcode: UInt8 { 172 }
        typealias Compare = CompareLtU

        var r1: Registers.Index
        var r2: Registers.Index
        var offset: UInt32
        public init(data: Data) throws { (r1, r2, offset) = try Self.parse(data: data) }
    }

    public struct BranchLtS: BranchInstructionBase2 {
        public static var opcode: UInt8 { 173 }
        typealias Compare = CompareLtS

        var r1: Registers.Index
        var r2: Registers.Index
        var offset: UInt32
        public init(data: Data) throws { (r1, r2, offset) = try Self.parse(data: data) }
    }

    public struct BranchGeU: BranchInstructionBase2 {
        public static var opcode: UInt8 { 174 }
        typealias Compare = CompareGeU

        var r1: Registers.Index
        var r2: Registers.Index
        var offset: UInt32
        public init(data: Data) throws { (r1, r2, offset) = try Self.parse(data: data) }
    }

    public struct BranchGeS: BranchInstructionBase2 {
        public static var opcode: UInt8 { 175 }
        typealias Compare = CompareGeS

        var r1: Registers.Index
        var r2: Registers.Index
        var offset: UInt32
        public init(data: Data) throws { (r1, r2, offset) = try Self.parse(data: data) }
    }

    // MARK: Instruction with Arguments of Two Registers and Two Immediates (5.12)

    public struct LoadImmJumpInd: Instruction {
        public static var opcode: UInt8 { 180 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let value: UInt32
        public let offset: UInt32

        public init(data: Data) throws {
            (ra, rb) = try Instructions.deocdeRegisters(data)
            (value, offset) = try Instructions.decodeImmediate2(data, minus: 2, startIdx: 1)
        }

        public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
            context.state.writeRegister(ra, value)
            return .continued
        }

        public func updatePC(context: ExecutionContext, skip _: UInt32) -> ExecOutcome {
            let rbVal: UInt32 = context.state.readRegister(rb)
            return Instructions.djump(context: context, target: rbVal &+ offset)
        }
    }

    // MARK: Instructions with Arguments of Three Registers (5.13)

    public struct Add32: Instruction {
        public static var opcode: UInt8 { 190 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let rd: Registers.Index

        public init(data: Data) throws {
            (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let (raVal, rbVal): (UInt32, UInt32) = context.state.readRegister(ra, rb)
            context.state.writeRegister(rd, Int32(bitPattern: raVal &+ rbVal))
            return .continued
        }
    }

    public struct Sub32: Instruction {
        public static var opcode: UInt8 { 191 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let rd: Registers.Index

        public init(data: Data) throws {
            (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let (raVal, rbVal): (UInt32, UInt32) = context.state.readRegister(ra, rb)
            context.state.writeRegister(rd, Int32(bitPattern: raVal &- rbVal))
            return .continued
        }
    }

    public struct Mul32: Instruction {
        public static var opcode: UInt8 { 192 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let rd: Registers.Index

        public init(data: Data) throws {
            (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let (raVal, rbVal): (UInt32, UInt32) = context.state.readRegister(ra, rb)
            context.state.writeRegister(rd, Int32(bitPattern: raVal &* rbVal))
            return .continued
        }
    }

    public struct DivU32: Instruction {
        public static var opcode: UInt8 { 193 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let rd: Registers.Index

        public init(data: Data) throws {
            (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let (raVal, rbVal): (UInt32, UInt32) = context.state.readRegister(ra, rb)
            if rbVal == 0 {
                context.state.writeRegister(rd, UInt64.max)
            } else {
                context.state.writeRegister(rd, raVal / rbVal)
            }
            return .continued
        }
    }

    public struct DivS32: Instruction {
        public static var opcode: UInt8 { 194 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let rd: Registers.Index

        public init(data: Data) throws {
            (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let (raVal, rbVal): (UInt32, UInt32) = context.state.readRegister(ra, rb)
            let a = Int32(bitPattern: raVal)
            let b = Int32(bitPattern: rbVal)
            if rbVal == 0 {
                context.state.writeRegister(rd, UInt64.max)
            } else if a == Int32.min, b == -1 {
                context.state.writeRegister(rd, a)
            } else {
                context.state.writeRegister(rd, Int64(a / b))
            }
            return .continued
        }
    }

    public struct RemU32: Instruction {
        public static var opcode: UInt8 { 195 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let rd: Registers.Index

        public init(data: Data) throws {
            (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let (raVal, rbVal): (UInt32, UInt32) = context.state.readRegister(ra, rb)
            if rbVal == 0 {
                context.state.writeRegister(rd, Int32(bitPattern: raVal))
            } else {
                context.state.writeRegister(rd, raVal % rbVal)
            }
            return .continued
        }
    }

    public struct RemS32: Instruction {
        public static var opcode: UInt8 { 196 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let rd: Registers.Index

        public init(data: Data) throws {
            (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let (raVal, rbVal): (UInt32, UInt32) = context.state.readRegister(ra, rb)
            let a = Int32(bitPattern: raVal)
            let b = Int32(bitPattern: rbVal)
            if rbVal == 0 {
                context.state.writeRegister(rd, a)
            } else if a == Int32.min, b == -1 {
                context.state.writeRegister(rd, 0)
            } else {
                context.state.writeRegister(rd, Int64(a % b))
            }
            return .continued
        }
    }

    public struct ShloL32: Instruction {
        public static var opcode: UInt8 { 197 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let rd: Registers.Index

        public init(data: Data) throws {
            (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let (raVal, rbVal): (UInt32, UInt32) = context.state.readRegister(ra, rb)
            let shift = rbVal & 0x1F
            context.state.writeRegister(rd, Int32(bitPattern: raVal << shift))
            return .continued
        }
    }

    public struct ShloR32: Instruction {
        public static var opcode: UInt8 { 198 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let rd: Registers.Index

        public init(data: Data) throws {
            (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let (raVal, rbVal): (UInt32, UInt32) = context.state.readRegister(ra, rb)
            let shift = rbVal & 0x1F
            context.state.writeRegister(rd, Int32(bitPattern: raVal >> shift))
            return .continued
        }
    }

    public struct SharR32: Instruction {
        public static var opcode: UInt8 { 199 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let rd: Registers.Index

        public init(data: Data) throws {
            (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let (raVal, rbVal): (UInt32, UInt32) = context.state.readRegister(ra, rb)
            let shift = rbVal & 0x1F
            context.state.writeRegister(rd, Int32(bitPattern: raVal) >> shift)
            return .continued
        }
    }

    public struct Add64: Instruction {
        public static var opcode: UInt8 { 200 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let rd: Registers.Index

        public init(data: Data) throws {
            (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let (raVal, rbVal): (UInt64, UInt64) = context.state.readRegister(ra, rb)
            context.state.writeRegister(rd, raVal &+ rbVal)
            return .continued
        }
    }

    public struct Sub64: Instruction {
        public static var opcode: UInt8 { 201 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let rd: Registers.Index

        public init(data: Data) throws {
            (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let (raVal, rbVal): (UInt64, UInt64) = context.state.readRegister(ra, rb)
            context.state.writeRegister(rd, raVal &- rbVal)
            return .continued
        }
    }

    public struct Mul64: Instruction {
        public static var opcode: UInt8 { 202 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let rd: Registers.Index

        public init(data: Data) throws {
            (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let (raVal, rbVal): (UInt64, UInt64) = context.state.readRegister(ra, rb)
            context.state.writeRegister(rd, raVal &* rbVal)
            return .continued
        }
    }

    public struct DivU64: Instruction {
        public static var opcode: UInt8 { 203 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let rd: Registers.Index

        public init(data: Data) throws {
            (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let (raVal, rbVal): (UInt64, UInt64) = context.state.readRegister(ra, rb)
            if rbVal == 0 {
                context.state.writeRegister(rd, UInt64.max)
            } else {
                context.state.writeRegister(rd, raVal / rbVal)
            }
            return .continued
        }
    }

    public struct DivS64: Instruction {
        public static var opcode: UInt8 { 204 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let rd: Registers.Index

        public init(data: Data) throws {
            (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let (raVal, rbVal): (UInt64, UInt64) = context.state.readRegister(ra, rb)
            let a = Int64(bitPattern: raVal)
            let b = Int64(bitPattern: rbVal)
            if rbVal == 0 {
                context.state.writeRegister(rd, UInt64.max)
            } else if a == Int64.min, b == -1 {
                context.state.writeRegister(rd, a)
            } else {
                context.state.writeRegister(rd, Int64(a / b))
            }
            return .continued
        }
    }

    public struct RemU64: Instruction {
        public static var opcode: UInt8 { 205 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let rd: Registers.Index

        public init(data: Data) throws {
            (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let (raVal, rbVal): (UInt64, UInt64) = context.state.readRegister(ra, rb)
            if rbVal == 0 {
                context.state.writeRegister(rd, raVal)
            } else {
                context.state.writeRegister(rd, raVal % rbVal)
            }
            return .continued
        }
    }

    public struct RemS64: Instruction {
        public static var opcode: UInt8 { 206 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let rd: Registers.Index

        public init(data: Data) throws {
            (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let (raVal, rbVal): (UInt64, UInt64) = context.state.readRegister(ra, rb)
            let a = Int64(bitPattern: raVal)
            let b = Int64(bitPattern: rbVal)
            if rbVal == 0 {
                context.state.writeRegister(rd, raVal)
            } else if a == Int64.min, b == -1 {
                context.state.writeRegister(rd, 0)
            } else {
                context.state.writeRegister(rd, UInt64(bitPattern: a % b))
            }
            return .continued
        }
    }

    public struct ShloL64: Instruction {
        public static var opcode: UInt8 { 207 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let rd: Registers.Index

        public init(data: Data) throws {
            (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let (raVal, rbVal): (UInt64, UInt64) = context.state.readRegister(ra, rb)
            let shift = rbVal & 0x1F
            context.state.writeRegister(rd, UInt64(truncatingIfNeeded: raVal << shift))
            return .continued
        }
    }

    public struct ShloR64: Instruction {
        public static var opcode: UInt8 { 208 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let rd: Registers.Index

        public init(data: Data) throws {
            (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let (raVal, rbVal): (UInt64, UInt64) = context.state.readRegister(ra, rb)
            let shift = rbVal & 0x1F
            context.state.writeRegister(rd, raVal >> shift)
            return .continued
        }
    }

    public struct SharR64: Instruction {
        public static var opcode: UInt8 { 209 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let rd: Registers.Index

        public init(data: Data) throws {
            (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let (raVal, rbVal): (UInt64, UInt64) = context.state.readRegister(ra, rb)
            let shift = rbVal & 0x1F
            context.state.writeRegister(rd, Int64(bitPattern: raVal) >> shift)
            return .continued
        }
    }

    public struct And: Instruction {
        public static var opcode: UInt8 { 210 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let rd: Registers.Index

        public init(data: Data) throws {
            (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let (raVal, rbVal): (UInt64, UInt64) = context.state.readRegister(ra, rb)
            context.state.writeRegister(rd, raVal & rbVal)
            return .continued
        }
    }

    public struct Xor: Instruction {
        public static var opcode: UInt8 { 211 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let rd: Registers.Index

        public init(data: Data) throws {
            (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let (raVal, rbVal): (UInt64, UInt64) = context.state.readRegister(ra, rb)
            context.state.writeRegister(rd, raVal ^ rbVal)
            return .continued
        }
    }

    public struct Or: Instruction {
        public static var opcode: UInt8 { 212 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let rd: Registers.Index

        public init(data: Data) throws {
            (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let (raVal, rbVal): (UInt64, UInt64) = context.state.readRegister(ra, rb)
            context.state.writeRegister(rd, raVal | rbVal)
            return .continued
        }
    }

    public struct MulUpperSS: Instruction {
        public static var opcode: UInt8 { 213 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let rd: Registers.Index

        public init(data: Data) throws {
            (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let (raVal, rbVal): (UInt64, UInt64) = context.state.readRegister(ra, rb)
            let a = Int128(Int64(bitPattern: raVal))
            let b = Int128(Int64(bitPattern: rbVal))
            context.state.writeRegister(rd, Int64(truncatingIfNeeded: (a * b) >> 64))
            return .continued
        }
    }

    public struct MulUpperUU: Instruction {
        public static var opcode: UInt8 { 214 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let rd: Registers.Index

        public init(data: Data) throws {
            (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let (raVal, rbVal): (UInt64, UInt64) = context.state.readRegister(ra, rb)
            context.state.writeRegister(rd, (UInt128(raVal) * UInt128(rbVal)) >> 64)
            return .continued
        }
    }

    public struct MulUpperSU: Instruction {
        public static var opcode: UInt8 { 215 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let rd: Registers.Index

        public init(data: Data) throws {
            (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let (raVal, rbVal): (UInt64, UInt64) = context.state.readRegister(ra, rb)
            let a = Int128(Int64(bitPattern: raVal))
            let b = Int128(rbVal)
            context.state.writeRegister(rd, Int64(truncatingIfNeeded: (a * b) >> 64))
            return .continued
        }
    }

    public struct SetLtU: Instruction {
        public static var opcode: UInt8 { 216 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let rd: Registers.Index

        public init(data: Data) throws {
            (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let (raVal, rbVal): (UInt64, UInt64) = context.state.readRegister(ra, rb)
            context.state.writeRegister(rd, raVal < rbVal ? 1 : 0)
            return .continued
        }
    }

    public struct SetLtS: Instruction {
        public static var opcode: UInt8 { 217 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let rd: Registers.Index

        public init(data: Data) throws {
            (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let (raVal, rbVal): (UInt64, UInt64) = context.state.readRegister(ra, rb)
            context.state.writeRegister(rd, Int64(bitPattern: raVal) < Int64(bitPattern: rbVal) ? 1 : 0)
            return .continued
        }
    }

    public struct CmovIz: Instruction {
        public static var opcode: UInt8 { 218 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let rd: Registers.Index

        public init(data: Data) throws {
            (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let (raVal, rbVal): (UInt64, UInt64) = context.state.readRegister(ra, rb)
            if rbVal == 0 {
                context.state.writeRegister(rd, raVal)
            }
            return .continued
        }
    }

    public struct CmovNz: Instruction {
        public static var opcode: UInt8 { 219 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let rd: Registers.Index

        public init(data: Data) throws {
            (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let (raVal, rbVal): (UInt64, UInt64) = context.state.readRegister(ra, rb)
            if rbVal != 0 {
                context.state.writeRegister(rd, raVal)
            }
            return .continued
        }
    }

    public struct RotL64: Instruction {
        public static var opcode: UInt8 { 220 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let rd: Registers.Index

        public init(data: Data) throws {
            (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let (raVal, rbVal): (UInt64, UInt64) = context.state.readRegister(ra, rb)
            context.state.writeRegister(rd, raVal.rotated(left: rbVal))
            return .continued
        }
    }

    public struct RotL32: Instruction {
        public static var opcode: UInt8 { 221 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let rd: Registers.Index

        public init(data: Data) throws {
            (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let (raVal, rbVal): (UInt32, UInt32) = context.state.readRegister(ra, rb)
            context.state.writeRegister(rd, Int32(bitPattern: raVal.rotated(left: rbVal)))
            return .continued
        }
    }

    public struct RotR64: Instruction {
        public static var opcode: UInt8 { 222 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let rd: Registers.Index

        public init(data: Data) throws {
            (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let (raVal, rbVal): (UInt64, UInt64) = context.state.readRegister(ra, rb)
            context.state.writeRegister(rd, raVal.rotated(right: rbVal))
            return .continued
        }
    }

    public struct RotR32: Instruction {
        public static var opcode: UInt8 { 223 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let rd: Registers.Index

        public init(data: Data) throws {
            (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let (raVal, rbVal): (UInt32, UInt32) = context.state.readRegister(ra, rb)
            context.state.writeRegister(rd, Int32(bitPattern: raVal.rotated(right: rbVal)))
            return .continued
        }
    }

    public struct AndInv: Instruction {
        public static var opcode: UInt8 { 224 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let rd: Registers.Index

        public init(data: Data) throws {
            (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let (raVal, rbVal): (UInt64, UInt64) = context.state.readRegister(ra, rb)
            context.state.writeRegister(rd, raVal & ~rbVal)
            return .continued
        }
    }

    public struct OrInv: Instruction {
        public static var opcode: UInt8 { 225 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let rd: Registers.Index

        public init(data: Data) throws {
            (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let (raVal, rbVal): (UInt64, UInt64) = context.state.readRegister(ra, rb)
            context.state.writeRegister(rd, raVal | ~rbVal)
            return .continued
        }
    }

    public struct Xnor: Instruction {
        public static var opcode: UInt8 { 226 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let rd: Registers.Index

        public init(data: Data) throws {
            (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let (raVal, rbVal): (UInt64, UInt64) = context.state.readRegister(ra, rb)
            context.state.writeRegister(rd, ~(raVal ^ rbVal))
            return .continued
        }
    }

    public struct Max: Instruction {
        public static var opcode: UInt8 { 227 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let rd: Registers.Index

        public init(data: Data) throws {
            (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let (raVal, rbVal): (UInt64, UInt64) = context.state.readRegister(ra, rb)
            context.state.writeRegister(rd, max(Int64(bitPattern: raVal), Int64(bitPattern: rbVal)))
            return .continued
        }
    }

    public struct MaxU: Instruction {
        public static var opcode: UInt8 { 228 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let rd: Registers.Index

        public init(data: Data) throws {
            (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let (raVal, rbVal): (UInt64, UInt64) = context.state.readRegister(ra, rb)
            context.state.writeRegister(rd, max(raVal, rbVal))
            return .continued
        }
    }

    public struct Min: Instruction {
        public static var opcode: UInt8 { 229 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let rd: Registers.Index

        public init(data: Data) throws {
            (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let (raVal, rbVal): (UInt64, UInt64) = context.state.readRegister(ra, rb)
            context.state.writeRegister(rd, min(Int64(bitPattern: raVal), Int64(bitPattern: rbVal)))
            return .continued
        }
    }

    public struct MinU: Instruction {
        public static var opcode: UInt8 { 230 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let rd: Registers.Index

        public init(data: Data) throws {
            (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let (raVal, rbVal): (UInt64, UInt64) = context.state.readRegister(ra, rb)
            context.state.writeRegister(rd, min(raVal, rbVal))
            return .continued
        }
    }
}
