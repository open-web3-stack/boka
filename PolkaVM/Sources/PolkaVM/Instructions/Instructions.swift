import CppHelper
import Foundation
import TracingUtils
import Utils

private let logger = Logger(label: "Insts ")

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

extension CppHelper.Instructions.Trap: Instruction {
    public init(data _: Data) throws {
        self.init()
    }

    public func _executeImpl(context _: ExecutionContext) -> ExecOutcome {
        .exit(.panic(.trap))
    }
}

extension CppHelper.Instructions.Fallthrough: Instruction {
    public init(data _: Data) throws {
        self.init()
    }

    public func _executeImpl(context _: ExecutionContext) -> ExecOutcome { .continued }
}

extension CppHelper.Instructions.Ecalli: Instruction {
    public init(data: Data) throws {
        self.init(callIndex: Instructions.decodeImmediate(data))
    }

    public func _executeImpl(context _: ExecutionContext) -> ExecOutcome {
        .exit(.hostCall(callIndex))
    }
}

extension CppHelper.Instructions.LoadImm64: Instruction {
    public init(data: Data) throws {
        let register = try Registers.Index(r1: data.at(relative: 0))
        let value = try data.at(relative: 1 ..< 9).decode(UInt64.self)
        self.init(reg: register, value: value)
    }

    public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
        context.state.writeRegister(reg, value)
        return .continued
    }
}

extension CppHelper.Instructions.StoreImmU8: Instruction {
    public init(data: Data) throws {
        let (address, value): (UInt32, UInt8) = try Instructions.decodeImmediate2(data)
        self.init(address: address, value: value)
    }

    public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
        try context.state.writeMemory(address: address, value: value)
        return .continued
    }
}

extension CppHelper.Instructions.StoreImmU16: Instruction {
    public init(data: Data) throws {
        let (address, value): (UInt32, UInt16) = try Instructions.decodeImmediate2(data)
        self.init(address: address, value: value)
    }

    public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
        try context.state.writeMemory(address: address, values: value.encode(method: .fixedWidth(2)))
        return .continued
    }
}

extension CppHelper.Instructions.StoreImmU32: Instruction {
    public init(data: Data) throws {
        let (address, value): (UInt32, UInt32) = try Instructions.decodeImmediate2(data)
        self.init(address: address, value: value)
    }

    public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
        try context.state.writeMemory(address: address, values: value.encode(method: .fixedWidth(4)))
        return .continued
    }
}

extension CppHelper.Instructions.StoreImmU64: Instruction {
    public init(data: Data) throws {
        let (address, value): (UInt32, UInt64) = try Instructions.decodeImmediate2(data)
        self.init(address: address, value: value)
    }

    public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
        try context.state.writeMemory(address: address, values: value.encode(method: .fixedWidth(8)))
        return .continued
    }
}

extension CppHelper.Instructions.Jump: Instruction {
    public init(data: Data) throws {
        self.init(offset: Instructions.decodeImmediate(data))
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

extension CppHelper.Instructions.JumpInd: Instruction {
    public init(data: Data) throws {
        let register = try Registers.Index(r1: data.at(relative: 0))
        let offset: UInt32 = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        self.init(reg: register, offset: offset)
    }

    public func _executeImpl(context _: ExecutionContext) -> ExecOutcome { .continued }

    public func updatePC(context: ExecutionContext, skip _: UInt32) -> ExecOutcome {
        let regVal: UInt32 = context.state.readRegister(reg)
        return Instructions.djump(context: context, target: regVal &+ offset)
    }
}

extension CppHelper.Instructions.LoadImm: Instruction {
    public init(data: Data) throws {
        let register = try Registers.Index(r1: data.at(relative: 0))
        let value: UInt32 = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        self.init(reg: register, value: value)
    }

    public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
        context.state.writeRegister(reg, Int32(bitPattern: value))
        return .continued
    }
}

extension CppHelper.Instructions.LoadU8: Instruction {
    public init(data: Data) throws {
        let register = try Registers.Index(r1: data.at(relative: 0))
        let address: UInt32 = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        self.init(reg: register, address: address)
    }

    public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
        let value = try context.state.readMemory(address: address)
        context.state.writeRegister(reg, value)
        return .continued
    }
}

extension CppHelper.Instructions.LoadI8: Instruction {
    public init(data: Data) throws {
        let register = try Registers.Index(r1: data.at(relative: 0))
        let address: UInt32 = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        self.init(reg: register, address: address)
    }

    public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
        let value = try context.state.readMemory(address: address)
        context.state.writeRegister(reg, Int8(bitPattern: value))
        return .continued
    }
}

extension CppHelper.Instructions.LoadU16: Instruction {
    public init(data: Data) throws {
        let register = try Registers.Index(r1: data.at(relative: 0))
        let address: UInt32 = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        self.init(reg: register, address: address)
    }

    public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
        let data = try context.state.readMemory(address: address, length: 2)
        let value = data.decode(UInt16.self)
        context.state.writeRegister(reg, value)
        return .continued
    }
}

extension CppHelper.Instructions.LoadI16: Instruction {
    public init(data: Data) throws {
        let register = try Registers.Index(r1: data.at(relative: 0))
        let address: UInt32 = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        self.init(reg: register, address: address)
    }

    public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
        let data = try context.state.readMemory(address: address, length: 2)
        let value = data.decode(UInt16.self)
        context.state.writeRegister(reg, Int16(bitPattern: value))
        return .continued
    }
}

extension CppHelper.Instructions.LoadU32: Instruction {
    public init(data: Data) throws {
        let register = try Registers.Index(r1: data.at(relative: 0))
        let address: UInt32 = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        self.init(reg: register, address: address)
    }

    public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
        let data = try context.state.readMemory(address: address, length: 4)
        let value = data.decode(UInt32.self)
        context.state.writeRegister(reg, value)
        return .continued
    }
}

extension CppHelper.Instructions.LoadI32: Instruction {
    public init(data: Data) throws {
        let register = try Registers.Index(r1: data.at(relative: 0))
        let address: UInt32 = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        self.init(reg: register, address: address)
    }

    public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
        let data = try context.state.readMemory(address: address, length: 4)
        let value = data.decode(UInt32.self)
        context.state.writeRegister(reg, Int32(bitPattern: value))
        return .continued
    }
}

extension CppHelper.Instructions.LoadU64: Instruction {
    public init(data: Data) throws {
        let register = try Registers.Index(r1: data.at(relative: 0))
        let address: UInt32 = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        self.init(reg: register, address: address)
    }

    public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
        let data = try context.state.readMemory(address: address, length: 8)
        let value = data.decode(UInt64.self)
        context.state.writeRegister(reg, value)
        return .continued
    }
}

extension CppHelper.Instructions.StoreU8: Instruction {
    public init(data: Data) throws {
        let register = try Registers.Index(r1: data.at(relative: 0))
        let address: UInt32 = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        self.init(reg: register, address: address)
    }

    public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
        let value: UInt8 = context.state.readRegister(reg)
        try context.state.writeMemory(address: address, value: value)
        return .continued
    }
}

extension CppHelper.Instructions.StoreU16: Instruction {
    public init(data: Data) throws {
        let register = try Registers.Index(r1: data.at(relative: 0))
        let address: UInt32 = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        self.init(reg: register, address: address)
    }

    public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
        let value: UInt16 = context.state.readRegister(reg)
        try context.state.writeMemory(address: address, values: value.encode(method: .fixedWidth(2)))
        return .continued
    }
}

extension CppHelper.Instructions.StoreU32: Instruction {
    public init(data: Data) throws {
        let register = try Registers.Index(r1: data.at(relative: 0))
        let address: UInt32 = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        self.init(reg: register, address: address)
    }

    public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
        let value: UInt32 = context.state.readRegister(reg)
        try context.state.writeMemory(address: address, values: value.encode(method: .fixedWidth(4)))
        return .continued
    }
}

extension CppHelper.Instructions.StoreU64: Instruction {
    public init(data: Data) throws {
        let register = try Registers.Index(r1: data.at(relative: 0))
        let address: UInt32 = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        self.init(reg: register, address: address)
    }

    public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
        let value: UInt64 = context.state.readRegister(reg)
        try context.state.writeMemory(address: address, values: value.encode(method: .fixedWidth(8)))
        return .continued
    }
}

extension CppHelper.Instructions.StoreImmIndU8: Instruction {
    public init(data: Data) throws {
        let register = try Registers.Index(r1: data.at(relative: 0))
        let (address, value): (UInt32, UInt8) = try Instructions.decodeImmediate2(data, divideBy: 16)
        self.init(reg: register, address: address, value: value)
    }

