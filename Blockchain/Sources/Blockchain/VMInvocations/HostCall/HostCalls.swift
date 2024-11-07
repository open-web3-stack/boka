import Codec
import Foundation
import PolkaVM
import Utils

// MARK: - General

/// Get gas remaining
public class GasFn: HostCall {
    public static var identifier: UInt8 { 0 }

    public func _callImpl(config _: ProtocolConfigRef, state: VMState) async throws {
        state.writeRegister(Registers.Index(raw: 7), UInt32(bitPattern: Int32(state.getGas().value & 0xFFFF_FFFF)))
        state.writeRegister(Registers.Index(raw: 8), UInt32(bitPattern: Int32(state.getGas().value >> 32)))
    }
}

/// Lookup a preimage from a service account
public class Lookup: HostCall {
    public static var identifier: UInt8 { 1 }

    public let serviceIndex: ServiceIndex
    public let serviceAccounts: ServiceAccounts

    public init(serviceIndex: ServiceIndex, accounts: some ServiceAccounts) {
        self.serviceIndex = serviceIndex
        serviceAccounts = accounts
    }

    public func _callImpl(config _: ProtocolConfigRef, state: VMState) async throws {
        var service: ServiceIndex
        let reg = state.readRegister(Registers.Index(raw: 7))
        if reg == serviceIndex || reg == Int32.max {
            service = serviceIndex
        } else {
            service = reg
        }

        let regs = state.readRegisters(in: 8 ..< 11)

        let preimageHash = try? Blake2b256.hash(state.readMemory(address: regs[0], length: 32))

        let value: Data? = if let preimageHash {
            try await serviceAccounts.get(serviceAccount: service, preimageHash: preimageHash)
        } else {
            nil
        }

        let isWritable = state.isMemoryWritable(address: regs[1], length: Int(regs[2]))
        if let value, isWritable {
            let maxLen = min(regs[2], UInt32(value.count))
            try state.writeMemory(address: regs[1], values: value[0 ..< Int(maxLen)])
        }

        if preimageHash != nil, isWritable {
            if let value {
                state.writeRegister(Registers.Index(raw: 7), UInt32(value.count))
            } else {
                state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.NONE.rawValue)
            }
        } else {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.OOB.rawValue)
        }
    }
}

/// Read a service account storage
public class Read: HostCall {
    public static var identifier: UInt8 { 2 }

    public let serviceIndex: ServiceIndex
    public let serviceAccounts: ServiceAccounts

    public init(serviceIndex: ServiceIndex, accounts: ServiceAccounts) {
        self.serviceIndex = serviceIndex
        serviceAccounts = accounts
    }

    public func _callImpl(config _: ProtocolConfigRef, state: VMState) async throws {
        var service: ServiceIndex
        let reg = state.readRegister(Registers.Index(raw: 7))
        if reg == serviceIndex || reg == Int32.max {
            service = serviceIndex
        } else {
            service = reg
        }

        let regs = state.readRegisters(in: 8 ..< 12)

        let key = try? Blake2b256.hash(serviceIndex.encode(), state.readMemory(address: regs[0], length: Int(regs[1])))

        let value: Data? = if let key {
            try await serviceAccounts.get(serviceAccount: service, storageKey: key)
        } else {
            nil
        }

        let isWritable = state.isMemoryWritable(address: regs[2], length: Int(regs[3]))
        if let value, isWritable {
            let maxLen = min(regs[3], UInt32(value.count))
            try state.writeMemory(address: regs[2], values: value[0 ..< Int(maxLen)])
        }

        if key != nil, isWritable {
            if let value {
                state.writeRegister(Registers.Index(raw: 7), UInt32(value.count))
            } else {
                state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.NONE.rawValue)
            }
        } else {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.OOB.rawValue)
        }
    }
}

/// Write to a service account storage
public class Write: HostCall {
    public static var identifier: UInt8 { 3 }

    public let serviceIndex: ServiceIndex
    public var serviceAccounts: ServiceAccounts

    public init(serviceIndex: ServiceIndex, accounts: inout ServiceAccounts) {
        self.serviceIndex = serviceIndex
        serviceAccounts = accounts
    }

