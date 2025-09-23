import Codec
import Foundation
import PolkaVM
import TracingUtils
import Utils

private let logger = Logger(label: "HostCalls")

// MARK: - General

/// Get gas remaining
public class GasFn: HostCall {
    public static var identifier: UInt8 { 0 }

    public func _callImpl(config _: ProtocolConfigRef, state: VMState) async throws {
        state.writeRegister(Registers.Index(raw: 7), UInt64(bitPattern: state.getGas().value))
    }
}

/// Fetch
public class Fetch: HostCall {
    public static var identifier: UInt8 { 1 }

    public let serviceAccounts: ServiceAccountsRef?
    public let serviceIndex: ServiceIndex?

    // p
    public let workPackage: WorkPackage?
    // n
    public let entropy: Data32?
    // r
    public let authorizerTrace: Data?
    // i
    public let workItemIndex: Int?
    // overline i
    public let importSegments: [[Data4104]]?
    // overline x (no need pass in)
    // o
    public let operands: [OperandTuple]?
    // t
    public let transfers: [DeferredTransfers]?

    public init(
        serviceAccounts: ServiceAccountsRef? = nil,
        serviceIndex: ServiceIndex? = nil,
        workPackage: WorkPackage? = nil,
        entropy: Data32? = nil,
        authorizerTrace: Data? = nil,
        workItemIndex: Int? = nil,
        importSegments: [[Data4104]]? = nil,
        operands: [OperandTuple]? = nil,
        transfers: [DeferredTransfers]? = nil
    ) {
        self.serviceAccounts = serviceAccounts
        self.serviceIndex = serviceIndex
        self.workPackage = workPackage
        self.entropy = entropy
        self.authorizerTrace = authorizerTrace
        self.workItemIndex = workItemIndex
        self.importSegments = importSegments
        self.operands = operands
        self.transfers = transfers
    }

    private func getWorkItemMeta(item: WorkItem) throws -> Data {
        let encoder = JamEncoder(capacity: 4 + 32 + 8 + 8 + 2 + 2 + 2 + 4)
        try encoder.encode(item.serviceIndex)
        try encoder.encode(item.codeHash)
        try encoder.encode(item.refineGasLimit)
        try encoder.encode(item.accumulateGasLimit)
        try encoder.encode(item.exportsCount)
        try encoder.encode(UInt16(item.inputs.count))
        try encoder.encode(UInt16(item.outputs.count))
        try encoder.encode(UInt32(item.payloadBlob.count))
        return encoder.data
    }

    public func _callImpl(config: ProtocolConfigRef, state: VMState) async throws {
        let reg10: UInt64 = state.readRegister(Registers.Index(raw: 10))
        let reg11: UInt64 = state.readRegister(Registers.Index(raw: 11))
        let reg12: UInt64 = state.readRegister(Registers.Index(raw: 12))

        logger.debug("reg10: \(reg10), reg11: \(reg11), reg12: \(reg12)")

        var value: Data?
        switch reg10 {
        case 0:
            value = config.value.encoded
        case 1:
            if let entropy {
                value = entropy.data
            }
        case 2:
            if let authorizerTrace {
                value = authorizerTrace
            }
        case 3:
            if let workPackage, let serviceAccounts, reg11 < workPackage.workItems.count {
                let item = workPackage.workItems[Int(reg11)]
                let outputs = item.outputs
                if reg12 < outputs.count {
                    value = try await serviceAccounts.value.get(serviceAccount: item.serviceIndex, preimageHash: outputs[Int(reg12)].hash)
                }
            }
        case 4:
            if let workItemIndex, let workPackage, let serviceAccounts {
                let item = workPackage.workItems[workItemIndex]
                let outputs = item.outputs
                if reg11 < outputs.count {
                    value = try await serviceAccounts.value.get(serviceAccount: item.serviceIndex, preimageHash: outputs[Int(reg11)].hash)
                }
            }
        case 5:
            if let importSegments, reg11 < importSegments.count, reg12 < importSegments[Int(reg11)].count {
                value = importSegments[Int(reg11)][Int(reg12)].data
            }
        case 6:
            if let workItemIndex, let importSegments, reg11 < importSegments[workItemIndex].count {
                value = importSegments[workItemIndex][Int(reg11)].data
            }
        case 7:
            if let workPackage {
                value = try JamEncoder.encode(workPackage)
            }
        case 8:
            if let workPackage {
                value = try JamEncoder.encode(workPackage.authorizationCodeHash, workPackage.configurationBlob)
            }
        case 9:
            if let workPackage {
                value = workPackage.authorizationToken
            }
        case 10:
            if let workPackage {
                value = try JamEncoder.encode(workPackage.context)
            }
        case 11:
            if let workPackage {
                var arr: [Data] = []
                for item in workPackage.workItems {
                    let meta = try getWorkItemMeta(item: item)
                    arr.append(meta)
                }
                value = try JamEncoder.encode(arr)
            }
        case 12:
            if let workPackage, reg11 < workPackage.workItems.count {
                value = try getWorkItemMeta(item: workPackage.workItems[Int(reg11)])
            }
        case 13:
            if let workPackage, reg11 < workPackage.workItems.count {
                value = workPackage.workItems[Int(reg11)].payloadBlob
            }
        case 14:
            if let operands {
                value = try JamEncoder.encode(operands)
            }
        case 15:
            if let operands, reg11 < operands.count {
                value = try JamEncoder.encode(operands[Int(reg11)])
            }
        case 16:
            if let transfers {
                value = try JamEncoder.encode(transfers)
            }
        case 17:
            if let transfers, reg11 < transfers.count {
                value = try JamEncoder.encode(transfers[Int(reg11)])
            }
        default:
            value = nil
        }

        let writeAddr: UInt32 = state.readRegister(Registers.Index(raw: 7))

        let reg8: UInt64 = state.readRegister(Registers.Index(raw: 8))
        let reg9: UInt64 = state.readRegister(Registers.Index(raw: 9))

        let first = min(Int(reg8), value?.count ?? 0)
        let len = min(Int(reg9), (value?.count ?? 0) - first)

        logger.debug("writeAddr: \(writeAddr), first: \(first), len: \(len)")

        let isWritable = state.isMemoryWritable(address: writeAddr, length: len)

        logger.debug("isWritable: \(isWritable), value: \(value?.toDebugHexString() ?? "nil")")

        if !isWritable {
            throw VMInvocationsError.panic
        } else if let value {
            state.writeRegister(Registers.Index(raw: 7), value.count)
            try state.writeMemory(address: writeAddr, values: value[relative: first ..< (first + len)])
        } else {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.NONE.rawValue)
        }
    }
}