    public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
        try context.state.writeMemory(address: context.state.readRegister(reg) &+ address, value: value)
        return .continued
    }
}

extension CppHelper.Instructions.StoreImmIndU16: Instruction {
    public init(data: Data) throws {
        let register = try Registers.Index(r1: data.at(relative: 0))
        let (address, value): (UInt32, UInt16) = try Instructions.decodeImmediate2(data, divideBy: 16)
        self.init(reg: register, address: address, value: value)
    }

    public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
        try context.state.writeMemory(
            address: context.state.readRegister(reg) &+ address,
            values: value.encode(method: .fixedWidth(2))
        )
        return .continued
    }
}

extension CppHelper.Instructions.StoreImmIndU32: Instruction {
    public init(data: Data) throws {
        let register = try Registers.Index(r1: data.at(relative: 0))
        let (address, value): (UInt32, UInt32) = try Instructions.decodeImmediate2(data, divideBy: 16)
        self.init(reg: register, address: address, value: value)
    }

    public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
        try context.state.writeMemory(
            address: context.state.readRegister(reg) &+ address,
            values: value.encode(method: .fixedWidth(4))
        )
        return .continued
    }
}

extension CppHelper.Instructions.StoreImmIndU64: Instruction {
    public init(data: Data) throws {
        let register = try Registers.Index(r1: data.at(relative: 0))
        let (address, value): (UInt32, UInt64) = try Instructions.decodeImmediate2(data, divideBy: 16)
        self.init(reg: register, address: address, value: value)
    }

    public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
        try context.state.writeMemory(
            address: context.state.readRegister(reg) &+ address,
            values: value.encode(method: .fixedWidth(8))
        )
        return .continued
    }
}

extension CppHelper.Instructions.LoadImmJump: Instruction {
    public init(data: Data) throws {
        let register = try Registers.Index(r1: data.at(relative: 0))
        let (value, offset): (UInt32, UInt32) = try Instructions.decodeImmediate2(data, divideBy: 16)
        self.init(reg: register, value: value, offset: offset)
    }

    public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
        context.state.writeRegister(reg, value)
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

extension CppHelper.Instructions.BranchEqImm: BranchInstructionBase {
    public var register: Registers.Index {
        get {
            reg
        }
        set {
            reg = newValue
        }
    }

    typealias Compare = CompareEq
    public init(data: Data) throws {
        let (register, value, offset) = try Self.parse(data: data)
        self.init(reg: register, value: value, offset: offset)
    }
}

extension CppHelper.Instructions.BranchNeImm: BranchInstructionBase {
    public var register: Registers.Index {
        get { reg }
        set { reg = newValue }
    }

    typealias Compare = CompareNe
    public init(data: Data) throws {
        let (register, value, offset) = try Self.parse(data: data)
        self.init(reg: register, value: value, offset: offset)
    }
}

extension CppHelper.Instructions.BranchLtUImm: BranchInstructionBase {
    public var register: Registers.Index {
        get { reg }
        set { reg = newValue }
    }

    typealias Compare = CompareLtU
    public init(data: Data) throws {
        let (register, value, offset) = try Self.parse(data: data)
        self.init(reg: register, value: value, offset: offset)
    }
}

extension CppHelper.Instructions.BranchLeUImm: BranchInstructionBase {
    public var register: Registers.Index {
        get { reg }
        set { reg = newValue }
    }

    typealias Compare = CompareLeU
    public init(data: Data) throws {
        let (register, value, offset) = try Self.parse(data: data)
        self.init(reg: register, value: value, offset: offset)
    }
}

extension CppHelper.Instructions.BranchGeUImm: BranchInstructionBase {
    public var register: Registers.Index {
        get { reg }
        set { reg = newValue }
    }

    typealias Compare = CompareGeU
    public init(data: Data) throws {
        let (register, value, offset) = try Self.parse(data: data)
        self.init(reg: register, value: value, offset: offset)
    }
}

extension CppHelper.Instructions.BranchGtUImm: BranchInstructionBase {
    public var register: Registers.Index {
        get { reg }
        set { reg = newValue }
    }

    typealias Compare = CompareGtU
    public init(data: Data) throws {
        let (register, value, offset) = try Self.parse(data: data)
        self.init(reg: register, value: value, offset: offset)
    }
}

extension CppHelper.Instructions.BranchLtSImm: BranchInstructionBase {
    public var register: Registers.Index {
        get { reg }
        set { reg = newValue }
    }

    typealias Compare = CompareLtS
    public init(data: Data) throws {
        let (register, value, offset) = try Self.parse(data: data)
        self.init(reg: register, value: value, offset: offset)
    }
}

extension CppHelper.Instructions.BranchLeSImm: BranchInstructionBase {
    public var register: Registers.Index {
        get { reg }
        set { reg = newValue }
    }

    typealias Compare = CompareLeS
    public init(data: Data) throws {
        let (register, value, offset) = try Self.parse(data: data)
        self.init(reg: register, value: value, offset: offset)
    }
}

extension CppHelper.Instructions.BranchGeSImm: BranchInstructionBase {
    public var register: Registers.Index {
        get { reg }
        set { reg = newValue }
    }

    typealias Compare = CompareGeS
    public init(data: Data) throws {
        let (register, value, offset) = try Self.parse(data: data)
        self.init(reg: register, value: value, offset: offset)
    }
}

extension CppHelper.Instructions.BranchGtSImm: BranchInstructionBase {
    public var register: Registers.Index {
        get { reg }
        set { reg = newValue }
    }

    typealias Compare = CompareGtS
    public init(data: Data) throws {
        let (register, value, offset) = try Self.parse(data: data)
        self.init(reg: register, value: value, offset: offset)
    }
}

extension CppHelper.Instructions.MoveReg: Instruction {
    public init(data: Data) throws {
        let (dest, src) = try Instructions.deocdeRegisters(data)
        self.init(src: src, dest: dest)
    }

    public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
        context.state.writeRegister(dest, context.state.readRegister(src) as UInt64)
        return .continued
    }
}

extension CppHelper.Instructions.Sbrk: Instruction {
    public init(data: Data) throws {
        let (dest, src) = try Instructions.deocdeRegisters(data)
        self.init(src: src, dest: dest)
    }

    public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
        let increment: UInt32 = context.state.readRegister(src)
        let startAddr = try context.state.sbrk(increment)
        context.state.writeRegister(dest, startAddr)
        return .continued
    }
}

extension CppHelper.Instructions.CountSetBits64: Instruction {
    public init(data: Data) throws {
        let (dest, ra) = try Instructions.deocdeRegisters(data)
        self.init(ra: ra, dest: dest)
    }

    public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
        let regVal: UInt64 = context.state.readRegister(ra)
        context.state.writeRegister(dest, regVal.nonzeroBitCount)
        return .continued
    }
}

extension CppHelper.Instructions.CountSetBits32: Instruction {
    public init(data: Data) throws {
        let (dest, ra) = try Instructions.deocdeRegisters(data)
        self.init(ra: ra, dest: dest)
    }

    public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
        let regVal: UInt32 = context.state.readRegister(ra)
        context.state.writeRegister(dest, regVal.nonzeroBitCount)
        return .continued
    }
}

extension CppHelper.Instructions.LeadingZeroBits64: Instruction {
    public init(data: Data) throws {
        let (dest, ra) = try Instructions.deocdeRegisters(data)
        self.init(ra: ra, dest: dest)
    }

    public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
        let regVal: UInt64 = context.state.readRegister(ra)
        context.state.writeRegister(dest, regVal.leadingZeroBitCount)
        return .continued
    }
}

extension CppHelper.Instructions.LeadingZeroBits32: Instruction {
    public init(data: Data) throws {
        let (dest, ra) = try Instructions.deocdeRegisters(data)
        self.init(ra: ra, dest: dest)
    }

    public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
        let regVal: UInt32 = context.state.readRegister(ra)
        context.state.writeRegister(dest, regVal.leadingZeroBitCount)
        return .continued
    }
}

extension CppHelper.Instructions.TrailingZeroBits64: Instruction {
    public init(data: Data) throws {
        let (dest, ra) = try Instructions.deocdeRegisters(data)
        self.init(ra: ra, dest: dest)
    }

    public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
        let regVal: UInt64 = context.state.readRegister(ra)
        context.state.writeRegister(dest, regVal.trailingZeroBitCount)
        return .continued
    }
}

extension CppHelper.Instructions.TrailingZeroBits32: Instruction {
    public init(data: Data) throws {
        let (dest, ra) = try Instructions.deocdeRegisters(data)
        self.init(ra: ra, dest: dest)
    }

