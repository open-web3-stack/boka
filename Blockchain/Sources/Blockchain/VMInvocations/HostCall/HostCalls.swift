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
        let reg7: UInt64 = state.readRegister(Registers.Index(raw: 7))
        let service: ServiceIndex? = if reg7 == serviceIndex || reg7 == Int64.max {
            serviceIndex
        } else if try await serviceAccounts.get(serviceAccount: ServiceIndex(truncatingIfNeeded: reg7)) != nil {
            ServiceIndex(truncatingIfNeeded: reg7)
        } else {
            nil
        }

        let regs: [UInt32] = state.readRegisters(in: 8 ..< 10)

        if !state.isMemoryReadable(address: regs[0], length: 32) {
            throw VMInvocationsError.panic
        }

        let preimageHash = try? Blake2b256.hash(state.readMemory(address: regs[0], length: 32))

        let value: Data? = if let service, let preimageHash {
            try await serviceAccounts.get(serviceAccount: service, preimageHash: preimageHash)
        } else {
            nil
        }

        let reg10: UInt64 = state.readRegister(Registers.Index(raw: 10))
        let reg11: UInt64 = state.readRegister(Registers.Index(raw: 11))

        let first = min(Int(reg10), value?.count ?? 0)
        let len = min(Int(reg11), (value?.count ?? 0) - first)

        if !state.isMemoryWritable(address: regs[1], length: len) {
            throw VMInvocationsError.panic
        } else if value == nil {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.NONE.rawValue)
        } else {
            state.writeRegister(Registers.Index(raw: 7), value!.count)
            try state.writeMemory(address: regs[1], values: value![relative: first ..< (first + len)])
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
        let reg7: UInt64 = state.readRegister(Registers.Index(raw: 7))
        let serviceX = reg7 == Int64.max ? serviceIndex : ServiceIndex(truncatingIfNeeded: reg7)

        let service: ServiceIndex? = if serviceX == serviceIndex {
            serviceIndex
        } else if try await serviceAccounts.get(serviceAccount: serviceX) != nil {
            serviceX
        } else {
            nil
        }

        let regs: [UInt32] = state.readRegisters(in: 8 ..< 11)

        if !state.isMemoryReadable(address: regs[0], length: Int(regs[1])) {
            throw VMInvocationsError.panic
        }

        let key = try? Blake2b256.hash(serviceX.encode(), state.readMemory(address: regs[0], length: Int(regs[1])))

        let value: Data? = if let service, let key {
            try await serviceAccounts.get(serviceAccount: service, storageKey: key)
        } else {
            nil
        }

        let reg11: UInt64 = state.readRegister(Registers.Index(raw: 11))
        let reg12: UInt64 = state.readRegister(Registers.Index(raw: 12))

        let first = min(Int(reg11), value?.count ?? 0)
        let len = min(Int(reg12), (value?.count ?? 0) - first)

        if !state.isMemoryWritable(address: regs[2], length: len) {
            throw VMInvocationsError.panic
        } else if value == nil {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.NONE.rawValue)
        } else {
            state.writeRegister(Registers.Index(raw: 7), value!.count)
            try state.writeMemory(address: regs[2], values: value![relative: first ..< (first + len)])
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
        let regs: [UInt32] = state.readRegisters(in: 7 ..< 11)

        let key = try? Blake2b256.hash(serviceIndex.encode(), state.readMemory(address: regs[0], length: Int(regs[1])))

        if key == nil || (regs[3] != 0 && !state.isMemoryReadable(address: regs[2], length: Int(regs[3]))) {
            throw VMInvocationsError.panic
        }

        let len = if let key, let value = try await serviceAccounts.get(serviceAccount: serviceIndex, storageKey: key) {
            UInt64(value.count)
        } else {
            HostCallResultCode.NONE.rawValue
        }

        let accountDetails = try await serviceAccounts.get(serviceAccount: serviceIndex)
        if let accountDetails, accountDetails.thresholdBalance(config: config) > accountDetails.balance {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.FULL.rawValue)
        } else {
            state.writeRegister(Registers.Index(raw: 7), len)
            if regs[3] == 0 {
                serviceAccounts.set(serviceAccount: serviceIndex, storageKey: key!, value: nil)
            } else {
                try serviceAccounts.set(
                    serviceAccount: serviceIndex,
                    storageKey: key!,
                    value: state.readMemory(address: regs[2], length: Int(regs[3]))
                )
            }
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
        let reg: UInt64 = state.readRegister(Registers.Index(raw: 7))
        if reg == Int64.max {
            service = serviceIndex
        } else {
            service = ServiceIndex(truncatingIfNeeded: reg)
        }

        let o: UInt32 = state.readRegister(Registers.Index(raw: 8))

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
        }

        if !state.isMemoryWritable(address: o, length: Int(m!.count)) {
            throw VMInvocationsError.panic
        } else if m == nil {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.NONE.rawValue)
        } else {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.OK.rawValue)
        }
    }
}