    public func _callImpl(config: ProtocolConfigRef, state: VMState) async throws {
        let regs = state.readRegisters(in: 7 ..< 11)

        let key = try? Blake2b256.hash(serviceIndex.encode(), state.readMemory(address: regs[0], length: Int(regs[1])))

        let service: ServiceIndex? = if key != nil, state.isMemoryReadable(address: regs[2], length: Int(regs[3])) {
            serviceIndex
        } else {
            nil
        }

        let len = if let key, let value = try await serviceAccounts.get(serviceAccount: service!, storageKey: key) {
            UInt32(value.count)
        } else {
            HostCallResultCode.NONE.rawValue
        }

        let acc: ServiceAccountDetails? = (service != nil) ? try await serviceAccounts.get(serviceAccount: service!) : nil
        if key != nil, let service, let acc, acc.thresholdBalance(config: config) <= acc.balance {
            state.writeRegister(Registers.Index(raw: 7), len)
            if regs[3] == 0 {
                serviceAccounts.remove(serviceAccount: service, storageKey: key!)
            } else {
                try serviceAccounts.set(
                    serviceAccount: service,
                    storageKey: key!,
                    value: state.readMemory(address: regs[2], length: Int(regs[3]))
                )
            }
        } else if let acc, acc.thresholdBalance(config: config) > acc.balance {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.FULL.rawValue)
        } else {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.OOB.rawValue)
        }
    }
}

/// Get information about a service account
public class Info: HostCall {
    public static var identifier: UInt8 { 4 }

    public let serviceIndex: ServiceIndex
    public let serviceAccounts: ServiceAccounts

    public init(serviceIndex: ServiceIndex, accounts: ServiceAccounts) {
        self.serviceIndex = serviceIndex
        serviceAccounts = accounts
    }

    public func _callImpl(config: ProtocolConfigRef, state: VMState) async throws {
        var service: ServiceIndex
        let reg = state.readRegister(Registers.Index(raw: 7))
        if reg == Int32.max {
            service = serviceIndex
        } else {
            service = reg
        }

        let o = state.readRegister(Registers.Index(raw: 8))

        let m: Data?
        let account = try await serviceAccounts.get(serviceAccount: service)
        if let account {
            // codeHash, balance, thresholdBalance, minAccumlateGas, minOnTransferGas, totalByteLength, itemsCount
            let capacity = 32 + 8 * 5 + 4
            let encoder = JamEncoder(capacity: capacity)
            try encoder.encode(account.codeHash)
            try encoder.encode(account.balance)
            try encoder.encode(account.thresholdBalance(config: config))
            try encoder.encode(account.minAccumlateGas)
            try encoder.encode(account.minOnTransferGas)
            try encoder.encode(account.totalByteLength)
            try encoder.encode(account.itemsCount)
            m = encoder.data
        } else {
            m = nil
        }

        if let m, state.isMemoryWritable(address: o, length: Int(m.count)) {
            try state.writeMemory(address: o, values: m)
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.OK.rawValue)
        } else if m == nil {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.NONE.rawValue)
        } else {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.OOB.rawValue)
        }
    }
}

// MARK: - Accumulate

/// Set privileged services details
public class Empower: HostCall {
    public static var identifier: UInt8 { 5 }

    public var x: AccumlateResultContext

    public init(x: inout AccumlateResultContext) {
        self.x = x
    }

    public func _callImpl(config _: ProtocolConfigRef, state: VMState) async throws {
        let regs = state.readRegisters(in: 7 ..< 12)

        var basicGas: [ServiceIndex: Gas] = [:]
        let length = 12 * Int(regs[4])
        if state.isMemoryReadable(address: regs[3], length: length) {
            let data = try state.readMemory(address: regs[3], length: length)
            for i in stride(from: 0, to: length, by: 12) {
                let serviceIndex = ServiceIndex(data[i ..< i + 4].decode(UInt32.self))
                let gas = Gas(data[i + 4 ..< i + 12].decode(UInt64.self))
                basicGas[serviceIndex] = gas
            }
        }

        if basicGas.count != 0 {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.OK.rawValue)
            x.accumulateState.privilegedServices.empower = regs[0]
            x.accumulateState.privilegedServices.assign = regs[1]
            x.accumulateState.privilegedServices.designate = regs[2]
            x.accumulateState.privilegedServices.basicGas = basicGas
        } else {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.OOB.rawValue)
        }
    }
}

/// Assign the authorization queue for a core
public class Assign: HostCall {
    public static var identifier: UInt8 { 6 }

    public var x: AccumlateResultContext

    public init(x: inout AccumlateResultContext) {
        self.x = x
    }