/// Lookup a preimage from a service account
public class Lookup: HostCall {
    public static var identifier: UInt8 { 2 }

    public let serviceIndex: ServiceIndex
    public let serviceAccounts: ServiceAccountsRef

    public init(serviceIndex: ServiceIndex, accounts: ServiceAccountsRef) {
        self.serviceIndex = serviceIndex
        serviceAccounts = accounts
    }

    public func _callImpl(config _: ProtocolConfigRef, state: VMState) async throws {
        let reg7: UInt64 = state.readRegister(Registers.Index(raw: 7))
        let service: ServiceIndex? = if reg7 == serviceIndex || reg7 == UInt64.max {
            serviceIndex
        } else if try await serviceAccounts.value.get(serviceAccount: ServiceIndex(truncatingIfNeeded: reg7)) != nil {
            ServiceIndex(truncatingIfNeeded: reg7)
        } else {
            nil
        }

        let regs: [UInt32] = state.readRegisters(in: 8 ..< 10)

        if !state.isMemoryReadable(address: regs[0], length: 32) {
            throw VMInvocationsError.panic
        }

        let preimageHash = try Data32(state.readMemory(address: regs[0], length: 32))
        logger.debug("preimageHash: \(String(describing: preimageHash))")

        let value: Data? = if let service, let preimageHash {
            try await serviceAccounts.value.get(serviceAccount: service, preimageHash: preimageHash)
        } else {
            nil
        }

        logger.debug("value: \(String(describing: value))")

        let reg10: UInt64 = state.readRegister(Registers.Index(raw: 10))
        let reg11: UInt64 = state.readRegister(Registers.Index(raw: 11))

        let first = min(Int(reg10), value?.count ?? 0)
        let len = min(Int(reg11), (value?.count ?? 0) - first)

        if !state.isMemoryWritable(address: regs[1], length: len) {
            throw VMInvocationsError.panic
        } else if let value {
            state.writeRegister(Registers.Index(raw: 7), value.count)
            try state.writeMemory(address: regs[1], values: value[relative: first ..< (first + len)])
        } else {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.NONE.rawValue)
        }
    }
}

/// Read a service account storage
public class Read: HostCall {
    public static var identifier: UInt8 { 3 }

    public let serviceIndex: ServiceIndex
    public let serviceAccounts: ServiceAccountsRef

    public init(serviceIndex: ServiceIndex, accounts: ServiceAccountsRef) {
        self.serviceIndex = serviceIndex
        serviceAccounts = accounts
    }

    public func _callImpl(config _: ProtocolConfigRef, state: VMState) async throws {
        let reg7: UInt64 = state.readRegister(Registers.Index(raw: 7))
        let serviceX = reg7 == UInt64.max ? serviceIndex : ServiceIndex(truncatingIfNeeded: reg7)

        let service: ServiceIndex? = if serviceX == serviceIndex {
            serviceIndex
        } else if try await serviceAccounts.value.get(serviceAccount: serviceX) != nil {
            serviceX
        } else {
            nil
        }

        logger.debug("service: \(service?.description ?? "nil")")

        let regs: [UInt32] = state.readRegisters(in: 8 ..< 11)

        if !state.isMemoryReadable(address: regs[0], length: Int(regs[1])) {
            throw VMInvocationsError.panic
        }

        let key = try state.readMemory(address: regs[0], length: Int(regs[1]))

        logger.debug("key: \(key.toHexString())")

        let value: Data? = if let service {
            try await serviceAccounts.value.get(serviceAccount: service, storageKey: key)
        } else {
            nil
        }

        guard let value else {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.NONE.rawValue)
            return
        }

        let reg11: UInt64 = state.readRegister(Registers.Index(raw: 11))
        let reg12: UInt64 = state.readRegister(Registers.Index(raw: 12))

        let first = min(Int(reg11), value.count)
        let len = min(Int(reg12), (value.count) - first)

        logger.debug("first: \(first), len: \(len)")

        if !state.isMemoryWritable(address: regs[2], length: len) {
            throw VMInvocationsError.panic
        } else {
            state.writeRegister(Registers.Index(raw: 7), value.count)
            logger.debug("val: \(value[relative: first ..< (first + len)].toDebugHexString())")
            try state.writeMemory(address: regs[2], values: value[relative: first ..< (first + len)])
        }
    }
}