// MARK: - Accumulate

/// Set privileged services details
public class Bless: HostCall {
    public static var identifier: UInt8 { 5 }

    public var x: AccumlateResultContext

    public init(x: inout AccumlateResultContext) {
        self.x = x
    }

    public func _callImpl(config _: ProtocolConfigRef, state: VMState) async throws {
        let regs: [UInt32] = state.readRegisters(in: 7 ..< 12)

        var basicGas: [ServiceIndex: Gas]?
        let length = 12 * Int(regs[4])
        if state.isMemoryReadable(address: regs[3], length: length) {
            basicGas = [:]
            let data = try state.readMemory(address: regs[3], length: length)
            for i in stride(from: 0, to: length, by: 12) {
                let serviceIndex = ServiceIndex(data[i ..< i + 4].decode(UInt32.self))
                let gas = Gas(data[i + 4 ..< i + 12].decode(UInt64.self))
                basicGas![serviceIndex] = gas
            }
        }

        if basicGas == nil {
            throw VMInvocationsError.panic
        } else if !regs[0 ..< 3].allSatisfy({ $0 >= 0 && $0 <= Int(UInt32.max) }) {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.WHO.rawValue)
        } else {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.OK.rawValue)
            x.accumulateState.privilegedServices.blessed = regs[0]
            x.accumulateState.privilegedServices.assign = regs[1]
            x.accumulateState.privilegedServices.designate = regs[2]
            x.accumulateState.privilegedServices.basicGas = basicGas!
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
        let (targetCoreIndex, startAddr): (UInt32, UInt32) = state.readRegister(Registers.Index(raw: 7), Registers.Index(raw: 8))

        var authorizationQueue: [Data32]?
        let length = 32 * config.value.maxAuthorizationsQueueItems
        if state.isMemoryReadable(address: startAddr, length: length) {
            authorizationQueue = [Data32]()
            let data = try state.readMemory(address: startAddr, length: length)
            for i in stride(from: 0, to: length, by: 32) {
                authorizationQueue!.append(Data32(data[i ..< i + 32])!)
            }
        }

