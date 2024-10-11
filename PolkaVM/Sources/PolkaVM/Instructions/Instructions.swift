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
        public static var opcode: UInt8 { 17 }

        public init(data _: Data) {}

        public func _executeImpl(context _: ExecutionContext) -> ExecOutcome { .continued }
    }

    // MARK: Instructions with Arguments of One Immediate (5.2)

    public struct Ecalli: Instruction {
        public static var opcode: UInt8 { 78 }

        public let callIndex: UInt32

        public init(data: Data) {
            callIndex = Instructions.decodeImmediate(data)
        }

        public func _executeImpl(context _: ExecutionContext) -> ExecOutcome {
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

        public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
            try context.state.writeMemory(address: address, value: value)
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

        public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
            try context.state.writeMemory(address: address, values: value.encode(method: .fixedWidth(2)))
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

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            if (try? context.state.writeMemory(
                address: address, values: value.encode(method: .fixedWidth(4))
            )) != nil {
                return .continued
            }
            return .exit(.pageFault(address))
        }
    }

    // MARK: Instructions with Arguments of One Offset (5.4)

    public struct Jump: Instruction {
        public static var opcode: UInt8 { 5 }

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

    // Instructions with Arguments of One Register & One Immediate (5.5)

    public struct JumpInd: Instruction {
        public static var opcode: UInt8 { 19 }

        public let register: Registers.Index
        public let offset: UInt32

        public init(data: Data) throws {
            register = try Registers.Index(ra: data.at(relative: 0))
            offset = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        }

        public func _executeImpl(context _: ExecutionContext) -> ExecOutcome { .continued }

        public func updatePC(context: ExecutionContext, skip _: UInt32) -> ExecOutcome {
            let regVal = context.state.readRegister(register)
            return Instructions.djump(context: context, target: regVal &+ offset)
        }
    }

    public struct LoadImm: Instruction {
        public static var opcode: UInt8 { 4 }

        public let register: Registers.Index
        public let value: UInt32

        public init(data: Data) throws {
            register = try Registers.Index(ra: data.at(relative: 0))
            value = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            context.state.writeRegister(register, value)
            return .continued
        }
    }

    public struct LoadU8: Instruction {
        public static var opcode: UInt8 { 60 }

        public let register: Registers.Index
        public let address: UInt32

        public init(data: Data) throws {
            register = try Registers.Index(ra: data.at(relative: 0))
            address = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        }

        public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
            let value = try context.state.readMemory(address: address)
            context.state.writeRegister(register, UInt32(value))
            return .continued
        }
    }

    public struct LoadI8: Instruction {
        public static var opcode: UInt8 { 74 }

        public let register: Registers.Index
        public let address: UInt32

        public init(data: Data) throws {
            register = try Registers.Index(ra: data.at(relative: 0))
            address = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        }

        public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
            let value = try context.state.readMemory(address: address)
            context.state.writeRegister(register, UInt32(bitPattern: Int32(Int8(bitPattern: value))))
            return .continued
        }
    }

    public struct LoadU16: Instruction {
        public static var opcode: UInt8 { 76 }

        public let register: Registers.Index
        public let address: UInt32

        public init(data: Data) throws {
            register = try Registers.Index(ra: data.at(relative: 0))
            address = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        }

        public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
            let data = try context.state.readMemory(address: address, length: 2)
            let value = data.decode(UInt16.self)
            context.state.writeRegister(register, UInt32(value))
            return .continued
        }
    }

    public struct LoadI16: Instruction {
        public static var opcode: UInt8 { 66 }

        public let register: Registers.Index
        public let address: UInt32

        public init(data: Data) throws {
            register = try Registers.Index(ra: data.at(relative: 0))
            address = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        }

        public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
            let data = try context.state.readMemory(address: address, length: 2)
            let value = data.decode(UInt16.self)
            context.state.writeRegister(register, UInt32(bitPattern: Int32(Int16(bitPattern: value))))
            return .continued
        }
    }

    public struct LoadU32: Instruction {
        public static var opcode: UInt8 { 10 }

        public let register: Registers.Index
        public let address: UInt32

        public init(data: Data) throws {
            register = try Registers.Index(ra: data.at(relative: 0))
            address = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        }

        public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
            let data = try context.state.readMemory(address: address, length: 4)
            let value = data.decode(UInt32.self)
            context.state.writeRegister(register, value)
            return .continued
        }
    }

    public struct StoreU8: Instruction {
        public static var opcode: UInt8 { 71 }

        public let register: Registers.Index
        public let address: UInt32

        public init(data: Data) throws {
            register = try Registers.Index(ra: data.at(relative: 0))
            address = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        }

        public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
            let value = UInt8(truncatingIfNeeded: context.state.readRegister(register))
            try context.state.writeMemory(address: address, value: value)
            return .continued
        }
    }

    public struct StoreU16: Instruction {
        public static var opcode: UInt8 { 69 }

        public let register: Registers.Index
        public let address: UInt32

        public init(data: Data) throws {
            register = try Registers.Index(ra: data.at(relative: 0))
            address = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        }

        public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
            let value = UInt16(truncatingIfNeeded: context.state.readRegister(register))
            try context.state.writeMemory(address: address, values: value.encode(method: .fixedWidth(2)))
            return .continued
        }
    }

    public struct StoreU32: Instruction {
        public static var opcode: UInt8 { 22 }

        public let register: Registers.Index
        public let address: UInt32

        public init(data: Data) throws {
            register = try Registers.Index(ra: data.at(relative: 0))
            address = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        }

        public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
            let value = context.state.readRegister(register)
            try context.state.writeMemory(address: address, values: value.encode(method: .fixedWidth(4)))
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

        public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
            try context.state.writeMemory(address: context.state.readRegister(register) &+ address, value: value)
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

        public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
            try context.state.writeMemory(
                address: context.state.readRegister(register) &+ address,
                values: value.encode(method: .fixedWidth(2))
            )
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

        public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
            try context.state.writeMemory(
                address: context.state.readRegister(register) &+ address,
                values: value.encode(method: .fixedWidth(4))
            )
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
        typealias Compare = CompareLtU

        var register: Registers.Index
        var value: UInt32
        var offset: UInt32
        public init(data: Data) throws { (register, value, offset) = try Self.parse(data: data) }
    }

    public struct BranchLeUImm: BranchInstructionBase {
        public static var opcode: UInt8 { 59 }
        typealias Compare = CompareLeU

        var register: Registers.Index
        var value: UInt32
        var offset: UInt32
        public init(data: Data) throws { (register, value, offset) = try Self.parse(data: data) }
    }

    public struct BranchGeUImm: BranchInstructionBase {
        public static var opcode: UInt8 { 52 }
        typealias Compare = CompareGeU

        var register: Registers.Index
        var value: UInt32
        var offset: UInt32
        public init(data: Data) throws { (register, value, offset) = try Self.parse(data: data) }
    }

    public struct BranchGtUImm: BranchInstructionBase {
        public static var opcode: UInt8 { 50 }
        typealias Compare = CompareGtU

        var register: Registers.Index
        var value: UInt32
        var offset: UInt32
        public init(data: Data) throws { (register, value, offset) = try Self.parse(data: data) }
    }

    public struct BranchLtSImm: BranchInstructionBase {
        public static var opcode: UInt8 { 32 }
        typealias Compare = CompareLtS

        var register: Registers.Index
        var value: UInt32
        var offset: UInt32
        public init(data: Data) throws { (register, value, offset) = try Self.parse(data: data) }
    }

    public struct BranchLeSImm: BranchInstructionBase {
        public static var opcode: UInt8 { 46 }
        typealias Compare = CompareLeS

        var register: Registers.Index
        var value: UInt32
        var offset: UInt32
        public init(data: Data) throws { (register, value, offset) = try Self.parse(data: data) }
    }

    public struct BranchGeSImm: BranchInstructionBase {
        public static var opcode: UInt8 { 45 }
        typealias Compare = CompareGeS

        var register: Registers.Index
        var value: UInt32
        var offset: UInt32
        public init(data: Data) throws { (register, value, offset) = try Self.parse(data: data) }
    }

    public struct BranchGtSImm: BranchInstructionBase {
        public static var opcode: UInt8 { 53 }
        typealias Compare = CompareGtS

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
            (dest, src) = try Instructions.deocdeRegisters(data)
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            context.state.writeRegister(dest, context.state.readRegister(src))
            return .continued
        }
    }

    public struct Sbrk: Instruction {
        public static var opcode: UInt8 { 87 }

        public let src: Registers.Index
        public let dest: Registers.Index

        public init(data: Data) throws {
            (dest, src) = try Instructions.deocdeRegisters(data)
        }

        public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
            let increment = context.state.readRegister(src)
            let startAddr = try context.state.sbrk(increment)
            context.state.writeRegister(dest, startAddr)

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
            (src, dest) = try Instructions.deocdeRegisters(data)
            offset = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        }

        public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
            let value = UInt8(truncatingIfNeeded: context.state.readRegister(src))
            try context.state.writeMemory(address: context.state.readRegister(dest) &+ offset, value: value)
            return .continued
        }
    }

    public struct StoreIndU16: Instruction {
        public static var opcode: UInt8 { 29 }

        public let src: Registers.Index
        public let dest: Registers.Index
        public let offset: UInt32

        public init(data: Data) throws {
            (src, dest) = try Instructions.deocdeRegisters(data)
            offset = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        }

        public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
            let value = UInt16(truncatingIfNeeded: context.state.readRegister(src))
            try context.state.writeMemory(address: context.state.readRegister(dest) &+ offset, values: value.encode(method: .fixedWidth(2)))
            return .continued
        }
    }

    public struct StoreIndU32: Instruction {
        public static var opcode: UInt8 { 3 }

        public let src: Registers.Index
        public let dest: Registers.Index
        public let offset: UInt32

        public init(data: Data) throws {
            (src, dest) = try Instructions.deocdeRegisters(data)
            offset = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        }

        public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
            let value = context.state.readRegister(src)
            try context.state.writeMemory(address: context.state.readRegister(dest) &+ offset, values: value.encode(method: .fixedWidth(4)))
            return .continued
        }
    }

    public struct LoadIndU8: Instruction {
        public static var opcode: UInt8 { 11 }

        public let src: Registers.Index
        public let dest: Registers.Index
        public let offset: UInt32

        public init(data: Data) throws {
            (dest, src) = try Instructions.deocdeRegisters(data)
            offset = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        }

        public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
            let value = try context.state.readMemory(address: context.state.readRegister(src) + offset)
            context.state.writeRegister(dest, UInt32(value))
            return .continued
        }
    }

    public struct LoadIndI8: Instruction {
        public static var opcode: UInt8 { 21 }

        public let src: Registers.Index
        public let dest: Registers.Index
        public let offset: UInt32

        public init(data: Data) throws {
            (dest, src) = try Instructions.deocdeRegisters(data)
            offset = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        }

        public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
            let value = try context.state.readMemory(address: context.state.readRegister(src) + offset)
            context.state.writeRegister(dest, UInt32(bitPattern: Int32(Int8(bitPattern: value))))
            return .continued
        }
    }

    public struct LoadIndU16: Instruction {
        public static var opcode: UInt8 { 37 }

        public let src: Registers.Index
        public let dest: Registers.Index
        public let offset: UInt32

        public init(data: Data) throws {
            (dest, src) = try Instructions.deocdeRegisters(data)
            offset = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        }

        public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
            let data = try context.state.readMemory(address: context.state.readRegister(src) &+ offset, length: 2)
            let value = data.decode(UInt16.self)
            context.state.writeRegister(dest, UInt32(value))
            return .continued
        }
    }

    public struct LoadIndI16: Instruction {
        public static var opcode: UInt8 { 33 }

        public let src: Registers.Index
        public let dest: Registers.Index
        public let offset: UInt32

        public init(data: Data) throws {
            (dest, src) = try Instructions.deocdeRegisters(data)
            offset = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        }

        public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
            let data = try context.state.readMemory(address: context.state.readRegister(src) &+ offset, length: 2)
            let value = data.decode(UInt16.self)
            context.state.writeRegister(dest, UInt32(bitPattern: Int32(Int16(bitPattern: value))))
            return .continued
        }
    }

    public struct LoadIndU32: Instruction {
        public static var opcode: UInt8 { 1 }

        public let src: Registers.Index
        public let dest: Registers.Index
        public let offset: UInt32

        public init(data: Data) throws {
            (dest, src) = try Instructions.deocdeRegisters(data)
            offset = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        }

        public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
            let data = try context.state.readMemory(address: context.state.readRegister(src) &+ offset, length: 4)
            let value = data.decode(UInt32.self)
            context.state.writeRegister(dest, value)
            return .continued
        }
    }

    public struct AddImm: Instruction {
        public static var opcode: UInt8 { 2 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let value: UInt32

        public init(data: Data) throws {
            (ra, rb) = try Instructions.deocdeRegisters(data)
            value = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let regVal = context.state.readRegister(rb)
            context.state.writeRegister(ra, regVal &+ value)
            return .continued
        }
    }

    public struct AndImm: Instruction {
        public static var opcode: UInt8 { 18 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let value: UInt32

        public init(data: Data) throws {
            (ra, rb) = try Instructions.deocdeRegisters(data)
            value = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let regVal = context.state.readRegister(rb)
            context.state.writeRegister(ra, regVal & value)
            return .continued
        }
    }

    public struct XorImm: Instruction {
        public static var opcode: UInt8 { 31 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let value: UInt32

        public init(data: Data) throws {
            (ra, rb) = try Instructions.deocdeRegisters(data)
            value = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let regVal = context.state.readRegister(rb)
            context.state.writeRegister(ra, regVal ^ value)
            return .continued
        }
    }

    public struct OrImm: Instruction {
        public static var opcode: UInt8 { 49 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let value: UInt32

        public init(data: Data) throws {
            (ra, rb) = try Instructions.deocdeRegisters(data)
            value = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let regVal = context.state.readRegister(rb)
            context.state.writeRegister(ra, regVal | value)
            return .continued
        }
    }

    public struct MulImm: Instruction {
        public static var opcode: UInt8 { 35 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let value: UInt32

        public init(data: Data) throws {
            (ra, rb) = try Instructions.deocdeRegisters(data)
            value = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let regVal = context.state.readRegister(rb)
            context.state.writeRegister(ra, regVal &* value)
            return .continued
        }
    }

    public struct MulUpperSSImm: Instruction {
        public static var opcode: UInt8 { 65 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let value: UInt32

        public init(data: Data) throws {
            (ra, rb) = try Instructions.deocdeRegisters(data)
            value = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let regVal = context.state.readRegister(rb)
            context.state.writeRegister(
                ra,
                UInt32(bitPattern: Int32((Int64(Int32(bitPattern: regVal)) * Int64(Int32(bitPattern: value))) >> 32))
            )
            return .continued
        }
    }

    public struct MulUpperUUImm: Instruction {
        public static var opcode: UInt8 { 63 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let value: UInt32

        public init(data: Data) throws {
            (ra, rb) = try Instructions.deocdeRegisters(data)
            value = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let regVal = context.state.readRegister(rb)
            context.state.writeRegister(ra, UInt32((UInt64(regVal) * UInt64(value)) >> 32))
            return .continued
        }
    }

    public struct SetLtUImm: Instruction {
        public static var opcode: UInt8 { 27 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let value: UInt32

        public init(data: Data) throws {
            (ra, rb) = try Instructions.deocdeRegisters(data)
            value = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let regVal = context.state.readRegister(rb)
            context.state.writeRegister(ra, regVal < value ? 1 : 0)
            return .continued
        }
    }

    public struct SetLtSImm: Instruction {
        public static var opcode: UInt8 { 56 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let value: UInt32

        public init(data: Data) throws {
            (ra, rb) = try Instructions.deocdeRegisters(data)
            value = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let regVal = context.state.readRegister(rb)
            context.state.writeRegister(ra, Int32(bitPattern: regVal) < Int32(bitPattern: value) ? 1 : 0)
            return .continued
        }
    }

    public struct ShloLImm: Instruction {
        public static var opcode: UInt8 { 9 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let value: UInt32

        public init(data: Data) throws {
            (ra, rb) = try Instructions.deocdeRegisters(data)
            value = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let regVal = context.state.readRegister(rb)
            let shift = value & 0x1F
            context.state.writeRegister(ra, UInt32(truncatingIfNeeded: regVal << shift))
            return .continued
        }
    }

    public struct ShloRImm: Instruction {
        public static var opcode: UInt8 { 14 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let value: UInt32

        public init(data: Data) throws {
            (ra, rb) = try Instructions.deocdeRegisters(data)
            value = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let regVal = context.state.readRegister(rb)
            let shift = value & 0x1F
            context.state.writeRegister(ra, regVal >> shift)
            return .continued
        }
    }

    public struct SharRImm: Instruction {
        public static var opcode: UInt8 { 25 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let value: UInt32

        public init(data: Data) throws {
            (ra, rb) = try Instructions.deocdeRegisters(data)
            value = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let regVal = context.state.readRegister(rb)
            let shift = value & 0x1F
            context.state.writeRegister(ra, UInt32(bitPattern: Int32(bitPattern: regVal) >> shift))
            return .continued
        }
    }

    public struct NegAddImm: Instruction {
        public static var opcode: UInt8 { 40 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let value: UInt32

        public init(data: Data) throws {
            (ra, rb) = try Instructions.deocdeRegisters(data)
            value = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let regVal = context.state.readRegister(rb)
            context.state.writeRegister(ra, value &- regVal)
            return .continued
        }
    }

    public struct SetGtUImm: Instruction {
        public static var opcode: UInt8 { 39 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let value: UInt32

        public init(data: Data) throws {
            (ra, rb) = try Instructions.deocdeRegisters(data)
            value = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let regVal = context.state.readRegister(rb)
            context.state.writeRegister(ra, regVal > value ? 1 : 0)
            return .continued
        }
    }

    public struct SetGtSImm: Instruction {
        public static var opcode: UInt8 { 61 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let value: UInt32

        public init(data: Data) throws {
            (ra, rb) = try Instructions.deocdeRegisters(data)
            value = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let regVal = context.state.readRegister(rb)
            context.state.writeRegister(ra, Int32(bitPattern: regVal) > Int32(bitPattern: value) ? 1 : 0)
            return .continued
        }
    }

    public struct ShloLImmAlt: Instruction {
        public static var opcode: UInt8 { 75 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let value: UInt32

        public init(data: Data) throws {
            (ra, rb) = try Instructions.deocdeRegisters(data)
            value = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let regVal = context.state.readRegister(rb)
            let shift = regVal & 0x1F
            context.state.writeRegister(ra, UInt32(truncatingIfNeeded: value << shift))
            return .continued
        }
    }

    public struct ShloRImmAlt: Instruction {
        public static var opcode: UInt8 { 72 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let value: UInt32

        public init(data: Data) throws {
            (ra, rb) = try Instructions.deocdeRegisters(data)
            value = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let regVal = context.state.readRegister(rb)
            let shift = regVal & 0x1F
            context.state.writeRegister(ra, value >> shift)
            return .continued
        }
    }

    public struct SharRImmAlt: Instruction {
        public static var opcode: UInt8 { 80 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let value: UInt32

        public init(data: Data) throws {
            (ra, rb) = try Instructions.deocdeRegisters(data)
            value = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let regVal = context.state.readRegister(rb)
            let shift = regVal & 0x1F
            context.state.writeRegister(ra, UInt32(bitPattern: Int32(bitPattern: value) >> shift))
            return .continued
        }
    }

    public struct CmovIzImm: Instruction {
        public static var opcode: UInt8 { 85 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let value: UInt32

        public init(data: Data) throws {
            (ra, rb) = try Instructions.deocdeRegisters(data)
            value = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let rbVal = context.state.readRegister(rb)
            if rbVal == 0 {
                context.state.writeRegister(ra, value)
            }
            return .continued
        }
    }

    public struct CmovNzImm: Instruction {
        public static var opcode: UInt8 { 86 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let value: UInt32

        public init(data: Data) throws {
            (ra, rb) = try Instructions.deocdeRegisters(data)
            value = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let regVal = context.state.readRegister(rb)
            context.state.writeRegister(ra, regVal != 0 ? value : regVal)
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
        typealias Compare = CompareLtU

        var r1: Registers.Index
        var r2: Registers.Index
        var offset: UInt32
        public init(data: Data) throws { (r1, r2, offset) = try Self.parse(data: data) }
    }

    public struct BranchLtS: BranchInstructionBase2 {
        public static var opcode: UInt8 { 48 }
        typealias Compare = CompareLtS

        var r1: Registers.Index
        var r2: Registers.Index
        var offset: UInt32
        public init(data: Data) throws { (r1, r2, offset) = try Self.parse(data: data) }
    }

    public struct BranchGeU: BranchInstructionBase2 {
        public static var opcode: UInt8 { 41 }
        typealias Compare = CompareGeU

        var r1: Registers.Index
        var r2: Registers.Index
        var offset: UInt32
        public init(data: Data) throws { (r1, r2, offset) = try Self.parse(data: data) }
    }

    public struct BranchGeS: BranchInstructionBase2 {
        public static var opcode: UInt8 { 43 }
        typealias Compare = CompareGeS

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
            (ra, rb) = try Instructions.deocdeRegisters(data)
            (value, offset) = try Instructions.decodeImmediate2(data[relative: 1...], divideBy: 1, minus: 2)
        }

        public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
            context.state.writeRegister(ra, value)
            return .continued
        }

        public func updatePC(context: ExecutionContext, skip _: UInt32) -> ExecOutcome {
            let rbVal = context.state.readRegister(rb)
            return Instructions.djump(context: context, target: rbVal &+ offset)
        }
    }

    // MARK: Instructions with Arguments of Three Registers (5.12)

    public struct Add: Instruction {
        public static var opcode: UInt8 { 8 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let rd: Registers.Index

        public init(data: Data) throws {
            (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let (raVal, rbVal) = context.state.readRegister(ra, rb)
            context.state.writeRegister(rd, raVal &+ rbVal)
            return .continued
        }
    }

    public struct Sub: Instruction {
        public static var opcode: UInt8 { 20 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let rd: Registers.Index

        public init(data: Data) throws {
            (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let (raVal, rbVal) = context.state.readRegister(ra, rb)
            context.state.writeRegister(rd, raVal &- rbVal)
            return .continued
        }
    }

    public struct And: Instruction {
        public static var opcode: UInt8 { 23 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let rd: Registers.Index

        public init(data: Data) throws {
            (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let (raVal, rbVal) = context.state.readRegister(ra, rb)
            context.state.writeRegister(rd, raVal & rbVal)
            return .continued
        }
    }

    public struct Xor: Instruction {
        public static var opcode: UInt8 { 28 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let rd: Registers.Index

        public init(data: Data) throws {
            (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let (raVal, rbVal) = context.state.readRegister(ra, rb)
            context.state.writeRegister(rd, raVal ^ rbVal)
            return .continued
        }
    }

    public struct Or: Instruction {
        public static var opcode: UInt8 { 12 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let rd: Registers.Index

        public init(data: Data) throws {
            (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let (raVal, rbVal) = context.state.readRegister(ra, rb)
            context.state.writeRegister(rd, raVal | rbVal)
            return .continued
        }
    }

    public struct Mul: Instruction {
        public static var opcode: UInt8 { 34 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let rd: Registers.Index

        public init(data: Data) throws {
            (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let (raVal, rbVal) = context.state.readRegister(ra, rb)
            context.state.writeRegister(rd, raVal &* rbVal)
            return .continued
        }
    }

    public struct MulUpperSS: Instruction {
        public static var opcode: UInt8 { 67 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let rd: Registers.Index

        public init(data: Data) throws {
            (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let (raVal, rbVal) = context.state.readRegister(ra, rb)
            context.state.writeRegister(
                rd,
                UInt32(bitPattern: Int32((Int64(Int32(bitPattern: raVal)) * Int64(Int32(bitPattern: rbVal))) >> 32))
            )
            return .continued
        }
    }

    public struct MulUpperUU: Instruction {
        public static var opcode: UInt8 { 57 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let rd: Registers.Index

        public init(data: Data) throws {
            (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let (raVal, rbVal) = context.state.readRegister(ra, rb)
            context.state.writeRegister(rd, UInt32((UInt64(raVal) * UInt64(rbVal)) >> 32))
            return .continued
        }
    }

    public struct MulUpperSU: Instruction {
        public static var opcode: UInt8 { 81 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let rd: Registers.Index

        public init(data: Data) throws {
            (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let (raVal, rbVal) = context.state.readRegister(ra, rb)
            context.state.writeRegister(
                rd,
                UInt32(bitPattern: Int32((Int64(Int32(bitPattern: raVal)) * Int64(Int32(bitPattern: rbVal))) >> 32))
            )
            return .continued
        }
    }

    public struct DivU: Instruction {
        public static var opcode: UInt8 { 68 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let rd: Registers.Index

        public init(data: Data) throws {
            (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let (raVal, rbVal) = context.state.readRegister(ra, rb)
            if rbVal == 0 {
                context.state.writeRegister(rd, UInt32.max)
            } else {
                context.state.writeRegister(rd, raVal / rbVal)
            }
            return .continued
        }
    }

    public struct DivS: Instruction {
        public static var opcode: UInt8 { 64 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let rd: Registers.Index

        public init(data: Data) throws {
            (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let (raVal, rbVal) = context.state.readRegister(ra, rb)
            if rbVal == 0 {
                context.state.writeRegister(rd, UInt32.max)
            } else if Int32(bitPattern: raVal) == Int32.min, Int32(bitPattern: rbVal) == -1 {
                context.state.writeRegister(rd, raVal)
            } else {
                context.state.writeRegister(rd, UInt32(bitPattern: Int32(bitPattern: raVal) / Int32(bitPattern: rbVal)))
            }
            return .continued
        }
    }

    public struct RemU: Instruction {
        public static var opcode: UInt8 { 73 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let rd: Registers.Index

        public init(data: Data) throws {
            (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let (raVal, rbVal) = context.state.readRegister(ra, rb)
            if rbVal == 0 {
                context.state.writeRegister(rd, raVal)
            } else {
                context.state.writeRegister(rd, raVal % rbVal)
            }
            return .continued
        }
    }

    public struct RemS: Instruction {
        public static var opcode: UInt8 { 70 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let rd: Registers.Index

        public init(data: Data) throws {
            (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let (raVal, rbVal) = context.state.readRegister(ra, rb)
            if rbVal == 0 {
                context.state.writeRegister(rd, raVal)
            } else if Int32(bitPattern: raVal) == Int32.min, Int32(bitPattern: rbVal) == -1 {
                context.state.writeRegister(rd, 0)
            } else {
                context.state.writeRegister(rd, UInt32(bitPattern: Int32(bitPattern: raVal) % Int32(bitPattern: rbVal)))
            }
            return .continued
        }
    }

    public struct SetLtU: Instruction {
        public static var opcode: UInt8 { 36 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let rd: Registers.Index

        public init(data: Data) throws {
            (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let (raVal, rbVal) = context.state.readRegister(ra, rb)
            context.state.writeRegister(rd, raVal < rbVal ? 1 : 0)
            return .continued
        }
    }

    public struct SetLtS: Instruction {
        public static var opcode: UInt8 { 58 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let rd: Registers.Index

        public init(data: Data) throws {
            (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let (raVal, rbVal) = context.state.readRegister(ra, rb)
            context.state.writeRegister(rd, Int32(bitPattern: raVal) < Int32(bitPattern: rbVal) ? 1 : 0)
            return .continued
        }
    }

    public struct ShloL: Instruction {
        public static var opcode: UInt8 { 55 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let rd: Registers.Index

        public init(data: Data) throws {
            (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let (raVal, rbVal) = context.state.readRegister(ra, rb)
            let shift = rbVal & 0x1F
            context.state.writeRegister(rd, UInt32(truncatingIfNeeded: raVal << shift))
            return .continued
        }
    }

    public struct ShloR: Instruction {
        public static var opcode: UInt8 { 51 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let rd: Registers.Index

        public init(data: Data) throws {
            (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let (raVal, rbVal) = context.state.readRegister(ra, rb)
            let shift = rbVal & 0x1F
            context.state.writeRegister(rd, raVal >> shift)
            return .continued
        }
    }

    public struct SharR: Instruction {
        public static var opcode: UInt8 { 77 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let rd: Registers.Index

        public init(data: Data) throws {
            (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let (raVal, rbVal) = context.state.readRegister(ra, rb)
            let shift = rbVal & 0x1F
            context.state.writeRegister(rd, UInt32(bitPattern: Int32(bitPattern: raVal) >> shift))
            return .continued
        }
    }

    public struct CmovIz: Instruction {
        public static var opcode: UInt8 { 83 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let rd: Registers.Index

        public init(data: Data) throws {
            (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let (raVal, rbVal) = context.state.readRegister(ra, rb)
            if rbVal == 0 {
                context.state.writeRegister(rd, raVal)
            }
            return .continued
        }
    }

    public struct CmovNz: Instruction {
        public static var opcode: UInt8 { 84 }

        public let ra: Registers.Index
        public let rb: Registers.Index
        public let rd: Registers.Index

        public init(data: Data) throws {
            (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        }

        public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
            let (raVal, rbVal) = context.state.readRegister(ra, rb)
            if rbVal != 0 {
                context.state.writeRegister(rd, raVal)
            }
            return .continued
        }
    }
}
