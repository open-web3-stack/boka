import Codec
import Foundation
import Numerics
import PolkaVM
import Utils

// MARK: - General

/// Get gas remaining
public class GasFn: HostCall {
    public static var identifier: UInt8 { 0 }

    public func _callImpl(config _: ProtocolConfigRef, state: VMState) throws {
        state.writeRegister(Registers.Index(raw: 0), UInt32(bitPattern: Int32(state.getGas() & 0xFFFF_FFFF)))
        state.writeRegister(Registers.Index(raw: 1), UInt32(bitPattern: Int32(state.getGas() >> 32)))
    }
}

/// Lookup a preimage from a service account
public class Lookup: HostCall {
    public static var identifier: UInt8 { 1 }

    public let serviceAccount: ServiceAccount
    public let serviceIndex: ServiceIndex
    public let serviceAccounts: [ServiceIndex: ServiceAccount]

    public init(serviceAccount: ServiceAccount, serviceIndex: ServiceIndex, serviceAccounts: [ServiceIndex: ServiceAccount]) {
        self.serviceAccount = serviceAccount
        self.serviceIndex = serviceIndex
        self.serviceAccounts = serviceAccounts
    }

    public func _callImpl(config _: ProtocolConfigRef, state: VMState) throws {
        var account: ServiceAccount?
        let reg0 = state.readRegister(Registers.Index(raw: 0))
        if reg0 == serviceIndex || reg0 == Int32.max {
            account = serviceAccount
        } else {
            account = serviceAccounts[reg0]
        }

        let regs = state.readRegisters(in: 1 ..< 4)

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
                state.writeRegister(Registers.Index(raw: 0), UInt32(value.count))
            } else {
                state.writeRegister(Registers.Index(raw: 0), HostCallResultCode.NONE.rawValue)
            }
        } else {
            state.writeRegister(Registers.Index(raw: 0), HostCallResultCode.OOB.rawValue)
        }
    }
}

/// Read a service account storage
public class Read: HostCall {
    public static var identifier: UInt8 { 2 }

    public let serviceAccount: ServiceAccount
    public let serviceIndex: ServiceIndex
    public let serviceAccounts: [ServiceIndex: ServiceAccount]

    public init(serviceAccount: ServiceAccount, serviceIndex: ServiceIndex, serviceAccounts: [ServiceIndex: ServiceAccount]) {
        self.serviceAccount = serviceAccount
        self.serviceIndex = serviceIndex
        self.serviceAccounts = serviceAccounts
    }

    public func _callImpl(config _: ProtocolConfigRef, state: VMState) throws {
        var account: ServiceAccount?
        let reg0 = state.readRegister(Registers.Index(raw: 0))
        if reg0 == serviceIndex || reg0 == Int32.max {
            account = serviceAccount
        } else {
            account = serviceAccounts[reg0]
        }

        let regs = state.readRegisters(in: 1 ..< 5)

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
                state.writeRegister(Registers.Index(raw: 0), UInt32(value.count))
            } else {
                state.writeRegister(Registers.Index(raw: 0), HostCallResultCode.NONE.rawValue)
            }
        } else {
            state.writeRegister(Registers.Index(raw: 0), HostCallResultCode.OOB.rawValue)
        }
    }
}

/// Write to a service account storage
public class Write: HostCall {
    public static var identifier: UInt8 { 3 }

    public var serviceAccount: ServiceAccount
    public let serviceIndex: ServiceIndex

    public init(serviceAccount: inout ServiceAccount, serviceIndex: ServiceIndex) {
        self.serviceAccount = serviceAccount
        self.serviceIndex = serviceIndex
    }

    public func _callImpl(config: ProtocolConfigRef, state: VMState) throws {
        let regs = state.readRegisters(in: 0 ..< 4)

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
            state.writeRegister(Registers.Index(raw: 0), l)
            serviceAccount = account
        } else if let account, account.thresholdBalance(config: config) > account.balance {
            state.writeRegister(Registers.Index(raw: 0), HostCallResultCode.FULL.rawValue)
        } else {
            state.writeRegister(Registers.Index(raw: 0), HostCallResultCode.OOB.rawValue)
        }
    }
}

/// Get information about a service account
public class Info: HostCall {
    public static var identifier: UInt8 { 4 }