        if authorizationQueue == nil {
            throw VMInvocationsError.panic
        } else if targetCoreIndex > config.value.totalNumberOfCores {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.CORE.rawValue)
        } else {
            x.accumulateState.authorizationQueue[targetCoreIndex] = try ConfigFixedSizeArray(config: config, array: authorizationQueue!)
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.OK.rawValue)
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
        let startAddr: UInt32 = state.readRegister(Registers.Index(raw: 7))

        var validatorQueue: [ValidatorKey]?
        let length = 336 * config.value.totalNumberOfValidators
        if state.isMemoryReadable(address: startAddr, length: length) {
            validatorQueue = [ValidatorKey]()
            let data = try state.readMemory(address: startAddr, length: length)
            for i in stride(from: 0, to: length, by: 336) {
                try validatorQueue!.append(ValidatorKey(data: Data(data[i ..< i + 336])))
            }
        }

        if validatorQueue == nil {
            throw VMInvocationsError.panic
        } else {
            x.accumulateState.validatorQueue = try ConfigFixedSizeArray(config: config, array: validatorQueue!)
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.OK.rawValue)
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
        state.writeRegister(Registers.Index(raw: 7), UInt64(bitPattern: state.getGas().value))

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
        let regs: [UInt64] = state.readRegisters(in: 7 ..< 11)

        let codeHash: Data32? = try? Data32(state.readMemory(address: regs[0], length: 32))
        let minAccumlateGas = Gas(regs[2])
        let minOnTransferGas = Gas(regs[3])

        var newAccount: ServiceAccount?
        if let codeHash {
            newAccount = ServiceAccount(
                storage: [:],
                preimages: [:],
                preimageInfos: [HashAndLength(hash: codeHash, length: UInt32(truncatingIfNeeded: regs[1])): []],
                codeHash: codeHash,
                balance: Balance(0),
                minAccumlateGas: minAccumlateGas,
                minOnTransferGas: minOnTransferGas
            )
            newAccount!.balance = newAccount!.thresholdBalance(config: config)
        }

        if codeHash == nil {
            throw VMInvocationsError.panic
        } else if let newAccount, let account = try await x.serviceAccounts.get(serviceAccount: x.serviceIndex),
                  account.balance - newAccount.thresholdBalance(config: config) < account.thresholdBalance(config: config)
        {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.CASH.rawValue)
        } else {
            guard let newAccount, var account = try await x.serviceAccounts.get(serviceAccount: x.serviceIndex) else {
                throw VMInvocationsError.panic
            }
            state.writeRegister(Registers.Index(raw: 7), x.nextAccountIndex)
            x.nextAccountIndex = AccumulateContext.check(
                i: bump(i: x.nextAccountIndex),
                serviceAccounts: x.accumulateState.newServiceAccounts
            )

            account.balance -= newAccount.thresholdBalance(config: config)
            x.serviceAccounts.set(serviceAccount: x.serviceIndex, account: account)
            x.accumulateState.newServiceAccounts.merge([x.nextAccountIndex: newAccount]) { _, new in new }
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
        let regs: [UInt64] = state.readRegisters(in: 7 ..< 10)

        let codeHash: Data32? = try? Data32(state.readMemory(address: regs[0], length: 32))

        if let codeHash, var acc = try await x.serviceAccounts.get(serviceAccount: x.serviceIndex) {
            acc.codeHash = codeHash
            acc.minAccumlateGas = Gas(regs[1])
            acc.minOnTransferGas = Gas(regs[2])
            x.serviceAccounts.set(serviceAccount: x.serviceIndex, account: acc)
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.OK.rawValue)
        } else {
            throw VMInvocationsError.panic
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
        let reg9: UInt64 = state.readRegister(Registers.Index(raw: 9))
        return Gas(10) + Gas(reg9)
    }

    public func _callImpl(config: ProtocolConfigRef, state: VMState) async throws {
        let regs: [UInt64] = state.readRegisters(in: 7 ..< 11)
        let amount = Balance(regs[1])
        let gasLimit = Gas(regs[2])
        let memo = try? state.readMemory(address: regs[5], length: config.value.transferMemoSize)
        let dest = UInt32(truncatingIfNeeded: regs[0])

        let acc = try await x.serviceAccounts.get(serviceAccount: x.serviceIndex)

        let destAcc: ServiceAccountDetails? = if try await x.serviceAccounts.get(serviceAccount: dest) != nil {
            try await x.serviceAccounts.get(serviceAccount: dest)
        } else if x.accumulateState.newServiceAccounts[dest] != nil {
            x.accumulateState.newServiceAccounts[dest]?.toDetails()
        } else {
            nil
        }

        if memo == nil {
            throw VMInvocationsError.panic
        } else if destAcc == nil {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.WHO.rawValue)
        } else if gasLimit < destAcc!.minOnTransferGas {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.LOW.rawValue)
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
            acc.balance -= amount
            x.serviceAccounts.set(serviceAccount: x.serviceIndex, account: acc)
        }
    }
}

/// Eject (remove) a service account
public class Eject: HostCall {
    public static var identifier: UInt8 { 12 }

    public var x: AccumlateResultContext
    public let timeslot: TimeslotIndex

    public init(x: inout AccumlateResultContext, timeslot: TimeslotIndex) {
        self.x = x
        self.timeslot = timeslot
    }

    public func _callImpl(config: ProtocolConfigRef, state: VMState) async throws {
        let (reg7, reg8): (UInt64, UInt64) = state.readRegister(Registers.Index(raw: 7), Registers.Index(raw: 8))
        let ejectIndex = ServiceIndex(truncatingIfNeeded: reg7)
        let preimageHash = try? state.readMemory(address: reg8, length: 32)
        let ejectAccount: ServiceAccountDetails? = if ejectIndex == x.serviceIndex {
            nil
        } else if try await x.serviceAccounts.get(serviceAccount: ejectIndex) != nil {
            try await x.serviceAccounts.get(serviceAccount: ejectIndex)
        } else if x.accumulateState.newServiceAccounts[ejectIndex] != nil {
            x.accumulateState.newServiceAccounts[ejectIndex]?.toDetails()
        } else {
            nil
        }
        let minHoldPeriod = TimeslotIndex(config.value.preimagePurgePeriod)

        if preimageHash == nil {
            throw VMInvocationsError.panic
        } else if ejectAccount == nil || ejectAccount?.codeHash.data != Data(x.serviceIndex.encode(method: .fixedWidth(32))) {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.WHO.rawValue)
        }