    public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
        let regVal: UInt32 = context.state.readRegister(ra)
        context.state.writeRegister(dest, regVal.trailingZeroBitCount)
        return .continued
    }
}

extension CppHelper.Instructions.SignExtend8: Instruction {
    public init(data: Data) throws {
        let (dest, ra) = try Instructions.deocdeRegisters(data)
        self.init(ra: ra, dest: dest)
    }

    public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
        let regVal: UInt8 = context.state.readRegister(ra)
        context.state.writeRegister(dest, Int8(bitPattern: regVal))
        return .continued
    }
}

extension CppHelper.Instructions.SignExtend16: Instruction {
    public init(data: Data) throws {
        let (dest, ra) = try Instructions.deocdeRegisters(data)
        self.init(ra: ra, dest: dest)
    }

    public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
        let regVal: UInt16 = context.state.readRegister(ra)
        context.state.writeRegister(dest, Int16(bitPattern: regVal))
        return .continued
    }
}

extension CppHelper.Instructions.ZeroExtend16: Instruction {
    public init(data: Data) throws {
        let (dest, ra) = try Instructions.deocdeRegisters(data)
        self.init(ra: ra, dest: dest)
    }

    public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
        let regVal: UInt16 = context.state.readRegister(ra)
        context.state.writeRegister(dest, regVal)
        return .continued
    }
}

extension CppHelper.Instructions.ReverseBytes: Instruction {
    public init(data: Data) throws {
        let (dest, ra) = try Instructions.deocdeRegisters(data)
        self.init(ra: ra, dest: dest)
    }

    public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
        let regVal: UInt64 = context.state.readRegister(ra)
        context.state.writeRegister(dest, regVal.byteSwapped)
        return .continued
    }
}

extension CppHelper.Instructions.StoreIndU8: Instruction {
    public init(data: Data) throws {
        let (src, dest) = try Instructions.deocdeRegisters(data)
        let offset: UInt32 = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        self.init(src: src, dest: dest, offset: offset)
    }

    public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
        let value: UInt8 = context.state.readRegister(src)
        try context.state.writeMemory(address: context.state.readRegister(dest) &+ offset, value: value)
        return .continued
    }
}

extension CppHelper.Instructions.StoreIndU16: Instruction {
    public init(data: Data) throws {
        let (src, dest) = try Instructions.deocdeRegisters(data)
        let offset: UInt32 = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        self.init(src: src, dest: dest, offset: offset)
    }

    public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
        let value: UInt16 = context.state.readRegister(src)
        try context.state.writeMemory(
            address: context.state.readRegister(dest) &+ offset,
            values: value.encode(method: .fixedWidth(2))
        )
        return .continued
    }
}

extension CppHelper.Instructions.StoreIndU32: Instruction {
    public init(data: Data) throws {
        let (src, dest) = try Instructions.deocdeRegisters(data)
        let offset: UInt32 = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        self.init(src: src, dest: dest, offset: offset)
    }

    public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
        let value: UInt32 = context.state.readRegister(src)
        try context.state.writeMemory(
            address: context.state.readRegister(dest) &+ offset,
            values: value.encode(method: .fixedWidth(4))
        )
        return .continued
    }
}

extension CppHelper.Instructions.StoreIndU64: Instruction {
    public init(data: Data) throws {
        let (src, dest) = try Instructions.deocdeRegisters(data)
        let offset: UInt32 = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        self.init(src: src, dest: dest, offset: offset)
    }

    public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
        let value: UInt64 = context.state.readRegister(src)
        try context.state.writeMemory(
            address: context.state.readRegister(dest) &+ offset,
            values: value.encode(method: .fixedWidth(8))
        )
        return .continued
    }
}

extension CppHelper.Instructions.LoadIndU8: Instruction {
    public init(data: Data) throws {
        let (ra, rb) = try Instructions.deocdeRegisters(data)
        let offset: UInt32 = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        self.init(ra: ra, rb: rb, offset: offset)
    }

    public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
        let value = try context.state.readMemory(address: context.state.readRegister(rb) &+ offset)
        context.state.writeRegister(ra, value)
        return .continued
    }
}

extension CppHelper.Instructions.LoadIndI8: Instruction {
    public init(data: Data) throws {
        let (ra, rb) = try Instructions.deocdeRegisters(data)
        let offset: UInt32 = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        self.init(ra: ra, rb: rb, offset: offset)
    }

    public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
        let value = try context.state.readMemory(address: context.state.readRegister(rb) &+ offset)
        context.state.writeRegister(ra, Int8(bitPattern: value))
        return .continued
    }
}

extension CppHelper.Instructions.LoadIndU16: Instruction {
    public init(data: Data) throws {
        let (ra, rb) = try Instructions.deocdeRegisters(data)
        let offset: UInt32 = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        self.init(ra: ra, rb: rb, offset: offset)
    }

    public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
        let data = try context.state.readMemory(address: context.state.readRegister(rb) &+ offset, length: 2)
        let value = data.decode(UInt16.self)
        context.state.writeRegister(ra, value)
        return .continued
    }
}

extension CppHelper.Instructions.LoadIndI16: Instruction {
    public init(data: Data) throws {
        let (ra, rb) = try Instructions.deocdeRegisters(data)
        let offset: UInt32 = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        self.init(ra: ra, rb: rb, offset: offset)
    }

    public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
        let data = try context.state.readMemory(address: context.state.readRegister(rb) &+ offset, length: 2)
        let value = data.decode(UInt16.self)
        context.state.writeRegister(ra, Int16(bitPattern: value))
        return .continued
    }
}

extension CppHelper.Instructions.LoadIndU32: Instruction {
    public init(data: Data) throws {
        let (ra, rb) = try Instructions.deocdeRegisters(data)
        let offset: UInt32 = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        self.init(ra: ra, rb: rb, offset: offset)
    }

    public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
        let data = try context.state.readMemory(address: context.state.readRegister(rb) &+ offset, length: 4)
        let value = data.decode(UInt32.self)
        context.state.writeRegister(ra, value)
        return .continued
    }
}

extension CppHelper.Instructions.LoadIndI32: Instruction {
    public init(data: Data) throws {
        let (ra, rb) = try Instructions.deocdeRegisters(data)
        let offset: UInt32 = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        self.init(ra: ra, rb: rb, offset: offset)
    }

    public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
        let data = try context.state.readMemory(address: context.state.readRegister(rb) &+ offset, length: 4)
        let value = data.decode(UInt32.self)
        context.state.writeRegister(ra, Int32(bitPattern: value))
        return .continued
    }
}

extension CppHelper.Instructions.LoadIndU64: Instruction {
    public init(data: Data) throws {
        let (ra, rb) = try Instructions.deocdeRegisters(data)
        let offset: UInt32 = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        self.init(ra: ra, rb: rb, offset: offset)
    }

    public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
        let data = try context.state.readMemory(address: context.state.readRegister(rb) &+ offset, length: 8)
        let value = data.decode(UInt64.self)
        context.state.writeRegister(ra, value)
        return .continued
    }
}

extension CppHelper.Instructions.AddImm32: Instruction {
    public init(data: Data) throws {
        let (ra, rb) = try Instructions.deocdeRegisters(data)
        let value: UInt32 = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        self.init(ra: ra, rb: rb, value: value)
    }

    public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
        let regVal: UInt32 = context.state.readRegister(rb)
        context.state.writeRegister(ra, Int32(bitPattern: regVal &+ value))
        return .continued
    }
}

extension CppHelper.Instructions.AndImm: Instruction {
    public init(data: Data) throws {
        let (ra, rb) = try Instructions.deocdeRegisters(data)
        let value: UInt64 = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        self.init(ra: ra, rb: rb, value: value)
    }

    public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
        let regVal: UInt64 = context.state.readRegister(rb)
        context.state.writeRegister(ra, regVal & value)
        return .continued
    }
}

extension CppHelper.Instructions.XorImm: Instruction {
    public init(data: Data) throws {
        let (ra, rb) = try Instructions.deocdeRegisters(data)
        let value: UInt64 = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        self.init(ra: ra, rb: rb, value: value)
    }

    public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
        let regVal: UInt64 = context.state.readRegister(rb)
        context.state.writeRegister(ra, regVal ^ value)
        return .continued
    }
}

extension CppHelper.Instructions.OrImm: Instruction {
    public init(data: Data) throws {
        let (ra, rb) = try Instructions.deocdeRegisters(data)
        let value: UInt64 = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        self.init(ra: ra, rb: rb, value: value)
    }

    public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
        let regVal: UInt64 = context.state.readRegister(rb)
        context.state.writeRegister(ra, regVal | value)
        return .continued
    }
}

