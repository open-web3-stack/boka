import Codec
import Foundation
import PolkaVM
import TracingUtils
import Utils

private let logger = Logger(label: "HostCalls.General")

// MARK: - General

/// Get gas remaining
public class GasFn: HostCall {
    public static var identifier: UInt8 {
        0
    }

    public func _callImpl(config _: ProtocolConfigRef, state: VMState) async throws {
        state.writeRegister(Registers.Index(raw: 7), UInt64(bitPattern: state.getGas().value))
    }
}

/// Fetch
public class Fetch: HostCall {
    public static var identifier: UInt8 {
        1
    }

    public let serviceAccounts: ServiceAccountsRef?
    public let serviceIndex: ServiceIndex?

    /// p
    public let workPackage: WorkPackage?
    /// n
    public let entropy: Data32?
    /// r
    public let authorizerTrace: Data?
    /// i
    public let workItemIndex: Int?
    /// overline i
    public let importSegments: [[Data4104]]?
    /// overline x (no need pass in)
    /// o
    public let inputs: [AccumulationInput]?
    /// c
    public let coreIndex: CoreIndex?

    public init(
        serviceAccounts: ServiceAccountsRef? = nil,
        serviceIndex: ServiceIndex? = nil,
        workPackage: WorkPackage? = nil,
        entropy: Data32? = nil,
        authorizerTrace: Data? = nil,
        workItemIndex: Int? = nil,
        importSegments: [[Data4104]]? = nil,
        inputs: [AccumulationInput]? = nil,
        coreIndex: CoreIndex? = nil,
    ) {
        self.serviceAccounts = serviceAccounts
        self.serviceIndex = serviceIndex
        self.workPackage = workPackage
        self.entropy = entropy
        self.authorizerTrace = authorizerTrace
        self.workItemIndex = workItemIndex
        self.importSegments = importSegments
        self.inputs = inputs
        self.coreIndex = coreIndex
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
                value = workPackage.configurationBlob
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
            if let inputs {
                value = try JamEncoder.encode(inputs)
            }
        case 15:
            if let inputs, reg11 < inputs.count {
                value = try JamEncoder.encode(inputs[Int(reg11)])
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
    public static var identifier: UInt8 {
        2
    }

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
    public static var identifier: UInt8 {
        3
    }

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

        logger.debug("value: \(value?.toDebugHexString() ?? "nil")")

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
            logger.debug("writing val: \(value[relative: first ..< (first + len)].toDebugHexString())")
            try state.writeMemory(address: regs[2], values: value[relative: first ..< (first + len)])
        }
    }
}

/// Write to a service account storage
public class Write: HostCall {
    public static var identifier: UInt8 {
        4
    }

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

        // update footprint for threshold balance check
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
    public static var identifier: UInt8 {
        5
    }

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
                account.minMemoGas,
                account.totalByteLength,
                account.itemsCount,
                account.gratisStorage,
                account.createdAt,
                account.lastAccAt,
                account.parentService,
            )
        } else {
            value = nil
        }

        let reg9: UInt64 = state.readRegister(Registers.Index(raw: 9))
        let reg10: UInt64 = state.readRegister(Registers.Index(raw: 10))
        let first = min(Int(reg9), value?.count ?? 0)
        let len = min(Int(reg10), (value?.count ?? 0) - first)

        let isWritable = state.isMemoryWritable(address: o, length: len)

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

/// Historical lookup
public class HistoricalLookup: HostCall {
    public static var identifier: UInt8 {
        6
    }

    public let context: RefineContext.ContextType
    public let serviceIndex: ServiceIndex
    public let serviceAccounts: ServiceAccountsRef
    public let lookupAnchorTimeslot: TimeslotIndex

    public init(
        context: RefineContext.ContextType,
        serviceIndex: ServiceIndex,
        serviceAccounts: ServiceAccountsRef,
        lookupAnchorTimeslot: TimeslotIndex,
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
            preimageHash: Data32(state.readMemory(address: regs[0], length: 32))!,
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