    public let serviceAccount: ServiceAccount
    public let serviceIndex: ServiceIndex
    public let serviceAccounts: [ServiceIndex: ServiceAccount]
    // only used in accumulation x.n
    public let newServiceAccounts: [ServiceIndex: ServiceAccount]

    public init(
        serviceAccount: ServiceAccount,
        serviceIndex: ServiceIndex,
        serviceAccounts: [ServiceIndex: ServiceAccount],
        newServiceAccounts: [ServiceIndex: ServiceAccount]
    ) {
        self.serviceAccount = serviceAccount
        self.serviceIndex = serviceIndex
        self.serviceAccounts = serviceAccounts
        self.newServiceAccounts = newServiceAccounts
    }

    public func _callImpl(config: ProtocolConfigRef, state: VMState) throws {
        var account: ServiceAccount?
        let reg0 = state.readRegister(Registers.Index(raw: 0))
        if reg0 == serviceIndex || reg0 == Int32.max {
            account = serviceAccount
        } else {
            let accounts = serviceAccounts.merging(newServiceAccounts) { _, new in new }
            account = accounts[reg0]
        }

        let o = state.readRegister(Registers.Index(raw: 1))

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
            state.writeRegister(Registers.Index(raw: 0), HostCallResultCode.OK.rawValue)
        } else if m == nil {
            state.writeRegister(Registers.Index(raw: 0), HostCallResultCode.NONE.rawValue)
        } else {
            state.writeRegister(Registers.Index(raw: 0), HostCallResultCode.OOB.rawValue)
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
        let regs = state.readRegisters(in: 0 ..< 5)

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
            state.writeRegister(Registers.Index(raw: 0), HostCallResultCode.OK.rawValue)
            x.privilegedServices.empower = regs[0]
            x.privilegedServices.assign = regs[1]
            x.privilegedServices.designate = regs[2]
            x.privilegedServices.basicGas = basicGas
        } else {
            state.writeRegister(Registers.Index(raw: 0), HostCallResultCode.OOB.rawValue)
        }
    }
}

/// Set authorization queue for a service account
public class Assign: HostCall {
    public static var identifier: UInt8 { 6 }

    public var x: AccumlateResultContext

    public init(x: inout AccumlateResultContext) {
        self.x = x
    }

    public func _callImpl(config: ProtocolConfigRef, state: VMState) throws {
        let (targetCoreIndex, startAddr) = state.readRegister(Registers.Index(raw: 0), Registers.Index(raw: 1))

        var authorizationQueue: [Data32] = []
        let length = 32 * config.value.maxAuthorizationsQueueItems
        if state.isMemoryReadable(address: startAddr, length: length) {
            let data = try state.readMemory(address: startAddr, length: length)
            for i in stride(from: 0, to: length, by: 32) {
                authorizationQueue.append(Data32(data[i ..< i + 32])!)
            }
        }

        if targetCoreIndex < config.value.totalNumberOfCores, !authorizationQueue.isEmpty {
            x.authorizationQueue[targetCoreIndex] = try ConfigFixedSizeArray(config: config, array: authorizationQueue)
            state.writeRegister(Registers.Index(raw: 0), HostCallResultCode.OK.rawValue)
        } else if authorizationQueue.isEmpty {
            state.writeRegister(Registers.Index(raw: 0), HostCallResultCode.OOB.rawValue)
        } else {
            state.writeRegister(Registers.Index(raw: 0), HostCallResultCode.CORE.rawValue)
        }
    }
}

/// Set validator queue for a service account
public class Designate: HostCall {
    public static var identifier: UInt8 { 7 }

    public var x: AccumlateResultContext

    public init(x: inout AccumlateResultContext) {
        self.x = x
    }

