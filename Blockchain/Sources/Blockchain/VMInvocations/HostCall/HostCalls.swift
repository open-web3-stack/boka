import Codec
import Foundation
import PolkaVM
import Utils

// MARK: - General

/// Get gas remaining
public class GasFn: HostCall {
    public static var identifier: UInt8 { 0 }

    public func _callImpl(config _: ProtocolConfigRef, state: VMState) throws {
        state.writeRegister(Registers.Index(raw: 7), UInt32(bitPattern: Int32(state.getGas().value & 0xFFFF_FFFF)))
        state.writeRegister(Registers.Index(raw: 8), UInt32(bitPattern: Int32(state.getGas().value >> 32)))
    }
}

/// Lookup a preimage from a service account
public class Lookup: HostCall {
    public static var identifier: UInt8 { 1 }

    public let serviceAccount: ServiceAccount
    public let serviceIndex: ServiceIndex
    public let serviceAccounts: [ServiceIndex: ServiceAccount]

    public init(account: ServiceAccount, serviceIndex: ServiceIndex, accounts: [ServiceIndex: ServiceAccount]) {
        serviceAccount = account
        self.serviceIndex = serviceIndex
        serviceAccounts = accounts
    }

    public func _callImpl(config _: ProtocolConfigRef, state: VMState) throws {
        var account: ServiceAccount?
        let reg = state.readRegister(Registers.Index(raw: 7))
        if reg == serviceIndex || reg == Int32.max {
            account = serviceAccount
        } else {
            account = serviceAccounts[reg]
        }

        let regs = state.readRegisters(in: 8 ..< 11)

        let preimageHash = try? Blake2b256.hash(state.readMemory(address: regs[0], length: 32))

        let value: Data? = if let account, let preimageHash {
            account.preimages[preimageHash]
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

    public let serviceAccount: ServiceAccount
    public let serviceIndex: ServiceIndex
    public let serviceAccounts: [ServiceIndex: ServiceAccount]

    public init(account: ServiceAccount, serviceIndex: ServiceIndex, accounts: [ServiceIndex: ServiceAccount]) {
        serviceAccount = account
        self.serviceIndex = serviceIndex
        serviceAccounts = accounts
    }

    public func _callImpl(config _: ProtocolConfigRef, state: VMState) throws {
        var account: ServiceAccount?
        let reg = state.readRegister(Registers.Index(raw: 7))
        if reg == serviceIndex || reg == Int32.max {
            account = serviceAccount
        } else {
            account = serviceAccounts[reg]
        }

        let regs = state.readRegisters(in: 8 ..< 12)

        let key = try? Blake2b256.hash(serviceIndex.encode(), state.readMemory(address: regs[0], length: Int(regs[1])))

        let value: Data? = if let account, let key {
            account.storage[key]
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

    public var serviceAccount: ServiceAccount
    public let serviceIndex: ServiceIndex

    public init(account: inout ServiceAccount, serviceIndex: ServiceIndex) {
        serviceAccount = account
        self.serviceIndex = serviceIndex
    }

    public func _callImpl(config: ProtocolConfigRef, state: VMState) throws {
        let regs = state.readRegisters(in: 7 ..< 11)

        let key = try? Blake2b256.hash(serviceIndex.encode(), state.readMemory(address: regs[0], length: Int(regs[1])))

        var account: ServiceAccount?
        if let key, state.isMemoryReadable(address: regs[2], length: Int(regs[3])) {
            account = serviceAccount
            if regs[3] == 0 {
                account?.storage.removeValue(forKey: key)
            } else {
                account?.storage[key] = try state.readMemory(address: regs[2], length: Int(regs[3]))
            }
        } else {
            account = nil
        }

        let l = if let key, serviceAccount.storage.keys.contains(key) {
            UInt32(serviceAccount.storage[key]!.count)
        } else {
            HostCallResultCode.NONE.rawValue
        }

        if key != nil, let account, account.thresholdBalance(config: config) <= account.balance {
            state.writeRegister(Registers.Index(raw: 7), l)
            serviceAccount = account
        } else if let account, account.thresholdBalance(config: config) > account.balance {
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
    public let serviceAccounts: [ServiceIndex: ServiceAccount]

    public init(
        serviceIndex: ServiceIndex,
        accounts: [ServiceIndex: ServiceAccount]
    ) {
        self.serviceIndex = serviceIndex
        serviceAccounts = accounts
    }

    public func _callImpl(config: ProtocolConfigRef, state: VMState) throws {
        var account: ServiceAccount?
        let reg = state.readRegister(Registers.Index(raw: 7))
        if reg == Int32.max {
            account = serviceAccounts[serviceIndex]
        } else {
            account = serviceAccounts[reg]
        }

        let o = state.readRegister(Registers.Index(raw: 8))

        let m: Data?
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

    public func _callImpl(config _: ProtocolConfigRef, state: VMState) throws {
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

    public func _callImpl(config: ProtocolConfigRef, state: VMState) throws {
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

    public func _callImpl(config: ProtocolConfigRef, state: VMState) throws {
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

    public func _callImpl(config _: ProtocolConfigRef, state: VMState) throws {
        state.writeRegister(Registers.Index(raw: 7), UInt32(bitPattern: Int32(state.getGas().value & 0xFFFF_FFFF)))
        state.writeRegister(Registers.Index(raw: 8), UInt32(bitPattern: Int32(state.getGas().value >> 32)))

        y = x
    }
}

/// Create a new service account
public class New: HostCall {
    public static var identifier: UInt8 { 9 }

    public var x: AccumlateResultContext
    public var account: ServiceAccount
    public let accounts: [ServiceIndex: ServiceAccount]

    public init(x: inout AccumlateResultContext, account: ServiceAccount, accounts: [ServiceIndex: ServiceAccount]) {
        self.x = x
        self.account = account
        self.accounts = accounts
    }

    private func bump(i: ServiceIndex) -> ServiceIndex {
        256 + ((i - 256 + 42) & (serviceIndexModValue - 1))
    }

    public func _callImpl(config: ProtocolConfigRef, state: VMState) throws {
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

        if let newAccount {
            account.balance -= newAccount.balance
        }

        if let newAccount, account.balance >= account.thresholdBalance(config: config) {
            state.writeRegister(Registers.Index(raw: 7), x.nextAccountIndex)
            x.accumulateState.serviceAccounts.merge([x.nextAccountIndex: newAccount, x.serviceIndex: account]) { _, new in new }
            x.nextAccountIndex = try AccumulateContext.check(i: bump(i: x.nextAccountIndex), serviceAccounts: accounts)
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

    public func _callImpl(config _: ProtocolConfigRef, state: VMState) throws {
        let regs = state.readRegisters(in: 7 ..< 12)

        let codeHash: Data32? = try? Data32(state.readMemory(address: regs[0], length: 32))
        let minAccumlateGas = Gas(0x1_0000_0000) * Gas(regs[1]) + Gas(regs[2])
        let minOnTransferGas = Gas(0x1_0000_0000) * Gas(regs[3]) + Gas(regs[4])

        if let codeHash {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.OK.rawValue)
            x.accumulateState.serviceAccounts[x.serviceIndex]?.codeHash = codeHash
            x.accumulateState.serviceAccounts[x.serviceIndex]?.minAccumlateGas = minAccumlateGas
            x.accumulateState.serviceAccounts[x.serviceIndex]?.minOnTransferGas = minOnTransferGas
        } else {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.OOB.rawValue)
        }
    }
}

/// Make a transfer
public class Transfer: HostCall {
    public static var identifier: UInt8 { 11 }

    public var x: AccumlateResultContext
    public let account: ServiceAccount
    public let accounts: [ServiceIndex: ServiceAccount]

    public init(x: inout AccumlateResultContext, account: ServiceAccount, accounts: [ServiceIndex: ServiceAccount]) {
        self.x = x
        self.account = account
        self.accounts = accounts
    }

    public func gasCost(state: VMState) -> Gas {
        let (reg8, reg9) = state.readRegister(Registers.Index(raw: 8), Registers.Index(raw: 9))
        return Gas(10) + Gas(reg8) + Gas(0x1_0000_0000) * Gas(reg9)
    }

    public func _callImpl(config: ProtocolConfigRef, state: VMState) throws {
        let regs = state.readRegisters(in: 0 ..< 6)
        let amount = Balance(0x1_0000_0000) * Balance(regs[2]) + Balance(regs[1])
        let gasLimit = Gas(0x1_0000_0000) * Gas(regs[4]) + Gas(regs[3])
        let memo = try? state.readMemory(address: regs[5], length: config.value.transferMemoSize)
        let dest = regs[0]

        let newBalance = account.balance - amount

        if memo == nil {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.OOB.rawValue)
        } else if accounts[dest] == nil {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.WHO.rawValue)
        } else if gasLimit < accounts[dest]!.minOnTransferGas {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.LOW.rawValue)
        } else if Gas(state.getGas()) < gasLimit {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.HIGH.rawValue)
        } else if newBalance < account.thresholdBalance(config: config) {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.CASH.rawValue)
        } else {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.OK.rawValue)
            x.transfers.append(DeferredTransfers(
                sender: x.serviceIndex,
                destination: dest,
                amount: amount,
                memo: Data128(memo!)!,
                gasLimit: gasLimit
            ))
            x.accumulateState.serviceAccounts[x.serviceIndex]!.balance = newBalance
        }
    }
}

/// Quit (remove) a service account
public class Quit: HostCall {
    public static var identifier: UInt8 { 12 }

    public var x: AccumlateResultContext
    public let account: ServiceAccount
    public let accounts: [ServiceIndex: ServiceAccount]

    public init(x: inout AccumlateResultContext, account: ServiceAccount, accounts: [ServiceIndex: ServiceAccount]) {
        self.x = x
        self.account = account
        self.accounts = accounts
    }

    public func gasCost(state: VMState) -> Gas {
        let (reg8, reg9) = state.readRegister(Registers.Index(raw: 8), Registers.Index(raw: 9))
        return Gas(10) + Gas(reg8) + Gas(0x1_0000_0000) * Gas(reg9)
    }

    public func _callImpl(config: ProtocolConfigRef, state: VMState) throws {
        let (dest, startAddr) = state.readRegister(Registers.Index(raw: 7), Registers.Index(raw: 8))
        let amount = account.balance - account.thresholdBalance(config: config) + Balance(config.value.serviceMinBalance)
        let gasLimit = Gas(state.getGas())

        let isValidDest = dest == x.serviceIndex || dest == Int32.max
        let memoData = try? state.readMemory(address: startAddr, length: config.value.transferMemoSize)
        let memo = memoData != nil ? try JamDecoder.decode(Data128.self, from: memoData!) : nil

        if isValidDest {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.OK.rawValue)
            x.accumulateState.serviceAccounts.removeValue(forKey: x.serviceIndex)
            throw VMInvocationsError.forceHalt
        } else if memo == nil {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.OOB.rawValue)
        } else if accounts[dest] == nil {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.WHO.rawValue)
        } else if gasLimit < accounts[dest]!.minOnTransferGas {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.LOW.rawValue)
        } else {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.OK.rawValue)
            x.accumulateState.serviceAccounts.removeValue(forKey: x.serviceIndex)
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

    public func _callImpl(config: ProtocolConfigRef, state: VMState) throws {
        let (startAddr, length) = state.readRegister(Registers.Index(raw: 7), Registers.Index(raw: 8))
        let hash = try? state.readMemory(address: startAddr, length: 32)
        var account: ServiceAccount?
        if let hash {
            let hashAndLength = HashAndLength(hash: Data32(hash)!, length: length)
            account = x.accumulateState.serviceAccounts[x.serviceIndex]
            if account?.preimageInfos[hashAndLength] == nil {
                account?.preimageInfos[hashAndLength] = []
            } else if account?.preimageInfos[hashAndLength]!.count == 2 {
                account?.preimageInfos[hashAndLength]!.append(timeslot)
            }
        }

        if hash == nil {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.OOB.rawValue)
        } else if account == nil {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.HUH.rawValue)
        } else if account!.balance < account!.thresholdBalance(config: config) {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.FULL.rawValue)
        } else {
            x.accumulateState.serviceAccounts[x.serviceIndex] = account
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

    public func _callImpl(config: ProtocolConfigRef, state: VMState) throws {
        let (startAddr, length) = state.readRegister(Registers.Index(raw: 7), Registers.Index(raw: 8))
        let hash = try? state.readMemory(address: startAddr, length: 32)
        var account: ServiceAccount?
        if let hash {
            let hashAndLength = HashAndLength(hash: Data32(hash)!, length: length)
            account = x.accumulateState.serviceAccounts[x.serviceIndex]
            let value = account?.preimageInfos[hashAndLength]
            let minHoldPeriod = TimeslotIndex(config.value.preimagePurgePeriod)

            if value?.count == 0 || (value?.count == 2 && value![1] < timeslot - minHoldPeriod) {
                account?.preimageInfos.removeValue(forKey: hashAndLength)
                account?.preimages.removeValue(forKey: hashAndLength.hash)
            } else if value?.count == 1 {
                account?.preimageInfos[hashAndLength]!.append(timeslot)
            } else if value?.count == 3, value![1] < timeslot - minHoldPeriod {
                account?.preimageInfos[hashAndLength] = [value![2], timeslot]
            }
        }

        if hash == nil {
            state.writeRegister(Registers.Index(raw: 0), HostCallResultCode.OOB.rawValue)
        } else if account == nil {
            state.writeRegister(Registers.Index(raw: 0), HostCallResultCode.HUH.rawValue)
        } else {
            x.accumulateState.serviceAccounts[x.serviceIndex] = account
        }
    }
}