/// Write to a service account storage
public class Write: HostCall {
    public static var identifier: UInt8 { 4 }

    public let serviceIndex: ServiceIndex
    public let serviceAccounts: ServiceAccountsMutRef

    public init(serviceIndex: ServiceIndex, accounts: ServiceAccountsMutRef) {
        self.serviceIndex = serviceIndex
        serviceAccounts = accounts
    }

    public func _callImpl(config: ProtocolConfigRef, state: VMState) async throws {
        let regs: [UInt32] = state.readRegisters(in: 7 ..< 11)

        if !state.isMemoryReadable(address: regs[0], length: Int(regs[1])) {
            throw VMInvocationsError.panic
        }

        logger.debug("regs: \(regs), service: \(serviceIndex)")

        let key = try state.readMemory(address: regs[0], length: Int(regs[1]))

        if regs[3] != 0, !state.isMemoryReadable(address: regs[2], length: Int(regs[3])) {
            throw VMInvocationsError.panic
        }

        logger.debug("key: \(key.toDebugHexString())")

        let accountDetails = try await serviceAccounts.value.get(serviceAccount: serviceIndex)

        guard var accountDetails else {
            throw VMInvocationsError.panic
        }

        let oldValue = try await serviceAccounts.value.get(serviceAccount: serviceIndex, storageKey: key)
        if regs[3] == 0 {
            accountDetails.updateFootprintStorage(key: key, oldValue: oldValue, newValue: nil)
        } else {
            let value = try state.readMemory(address: regs[2], length: Int(regs[3]))
            accountDetails.updateFootprintStorage(key: key, oldValue: oldValue, newValue: value)
        }

        if accountDetails.thresholdBalance(config: config) > accountDetails.balance {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.FULL.rawValue)
        } else {
            let l = if let value = try await serviceAccounts.value.get(serviceAccount: serviceIndex, storageKey: key) {
                UInt64(value.count)
            } else {
                HostCallResultCode.NONE.rawValue
            }
            logger.debug("l: \(l), is none: \(l == HostCallResultCode.NONE.rawValue)")
            state.writeRegister(Registers.Index(raw: 7), l)
            if regs[3] == 0 {
                logger.debug("deleting key: \(key.toDebugHexString())")
                try await serviceAccounts.set(serviceAccount: serviceIndex, storageKey: key, value: nil)
            } else {
                let value = try state.readMemory(address: regs[2], length: Int(regs[3]))
                logger.debug("writing key: \(key.toDebugHexString()), val: \(value.toDebugHexString()), len: \(value.count)")
                try await serviceAccounts.set(serviceAccount: serviceIndex, storageKey: key, value: value)
            }
        }
    }
}

/// Get information about a service account
public class Info: HostCall {
    public static var identifier: UInt8 { 5 }

    public let serviceIndex: ServiceIndex
    public let serviceAccounts: ServiceAccountsRef

    public init(serviceIndex: ServiceIndex, accounts: ServiceAccountsRef) {
        self.serviceIndex = serviceIndex
        serviceAccounts = accounts
    }

    public func _callImpl(config: ProtocolConfigRef, state: VMState) async throws {
        var service: ServiceIndex
        let reg: UInt64 = state.readRegister(Registers.Index(raw: 7))
        if reg == UInt64.max {
            service = serviceIndex
        } else {
            service = ServiceIndex(truncatingIfNeeded: reg)
        }

        let o: UInt32 = state.readRegister(Registers.Index(raw: 8))

        let value: Data?
        let account = try await serviceAccounts.value.get(serviceAccount: service)
        if let account {
            value = try JamEncoder.encode(
                account.codeHash,
                account.balance,
                account.thresholdBalance(config: config),
                account.minAccumlateGas,
                account.minOnTransferGas,
                account.totalByteLength,
                account.itemsCount,
                account.gratisStorage,
                account.createdAt,
                account.lastAccAt,
                account.parentService
            )
        } else {
            value = nil
        }

        let reg9: UInt64 = state.readRegister(Registers.Index(raw: 9))
        let reg10: UInt64 = state.readRegister(Registers.Index(raw: 10))
        let first = min(Int(reg9), value?.count ?? 0)
        let len = min(Int(reg10), (value?.count ?? 0) - first)

        let isWritable = value != nil && state.isMemoryWritable(address: o, length: len)

        logger.debug("value: \(value?.debugDescription ?? "nil"), isWritable: \(isWritable)")

        if !isWritable {
            throw VMInvocationsError.panic
        } else if let value {
            state.writeRegister(Registers.Index(raw: 7), value.count)
            logger.debug("writing addr: \(o), len: \(len), val: \(value[relative: first ..< (first + len)].toHexString())")
            try state.writeMemory(address: o, values: value[relative: first ..< (first + len)])
        } else {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.NONE.rawValue)
        }
    }
}

// MARK: - Refine

/// Historical lookup
public class HistoricalLookup: HostCall {
    public static var identifier: UInt8 { 6 }

    public let context: RefineContext.ContextType
    public let serviceIndex: ServiceIndex
    public let serviceAccounts: ServiceAccountsRef
    public let lookupAnchorTimeslot: TimeslotIndex

    public init(
        context: RefineContext.ContextType,
        serviceIndex: ServiceIndex,
        serviceAccounts: ServiceAccountsRef,
        lookupAnchorTimeslot: TimeslotIndex
    ) {
        self.context = context
        self.lookupAnchorTimeslot = lookupAnchorTimeslot
        self.serviceIndex = serviceIndex
        self.serviceAccounts = serviceAccounts
    }

