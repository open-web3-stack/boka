import Codec
import Foundation
import PolkaVM
import TracingUtils
import Utils

private let logger = Logger(label: "HostCalls.Refine")

// MARK: - Refine

/// Export a segment from memory
public class Export: HostCall {
    public static var identifier: UInt8 { 7 }

    public let context: RefineContext.ContextType
    public let exportSegmentOffset: UInt64

    public init(context: RefineContext.ContextType, exportSegmentOffset: UInt64) {
        self.context = context
        self.exportSegmentOffset = exportSegmentOffset
    }

    public func _callImpl(config: ProtocolConfigRef, state: VMState) async throws {
        let startAddr: UInt32 = state.readRegister(Registers.Index(raw: 7))
        let segmentSize = UInt64(config.value.segmentSize)
        let length = min(state.readRegister(Registers.Index(raw: 8)), segmentSize)
        let isReadable = state.isMemoryReadable(address: startAddr, length: Int(length))

        guard isReadable else {
            throw VMInvocationsError.panic
        }

        var data = try state.readMemory(address: startAddr, length: Int(length))
        let remainder = data.count % Int(segmentSize)
        if remainder != 0 {
            data.append(Data(repeating: 0, count: Int(segmentSize) - remainder))
        }
        let segment = Data4104(data)!

        if exportSegmentOffset + UInt64(context.exports.count) >= UInt64(config.value.maxWorkPackageImports) {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.FULL.rawValue)
        } else {
            state.writeRegister(Registers.Index(raw: 7), exportSegmentOffset + UInt64(context.exports.count))
            context.exports.append(segment)
        }
    }
}

/// Create an inner PVM
public class Machine: HostCall {
    public static var identifier: UInt8 { 8 }

    public let context: RefineContext.ContextType

    public init(context: RefineContext.ContextType) {
        self.context = context
    }

    public func _callImpl(config _: ProtocolConfigRef, state: VMState) async throws {
        let regs: [UInt32] = state.readRegisters(in: 7 ..< 10)

        let isReadable = state.isMemoryReadable(address: regs[0], length: Int(regs[1]))

        let max = context.pvms.keys.max() ?? 0
        var innerVmIndex: UInt64 = max + 1
        for i in 0 ..< max where context.pvms[i] == nil {
            innerVmIndex = i
            break
        }

        let code = isReadable ? try state.readMemory(address: regs[0], length: Int(regs[1])) : nil
        let pc = UInt32(truncatingIfNeeded: regs[2])
        let mem = try GeneralMemory(pageMap: [], chunks: [])

        guard let code else {
            throw VMInvocationsError.panic
        }

        if (try? ProgramCode(code)) == nil {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.HUH.rawValue)
        } else {
            state.writeRegister(Registers.Index(raw: 7), innerVmIndex)
            context.pvms[innerVmIndex] = InnerPvm(code: code, memory: mem, pc: pc)
        }
    }
}

/// Peek (read inner memory into outer memory)
public class Peek: HostCall {
    public static var identifier: UInt8 { 9 }

    public let context: RefineContext.ContextType

    public init(context: RefineContext.ContextType) {
        self.context = context
    }

    public func _callImpl(config _: ProtocolConfigRef, state: VMState) async throws {
        let regs: [UInt64] = state.readRegisters(in: 7 ..< 11)

        guard state.isMemoryWritable(address: regs[1], length: Int(regs[3])) else {
            throw VMInvocationsError.panic
        }

        if context.pvms[regs[0]] == nil {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.WHO.rawValue)
        } else if !context.pvms[regs[0]]!.memory.isReadable(address: UInt32(truncatingIfNeeded: regs[2]), length: Int(regs[3])) {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.OOB.rawValue)
        } else {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.OK.rawValue)
            let data = try context.pvms[regs[0]]!.memory.read(address: UInt32(truncatingIfNeeded: regs[2]), length: Int(regs[3]))
            try state.writeMemory(address: regs[1], values: data)
        }
    }
}

/// Poke (write outer memory into inner memory)
public class Poke: HostCall {
    public static var identifier: UInt8 { 10 }

    public let context: RefineContext.ContextType

    public init(context: RefineContext.ContextType) {
        self.context = context
    }