    public func _callImpl(config: ProtocolConfigRef, state: VMState) throws {
        let startAddr = state.readRegister(Registers.Index(raw: 0))

        var validatorQueue: [ValidatorKey] = []
        let length = 336 * config.value.totalNumberOfValidators
        if state.isMemoryReadable(address: startAddr, length: length) {
            let data = try state.readMemory(address: startAddr, length: length)
            for i in stride(from: 0, to: length, by: 336) {
                try validatorQueue.append(ValidatorKey(data: Data(data[i ..< i + 336])))
            }
        }

        if !validatorQueue.isEmpty {
            x.validatorQueue = try ConfigFixedSizeArray(config: config, array: validatorQueue)
            state.writeRegister(Registers.Index(raw: 0), HostCallResultCode.OK.rawValue)
        } else {
            state.writeRegister(Registers.Index(raw: 0), HostCallResultCode.OOB.rawValue)
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
        state.writeRegister(Registers.Index(raw: 0), UInt32(bitPattern: Int32(state.getGas() & 0xFFFF_FFFF)))
        state.writeRegister(Registers.Index(raw: 1), UInt32(bitPattern: Int32(state.getGas() >> 32)))

        y = x
    }
}

/// Create a new service account
public class New: HostCall {
    public static var identifier: UInt8 { 9 }

    public var x: AccumlateResultContext
    public let accounts: [ServiceIndex: ServiceAccount]

    public init(x: inout AccumlateResultContext, accounts: [ServiceIndex: ServiceAccount]) {
        self.x = x
        self.accounts = accounts
    }

    private static func bump(i: ServiceIndex) -> ServiceIndex {
        256 + ((i - 256 + 42) & (serviceIndexModValue - 1))
    }

    public func _callImpl(config: ProtocolConfigRef, state: VMState) throws {
        let regs = state.readRegisters(in: 0 ..< 6)

        let codeHash: Data32? = try? Data32(state.readMemory(address: regs[0], length: 32))
        let minAccumlateGas: Gas = (UInt64(UInt32.max) + 1) * UInt64(regs[3]) + UInt64(regs[2])
        let minOnTransferGas: Gas = (UInt64(UInt32.max) + 1) * UInt64(regs[5]) + UInt64(regs[4])

        var newAccount: ServiceAccount?
        if let codeHash {
            newAccount = ServiceAccount(
                storage: [:],
                preimages: [:],
                preimageInfos: [HashAndLength(hash: codeHash, length: regs[1]): LimitedSizeArray([])],
                codeHash: codeHash,
                balance: 0,
                minAccumlateGas: minAccumlateGas,
                minOnTransferGas: minOnTransferGas
            )
            newAccount!.balance = newAccount!.thresholdBalance(config: config)
        }

        let newBalance = (x.account?.balance ?? 0).subtractingWithSaturation(newAccount!.balance)

        if let newAccount, x.account != nil, newBalance >= x.account!.thresholdBalance(config: config) {
            state.writeRegister(Registers.Index(raw: 0), x.serviceIndex)
            x.newAccounts[x.serviceIndex] = newAccount
            x.account!.balance = newBalance
            x.serviceIndex = try AccumulateContext.check(i: New.bump(i: x.serviceIndex), serviceAccounts: accounts)
        } else if codeHash == nil {
            state.writeRegister(Registers.Index(raw: 0), HostCallResultCode.OOB.rawValue)
        } else {
            state.writeRegister(Registers.Index(raw: 0), HostCallResultCode.CASH.rawValue)
        }
    }
}

/// Upgrade a service account
public class Upgrade: HostCall {
    public static var identifier: UInt8 { 10 }

    public var x: AccumlateResultContext
    public let serviceIndex: ServiceIndex

    public init(x: inout AccumlateResultContext, serviceIndex: ServiceIndex) {
        self.x = x
        self.serviceIndex = serviceIndex
    }

    public func _callImpl(config _: ProtocolConfigRef, state: VMState) throws {
        let regs = state.readRegisters(in: 0 ..< 5)

        let codeHash: Data32? = try? Data32(state.readMemory(address: regs[0], length: 32))
        let minAccumlateGas: Gas = (UInt64(UInt32.max) + 1) * UInt64(regs[1]) + UInt64(regs[2])
        let minOnTransferGas: Gas = (UInt64(UInt32.max) + 1) * UInt64(regs[3]) + UInt64(regs[4])

        if let codeHash {
            state.writeRegister(Registers.Index(raw: 0), HostCallResultCode.OK.rawValue)
            x.newAccounts[serviceIndex]?.codeHash = codeHash
            x.newAccounts[serviceIndex]?.minAccumlateGas = minAccumlateGas
            x.newAccounts[serviceIndex]?.minOnTransferGas = minOnTransferGas
        } else {
            state.writeRegister(Registers.Index(raw: 0), HostCallResultCode.OOB.rawValue)
        }
    }
}