    public func _callImpl(config _: ProtocolConfigRef, state: VMState) async throws {
        let reg7: UInt64 = state.readRegister(Registers.Index(raw: 7))
        let service: ServiceIndex? = if reg7 == UInt64.max, try await serviceAccounts.value.get(serviceAccount: serviceIndex) != nil {
            serviceIndex
        } else if try await serviceAccounts.value.get(serviceAccount: UInt32(truncatingIfNeeded: reg7)) != nil {
            UInt32(truncatingIfNeeded: reg7)
        } else {
            nil
        }

        guard let service else {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.NONE.rawValue)
            return
        }

        let regs: [UInt32] = state.readRegisters(in: 8 ..< 10)

        guard state.isMemoryReadable(address: regs[0], length: 32) else {
            throw VMInvocationsError.panic
        }

        let preimage = try await serviceAccounts.value.historicalLookup(
            serviceAccount: service,
            timeslot: lookupAnchorTimeslot,
            preimageHash: Data32(state.readMemory(address: regs[0], length: 32))!
        )

        let reg10: UInt64 = state.readRegister(Registers.Index(raw: 10))
        let reg11: UInt64 = state.readRegister(Registers.Index(raw: 11))
        let first = min(Int(reg10), preimage?.count ?? 0)
        let len = min(Int(reg11), (preimage?.count ?? 0) - first)

        let isWritable = state.isMemoryWritable(address: regs[1], length: len)

        if !isWritable {
            throw VMInvocationsError.panic
        } else if let preimage {
            state.writeRegister(Registers.Index(raw: 7), preimage.count)
            try state.writeMemory(address: regs[1], values: preimage[relative: first ..< (first + len)])
        } else {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.NONE.rawValue)
        }
    }
}

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
            context.pvms[pvmIndex]?.pc = innerPvm.pc + 1
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

// MARK: - Accumulate

/// Set privileged services details
public class Bless: HostCall {
    public static var identifier: UInt8 { 14 }

    public let x: AccumlateResultContext

    public init(x: AccumlateResultContext) {
        self.x = x
    }

    public func _callImpl(config: ProtocolConfigRef, state: VMState) async throws {
        let regs: [UInt32] = state.readRegisters(in: 7 ..< 12)

        var assigners: ConfigFixedSizeArray<ServiceIndex, ProtocolConfig.TotalNumberOfCores>?
        if state.isMemoryReadable(address: regs[1], length: 4 * config.value.totalNumberOfCores) {
            assigners = try JamDecoder.decode(
                ConfigFixedSizeArray<ServiceIndex, ProtocolConfig.TotalNumberOfCores>.self,
                from: state.readMemory(address: regs[1], length: 4 * config.value.totalNumberOfCores),
                withConfig: config
            )
        }

        var alwaysAcc: [ServiceIndex: Gas]?
        let length = 12 * Int(regs[4])
        if state.isMemoryReadable(address: regs[3], length: length) {
            let data = try state.readMemory(address: regs[3], length: length)
            for i in stride(from: 0, to: length, by: 12) {
                let serviceIndex = ServiceIndex(data[i ..< i + 4].decode(UInt32.self))
                let gas = Gas(data[i + 4 ..< i + 12].decode(UInt64.self))
                if var alwaysAcc {
                    alwaysAcc[serviceIndex] = gas
                } else {
                    alwaysAcc = [serviceIndex: gas]
                }
            }
        }

        if alwaysAcc == nil || assigners == nil {
            throw VMInvocationsError.panic
        } else if x.serviceIndex != x.state.manager {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.HUH.rawValue)
        } else if ![regs[0], regs[2]].allSatisfy({ $0 >= 0 && $0 <= Int(UInt32.max) }) {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.WHO.rawValue)
        } else {
            logger.debug("manager: \(regs[0])")
            logger.debug("assigners: \(String(describing: assigners))")
            logger.debug("delegator: \(regs[2])")
            logger.debug("alwaysAcc: \(String(describing: alwaysAcc))")

            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.OK.rawValue)
            x.state.manager = regs[0]
            x.state.assigners = assigners!
            x.state.delegator = regs[2]
            x.state.alwaysAcc = alwaysAcc!
        }
    }
}

/// Assign the authorization queue for a core
public class Assign: HostCall {
    public static var identifier: UInt8 { 15 }

    public let x: AccumlateResultContext

    public init(x: AccumlateResultContext) {
        self.x = x
    }

    public func _callImpl(config: ProtocolConfigRef, state: VMState) async throws {
        let targetCoreIndex: UInt32 = state.readRegister(Registers.Index(raw: 7))
        let startAddr: UInt32 = state.readRegister(Registers.Index(raw: 8))
        let assigner: UInt32 = state.readRegister(Registers.Index(raw: 9))

        var authorizationQueue: [Data32]?
        let length = 32 * config.value.maxAuthorizationsQueueItems
        if state.isMemoryReadable(address: startAddr, length: length) {
            let data = try state.readMemory(address: startAddr, length: length)
            for i in stride(from: 0, to: length, by: 32) {
                if authorizationQueue == nil {
                    authorizationQueue = [Data32]()
                }
                authorizationQueue!.append(Data32(data[i ..< i + 32])!)
            }
        }

        if authorizationQueue == nil {
            throw VMInvocationsError.panic
        } else if targetCoreIndex >= config.value.totalNumberOfCores {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.CORE.rawValue)
        } else if x.serviceIndex != x.state.assigners[targetCoreIndex] {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.HUH.rawValue)
        } else {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.OK.rawValue)
            // update authorizationQueue
            var newAuthorizationQueue = x.state.authorizationQueue
            newAuthorizationQueue[targetCoreIndex] = try ConfigFixedSizeArray(config: config, array: authorizationQueue!)
            x.state.authorizationQueue = newAuthorizationQueue
            // update assigner
            x.state.assigners[targetCoreIndex] = assigner
        }
    }
}