extension CppHelper.Instructions.MulImm32: Instruction {
    public init(data: Data) throws {
        let (ra, rb) = try Instructions.deocdeRegisters(data)
        let value: UInt32 = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        self.init(ra: ra, rb: rb, value: value)
    }

    public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
        let regVal: UInt32 = context.state.readRegister(rb)
        context.state.writeRegister(ra, Int32(bitPattern: regVal &* value))
        return .continued
    }
}

extension CppHelper.Instructions.SetLtUImm: Instruction {
    public init(data: Data) throws {
        let (ra, rb) = try Instructions.deocdeRegisters(data)
        let value: UInt64 = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        self.init(ra: ra, rb: rb, value: value)
    }

    public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
        let regVal: UInt64 = context.state.readRegister(rb)
        context.state.writeRegister(ra, regVal < value ? 1 : 0)
        return .continued
    }
}

extension CppHelper.Instructions.SetLtSImm: Instruction {
    public init(data: Data) throws {
        let (ra, rb) = try Instructions.deocdeRegisters(data)
        let value: UInt64 = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        self.init(ra: ra, rb: rb, value: value)
    }

    public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
        let regVal: UInt64 = context.state.readRegister(rb)
        context.state.writeRegister(ra, Int64(bitPattern: regVal) < Int64(bitPattern: value) ? 1 : 0)
        return .continued
    }
}

extension CppHelper.Instructions.ShloLImm32: Instruction {
    public init(data: Data) throws {
        let (ra, rb) = try Instructions.deocdeRegisters(data)
        let value: UInt32 = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        self.init(ra: ra, rb: rb, value: value)
    }

    public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
        let regVal: UInt32 = context.state.readRegister(rb)
        let shift = value & 0x1F
        context.state.writeRegister(ra, Int32(bitPattern: regVal << shift))
        return .continued
    }
}

extension CppHelper.Instructions.ShloRImm32: Instruction {
    public init(data: Data) throws {
        let (ra, rb) = try Instructions.deocdeRegisters(data)
        let value: UInt32 = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        self.init(ra: ra, rb: rb, value: value)
    }

    public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
        let regVal: UInt32 = context.state.readRegister(rb)
        let shift = value & 0x1F
        context.state.writeRegister(ra, Int32(bitPattern: regVal >> shift))
        return .continued
    }
}

extension CppHelper.Instructions.SharRImm32: Instruction {
    public init(data: Data) throws {
        let (ra, rb) = try Instructions.deocdeRegisters(data)
        let value: UInt32 = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        self.init(ra: ra, rb: rb, value: value)
    }

    public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
        let regVal: UInt32 = context.state.readRegister(rb)
        let shift = value & 0x1F
        context.state.writeRegister(ra, Int32(bitPattern: regVal) >> shift)
        return .continued
    }
}

extension CppHelper.Instructions.NegAddImm32: Instruction {
    public init(data: Data) throws {
        let (ra, rb) = try Instructions.deocdeRegisters(data)
        let value: UInt32 = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        self.init(ra: ra, rb: rb, value: value)
    }

    public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
        let regVal: UInt32 = context.state.readRegister(rb)
        context.state.writeRegister(ra, Int32(bitPattern: value &- regVal))
        return .continued
    }
}

extension CppHelper.Instructions.SetGtUImm: Instruction {
    public init(data: Data) throws {
        let (ra, rb) = try Instructions.deocdeRegisters(data)
        let value: UInt64 = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        self.init(ra: ra, rb: rb, value: value)
    }

    public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
        let regVal: UInt64 = context.state.readRegister(rb)
        context.state.writeRegister(ra, regVal > value ? 1 : 0)
        return .continued
    }
}

extension CppHelper.Instructions.SetGtSImm: Instruction {
    public init(data: Data) throws {
        let (ra, rb) = try Instructions.deocdeRegisters(data)
        let value: UInt64 = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        self.init(ra: ra, rb: rb, value: value)
    }

    public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
        let regVal: UInt64 = context.state.readRegister(rb)
        context.state.writeRegister(ra, Int64(bitPattern: regVal) > Int64(bitPattern: value) ? 1 : 0)
        return .continued
    }
}

extension CppHelper.Instructions.ShloLImmAlt32: Instruction {
    public init(data: Data) throws {
        let (ra, rb) = try Instructions.deocdeRegisters(data)
        let value: UInt32 = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        self.init(ra: ra, rb: rb, value: value)
    }

    public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
        let regVal: UInt32 = context.state.readRegister(rb)
        let shift = regVal & 0x1F
        context.state.writeRegister(ra, Int32(bitPattern: value << shift))
        return .continued
    }
}

extension CppHelper.Instructions.ShloRImmAlt32: Instruction {
    public init(data: Data) throws {
        let (ra, rb) = try Instructions.deocdeRegisters(data)
        let value: UInt32 = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        self.init(ra: ra, rb: rb, value: value)
    }

    public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
        let regVal: UInt32 = context.state.readRegister(rb)
        let shift = regVal & 0x1F
        context.state.writeRegister(ra, Int32(bitPattern: value >> shift))
        return .continued
    }
}

extension CppHelper.Instructions.SharRImmAlt32: Instruction {
    public init(data: Data) throws {
        let (ra, rb) = try Instructions.deocdeRegisters(data)
        let value: UInt32 = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        self.init(ra: ra, rb: rb, value: value)
    }

    public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
        let regVal: UInt32 = context.state.readRegister(rb)
        let shift = regVal & 0x1F
        context.state.writeRegister(ra, Int32(bitPattern: value) >> shift)
        return .continued
    }
}

extension CppHelper.Instructions.CmovIzImm: Instruction {
    public init(data: Data) throws {
        let (ra, rb) = try Instructions.deocdeRegisters(data)
        let value: UInt64 = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        self.init(ra: ra, rb: rb, value: value)
    }

    public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
        let rbVal: UInt64 = context.state.readRegister(rb)
        if rbVal == 0 {
            context.state.writeRegister(ra, value)
        }
        return .continued
    }
}

extension CppHelper.Instructions.CmovNzImm: Instruction {
    public init(data: Data) throws {
        let (ra, rb) = try Instructions.deocdeRegisters(data)
        let value: UInt64 = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        self.init(ra: ra, rb: rb, value: value)
    }

    public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
        let regVal: UInt64 = context.state.readRegister(rb)
        context.state.writeRegister(ra, regVal != 0 ? value : regVal)
        return .continued
    }
}

extension CppHelper.Instructions.AddImm64: Instruction {
    public init(data: Data) throws {
        let (ra, rb) = try Instructions.deocdeRegisters(data)
        let value: UInt64 = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        self.init(ra: ra, rb: rb, value: value)
    }

    public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
        let regVal: UInt64 = context.state.readRegister(rb)
        context.state.writeRegister(ra, regVal &+ value)
        return .continued
    }
}

extension CppHelper.Instructions.MulImm64: Instruction {
    public init(data: Data) throws {
        let (ra, rb) = try Instructions.deocdeRegisters(data)
        let value: UInt64 = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        self.init(ra: ra, rb: rb, value: value)
    }

    public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
        let regVal: UInt64 = context.state.readRegister(rb)
        context.state.writeRegister(ra, regVal &* value)
        return .continued
    }
}

extension CppHelper.Instructions.ShloLImm64: Instruction {
    public init(data: Data) throws {
        let (ra, rb) = try Instructions.deocdeRegisters(data)
        let value: UInt64 = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        self.init(ra: ra, rb: rb, value: value)
    }

    public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
        let regVal: UInt64 = context.state.readRegister(rb)
        let shift = value & 0x3F
        context.state.writeRegister(ra, Int64(bitPattern: regVal << shift))
        return .continued
    }
}

extension CppHelper.Instructions.ShloRImm64: Instruction {
    public init(data: Data) throws {
        let (ra, rb) = try Instructions.deocdeRegisters(data)
        let value: UInt64 = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        self.init(ra: ra, rb: rb, value: value)
    }

    public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
        let regVal: UInt64 = context.state.readRegister(rb)
        let shift = value & 0x3F
        context.state.writeRegister(ra, Int64(bitPattern: regVal >> shift))
        return .continued
    }
}

extension CppHelper.Instructions.SharRImm64: Instruction {
    public init(data: Data) throws {
        let (ra, rb) = try Instructions.deocdeRegisters(data)
        let value: UInt64 = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        self.init(ra: ra, rb: rb, value: value)
    }

    public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
        let regVal: UInt64 = context.state.readRegister(rb)
        let shift = value & 0x3F
        context.state.writeRegister(ra, Int64(bitPattern: regVal) >> shift)
        return .continued
    }
}