        let preimageInfo = try await x.serviceAccounts.get(
            serviceAccount: ejectIndex,
            preimageHash: Data32(preimageHash!)!,
            length: max(81, UInt32(ejectAccount!.totalByteLength)) - 81
        )

        if ejectAccount!.itemsCount != 2 || preimageInfo == nil {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.HUH.rawValue)
        } else if preimageInfo!.count == 2, preimageInfo![1] < timeslot - minHoldPeriod {
            var destAccount = try await x.serviceAccounts.get(serviceAccount: x.serviceIndex)
            destAccount?.balance += ejectAccount!.balance
            x.serviceAccounts.set(serviceAccount: ejectIndex, account: nil)
            x.serviceAccounts.set(serviceAccount: x.serviceIndex, account: destAccount)
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.OK.rawValue)
        } else {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.HUH.rawValue)
        }
    }
}

/// Query preimage info
public class Query: HostCall {
    public static var identifier: UInt8 { 13 }

    public var x: AccumlateResultContext

    public init(x: inout AccumlateResultContext) {
        self.x = x
    }

    public func _callImpl(config _: ProtocolConfigRef, state: VMState) async throws {
        let (startAddr, length): (UInt32, UInt32) = state.readRegister(Registers.Index(raw: 7), Registers.Index(raw: 8))
        let preimageHash = try? state.readMemory(address: startAddr, length: 32)
        if preimageHash == nil {
            throw VMInvocationsError.panic
        }

        let preimageInfo = try await x.serviceAccounts.get(
            serviceAccount: x.serviceIndex,
            preimageHash: Data32(preimageHash!)!,
            length: length
        )
        if preimageInfo == nil {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.NONE.rawValue)
            state.writeRegister(Registers.Index(raw: 8), 0)
            return
        }

        if preimageInfo!.isEmpty {
            state.writeRegister(Registers.Index(raw: 7), 0)
            state.writeRegister(Registers.Index(raw: 8), 0)
        } else if preimageInfo!.count == 1 {
            state.writeRegister(Registers.Index(raw: 7), 1 + (1 << 32) * preimageInfo![0])
            state.writeRegister(Registers.Index(raw: 8), 0)
        } else if preimageInfo!.count == 2 {
            state.writeRegister(Registers.Index(raw: 7), 2 + (1 << 32) * preimageInfo![0])
            state.writeRegister(Registers.Index(raw: 8), preimageInfo![1])
        } else if preimageInfo!.count == 3 {
            state.writeRegister(Registers.Index(raw: 7), 3 + (1 << 32) * preimageInfo![0])
            state.writeRegister(Registers.Index(raw: 8), preimageInfo![1] + (1 << 32) * preimageInfo![2])
        }
    }
}

/// Solicit data to be made available in-core (through preimage lookups)
public class Solicit: HostCall {
    public static var identifier: UInt8 { 14 }

    public var x: AccumlateResultContext
    public let timeslot: TimeslotIndex

    public init(x: inout AccumlateResultContext, timeslot: TimeslotIndex) {
        self.x = x
        self.timeslot = timeslot
    }

    public func _callImpl(config: ProtocolConfigRef, state: VMState) async throws {
        let (startAddr, length): (UInt32, UInt32) = state.readRegister(Registers.Index(raw: 7), Registers.Index(raw: 8))
        let hash = try? state.readMemory(address: startAddr, length: 32)

        let preimageInfo = try await x.serviceAccounts.get(serviceAccount: x.serviceIndex, preimageHash: Data32(hash!)!, length: length)
        let notRequestedYet = preimageInfo == nil
        let isPreviouslyAvailable = preimageInfo?.count == 2
        let canSolicit = notRequestedYet || isPreviouslyAvailable

        let acc = try await x.serviceAccounts.get(serviceAccount: x.serviceIndex)

        if hash == nil {
            throw VMInvocationsError.panic
        } else if !canSolicit {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.HUH.rawValue)
        } else if let acc, acc.balance < acc.thresholdBalance(config: config) {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.FULL.rawValue)
        } else {
            if notRequestedYet {
                x.serviceAccounts.set(serviceAccount: x.serviceIndex, preimageHash: Data32(hash!)!, length: length, value: [])
            } else if isPreviouslyAvailable, var preimageInfo {
                try preimageInfo.append(timeslot)
                x.serviceAccounts.set(serviceAccount: x.serviceIndex, preimageHash: Data32(hash!)!, length: length, value: preimageInfo)
            }
        }
    }
}