/// Designate the new validator queue
public class Designate: HostCall {
    public static var identifier: UInt8 { 16 }

    public let x: AccumlateResultContext

    public init(x: AccumlateResultContext) {
        self.x = x
    }

    public func _callImpl(config: ProtocolConfigRef, state: VMState) async throws {
        let startAddr: UInt32 = state.readRegister(Registers.Index(raw: 7))

        var validatorQueue: [ValidatorKey]?
        let length = 336 * config.value.totalNumberOfValidators
        if state.isMemoryReadable(address: startAddr, length: length) {
            let data = try state.readMemory(address: startAddr, length: length)
            for i in stride(from: 0, to: length, by: 336) {
                if validatorQueue == nil {
                    validatorQueue = [ValidatorKey]()
                }
                try validatorQueue!.append(ValidatorKey(data: Data(data[i ..< i + 336])))
            }
        }

        if validatorQueue == nil {
            throw VMInvocationsError.panic
        } else if x.serviceIndex != x.state.delegator {
            logger.debug("Designate HUH: \(x.serviceIndex) != \(x.state.delegator)")
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.HUH.rawValue)
        } else {
            x.state.validatorQueue = try ConfigFixedSizeArray(config: config, array: validatorQueue!)
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.OK.rawValue)
        }
    }
}

/// Save a checkpoint
public class Checkpoint: HostCall {
    public static var identifier: UInt8 { 17 }

    public let x: AccumlateResultContext
    public let y: AccumlateResultContext

    public init(x: AccumlateResultContext, y: AccumlateResultContext) {
        self.x = x
        self.y = y
    }

    public func _callImpl(config _: ProtocolConfigRef, state: VMState) async throws {
        state.writeRegister(Registers.Index(raw: 7), UInt64(bitPattern: state.getGas().value))

        y.serviceIndex = x.serviceIndex
        y.state = x.state.copy()
        y.nextAccountIndex = x.nextAccountIndex
        y.transfers = x.transfers
        y.yield = x.yield
        y.provide = x.provide
    }
}

/// Create a new service account
public class New: HostCall {
    public static var identifier: UInt8 { 18 }

    public let x: AccumlateResultContext
    public let timeslot: TimeslotIndex

    public init(x: AccumlateResultContext, timeslot: TimeslotIndex) {
        self.x = x
        self.timeslot = timeslot
    }

    private func bump(i: ServiceIndex) -> ServiceIndex {
        256 + ((i - 256 + 42) % serviceIndexModValue)
    }

    public func _callImpl(config: ProtocolConfigRef, state: VMState) async throws {
        let regs: [UInt64] = state.readRegisters(in: 7 ..< 12)

        let codeHash: Data32? = try? Data32(state.readMemory(address: regs[0], length: 32))
        logger.debug("codeHash: \(codeHash?.description ?? "nil")")
        logger.debug("new service index: \(x.nextAccountIndex)")

        let minAccumlateGas = Gas(regs[2])
        let minOnTransferGas = Gas(regs[3])
        let gratisStorage = Balance(regs[4])

        var newAccount: ServiceAccount?
        if let codeHash {
            newAccount = ServiceAccount(
                storage: [:],
                preimages: [:],
                preimageInfos: [HashAndLength(hash: codeHash, length: UInt32(truncatingIfNeeded: regs[1])): []],
                codeHash: codeHash,
                balance: Balance(0),
                minAccumlateGas: minAccumlateGas,
                minOnTransferGas: minOnTransferGas,
                gratisStorage: gratisStorage,
                createdAt: timeslot,
                lastAccAt: 0,
                parentService: x.serviceIndex,
            )
            newAccount!.balance = newAccount!.thresholdBalance(config: config)
        }

        if codeHash == nil {
            throw VMInvocationsError.panic
        } else if regs[4] != 0, x.serviceIndex != x.state.manager {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.HUH.rawValue)
        } else if let newAccount,
                  let account = try await x.state.accounts.value.get(serviceAccount: x.serviceIndex),
                  account.balance - newAccount.thresholdBalance(config: config) < account.thresholdBalance(config: config)
        {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.CASH.rawValue)
        } else {
            guard let newAccount, var account = try await x.state.accounts.value.get(serviceAccount: x.serviceIndex) else {
                throw VMInvocationsError.panic
            }
            state.writeRegister(Registers.Index(raw: 7), x.nextAccountIndex)

            account.balance -= newAccount.thresholdBalance(config: config)

            // update accumulating account details
            x.state.accounts.set(serviceAccount: x.serviceIndex, account: account)

            // add the new account
            try await x.state.accounts.addNew(serviceAccount: x.nextAccountIndex, account: newAccount)

            // update nextAccountIndex
            x.nextAccountIndex = try await AccumulateContext.check(
                i: bump(i: x.nextAccountIndex),
                accounts: x.state.accounts.toRef()
            )
        }
    }
}