    public func _callImpl(config: ProtocolConfigRef, state: VMState) async throws {
        let (targetCoreIndex, startAddr) = state.readRegister(Registers.Index(raw: 7), Registers.Index(raw: 8))

        var authorizationQueue: [Data32] = []
        let length = 32 * config.value.maxAuthorizationsQueueItems
        if state.isMemoryReadable(address: startAddr, length: length) {
            let data = try state.readMemory(address: startAddr, length: length)
            for i in stride(from: 0, to: length, by: 32) {
                authorizationQueue.append(Data32(data[i ..< i + 32])!)
            }
        }

        if targetCoreIndex < config.value.totalNumberOfCores, !authorizationQueue.isEmpty {
            x.accumulateState.authorizationQueue[targetCoreIndex] = try ConfigFixedSizeArray(config: config, array: authorizationQueue)
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.OK.rawValue)
        } else if authorizationQueue.isEmpty {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.OOB.rawValue)
        } else {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.CORE.rawValue)
        }
    }
}

/// Designate the new validator queue
public class Designate: HostCall {
    public static var identifier: UInt8 { 7 }

    public var x: AccumlateResultContext

    public init(x: inout AccumlateResultContext) {
        self.x = x
    }

    public func _callImpl(config: ProtocolConfigRef, state: VMState) async throws {
        let startAddr = state.readRegister(Registers.Index(raw: 7))

        var validatorQueue: [ValidatorKey] = []
        let length = 336 * config.value.totalNumberOfValidators
        if state.isMemoryReadable(address: startAddr, length: length) {
            let data = try state.readMemory(address: startAddr, length: length)
            for i in stride(from: 0, to: length, by: 336) {
                try validatorQueue.append(ValidatorKey(data: Data(data[i ..< i + 336])))
            }
        }

        if !validatorQueue.isEmpty {
            x.accumulateState.validatorQueue = try ConfigFixedSizeArray(config: config, array: validatorQueue)
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.OK.rawValue)
        } else {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.OOB.rawValue)
        }
    }
}

/// Save a checkpoint
public class Checkpoint: HostCall {
    public static var identifier: UInt8 { 8 }

    public let x: AccumlateResultContext
    public var y: AccumlateResultContext

    public init(x: AccumlateResultContext, y: inout AccumlateResultContext) {
        self.x = x
        self.y = y
    }

    public func _callImpl(config _: ProtocolConfigRef, state: VMState) async throws {
        state.writeRegister(Registers.Index(raw: 7), UInt32(bitPattern: Int32(state.getGas().value & 0xFFFF_FFFF)))
        state.writeRegister(Registers.Index(raw: 8), UInt32(bitPattern: Int32(state.getGas().value >> 32)))

        y = x
    }
}

/// Create a new service account
public class New: HostCall {
    public static var identifier: UInt8 { 9 }

    public var x: AccumlateResultContext

    public init(x: inout AccumlateResultContext) {
        self.x = x
    }

    private func bump(i: ServiceIndex) -> ServiceIndex {
        256 + ((i - 256 + 42) & (serviceIndexModValue - 1))
    }

    public func _callImpl(config: ProtocolConfigRef, state: VMState) async throws {
        let regs = state.readRegisters(in: 7 ..< 13)

        let codeHash: Data32? = try? Data32(state.readMemory(address: regs[0], length: 32))
        let minAccumlateGas = Gas(0x1_0000_0000) * Gas(regs[3]) + Gas(regs[2])
        let minOnTransferGas = Gas(0x1_0000_0000) * Gas(regs[5]) + Gas(regs[4])

        var newAccount: ServiceAccount?
        if let codeHash {
            newAccount = ServiceAccount(
                storage: [:],
                preimages: [:],
                preimageInfos: [HashAndLength(hash: codeHash, length: regs[1]): []],
                codeHash: codeHash,
                balance: Balance(0),
                minAccumlateGas: minAccumlateGas,
                minOnTransferGas: minOnTransferGas
            )
            newAccount!.balance = newAccount!.thresholdBalance(config: config)
        }

        if let newAccount,
           var acc = try await x.serviceAccounts.get(serviceAccount: x.serviceIndex),
           acc.balance >= acc.thresholdBalance(config: config)
        {
            acc.balance -= newAccount.balance
            x.serviceAccounts.set(serviceAccount: x.serviceIndex, account: acc)

            state.writeRegister(Registers.Index(raw: 7), x.nextAccountIndex)
            x.accumulateState.serviceAccounts.merge([x.nextAccountIndex: newAccount]) { _, new in new }
            x.nextAccountIndex = AccumulateContext.check(i: bump(i: x.nextAccountIndex), serviceAccounts: x.accumulateState.serviceAccounts)
        } else if codeHash == nil {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.OOB.rawValue)
        } else {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.CASH.rawValue)
        }
    }
}

/// Upgrade a service account
public class Upgrade: HostCall {
    public static var identifier: UInt8 { 10 }

    public var x: AccumlateResultContext

    public init(x: inout AccumlateResultContext) {
        self.x = x
    }