/// Forget data made available in-core (through preimage lookups)
public class Forget: HostCall {
    public static var identifier: UInt8 { 15 }

    public var x: AccumlateResultContext
    public let timeslot: TimeslotIndex

    public init(x: inout AccumlateResultContext, timeslot: TimeslotIndex) {
        self.x = x
        self.timeslot = timeslot
    }

    public func _callImpl(config: ProtocolConfigRef, state: VMState) async throws {
        let (startAddr, length): (UInt32, UInt32) = state.readRegister(Registers.Index(raw: 7), Registers.Index(raw: 8))
        let hash = try? state.readMemory(address: startAddr, length: 32)
        let minHoldPeriod = TimeslotIndex(config.value.preimagePurgePeriod)

        let preimageInfo = try await x.serviceAccounts.get(serviceAccount: x.serviceIndex, preimageHash: Data32(hash!)!, length: length)
        let historyCount = preimageInfo?.count

        let canExpunge = historyCount == 0 || (historyCount == 2 && preimageInfo![1] < timeslot - minHoldPeriod)
        let isAvailable1 = historyCount == 1
        let isAvailable3 = historyCount == 3 && (preimageInfo![1] < timeslot - minHoldPeriod)
        let canForget = canExpunge || isAvailable1 || isAvailable3

        if hash == nil {
            throw VMInvocationsError.panic
        } else if !canForget {
            state.writeRegister(Registers.Index(raw: 0), HostCallResultCode.HUH.rawValue)
        } else {
            if canExpunge {
                x.serviceAccounts.set(serviceAccount: x.serviceIndex, preimageHash: Data32(hash!)!, length: length, value: nil)
                x.serviceAccounts.set(serviceAccount: x.serviceIndex, preimageHash: Data32(hash!)!, value: nil)
            } else if isAvailable1, var preimageInfo {
                try preimageInfo.append(timeslot)
                x.serviceAccounts.set(serviceAccount: x.serviceIndex, preimageHash: Data32(hash!)!, length: length, value: preimageInfo)
            } else if isAvailable3, var preimageInfo {
                preimageInfo = [preimageInfo[2], timeslot]
                x.serviceAccounts.set(serviceAccount: x.serviceIndex, preimageHash: Data32(hash!)!, length: length, value: preimageInfo)
            }
        }
    }
}

/// Yield accumulation hash
public class Yield: HostCall {
    public static var identifier: UInt8 { 16 }

    public var x: AccumlateResultContext

    public init(x: inout AccumlateResultContext) {
        self.x = x
    }

    public func _callImpl(config _: ProtocolConfigRef, state: VMState) async throws {
        let startAddr: UInt32 = state.readRegister(Registers.Index(raw: 7))
        let hash = try? state.readMemory(address: startAddr, length: 32)
        if hash == nil {
            throw VMInvocationsError.panic
        } else {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.OK.rawValue)
            x.yield = Data32(hash!)!
        }
    }
}

// MARK: - Refine

/// Historical lookup
public class HistoricalLookup: HostCall {
    public static var identifier: UInt8 { 17 }

    public let context: RefineContext.ContextType
    public let serviceIndex: ServiceIndex
    public let serviceAccounts: ServiceAccounts
    public let lookupAnchorTimeslot: TimeslotIndex

    public init(
        context: RefineContext.ContextType,
        serviceIndex: ServiceIndex,
        serviceAccounts: ServiceAccounts,
        lookupAnchorTimeslot: TimeslotIndex
    ) {
        self.context = context
        self.lookupAnchorTimeslot = lookupAnchorTimeslot
        self.serviceIndex = serviceIndex
        self.serviceAccounts = serviceAccounts
    }