/// Upgrade a service account
public class Upgrade: HostCall {
    public static var identifier: UInt8 { 19 }

    public let x: AccumlateResultContext

    public init(x: AccumlateResultContext) {
        self.x = x
    }

    public func _callImpl(config _: ProtocolConfigRef, state: VMState) async throws {
        let regs: [UInt64] = state.readRegisters(in: 7 ..< 10)

        let codeHash: Data32? = try? Data32(state.readMemory(address: regs[0], length: 32))

        logger.debug("new codeHash: \(codeHash?.description ?? "nil")")

        if let codeHash, var acc = try await x.state.accounts.value.get(serviceAccount: x.serviceIndex) {
            acc.codeHash = codeHash
            acc.minAccumlateGas = Gas(regs[1])
            acc.minOnTransferGas = Gas(regs[2])
            x.state.accounts.set(serviceAccount: x.serviceIndex, account: acc)
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.OK.rawValue)
        } else {
            throw VMInvocationsError.panic
        }
    }
}

/// Make a transfer
public class Transfer: HostCall {
    public static var identifier: UInt8 { 20 }

    public let x: AccumlateResultContext

    public init(x: AccumlateResultContext) {
        self.x = x
    }

    public func gasCost(state: VMState) -> Gas {
        let reg9: UInt64 = state.readRegister(Registers.Index(raw: 9))
        return Gas(10) + Gas(reg9)
    }

    public func _callImpl(config: ProtocolConfigRef, state: VMState) async throws {
        let regs: [UInt64] = state.readRegisters(in: 7 ..< 11)
        let amount = Balance(regs[1])
        let gasLimit = Gas(regs[2])
        let memo = try? state.readMemory(address: regs[3], length: config.value.transferMemoSize)
        let dest = UInt32(truncatingIfNeeded: regs[0])

        let srcAccount = try await x.state.accounts.value.get(serviceAccount: x.serviceIndex)

        let destAccount = try await x.state.accounts.value.get(serviceAccount: dest)

        logger.debug("src: \(x.serviceIndex), dest: \(dest), amount: \(amount), gasLimit: \(gasLimit)")
        logger.debug("dest is found: \(destAccount != nil)")

        if memo == nil {
            throw VMInvocationsError.panic
        } else if destAccount == nil {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.WHO.rawValue)
        } else if gasLimit < destAccount!.minOnTransferGas {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.LOW.rawValue)
        } else if let srcAccount, srcAccount.balance - amount < srcAccount.thresholdBalance(config: config) {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.CASH.rawValue)
        } else if var srcAccount {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.OK.rawValue)
            x.transfers.append(DeferredTransfers(
                sender: x.serviceIndex,
                destination: dest,
                amount: amount,
                memo: Data128(memo!)!,
                gasLimit: gasLimit
            ))
            srcAccount.balance -= amount
            x.state.accounts.set(serviceAccount: x.serviceIndex, account: srcAccount)
        }
    }
}

/// Eject (remove) a service account
public class Eject: HostCall {
    public static var identifier: UInt8 { 21 }

    public let x: AccumlateResultContext
    public let timeslot: TimeslotIndex

    public init(x: AccumlateResultContext, timeslot: TimeslotIndex) {
        self.x = x
        self.timeslot = timeslot
    }

    public func _callImpl(config: ProtocolConfigRef, state: VMState) async throws {
        let (reg7, reg8): (UInt64, UInt64) = state.readRegister(Registers.Index(raw: 7), Registers.Index(raw: 8))
        let ejectIndex = ServiceIndex(truncatingIfNeeded: reg7)
        let preimageHash = try? state.readMemory(address: reg8, length: 32)
        let ejectAccount: ServiceAccountDetails? = if ejectIndex == x.serviceIndex {
            nil
        } else {
            try await x.state.accounts.value.get(serviceAccount: ejectIndex)
        }
        let minHoldPeriod = TimeslotIndex(config.value.preimagePurgePeriod)

        if preimageHash == nil {
            throw VMInvocationsError.panic
        } else if ejectAccount == nil || ejectAccount?.codeHash.data != Data(x.serviceIndex.encode(method: .fixedWidth(32))) {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.WHO.rawValue)
            return
        }

        let preimageInfo = try await x.state.accounts.value.get(
            serviceAccount: ejectIndex,
            preimageHash: Data32(preimageHash!)!,
            length: max(81, UInt32(ejectAccount!.totalByteLength)) - 81
        )

        let minHoldSlot = max(0, Int(timeslot) - Int(minHoldPeriod))

        if ejectAccount!.itemsCount != 2 || preimageInfo == nil {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.HUH.rawValue)
        } else if preimageInfo!.count == 2, preimageInfo![1] < minHoldSlot {
            // accumulating service definitely exist
            var destAccount = try await x.state.accounts.value.get(serviceAccount: x.serviceIndex)!
            destAccount.balance += ejectAccount!.balance
            try await x.state.accounts.remove(serviceAccount: ejectIndex)
            x.state.accounts.set(serviceAccount: x.serviceIndex, account: destAccount)
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.OK.rawValue)
        } else {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.HUH.rawValue)
        }
    }
}

/// Query preimage info
public class Query: HostCall {
    public static var identifier: UInt8 { 22 }

    public let x: AccumlateResultContext

    public init(x: AccumlateResultContext) {
        self.x = x
    }