    public func _callImpl(config _: ProtocolConfigRef, state: VMState) async throws {
        let regs: [UInt64] = state.readRegisters(in: 7 ..< 11)

        guard state.isMemoryReadable(address: regs[1], length: Int(regs[3])) else {
            throw VMInvocationsError.panic
        }

        if context.pvms[regs[0]] == nil {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.WHO.rawValue)
        } else if !context.pvms[regs[0]]!.memory.isWritable(address: UInt32(truncatingIfNeeded: regs[2]), length: Int(regs[3])) {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.OOB.rawValue)
        } else {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.OK.rawValue)
            let data = try state.readMemory(address: regs[1], length: Int(regs[3]))
            try context.pvms[regs[0]]!.memory.write(address: UInt32(truncatingIfNeeded: regs[2]), values: data)
        }
    }
}

/// Modify pages in the inner PVM
public class Pages: HostCall {
    public static var identifier: UInt8 { 11 }

    public let context: RefineContext.ContextType

    public init(context: RefineContext.ContextType) {
        self.context = context
    }

    public func _callImpl(config: ProtocolConfigRef, state: VMState) async throws {
        let regs: [UInt64] = state.readRegisters(in: 7 ..< 11)

        if context.pvms[regs[0]] == nil {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.WHO.rawValue)
        } else if regs[3] > 4 || regs[1] < 16 ||
            (regs[1] + regs[2]) >= ((1 << 32) / UInt32(config.value.pvmMemoryPageSize))
        {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.HUH.rawValue)
        } else if regs[3] > 2,
                  !context.pvms[regs[0]]!.memory.isReadable(pageStart: UInt32(truncatingIfNeeded: regs[1]), pages: Int(regs[2]))
        {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.HUH.rawValue)
        } else {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.OK.rawValue)
            try context.pvms[regs[0]]!.memory.pages(
                pageIndex: UInt32(truncatingIfNeeded: regs[1]),
                pages: Int(regs[2]),
                variant: regs[3]
            )
        }
    }
}

/// Invoke an inner PVM
public class Invoke: HostCall {
    public static var identifier: UInt8 { 12 }

    public let context: RefineContext.ContextType

    public init(context: RefineContext.ContextType) {
        self.context = context
    }

    public func _callImpl(config _: ProtocolConfigRef, state: VMState) async throws {
        let pvmIndex: UInt64 = state.readRegister(Registers.Index(raw: 7))
        let startAddr: UInt32 = state.readRegister(Registers.Index(raw: 8))

        var gas: UInt64?
        var registers: [UInt64] = []
        if state.isMemoryReadable(address: startAddr, length: 112) {
            gas = try state.readMemory(address: startAddr, length: 8).decode(UInt64.self)
            for i in 0 ..< 13 {
                try registers.append(state.readMemory(address: startAddr + 8 + 8 * UInt32(i), length: 8).decode(UInt64.self))
            }
        }

        guard let gas else {
            throw VMInvocationsError.panic
        }

        guard let innerPvm = context.pvms[pvmIndex] else {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.WHO.rawValue)
            return
        }

        let program = try ProgramCode(innerPvm.code)
        let vm = VMStateInterpreter(
            program: program,
            pc: innerPvm.pc,
            registers: Registers(registers),
            gas: Gas(gas),
            memory: innerPvm.memory
        )
        let engine = Engine(config: DefaultPvmConfig())
        let exitReason = await engine.execute(state: vm)

        try state.writeMemory(address: startAddr, values: JamEncoder.encode(vm.getGas(), vm.getRegisters()))
        context.pvms[pvmIndex]?.memory = vm.getMemoryUnsafe()

        switch exitReason {
        case let .hostCall(callIndex):
            let skip = program.skip(innerPvm.pc)
            context.pvms[pvmIndex]?.pc = innerPvm.pc + skip + 1
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCodeInner.HOST.rawValue)
            state.writeRegister(Registers.Index(raw: 8), callIndex)
        case let .pageFault(addr):
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCodeInner.FAULT.rawValue)
            state.writeRegister(Registers.Index(raw: 8), addr)
        case .outOfGas:
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCodeInner.OOG.rawValue)
        case .panic:
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCodeInner.PANIC.rawValue)
        case .halt:
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCodeInner.HALT.rawValue)
        }
    }
}

/// Expunge an inner PVM
public class Expunge: HostCall {
    public static var identifier: UInt8 { 13 }

    public let context: RefineContext.ContextType

    public init(context: RefineContext.ContextType) {
        self.context = context
    }

    public func _callImpl(config _: ProtocolConfigRef, state: VMState) async throws {
        let reg7: UInt64 = state.readRegister(Registers.Index(raw: 7))

        if context.pvms[reg7] == nil {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.WHO.rawValue)
            return
        }

        state.writeRegister(Registers.Index(raw: 7), context.pvms[reg7]!.pc)
        context.pvms.removeValue(forKey: reg7)
    }
}