    public func _callImpl(config _: ProtocolConfigRef, state: VMState) async throws {
        let reg7: UInt64 = state.readRegister(Registers.Index(raw: 7))
        let service: ServiceIndex? = if reg7 == Int64.max, try await serviceAccounts.get(serviceAccount: serviceIndex) != nil {
            serviceIndex
        } else if try await serviceAccounts.get(serviceAccount: UInt32(truncatingIfNeeded: reg7)) != nil {
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

        let preimage = try await serviceAccounts.historicalLookup(
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
        } else if preimage == nil {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.NONE.rawValue)
        } else {
            state.writeRegister(Registers.Index(raw: 7), preimage!.count)
            try state.writeMemory(address: regs[1], values: preimage![relative: first ..< (first + len)])
        }
    }
}

/// Fetch a segment to memory
public class Fetch: HostCall {
    public static var identifier: UInt8 { 18 }

    public let context: RefineContext.ContextType
    public let serviceAccounts: ServiceAccounts
    public let serviceIndex: ServiceIndex
    public let workPackage: WorkPackage
    public let authorizerOutput: Data
    public let importSegments: [[Data4104]]

    public init(
        context: RefineContext.ContextType,
        serviceAccounts: ServiceAccounts,
        serviceIndex: ServiceIndex,
        workPackage: WorkPackage,
        authorizerOutput: Data,
        importSegments: [[Data4104]]
    ) {
        self.context = context
        self.serviceAccounts = serviceAccounts
        self.serviceIndex = serviceIndex
        self.workPackage = workPackage
        self.authorizerOutput = authorizerOutput
        self.importSegments = importSegments
    }

    public func _callImpl(config _: ProtocolConfigRef, state: VMState) async throws {
        let reg10: UInt64 = state.readRegister(Registers.Index(raw: 10))
        let reg11: UInt64 = state.readRegister(Registers.Index(raw: 11))
        let reg12: UInt64 = state.readRegister(Registers.Index(raw: 12))

        var value: Data?
        switch reg10 {
        case 0:
            value = try JamEncoder.encode(workPackage)
        case 1:
            value = authorizerOutput
        case 2:
            if reg11 < workPackage.workItems.count {
                value = workPackage.workItems[Int(reg11)].payloadBlob
            }
        case 3:
            if reg11 < workPackage.workItems.count, reg12 < workPackage.workItems[Int(reg11)].outputs.count {
                let hash = workPackage.workItems[Int(reg11)].outputs[Int(reg12)].hash
                value = try await serviceAccounts.get(serviceAccount: serviceIndex, preimageHash: hash)
            }
        case 4:
            if reg11 < workPackage.workItems[Int(serviceIndex)].outputs.count {
                let hash = workPackage.workItems[Int(serviceIndex)].outputs[Int(reg11)].hash
                value = try await serviceAccounts.get(serviceAccount: serviceIndex, preimageHash: hash)
            }
        case 5:
            if reg11 < importSegments.count, reg12 < importSegments[Int(reg11)].count {
                value = importSegments[Int(reg11)][Int(reg12)].data
            }
        case 6:
            if reg11 < importSegments[Int(serviceIndex)].count {
                value = importSegments[Int(serviceIndex)][Int(reg11)].data
            }
        default:
            value = nil
        }

        let writeAddr: UInt32 = state.readRegister(Registers.Index(raw: 7))

        let reg8: UInt64 = state.readRegister(Registers.Index(raw: 8))
        let reg9: UInt64 = state.readRegister(Registers.Index(raw: 9))

        let first = min(Int(reg8), value?.count ?? 0)
        let len = min(Int(reg9), (value?.count ?? 0) - first)

        let isWritable = state.isMemoryWritable(address: writeAddr, length: len)

        if !isWritable {
            throw VMInvocationsError.panic
        } else if value == nil {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.NONE.rawValue)
        } else {
            state.writeRegister(Registers.Index(raw: 7), value!.count)
            try state.writeMemory(address: writeAddr, values: value![relative: first ..< (first + len)])
        }
    }
}

/// Export a segment from memory
public class Export: HostCall {
    public static var identifier: UInt8 { 19 }

    public var context: RefineContext.ContextType
    public let exportSegmentOffset: UInt64

    public init(context: inout RefineContext.ContextType, exportSegmentOffset: UInt64) {
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

        if exportSegmentOffset + UInt64(context.exports.count) >= UInt64(config.value.maxWorkPackageManifestEntries) {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.FULL.rawValue)
        } else {
            state.writeRegister(Registers.Index(raw: 7), exportSegmentOffset + UInt64(context.exports.count))
            context.exports.append(segment)
        }
    }
}