    public func _callImpl(config _: ProtocolConfigRef, state: VMState) async throws {
        let regs = state.readRegisters(in: 7 ..< 12)

        let codeHash: Data32? = try? Data32(state.readMemory(address: regs[0], length: 32))
        let minAccumlateGas = Gas(0x1_0000_0000) * Gas(regs[1]) + Gas(regs[2])
        let minOnTransferGas = Gas(0x1_0000_0000) * Gas(regs[3]) + Gas(regs[4])

        if let codeHash, var acc = try await x.serviceAccounts.get(serviceAccount: x.serviceIndex) {
            acc.codeHash = codeHash
            acc.minAccumlateGas = minAccumlateGas
            acc.minOnTransferGas = minOnTransferGas
            x.serviceAccounts.set(serviceAccount: x.serviceIndex, account: acc)
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.OK.rawValue)
        } else {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.OOB.rawValue)
        }
    }
}

/// Make a transfer
public class Transfer: HostCall {
    public static var identifier: UInt8 { 11 }

    public var x: AccumlateResultContext

    public init(x: inout AccumlateResultContext) {
        self.x = x
    }

    public func gasCost(state: VMState) -> Gas {
        let (reg8, reg9) = state.readRegister(Registers.Index(raw: 8), Registers.Index(raw: 9))
        return Gas(10) + Gas(reg8) + Gas(0x1_0000_0000) * Gas(reg9)
    }

    public func _callImpl(config: ProtocolConfigRef, state: VMState) async throws {
        let regs = state.readRegisters(in: 0 ..< 6)
        let amount = Balance(0x1_0000_0000) * Balance(regs[2]) + Balance(regs[1])
        let gasLimit = Gas(0x1_0000_0000) * Gas(regs[4]) + Gas(regs[3])
        let memo = try? state.readMemory(address: regs[5], length: config.value.transferMemoSize)
        let dest = regs[0]

        let acc = try await x.serviceAccounts.get(serviceAccount: x.serviceIndex)

        let destAcc: ServiceAccountDetails? = if try await x.serviceAccounts.get(serviceAccount: dest) != nil {
            try await x.serviceAccounts.get(serviceAccount: dest)
        } else if x.accumulateState.serviceAccounts[dest] != nil {
            x.accumulateState.serviceAccounts[dest]?.toDetails()
        } else {
            nil
        }

        if memo == nil {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.OOB.rawValue)
        } else if destAcc == nil {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.WHO.rawValue)
        } else if gasLimit < destAcc!.minOnTransferGas {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.LOW.rawValue)
        } else if Gas(state.getGas()) < gasLimit {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.HIGH.rawValue)
        } else if let acc, acc.balance - amount < acc.thresholdBalance(config: config) {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.CASH.rawValue)
        } else if var acc {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.OK.rawValue)
            x.transfers.append(DeferredTransfers(
                sender: x.serviceIndex,
                destination: dest,
                amount: amount,
                memo: Data128(memo!)!,
                gasLimit: gasLimit
            ))
            acc.balance = acc.balance - amount
            x.serviceAccounts.set(serviceAccount: x.serviceIndex, account: acc)
        }
    }
}

/// Quit (remove) a service account
public class Quit: HostCall {
    public static var identifier: UInt8 { 12 }

    public var x: AccumlateResultContext

    public init(x: inout AccumlateResultContext) {
        self.x = x
    }

    public func _callImpl(config: ProtocolConfigRef, state: VMState) async throws {
        let (dest, startAddr) = state.readRegister(Registers.Index(raw: 7), Registers.Index(raw: 8))
        let acc = try await x.serviceAccounts.get(serviceAccount: x.serviceIndex).expect("service account not found")
        let amount = acc.balance - acc.thresholdBalance(config: config) + Balance(config.value.serviceMinBalance)
        let gasLimit = Gas(state.getGas())

        let isValidDest = dest == x.serviceIndex || dest == Int32.max
        let memoData = try? state.readMemory(address: startAddr, length: config.value.transferMemoSize)
        let memo = memoData != nil ? try JamDecoder.decode(Data128.self, from: memoData!) : nil

        let destAcc: ServiceAccountDetails? = if try await x.serviceAccounts.get(serviceAccount: dest) != nil {
            try await x.serviceAccounts.get(serviceAccount: dest)
        } else if x.accumulateState.serviceAccounts[dest] != nil {
            x.accumulateState.serviceAccounts[dest]?.toDetails()
        } else {
            nil
        }

        if isValidDest {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.OK.rawValue)
            x.serviceAccounts.remove(serviceAccount: x.serviceIndex)
            throw VMInvocationsError.forceHalt
        } else if memo == nil {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.OOB.rawValue)
        } else if destAcc == nil {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.WHO.rawValue)
        } else if gasLimit < destAcc!.minOnTransferGas {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.LOW.rawValue)
        } else {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.OK.rawValue)
            x.serviceAccounts.remove(serviceAccount: x.serviceIndex)
            x.transfers.append(DeferredTransfers(
                sender: x.serviceIndex,
                destination: dest,
                amount: amount,
                memo: memo!,
                gasLimit: gasLimit
            ))
            throw VMInvocationsError.forceHalt
        }
    }
}