extension CppHelper.Instructions.NegAddImm64: Instruction {
    public init(data: Data) throws {
        let (ra, rb) = try Instructions.deocdeRegisters(data)
        let value: UInt64 = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        self.init(ra: ra, rb: rb, value: value)
    }

    public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
        let regVal: UInt64 = context.state.readRegister(rb)
        context.state.writeRegister(ra, value &- regVal)
        return .continued
    }
}

extension CppHelper.Instructions.ShloLImmAlt64: Instruction {
    public init(data: Data) throws {
        let (ra, rb) = try Instructions.deocdeRegisters(data)
        let value: UInt64 = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        self.init(ra: ra, rb: rb, value: value)
    }

    public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
        let regVal: UInt64 = context.state.readRegister(rb)
        let shift = regVal & 0x3F
        context.state.writeRegister(ra, UInt64(truncatingIfNeeded: value << shift))
        return .continued
    }
}

extension CppHelper.Instructions.ShloRImmAlt64: Instruction {
    public init(data: Data) throws {
        let (ra, rb) = try Instructions.deocdeRegisters(data)
        let value: UInt64 = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        self.init(ra: ra, rb: rb, value: value)
    }

    public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
        let regVal: UInt64 = context.state.readRegister(rb)
        let shift = regVal & 0x3F
        context.state.writeRegister(ra, value >> shift)
        return .continued
    }
}

extension CppHelper.Instructions.SharRImmAlt64: Instruction {
    public init(data: Data) throws {
        let (ra, rb) = try Instructions.deocdeRegisters(data)
        let value: UInt64 = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        self.init(ra: ra, rb: rb, value: value)
    }

    public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
        let regVal: UInt64 = context.state.readRegister(rb)
        let shift = regVal & 0x3F
        context.state.writeRegister(ra, Int64(bitPattern: value) >> shift)
        return .continued
    }
}

extension CppHelper.Instructions.RotR64Imm: Instruction {
    public init(data: Data) throws {
        let (ra, rb) = try Instructions.deocdeRegisters(data)
        let value: UInt64 = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        self.init(ra: ra, rb: rb, value: value)
    }

    public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
        let rbVal: UInt64 = context.state.readRegister(rb)
        context.state.writeRegister(ra, rbVal.rotated(right: value))
        return .continued
    }
}

extension CppHelper.Instructions.RotR64ImmAlt: Instruction {
    public init(data: Data) throws {
        let (ra, rb) = try Instructions.deocdeRegisters(data)
        let value: UInt64 = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        self.init(ra: ra, rb: rb, value: value)
    }

    public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
        let rbVal: UInt64 = context.state.readRegister(rb)
        context.state.writeRegister(ra, value.rotated(right: rbVal))
        return .continued
    }
}

extension CppHelper.Instructions.RotR32Imm: Instruction {
    public init(data: Data) throws {
        let (ra, rb) = try Instructions.deocdeRegisters(data)
        let value: UInt32 = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        self.init(ra: ra, rb: rb, value: value)
    }

    public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
        let rbVal: UInt32 = context.state.readRegister(rb)
        context.state.writeRegister(ra, Int32(bitPattern: rbVal.rotated(right: value)))
        return .continued
    }
}

extension CppHelper.Instructions.RotR32ImmAlt: Instruction {
    public init(data: Data) throws {
        let (ra, rb) = try Instructions.deocdeRegisters(data)
        let value: UInt32 = Instructions.decodeImmediate((try? data.at(relative: 1...)) ?? Data())
        self.init(ra: ra, rb: rb, value: value)
    }

    public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
        let rbVal: UInt32 = context.state.readRegister(rb)
        context.state.writeRegister(ra, Int32(bitPattern: value.rotated(right: rbVal)))
        return .continued
    }
}

extension CppHelper.Instructions.BranchEq: BranchInstructionBase2 {
    public var r1: Registers.Index {
        get { reg1 }
        set { reg1 = newValue }
    }

    public var r2: Registers.Index {
        get { reg2 }
        set { reg2 = newValue }
    }

    typealias Compare = CompareEq
    public init(data: Data) throws {
        let (r1, r2, offset) = try Self.parse(data: data)
        self.init(reg1: r1, reg2: r2, offset: offset)
    }
}

extension CppHelper.Instructions.BranchNe: BranchInstructionBase2 {
    public var r1: Registers.Index {
        get { reg1 }
        set { reg1 = newValue }
    }

    public var r2: Registers.Index {
        get { reg2 }
        set { reg2 = newValue }
    }

    typealias Compare = CompareNe
    public init(data: Data) throws {
        let (r1, r2, offset) = try Self.parse(data: data)
        self.init(reg1: r1, reg2: r2, offset: offset)
    }
}

extension CppHelper.Instructions.BranchLtU: BranchInstructionBase2 {
    public var r1: Registers.Index {
        get { reg1 }
        set { reg1 = newValue }
    }

    public var r2: Registers.Index {
        get { reg2 }
        set { reg2 = newValue }
    }

    typealias Compare = CompareLtU
    public init(data: Data) throws {
        let (r1, r2, offset) = try Self.parse(data: data)
        self.init(reg1: r1, reg2: r2, offset: offset)
    }
}

extension CppHelper.Instructions.BranchLtS: BranchInstructionBase2 {
    public var r1: Registers.Index {
        get { reg1 }
        set { reg1 = newValue }
    }

    public var r2: Registers.Index {
        get { reg2 }
        set { reg2 = newValue }
    }

    typealias Compare = CompareLtS
    public init(data: Data) throws {
        let (r1, r2, offset) = try Self.parse(data: data)
        self.init(reg1: r1, reg2: r2, offset: offset)
    }
}

extension CppHelper.Instructions.BranchGeU: BranchInstructionBase2 {
    public var r1: Registers.Index {
        get { reg1 }
        set { reg1 = newValue }
    }

    public var r2: Registers.Index {
        get { reg2 }
        set { reg2 = newValue }
    }

    typealias Compare = CompareGeU
    public init(data: Data) throws {
        let (r1, r2, offset) = try Self.parse(data: data)
        self.init(reg1: r1, reg2: r2, offset: offset)
    }
}

extension CppHelper.Instructions.BranchGeS: BranchInstructionBase2 {
    public var r1: Registers.Index {
        get { reg1 }
        set { reg1 = newValue }
    }

    public var r2: Registers.Index {
        get { reg2 }
        set { reg2 = newValue }
    }

    typealias Compare = CompareGeS
    public init(data: Data) throws {
        let (r1, r2, offset) = try Self.parse(data: data)
        self.init(reg1: r1, reg2: r2, offset: offset)
    }
}

extension CppHelper.Instructions.LoadImmJumpInd: Instruction {
    public init(data: Data) throws {
        let (ra, rb) = try Instructions.deocdeRegisters(data)
        let (value, offset): (UInt32, UInt32) = try Instructions.decodeImmediate2(data, minus: 2, startIdx: 1)
        self.init(ra: ra, rb: rb, value: value, offset: offset)
    }

    public func _executeImpl(context: ExecutionContext) throws -> ExecOutcome {
        // need to read rb value first in case ra and rb are the same
        let rbVal: UInt32 = context.state.readRegister(rb)

        context.state.writeRegister(ra, value)

        return Instructions.djump(context: context, target: rbVal &+ offset)
    }

    public func updatePC(context _: ExecutionContext, skip _: UInt32) -> ExecOutcome {
        .continued
    }
}

extension CppHelper.Instructions.Add32: Instruction {
    public init(data: Data) throws {
        let (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        self.init(ra: ra, rb: rb, rd: rd)
    }

    public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
        let (raVal, rbVal): (UInt32, UInt32) = context.state.readRegister(ra, rb)
        context.state.writeRegister(rd, Int32(bitPattern: raVal &+ rbVal))
        return .continued
    }
}

extension CppHelper.Instructions.Sub32: Instruction {
    public init(data: Data) throws {
        let (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        self.init(ra: ra, rb: rb, rd: rd)
    }

    public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
        let (raVal, rbVal): (UInt32, UInt32) = context.state.readRegister(ra, rb)
        context.state.writeRegister(rd, Int32(bitPattern: raVal &- rbVal))
        return .continued
    }
}

extension CppHelper.Instructions.Mul32: Instruction {
    public init(data: Data) throws {
        let (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        self.init(ra: ra, rb: rb, rd: rd)
    }

    public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
        let (raVal, rbVal): (UInt32, UInt32) = context.state.readRegister(ra, rb)
        context.state.writeRegister(rd, Int32(bitPattern: raVal &* rbVal))
        return .continued
    }
}