/// Create an inner PVM
public class Machine: HostCall {
    public static var identifier: UInt8 { 20 }

    public var context: RefineContext.ContextType

    public init(context: inout RefineContext.ContextType) {
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
    public static var identifier: UInt8 { 21 }

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
    public static var identifier: UInt8 { 22 }

    public var context: RefineContext.ContextType

    public init(context: inout RefineContext.ContextType) {
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

/// Make some pages zero and writable in the inner PVM
public class Zero: HostCall {
    public static var identifier: UInt8 { 23 }

    public var context: RefineContext.ContextType

    public init(context: inout RefineContext.ContextType) {
        self.context = context
    }

    public func _callImpl(config _: ProtocolConfigRef, state: VMState) async throws {
        let regs: [UInt64] = state.readRegisters(in: 7 ..< 10)

        if context.pvms[regs[0]] == nil {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.WHO.rawValue)
            return
        }

        if regs[1] < 16 || (regs[1] + regs[2]) >= (1 << 20) {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.HUH.rawValue)
        } else {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.OK.rawValue)
            try context.pvms[regs[0]]!.memory.zero(pageIndex: UInt32(truncatingIfNeeded: regs[1]), pages: Int(regs[2]))
        }
    }
}

/// Make some pages zero and inaccessible in the inner PVM
public class VoidFn: HostCall {
    public static var identifier: UInt8 { 24 }

    public var context: RefineContext.ContextType

    public init(context: inout RefineContext.ContextType) {
        self.context = context
    }

    public func _callImpl(config: ProtocolConfigRef, state: VMState) async throws {
        let regs: [UInt64] = state.readRegisters(in: 7 ..< 10)

        if context.pvms[regs[0]] == nil {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.WHO.rawValue)
        } else if regs[1] < 16 ||
            (regs[1] + regs[2]) >= ((1 << 32) / UInt32(config.value.pvmMemoryPageSize)) ||
            !context.pvms[regs[0]]!.memory.isReadable(pageStart: UInt32(truncatingIfNeeded: regs[1]), pages: Int(regs[2]))
        {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.HUH.rawValue)
        } else {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.OK.rawValue)
            try context.pvms[regs[0]]!.memory.void(pageIndex: UInt32(truncatingIfNeeded: regs[1]), pages: Int(regs[2]))
        }
    }
}

/// Invoke an inner PVM
public class Invoke: HostCall {
    public static var identifier: UInt8 { 25 }

    public var context: RefineContext.ContextType

    public init(context: inout RefineContext.ContextType) {
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
        let vm = VMState(program: program, pc: innerPvm.pc, registers: Registers(registers), gas: Gas(gas), memory: innerPvm.memory)
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
    public static var identifier: UInt8 { 26 }

    public var context: RefineContext.ContextType

    public init(context: inout RefineContext.ContextType) {
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

// MARK: - Debug

/// A host call for passing a debugging message from the service/authorizer to the hosting environment for logging to the node operator.
public class Log: HostCall {
    public static var identifier: UInt8 { 100 }

    public enum Level: UInt32, Codable {
        case error = 0
        case debug = 1
        case info = 2
        case warn = 3
        case trace = 4

        var description: String {
            switch self {
            case .error: "ERROR"
            case .debug: "DEBUG"
            case .info: "INFO"
            case .warn: "WARN"
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
                result += " @\(core)"
            }
            if let service {
                result += " #\(service)"
            }
            if let target {
                result += " \(String(data: target, encoding: .utf8) ?? "invalid string")"
            }
            result += " \(String(data: message, encoding: .utf8) ?? "invalid string")"

            return result
        }
    }

    public var core: CoreIndex?
    public var service: ServiceIndex?

    public init(core: CoreIndex? = nil, service: ServiceIndex? = nil) {
        self.core = core
        self.service = service
    }

    public func _callImpl(config _: ProtocolConfigRef, state: VMState) async throws {
        let regs: [UInt32] = state.readRegisters(in: 7 ..< 12)
        let level = regs[0]
        let target = regs[1] == 0 && regs[2] == 0 ? nil : try? state.readMemory(address: regs[1], length: Int(regs[2]))
        let message = try? state.readMemory(address: regs[3], length: Int(regs[4]))

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH-mm-ss"
        let time = dateFormatter.string(from: Date())

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