/// Solicit data to be made available in-core (through preimage lookups)
public class Solicit: HostCall {
    public static var identifier: UInt8 { 13 }

    public var x: AccumlateResultContext
    public let timeslot: TimeslotIndex

    public init(x: inout AccumlateResultContext, timeslot: TimeslotIndex) {
        self.x = x
        self.timeslot = timeslot
    }

    public func _callImpl(config: ProtocolConfigRef, state: VMState) async throws {
        let (startAddr, length) = state.readRegister(Registers.Index(raw: 7), Registers.Index(raw: 8))
        let hash = try? state.readMemory(address: startAddr, length: 32)

        let preimageInfo = try await x.serviceAccounts.get(serviceAccount: x.serviceIndex, preimageHash: Data32(hash!)!, length: length)
        let notRequestedYet = preimageInfo == nil
        let isPreviouslyAvailable = preimageInfo?.count == 2
        let canSolicit = notRequestedYet || isPreviouslyAvailable

        let acc = try await x.serviceAccounts.get(serviceAccount: x.serviceIndex)

        if hash == nil {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.OOB.rawValue)
        } else if !canSolicit {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.HUH.rawValue)
        } else if let acc, acc.balance < acc.thresholdBalance(config: config) {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.FULL.rawValue)
        } else {
            if notRequestedYet {
                x.serviceAccounts.set(serviceAccount: x.serviceIndex, preimageHash: Data32(hash!)!, length: length, value: [])
            } else if isPreviouslyAvailable, var preimageInfo {
                preimageInfo.append(timeslot)
                x.serviceAccounts.set(serviceAccount: x.serviceIndex, preimageHash: Data32(hash!)!, length: length, value: preimageInfo)
            }
        }
    }
}

/// Forget data made available in-core (through preimage lookups)
public class Forget: HostCall {
    public static var identifier: UInt8 { 14 }

    public var x: AccumlateResultContext
    public let timeslot: TimeslotIndex

    public init(x: inout AccumlateResultContext, timeslot: TimeslotIndex) {
        self.x = x
        self.timeslot = timeslot
    }

    public func _callImpl(config: ProtocolConfigRef, state: VMState) async throws {
        let (startAddr, length) = state.readRegister(Registers.Index(raw: 7), Registers.Index(raw: 8))
        let hash = try? state.readMemory(address: startAddr, length: 32)
        let minHoldPeriod = TimeslotIndex(config.value.preimagePurgePeriod)

        let preimageInfo = try await x.serviceAccounts.get(serviceAccount: x.serviceIndex, preimageHash: Data32(hash!)!, length: length)
        let historyCount = preimageInfo?.count

        let canExpunge = historyCount == 0 || (historyCount == 2 && preimageInfo![1] < timeslot - minHoldPeriod)
        let isAvailable1 = historyCount == 1
        let isAvailable3 = historyCount == 3 && (preimageInfo![1] < timeslot - minHoldPeriod)
        let canForget = canExpunge || isAvailable1 || isAvailable3

        if hash == nil {
            state.writeRegister(Registers.Index(raw: 0), HostCallResultCode.OOB.rawValue)
        } else if !canForget {
            state.writeRegister(Registers.Index(raw: 0), HostCallResultCode.HUH.rawValue)
        } else {
            if canExpunge {
                x.serviceAccounts.remove(serviceAccount: x.serviceIndex, preimageHash: Data32(hash!)!, length: length)
                x.serviceAccounts.remove(serviceAccount: x.serviceIndex, preimageHash: Data32(hash!)!)
            } else if isAvailable1, var preimageInfo {
                preimageInfo.append(timeslot)
                x.serviceAccounts.set(serviceAccount: x.serviceIndex, preimageHash: Data32(hash!)!, length: length, value: preimageInfo)
            } else if isAvailable3, var preimageInfo {
                preimageInfo = [preimageInfo[2], timeslot]
                x.serviceAccounts.set(serviceAccount: x.serviceIndex, preimageHash: Data32(hash!)!, length: length, value: preimageInfo)
            }
        }
    }
}