    public func _callImpl(config _: ProtocolConfigRef, state: VMState) async throws {
        let (startAddr, length): (UInt32, UInt32) = state.readRegister(Registers.Index(raw: 7), Registers.Index(raw: 8))
        let preimageHash = try? state.readMemory(address: startAddr, length: 32)
        guard let preimageHash else {
            throw VMInvocationsError.panic
        }

        let preimageInfo = try await x.state.accounts.value.get(
            serviceAccount: x.serviceIndex,
            preimageHash: Data32(preimageHash)!,
            length: length
        )
        guard let preimageInfo else {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.NONE.rawValue)
            state.writeRegister(Registers.Index(raw: 8), 0)
            return
        }

        if preimageInfo.isEmpty {
            state.writeRegister(Registers.Index(raw: 7), 0)
            state.writeRegister(Registers.Index(raw: 8), 0)
        } else if preimageInfo.count == 1 {
            state.writeRegister(Registers.Index(raw: 7), 1 + (1 << 32) * UInt64(preimageInfo[0]))
            state.writeRegister(Registers.Index(raw: 8), 0)
        } else if preimageInfo.count == 2 {
            state.writeRegister(Registers.Index(raw: 7), 2 + (1 << 32) * UInt64(preimageInfo[0]))
            state.writeRegister(Registers.Index(raw: 8), UInt64(preimageInfo[1]))
        } else if preimageInfo.count == 3 {
            state.writeRegister(Registers.Index(raw: 7), 3 + (1 << 32) * UInt64(preimageInfo[0]))
            state.writeRegister(Registers.Index(raw: 8), UInt64(preimageInfo[1]) + (1 << 32) * UInt64(preimageInfo[2]))
        }
    }
}

/// Solicit data to be made available in-core (through preimage lookups)
public class Solicit: HostCall {
    public static var identifier: UInt8 { 23 }

    public let x: AccumlateResultContext
    public let timeslot: TimeslotIndex

    public init(x: AccumlateResultContext, timeslot: TimeslotIndex) {
        self.x = x
        self.timeslot = timeslot
    }

    public func _callImpl(config: ProtocolConfigRef, state: VMState) async throws {
        let (startAddr, length): (UInt32, UInt32) = state.readRegister(Registers.Index(raw: 7), Registers.Index(raw: 8))
        let hashData = try? state.readMemory(address: startAddr, length: 32)
        let hash = Data32(hashData ?? Data())

        guard let hash else {
            throw VMInvocationsError.panic
        }

        let preimageInfo = try await x.state.accounts.value.get(
            serviceAccount: x.serviceIndex,
            preimageHash: hash,
            length: length
        )
        let notRequestedYet = preimageInfo == nil
        let isPreviouslyAvailable = preimageInfo?.count == 2
        let canSolicit = notRequestedYet || isPreviouslyAvailable

        let acc = try await x.state.accounts.value.get(serviceAccount: x.serviceIndex)

        if !canSolicit {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.HUH.rawValue)
        } else if let acc, acc.balance < acc.thresholdBalance(config: config) {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.FULL.rawValue)
        } else {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.OK.rawValue)
            if notRequestedYet {
                try await x.state.accounts.set(serviceAccount: x.serviceIndex, preimageHash: hash, length: length, value: [])
            } else if isPreviouslyAvailable, var preimageInfo {
                try preimageInfo.append(timeslot)
                try await x.state.accounts.set(
                    serviceAccount: x.serviceIndex,
                    preimageHash: hash,
                    length: length,
                    value: preimageInfo
                )
            }
        }
    }
}

/// Forget data made available in-core (through preimage lookups)
public class Forget: HostCall {
    public static var identifier: UInt8 { 24 }

    public let x: AccumlateResultContext
    public let timeslot: TimeslotIndex

    public init(x: AccumlateResultContext, timeslot: TimeslotIndex) {
        self.x = x
        self.timeslot = timeslot
    }

    public func _callImpl(config: ProtocolConfigRef, state: VMState) async throws {
        let (startAddr, length): (UInt32, UInt32) = state.readRegister(Registers.Index(raw: 7), Registers.Index(raw: 8))
        let hashData = try? state.readMemory(address: startAddr, length: 32)
        let hash = Data32(hashData ?? Data())

        guard let hash else {
            throw VMInvocationsError.panic
        }

        let preimageInfo = try await x.state.accounts.value.get(
            serviceAccount: x.serviceIndex,
            preimageHash: hash,
            length: length
        )
        let historyCount = preimageInfo?.count
        let minHoldSlot = max(0, Int(timeslot) - config.value.preimagePurgePeriod)

        let canExpunge = historyCount == 0 || (historyCount == 2 && preimageInfo![1] < minHoldSlot)
        let isAvailable1 = historyCount == 1
        let isAvailable3 = historyCount == 3 && (preimageInfo![1] < minHoldSlot)

        let canForget = canExpunge || isAvailable1 || isAvailable3

        if !canForget {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.HUH.rawValue)
        } else {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.OK.rawValue)
            if canExpunge {
                try await x.state.accounts.set(serviceAccount: x.serviceIndex, preimageHash: hash, length: length, value: nil)
                x.state.accounts.set(serviceAccount: x.serviceIndex, preimageHash: hash, value: nil)
            } else if isAvailable1, var preimageInfo {
                try preimageInfo.append(timeslot)
                try await x.state.accounts.set(
                    serviceAccount: x.serviceIndex,
                    preimageHash: hash,
                    length: length,
                    value: preimageInfo
                )
            } else if isAvailable3, var preimageInfo {
                preimageInfo = [preimageInfo[2], timeslot]
                try await x.state.accounts.set(
                    serviceAccount: x.serviceIndex,
                    preimageHash: hash,
                    length: length,
                    value: preimageInfo
                )
            }
        }
    }
}