extension CppHelper.Instructions.DivU32: Instruction {
    public init(data: Data) throws {
        let (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        self.init(ra: ra, rb: rb, rd: rd)
    }

    public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
        let (raVal, rbVal): (UInt32, UInt32) = context.state.readRegister(ra, rb)
        if rbVal == 0 {
            context.state.writeRegister(rd, UInt64.max)
        } else {
            context.state.writeRegister(rd, Int32(bitPattern: raVal / rbVal))
        }
        return .continued
    }
}

extension CppHelper.Instructions.DivS32: Instruction {
    public init(data: Data) throws {
        let (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        self.init(ra: ra, rb: rb, rd: rd)
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

extension CppHelper.Instructions.RemU32: Instruction {
    public init(data: Data) throws {
        let (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        self.init(ra: ra, rb: rb, rd: rd)
    }

    public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
        let (raVal, rbVal): (UInt32, UInt32) = context.state.readRegister(ra, rb)
        if rbVal == 0 {
            context.state.writeRegister(rd, Int32(bitPattern: raVal))
        } else {
            context.state.writeRegister(rd, Int32(bitPattern: raVal % rbVal))
        }
        return .continued
    }
}

extension CppHelper.Instructions.RemS32: Instruction {
    public init(data: Data) throws {
        let (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        self.init(ra: ra, rb: rb, rd: rd)
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

extension CppHelper.Instructions.ShloL32: Instruction {
    public init(data: Data) throws {
        let (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        self.init(ra: ra, rb: rb, rd: rd)
    }

    public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
        let (raVal, rbVal): (UInt32, UInt32) = context.state.readRegister(ra, rb)
        let shift = rbVal & 0x1F
        context.state.writeRegister(rd, Int32(bitPattern: raVal << shift))
        return .continued
    }
}

extension CppHelper.Instructions.ShloR32: Instruction {
    public init(data: Data) throws {
        let (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        self.init(ra: ra, rb: rb, rd: rd)
    }

    public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
        let (raVal, rbVal): (UInt32, UInt32) = context.state.readRegister(ra, rb)
        let shift = rbVal & 0x1F
        context.state.writeRegister(rd, Int32(bitPattern: raVal >> shift))
        return .continued
    }
}

extension CppHelper.Instructions.SharR32: Instruction {
    public init(data: Data) throws {
        let (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        self.init(ra: ra, rb: rb, rd: rd)
    }

    public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
        let (raVal, rbVal): (UInt32, UInt32) = context.state.readRegister(ra, rb)
        let shift = rbVal & 0x1F
        context.state.writeRegister(rd, Int32(bitPattern: raVal) >> shift)
        return .continued
    }
}

extension CppHelper.Instructions.Add64: Instruction {
    public init(data: Data) throws {
        let (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        self.init(ra: ra, rb: rb, rd: rd)
    }

    public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
        let (raVal, rbVal): (UInt64, UInt64) = context.state.readRegister(ra, rb)
        context.state.writeRegister(rd, raVal &+ rbVal)
        return .continued
    }
}

extension CppHelper.Instructions.Sub64: Instruction {
    public init(data: Data) throws {
        let (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        self.init(ra: ra, rb: rb, rd: rd)
    }

    public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
        let (raVal, rbVal): (UInt64, UInt64) = context.state.readRegister(ra, rb)
        context.state.writeRegister(rd, raVal &- rbVal)
        return .continued
    }
}

extension CppHelper.Instructions.Mul64: Instruction {
    public init(data: Data) throws {
        let (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        self.init(ra: ra, rb: rb, rd: rd)
    }

    public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
        let (raVal, rbVal): (UInt64, UInt64) = context.state.readRegister(ra, rb)
        context.state.writeRegister(rd, raVal &* rbVal)
        return .continued
    }
}

extension CppHelper.Instructions.DivU64: Instruction {
    public init(data: Data) throws {
        let (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        self.init(ra: ra, rb: rb, rd: rd)
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

extension CppHelper.Instructions.DivS64: Instruction {
    public init(data: Data) throws {
        let (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        self.init(ra: ra, rb: rb, rd: rd)
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

extension CppHelper.Instructions.RemU64: Instruction {
    public init(data: Data) throws {
        let (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        self.init(ra: ra, rb: rb, rd: rd)
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

extension CppHelper.Instructions.RemS64: Instruction {
    public init(data: Data) throws {
        let (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        self.init(ra: ra, rb: rb, rd: rd)
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

extension CppHelper.Instructions.ShloL64: Instruction {
    public init(data: Data) throws {
        let (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        self.init(ra: ra, rb: rb, rd: rd)
    }

    public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
        let (raVal, rbVal): (UInt64, UInt64) = context.state.readRegister(ra, rb)
        let shift = rbVal & 0x3F
        context.state.writeRegister(rd, UInt64(truncatingIfNeeded: raVal << shift))
        return .continued
    }
}

extension CppHelper.Instructions.ShloR64: Instruction {
    public init(data: Data) throws {
        let (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        self.init(ra: ra, rb: rb, rd: rd)
    }

    public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
        let (raVal, rbVal): (UInt64, UInt64) = context.state.readRegister(ra, rb)
        let shift = rbVal & 0x3F
        context.state.writeRegister(rd, raVal >> shift)
        return .continued
    }
}

extension CppHelper.Instructions.SharR64: Instruction {
    public init(data: Data) throws {
        let (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        self.init(ra: ra, rb: rb, rd: rd)
    }

    public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
        let (raVal, rbVal): (UInt64, UInt64) = context.state.readRegister(ra, rb)
        let shift = rbVal & 0x3F
        context.state.writeRegister(rd, Int64(bitPattern: raVal) >> shift)
        return .continued
    }
}

extension CppHelper.Instructions.And: Instruction {
    public init(data: Data) throws {
        let (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        self.init(ra: ra, rb: rb, rd: rd)
    }

    public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
        let (raVal, rbVal): (UInt64, UInt64) = context.state.readRegister(ra, rb)
        context.state.writeRegister(rd, raVal & rbVal)
        return .continued
    }
}

extension CppHelper.Instructions.Xor: Instruction {
    public init(data: Data) throws {
        let (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        self.init(ra: ra, rb: rb, rd: rd)
    }

    public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
        let (raVal, rbVal): (UInt64, UInt64) = context.state.readRegister(ra, rb)
        context.state.writeRegister(rd, raVal ^ rbVal)
        return .continued
    }
}

extension CppHelper.Instructions.Or: Instruction {
    public init(data: Data) throws {
        let (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        self.init(ra: ra, rb: rb, rd: rd)
    }

    public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
        let (raVal, rbVal): (UInt64, UInt64) = context.state.readRegister(ra, rb)
        context.state.writeRegister(rd, raVal | rbVal)
        return .continued
    }
}

extension CppHelper.Instructions.MulUpperSS: Instruction {
    public init(data: Data) throws {
        let (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        self.init(ra: ra, rb: rb, rd: rd)
    }

    public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
        let (raVal, rbVal): (UInt64, UInt64) = context.state.readRegister(ra, rb)
        let a = Int128(Int64(bitPattern: raVal))
        let b = Int128(Int64(bitPattern: rbVal))
        context.state.writeRegister(rd, Int64(truncatingIfNeeded: (a * b) >> 64))
        return .continued
    }
}

extension CppHelper.Instructions.MulUpperUU: Instruction {
    public init(data: Data) throws {
        let (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        self.init(ra: ra, rb: rb, rd: rd)
    }

    public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
        let (raVal, rbVal): (UInt64, UInt64) = context.state.readRegister(ra, rb)
        context.state.writeRegister(rd, (UInt128(raVal) * UInt128(rbVal)) >> 64)
        return .continued
    }
}

extension CppHelper.Instructions.MulUpperSU: Instruction {
    public init(data: Data) throws {
        let (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        self.init(ra: ra, rb: rb, rd: rd)
    }

    public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
        let (raVal, rbVal): (UInt64, UInt64) = context.state.readRegister(ra, rb)
        let a = Int128(Int64(bitPattern: raVal))
        let b = Int128(rbVal)
        context.state.writeRegister(rd, Int64(truncatingIfNeeded: (a * b) >> 64))
        return .continued
    }
}

extension CppHelper.Instructions.SetLtU: Instruction {
    public init(data: Data) throws {
        let (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        self.init(ra: ra, rb: rb, rd: rd)
    }

    public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
        let (raVal, rbVal): (UInt64, UInt64) = context.state.readRegister(ra, rb)
        context.state.writeRegister(rd, raVal < rbVal ? 1 : 0)
        return .continued
    }
}

extension CppHelper.Instructions.SetLtS: Instruction {
    public init(data: Data) throws {
        let (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        self.init(ra: ra, rb: rb, rd: rd)
    }

    public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
        let (raVal, rbVal): (UInt64, UInt64) = context.state.readRegister(ra, rb)
        context.state.writeRegister(rd, Int64(bitPattern: raVal) < Int64(bitPattern: rbVal) ? 1 : 0)
        return .continued
    }
}

extension CppHelper.Instructions.CmovIz: Instruction {
    public init(data: Data) throws {
        let (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        self.init(ra: ra, rb: rb, rd: rd)
    }

    public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
        let (raVal, rbVal): (UInt64, UInt64) = context.state.readRegister(ra, rb)
        if rbVal == 0 {
            context.state.writeRegister(rd, raVal)
        }
        return .continued
    }
}

extension CppHelper.Instructions.CmovNz: Instruction {
    public init(data: Data) throws {
        let (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        self.init(ra: ra, rb: rb, rd: rd)
    }

    public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
        let (raVal, rbVal): (UInt64, UInt64) = context.state.readRegister(ra, rb)
        if rbVal != 0 {
            context.state.writeRegister(rd, raVal)
        }
        return .continued
    }
}

extension CppHelper.Instructions.RotL64: Instruction {
    public init(data: Data) throws {
        let (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        self.init(ra: ra, rb: rb, rd: rd)
    }

    public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
        let (raVal, rbVal): (UInt64, UInt64) = context.state.readRegister(ra, rb)
        context.state.writeRegister(rd, raVal.rotated(left: rbVal))
        return .continued
    }
}

extension CppHelper.Instructions.RotL32: Instruction {
    public init(data: Data) throws {
        let (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        self.init(ra: ra, rb: rb, rd: rd)
    }

    public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
        let (raVal, rbVal): (UInt32, UInt32) = context.state.readRegister(ra, rb)
        context.state.writeRegister(rd, Int32(bitPattern: raVal.rotated(left: rbVal)))
        return .continued
    }
}

extension CppHelper.Instructions.RotR64: Instruction {
    public init(data: Data) throws {
        let (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        self.init(ra: ra, rb: rb, rd: rd)
    }

    public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
        let (raVal, rbVal): (UInt64, UInt64) = context.state.readRegister(ra, rb)
        context.state.writeRegister(rd, raVal.rotated(right: rbVal))
        return .continued
    }
}

extension CppHelper.Instructions.RotR32: Instruction {
    public init(data: Data) throws {
        let (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        self.init(ra: ra, rb: rb, rd: rd)
    }

    public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
        let (raVal, rbVal): (UInt32, UInt32) = context.state.readRegister(ra, rb)
        context.state.writeRegister(rd, Int32(bitPattern: raVal.rotated(right: rbVal)))
        return .continued
    }
}

extension CppHelper.Instructions.AndInv: Instruction {
    public init(data: Data) throws {
        let (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        self.init(ra: ra, rb: rb, rd: rd)
    }

    public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
        let (raVal, rbVal): (UInt64, UInt64) = context.state.readRegister(ra, rb)
        context.state.writeRegister(rd, raVal & ~rbVal)
        return .continued
    }
}

extension CppHelper.Instructions.OrInv: Instruction {
    public init(data: Data) throws {
        let (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        self.init(ra: ra, rb: rb, rd: rd)
    }

    public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
        let (raVal, rbVal): (UInt64, UInt64) = context.state.readRegister(ra, rb)
        context.state.writeRegister(rd, raVal | ~rbVal)
        return .continued
    }
}

extension CppHelper.Instructions.Xnor: Instruction {
    public init(data: Data) throws {
        let (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        self.init(ra: ra, rb: rb, rd: rd)
    }

    public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
        let (raVal, rbVal): (UInt64, UInt64) = context.state.readRegister(ra, rb)
        context.state.writeRegister(rd, ~(raVal ^ rbVal))
        return .continued
    }
}

extension CppHelper.Instructions.Max: Instruction {
    public init(data: Data) throws {
        let (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        self.init(ra: ra, rb: rb, rd: rd)
    }

    public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
        let (raVal, rbVal): (UInt64, UInt64) = context.state.readRegister(ra, rb)
        context.state.writeRegister(rd, max(Int64(bitPattern: raVal), Int64(bitPattern: rbVal)))
        return .continued
    }
}

extension CppHelper.Instructions.MaxU: Instruction {
    public init(data: Data) throws {
        let (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        self.init(ra: ra, rb: rb, rd: rd)
    }

    public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
        let (raVal, rbVal): (UInt64, UInt64) = context.state.readRegister(ra, rb)
        context.state.writeRegister(rd, max(raVal, rbVal))
        return .continued
    }
}

extension CppHelper.Instructions.Min: Instruction {
    public init(data: Data) throws {
        let (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        self.init(ra: ra, rb: rb, rd: rd)
    }

    public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
        let (raVal, rbVal): (UInt64, UInt64) = context.state.readRegister(ra, rb)
        context.state.writeRegister(rd, min(Int64(bitPattern: raVal), Int64(bitPattern: rbVal)))
        return .continued
    }
}

extension CppHelper.Instructions.MinU: Instruction {
    public init(data: Data) throws {
        let (ra, rb, rd) = try Instructions.deocdeRegisters(data)
        self.init(ra: ra, rb: rb, rd: rd)
    }

    public func _executeImpl(context: ExecutionContext) -> ExecOutcome {
        let (raVal, rbVal): (UInt64, UInt64) = context.state.readRegister(ra, rb)
        context.state.writeRegister(rd, min(raVal, rbVal))
        return .continued
    }
}

public enum Instructions {
    // MARK: Instructions without Arguments (5.1)

    public typealias Trap = CppHelper.Instructions.Trap

    public typealias Fallthrough = CppHelper.Instructions.Fallthrough

    // MARK: Instructions with Arguments of One Immediate (5.2)

    public typealias Ecalli = CppHelper.Instructions.Ecalli

    // MARK: Instructions with Arguments of One Register and One Extended Width Immediate (5.3)

    public typealias LoadImm64 = CppHelper.Instructions.LoadImm64

    // MARK: Instructions with Arguments of Two Immediates (5.4)

    public typealias StoreImmU8 = CppHelper.Instructions.StoreImmU8
    public typealias StoreImmU16 = CppHelper.Instructions.StoreImmU16
    public typealias StoreImmU32 = CppHelper.Instructions.StoreImmU32
    public typealias StoreImmU64 = CppHelper.Instructions.StoreImmU64

    // MARK: Instructions with Arguments of One Offset (5.5)

    public typealias Jump = CppHelper.Instructions.Jump

    // MARK: Instructions with Arguments of One Register & One Immediate (5.6)

    public typealias JumpInd = CppHelper.Instructions.JumpInd
    public typealias LoadImm = CppHelper.Instructions.LoadImm
    public typealias LoadU8 = CppHelper.Instructions.LoadU8
    public typealias LoadI8 = CppHelper.Instructions.LoadI8
    public typealias LoadU16 = CppHelper.Instructions.LoadU16
    public typealias LoadI16 = CppHelper.Instructions.LoadI16
    public typealias LoadU32 = CppHelper.Instructions.LoadU32
    public typealias LoadI32 = CppHelper.Instructions.LoadI32
    public typealias LoadU64 = CppHelper.Instructions.LoadU64
    public typealias StoreU8 = CppHelper.Instructions.StoreU8
    public typealias StoreU16 = CppHelper.Instructions.StoreU16
    public typealias StoreU32 = CppHelper.Instructions.StoreU32
    public typealias StoreU64 = CppHelper.Instructions.StoreU64

    // MARK: Instructions with Arguments of One Register & Two Immediates (5.7)

    public typealias StoreImmIndU8 = CppHelper.Instructions.StoreImmIndU8
    public typealias StoreImmIndU16 = CppHelper.Instructions.StoreImmIndU16
    public typealias StoreImmIndU32 = CppHelper.Instructions.StoreImmIndU32
    public typealias StoreImmIndU64 = CppHelper.Instructions.StoreImmIndU64

    // MARK: Instructions with Arguments of One Register, One Immediate and One Offset (5.8)

    public typealias LoadImmJump = CppHelper.Instructions.LoadImmJump
    public typealias BranchEqImm = CppHelper.Instructions.BranchEqImm
    public typealias BranchNeImm = CppHelper.Instructions.BranchNeImm
    public typealias BranchLtUImm = CppHelper.Instructions.BranchLtUImm
    public typealias BranchLeUImm = CppHelper.Instructions.BranchLeUImm
    public typealias BranchGeUImm = CppHelper.Instructions.BranchGeUImm
    public typealias BranchGtUImm = CppHelper.Instructions.BranchGtUImm
    public typealias BranchLtSImm = CppHelper.Instructions.BranchLtSImm
    public typealias BranchLeSImm = CppHelper.Instructions.BranchLeSImm
    public typealias BranchGeSImm = CppHelper.Instructions.BranchGeSImm
    public typealias BranchGtSImm = CppHelper.Instructions.BranchGtSImm

    // MARK: Instructions with Arguments of Two Registers (5.9)

    public typealias MoveReg = CppHelper.Instructions.MoveReg
    public typealias Sbrk = CppHelper.Instructions.Sbrk
    public typealias CountSetBits64 = CppHelper.Instructions.CountSetBits64
    public typealias CountSetBits32 = CppHelper.Instructions.CountSetBits32
    public typealias LeadingZeroBits64 = CppHelper.Instructions.LeadingZeroBits64
    public typealias LeadingZeroBits32 = CppHelper.Instructions.LeadingZeroBits32
    public typealias TrailingZeroBits64 = CppHelper.Instructions.TrailingZeroBits64
    public typealias TrailingZeroBits32 = CppHelper.Instructions.TrailingZeroBits32
    public typealias SignExtend8 = CppHelper.Instructions.SignExtend8
    public typealias SignExtend16 = CppHelper.Instructions.SignExtend16
    public typealias ZeroExtend16 = CppHelper.Instructions.ZeroExtend16
    public typealias ReverseBytes = CppHelper.Instructions.ReverseBytes

    // MARK: Instructions with Arguments of Two Registers & One Immediate (5.10)

    public typealias StoreIndU8 = CppHelper.Instructions.StoreIndU8
    public typealias StoreIndU16 = CppHelper.Instructions.StoreIndU16
    public typealias StoreIndU32 = CppHelper.Instructions.StoreIndU32
    public typealias StoreIndU64 = CppHelper.Instructions.StoreIndU64
    public typealias LoadIndU8 = CppHelper.Instructions.LoadIndU8
    public typealias LoadIndI8 = CppHelper.Instructions.LoadIndI8
    public typealias LoadIndU16 = CppHelper.Instructions.LoadIndU16
    public typealias LoadIndI16 = CppHelper.Instructions.LoadIndI16
    public typealias LoadIndU32 = CppHelper.Instructions.LoadIndU32
    public typealias LoadIndI32 = CppHelper.Instructions.LoadIndI32
    public typealias LoadIndU64 = CppHelper.Instructions.LoadIndU64
    public typealias AddImm32 = CppHelper.Instructions.AddImm32
    public typealias AndImm = CppHelper.Instructions.AndImm
    public typealias XorImm = CppHelper.Instructions.XorImm
    public typealias OrImm = CppHelper.Instructions.OrImm
    public typealias MulImm32 = CppHelper.Instructions.MulImm32
    public typealias SetLtUImm = CppHelper.Instructions.SetLtUImm
    public typealias SetLtSImm = CppHelper.Instructions.SetLtSImm
    public typealias ShloLImm32 = CppHelper.Instructions.ShloLImm32
    public typealias ShloRImm32 = CppHelper.Instructions.ShloRImm32
    public typealias SharRImm32 = CppHelper.Instructions.SharRImm32
    public typealias NegAddImm32 = CppHelper.Instructions.NegAddImm32
    public typealias SetGtUImm = CppHelper.Instructions.SetGtUImm
    public typealias SetGtSImm = CppHelper.Instructions.SetGtSImm
    public typealias ShloLImmAlt32 = CppHelper.Instructions.ShloLImmAlt32
    public typealias ShloRImmAlt32 = CppHelper.Instructions.ShloRImmAlt32
    public typealias SharRImmAlt32 = CppHelper.Instructions.SharRImmAlt32
    public typealias CmovIzImm = CppHelper.Instructions.CmovIzImm
    public typealias CmovNzImm = CppHelper.Instructions.CmovNzImm
    public typealias AddImm64 = CppHelper.Instructions.AddImm64
    public typealias MulImm64 = CppHelper.Instructions.MulImm64
    public typealias ShloLImm64 = CppHelper.Instructions.ShloLImm64
    public typealias ShloRImm64 = CppHelper.Instructions.ShloRImm64
    public typealias SharRImm64 = CppHelper.Instructions.SharRImm64
    public typealias NegAddImm64 = CppHelper.Instructions.NegAddImm64
    public typealias ShloLImmAlt64 = CppHelper.Instructions.ShloLImmAlt64
    public typealias ShloRImmAlt64 = CppHelper.Instructions.ShloRImmAlt64
    public typealias SharRImmAlt64 = CppHelper.Instructions.SharRImmAlt64
    public typealias RotR64Imm = CppHelper.Instructions.RotR64Imm
    public typealias RotR64ImmAlt = CppHelper.Instructions.RotR64ImmAlt
    public typealias RotR32Imm = CppHelper.Instructions.RotR32Imm
    public typealias RotR32ImmAlt = CppHelper.Instructions.RotR32ImmAlt

    // MARK: Instructions with Arguments of Two Registers & One Offset (5.11)

    public typealias BranchEq = CppHelper.Instructions.BranchEq
    public typealias BranchNe = CppHelper.Instructions.BranchNe
    public typealias BranchLtU = CppHelper.Instructions.BranchLtU
    public typealias BranchLtS = CppHelper.Instructions.BranchLtS
    public typealias BranchGeU = CppHelper.Instructions.BranchGeU
    public typealias BranchGeS = CppHelper.Instructions.BranchGeS

    // MARK: Instruction with Arguments of Two Registers and Two Immediates (5.12)

    public typealias LoadImmJumpInd = CppHelper.Instructions.LoadImmJumpInd

    // MARK: Instructions with Arguments of Three Registers (5.13)

    public typealias Add32 = CppHelper.Instructions.Add32
    public typealias Sub32 = CppHelper.Instructions.Sub32
    public typealias Mul32 = CppHelper.Instructions.Mul32
    public typealias DivU32 = CppHelper.Instructions.DivU32
    public typealias DivS32 = CppHelper.Instructions.DivS32
    public typealias RemU32 = CppHelper.Instructions.RemU32
    public typealias RemS32 = CppHelper.Instructions.RemS32
    public typealias ShloL32 = CppHelper.Instructions.ShloL32
    public typealias ShloR32 = CppHelper.Instructions.ShloR32
    public typealias SharR32 = CppHelper.Instructions.SharR32
    public typealias Add64 = CppHelper.Instructions.Add64
    public typealias Sub64 = CppHelper.Instructions.Sub64
    public typealias Mul64 = CppHelper.Instructions.Mul64
    public typealias DivU64 = CppHelper.Instructions.DivU64
    public typealias DivS64 = CppHelper.Instructions.DivS64
    public typealias RemU64 = CppHelper.Instructions.RemU64
    public typealias RemS64 = CppHelper.Instructions.RemS64
    public typealias ShloL64 = CppHelper.Instructions.ShloL64
    public typealias ShloR64 = CppHelper.Instructions.ShloR64
    public typealias SharR64 = CppHelper.Instructions.SharR64
    public typealias And = CppHelper.Instructions.And
    public typealias Xor = CppHelper.Instructions.Xor
    public typealias Or = CppHelper.Instructions.Or
    public typealias MulUpperSS = CppHelper.Instructions.MulUpperSS
    public typealias MulUpperUU = CppHelper.Instructions.MulUpperUU
    public typealias MulUpperSU = CppHelper.Instructions.MulUpperSU
    public typealias SetLtU = CppHelper.Instructions.SetLtU
    public typealias SetLtS = CppHelper.Instructions.SetLtS
    public typealias CmovIz = CppHelper.Instructions.CmovIz
    public typealias CmovNz = CppHelper.Instructions.CmovNz
    public typealias RotL64 = CppHelper.Instructions.RotL64
    public typealias RotL32 = CppHelper.Instructions.RotL32
    public typealias RotR64 = CppHelper.Instructions.RotR64
    public typealias RotR32 = CppHelper.Instructions.RotR32
    public typealias AndInv = CppHelper.Instructions.AndInv
    public typealias OrInv = CppHelper.Instructions.OrInv
    public typealias Xnor = CppHelper.Instructions.Xnor
    public typealias Max = CppHelper.Instructions.Max
    public typealias MaxU = CppHelper.Instructions.MaxU
    public typealias Min = CppHelper.Instructions.Min
    public typealias MinU = CppHelper.Instructions.MinU
}