/// Yield accumulation hash
public class Yield: HostCall {
    public static var identifier: UInt8 { 25 }

    public let x: AccumlateResultContext

    public init(x: AccumlateResultContext) {
        self.x = x
    }

    public func _callImpl(config _: ProtocolConfigRef, state: VMState) async throws {
        let startAddr: UInt32 = state.readRegister(Registers.Index(raw: 7))
        let hash = try? state.readMemory(address: startAddr, length: 32)
        if let hash {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.OK.rawValue)
            x.yield = Data32(hash)!
        } else {
            throw VMInvocationsError.panic
        }
    }
}

/// Provide some preimages (will be made available after invocation)
public class Provide: HostCall {
    public static var identifier: UInt8 { 26 }

    public let x: AccumlateResultContext

    public init(x: AccumlateResultContext) {
        self.x = x
    }

    public func _callImpl(config _: ProtocolConfigRef, state: VMState) async throws {
        let serviceIndex: UInt32 = if x.serviceIndex == UInt64.max {
            x.serviceIndex
        } else {
            state.readRegister(.init(raw: 7))
        }
        let (startAddr, length): (UInt32, UInt32) = state.readRegister(Registers.Index(raw: 8), Registers.Index(raw: 9))
        let preimage = try? state.readMemory(address: startAddr, length: Int(length))
        let accountDetails = try await x.state.accounts.value.get(serviceAccount: serviceIndex)
        var preimageLookupOk = false
        if let preimage {
            let lookup = try await x.state.accounts.value.get(
                serviceAccount: x.serviceIndex,
                preimageHash: Blake2b256.hash(preimage),
                length: length
            )
            if let lookup, lookup.isEmpty {
                preimageLookupOk = true
            }
        }

        if preimage == nil {
            throw VMInvocationsError.panic
        } else if accountDetails == nil {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.WHO.rawValue)
        } else if !preimageLookupOk {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.HUH.rawValue)
        } else if x.provide.contains(.init(service: serviceIndex, preimage: preimage!)) {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.HUH.rawValue)
        } else {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.OK.rawValue)
            x.provide.insert(.init(service: serviceIndex, preimage: preimage!))
        }
    }
}

// MARK: - Debug

/// A host call for passing a debugging message from the service/authorizer to the hosting environment for logging to the node operator.
public class Log: HostCall {
    public static var identifier: UInt8 { 100 }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd HH:mm:ss"
        return formatter
    }()

    public func gasCost(state _: VMState) -> Gas {
        Gas(0)
    }

    public enum Level: UInt32, Codable {
        case error = 0
        case warn = 1
        case info = 2
        case debug = 3
        case trace = 4

        var description: String {
            switch self {
            case .error: "ERROR"
            case .warn: "WARN"
            case .info: "INFO"
            case .debug: "DEBUG"
            case .trace: "TRACE"
            }
        }
    }

    public struct Details: Codable {
        public let time: String
        public let level: Level
        public let target: Data?
        public let message: Data
        public let core: CoreIndex?
        public let service: ServiceIndex?

        public var json: JSON {
            JSON.dictionary([
                "time": .string(time),
                "level": .string(level.description),
                "message": .string(String(data: message, encoding: .utf8) ?? "invalid string"),
                "target": target != nil ? .string(String(data: target!, encoding: .utf8) ?? "invalid string") : .null,
                "service": service != nil ? .string(String(service!)) : .null,
                "core": core != nil ? .string(String(core!)) : .null,
            ])
        }

        public var str: String {
            var result = time + " \(level.description)"
            if let core {
                result += "@\(core)"
            }
            if let service {
                result += "#\(service)"
            }
            if let target {
                result += " \(String(data: target, encoding: .utf8) ?? "invalid string")"
            }
            result += " \(String(data: message, encoding: .utf8) ?? "invalid string")"

            return result
        }
    }

    public let core: CoreIndex?
    public let service: ServiceIndex?

    public init(core: CoreIndex? = nil, service: ServiceIndex? = nil) {
        self.core = core
        self.service = service
    }

    public func _callImpl(config _: ProtocolConfigRef, state: VMState) async throws {
        let regs: [UInt32] = state.readRegisters(in: 7 ..< 12)
        let level = regs[0]
        let target = regs[1] == 0 && regs[2] == 0 ? nil : try? state.readMemory(address: regs[1], length: Int(regs[2]))
        let message = try? state.readMemory(address: regs[3], length: Int(regs[4]))

        let time = Self.dateFormatter.string(from: Date())

        let details = Details(
            time: time,
            level: Level(rawValue: level) ?? .debug,
            target: target,
            message: message ?? Data(),
            core: core,
            service: service
        )

        switch level {
        case 0:
            logger.error(Logger.Message(stringLiteral: details.str))
        case 1:
            logger.warning(Logger.Message(stringLiteral: details.str))
        case 2:
            logger.info(Logger.Message(stringLiteral: details.str))
        case 3:
            logger.debug(Logger.Message(stringLiteral: details.str))
        case 4:
            logger.trace(Logger.Message(stringLiteral: details.str))
        default:
            logger.error("Invalid log level: \(level)")
        }
    }
}
