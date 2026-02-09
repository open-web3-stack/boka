import Codec
import Foundation
import PolkaVM
import TracingUtils
import Utils

private let logger = Logger(label: "HostCalls.Accumulate")

// MARK: - Accumulate

/// Set privileged services details
public class Bless: HostCall {
    public static var identifier: UInt8 {
        14
    }

    public let x: AccumulateResultContext

    public init(x: AccumulateResultContext) {
        self.x = x
    }

    public func _callImpl(config: ProtocolConfigRef, state: VMState) async throws {
        let regs: [UInt64] = state.readRegisters(in: 7 ..< 13)

        var assigners: ConfigFixedSizeArray<ServiceIndex, ProtocolConfig.TotalNumberOfCores>?
        if state.isMemoryReadable(address: regs[1], length: 4 * config.value.totalNumberOfCores) {
            assigners = try JamDecoder.decode(
                ConfigFixedSizeArray<ServiceIndex, ProtocolConfig.TotalNumberOfCores>.self,
                from: state.readMemory(address: regs[1], length: 4 * config.value.totalNumberOfCores),
                withConfig: config,
            )
        }

        var alwaysAcc: [ServiceIndex: Gas]?
        let length = 12 * Int(regs[5])
        if state.isMemoryReadable(address: regs[4], length: length) {
            alwaysAcc = [:]
            let data = try state.readMemory(address: regs[4], length: length)
            for i in stride(from: 0, to: length, by: 12) {
                let serviceIndex = ServiceIndex(data[i ..< i + 4].decode(UInt32.self))
                let gas = Gas(data[i + 4 ..< i + 12].decode(UInt64.self))
                alwaysAcc![serviceIndex] = gas
            }
        }

        if alwaysAcc == nil || assigners == nil {
            throw VMInvocationsError.panic
        } else if ![regs[0], regs[2], regs[3]].allSatisfy({ $0 >= 0 && $0 <= UInt32.max }) {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.WHO.rawValue)
        } else {
            logger.debug("manager: \(regs[0])")
            logger.debug("assigners: \(String(describing: assigners))")
            logger.debug("delegator: \(regs[2])")
            logger.debug("registrar: \(regs[3])")
            logger.debug("alwaysAcc: \(String(describing: alwaysAcc))")

            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.OK.rawValue)
            x.state.manager = ServiceIndex(regs[0])
            x.state.assigners = assigners!
            x.state.delegator = ServiceIndex(regs[2])
            x.state.registrar = ServiceIndex(regs[3])
            x.state.alwaysAcc = alwaysAcc!
        }
    }
}

/// Assign the authorization queue for a core
public class Assign: HostCall {
    public static var identifier: UInt8 {
        15
    }

    public let x: AccumulateResultContext

    public init(x: AccumulateResultContext) {
        self.x = x
    }

    public func _callImpl(config: ProtocolConfigRef, state: VMState) async throws {
        let targetCoreIndex: UInt32 = state.readRegister(Registers.Index(raw: 7))
        let startAddr: UInt32 = state.readRegister(Registers.Index(raw: 8))
        let assigner: UInt64 = state.readRegister(Registers.Index(raw: 9))

        var authorizationQueue: [Data32]?
        let length = 32 * config.value.maxAuthorizationsQueueItems
        if state.isMemoryReadable(address: startAddr, length: length) {
            authorizationQueue = []
            let data = try state.readMemory(address: startAddr, length: length)
            for i in stride(from: 0, to: length, by: 32) {
                authorizationQueue!.append(Data32(data[i ..< i + 32])!)
            }
        }

        if authorizationQueue == nil {
            throw VMInvocationsError.panic
        } else if targetCoreIndex >= config.value.totalNumberOfCores {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.CORE.rawValue)
        } else if x.serviceIndex != x.state.assigners[targetCoreIndex] {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.HUH.rawValue)
        } else if assigner > UInt32.max {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.WHO.rawValue)
        } else {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.OK.rawValue)
            // update authorizationQueue
            var newAuthorizationQueue = x.state.authorizationQueue
            newAuthorizationQueue[targetCoreIndex] = try ConfigFixedSizeArray(config: config, array: authorizationQueue!)
            x.state.authorizationQueue = newAuthorizationQueue
            // update assigner
            x.state.assigners[targetCoreIndex] = UInt32(assigner)
        }
    }
}

/// Designate the new validator queue
public class Designate: HostCall {
    public static var identifier: UInt8 {
        16
    }

    public let x: AccumulateResultContext

    public init(x: AccumulateResultContext) {
        self.x = x
    }

    public func _callImpl(config: ProtocolConfigRef, state: VMState) async throws {
        let startAddr: UInt32 = state.readRegister(Registers.Index(raw: 7))

        var validatorQueue: [ValidatorKey]?
        let length = 336 * config.value.totalNumberOfValidators
        if state.isMemoryReadable(address: startAddr, length: length) {
            validatorQueue = []
            let data = try state.readMemory(address: startAddr, length: length)
            for i in stride(from: 0, to: length, by: 336) {
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
    public static var identifier: UInt8 {
        17
    }

    public let x: AccumulateResultContext
    public let y: AccumulateResultContext

    public init(x: AccumulateResultContext, y: AccumulateResultContext) {
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
    public static var identifier: UInt8 {
        18
    }

    public let x: AccumulateResultContext
    public let timeslot: TimeslotIndex

    public init(x: AccumulateResultContext, timeslot: TimeslotIndex) {
        self.x = x
        self.timeslot = timeslot
    }

    public func _callImpl(config: ProtocolConfigRef, state: VMState) async throws {
        let regs: [UInt64] = state.readRegisters(in: 7 ..< 13)

        let codeHash: Data32? = try? Data32(state.readMemory(address: regs[0], length: 32))
        logger.debug("codeHash: \(codeHash?.description ?? "nil")")
        logger.debug("new service index: \(x.nextAccountIndex)")

        let minAccumlateGas = Gas(regs[2])
        let minMemoGas = Gas(regs[3])
        let gratisStorage = Balance(regs[4])

        var newAccount: ServiceAccount?
        if let codeHash {
            newAccount = ServiceAccount(
                version: 0,
                storage: [:],
                preimages: [:],
                preimageInfos: [HashAndLength(hash: codeHash, length: UInt32(truncatingIfNeeded: regs[1])): []],
                codeHash: codeHash,
                balance: Balance(0),
                minAccumlateGas: minAccumlateGas,
                minMemoGas: minMemoGas,
                gratisStorage: gratisStorage,
                createdAt: timeslot,
                lastAccAt: 0,
                parentService: x.serviceIndex,
            )
            newAccount!.balance = newAccount!.thresholdBalance(config: config)
        }

        func updateAccounts(newAccountIndex: ServiceIndex) async throws {
            guard let newAccount, var account = try await x.state.accounts.value.get(serviceAccount: x.serviceIndex) else {
                throw VMInvocationsError.panic
            }

            account.balance -= newAccount.thresholdBalance(config: config)

            // update accumulating account details
            x.state.accounts.set(serviceAccount: x.serviceIndex, account: account)

            // add the new account
            try await x.state.accounts.addNew(serviceAccount: newAccountIndex, account: newAccount)
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
        } else if x.serviceIndex == x.state.registrar, regs[5] < config.value.minPublicServiceIndex {
            if try await x.state.accounts.value.get(serviceAccount: ServiceIndex(truncatingIfNeeded: regs[5])) != nil {
                state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.FULL.rawValue)
            } else {
                try await updateAccounts(newAccountIndex: ServiceIndex(truncatingIfNeeded: regs[5]))
                state.writeRegister(Registers.Index(raw: 7), regs[5])
            }
        } else {
            try await updateAccounts(newAccountIndex: x.nextAccountIndex)
            state.writeRegister(Registers.Index(raw: 7), x.nextAccountIndex)

            // update nextAccountIndex
            let S = UInt32(config.value.minPublicServiceIndex)
            let left = x.nextAccountIndex - S + 42
            let right = UInt32.max - S - 255
            x.nextAccountIndex = try await AccumulateContext.check(
                i: S + (left % right),
                accounts: x.state.accounts.toRef(),
                config: config,
            )
        }
    }
}

/// Upgrade a service account
public class Upgrade: HostCall {
    public static var identifier: UInt8 {
        19
    }

    public let x: AccumulateResultContext

    public init(x: AccumulateResultContext) {
        self.x = x
    }

    public func _callImpl(config _: ProtocolConfigRef, state: VMState) async throws {
        let regs: [UInt64] = state.readRegisters(in: 7 ..< 10)

        let codeHash: Data32? = try? Data32(state.readMemory(address: regs[0], length: 32))

        logger.debug("new codeHash: \(codeHash?.description ?? "nil")")

        if let codeHash, var acc = try await x.state.accounts.value.get(serviceAccount: x.serviceIndex) {
            acc.codeHash = codeHash
            acc.minAccumlateGas = Gas(regs[1])
            acc.minMemoGas = Gas(regs[2])
            x.state.accounts.set(serviceAccount: x.serviceIndex, account: acc)
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.OK.rawValue)
        } else {
            throw VMInvocationsError.panic
        }
    }
}

/// Make a transfer
public class Transfer: HostCall {
    public static var identifier: UInt8 {
        20
    }

    public let x: AccumulateResultContext

    public init(x: AccumulateResultContext) {
        self.x = x
    }

    /// GP v0.7.2: g = 10 + t, where t = gasLimit when OK, 0 otherwise
    /// We override call() to implement conditional gas charging
    public func call(config: ProtocolConfigRef, state: VMState) async -> ExecOutcome {
        logger.debug("===== host call: \(Self.self) =====")

        state.consumeGas(Gas(10))
        logger.debug("consumed base 10 gas, \(state.getGas()) left")

        guard state.getGas() >= GasInt(0) else {
            logger.debug("not enough gas")
            return .exit(.outOfGas)
        }

        let regs: [UInt64] = state.readRegisters(in: 7 ..< 11)
        let amount = Balance(regs[1])
        let gasLimit = Gas(regs[2])
        let memo = try? state.readMemory(address: regs[3], length: config.value.transferMemoSize)
        let dest = UInt32(truncatingIfNeeded: regs[0])

        let srcAccount = try? await x.state.accounts.value.get(serviceAccount: x.serviceIndex)
        let destAccount = try? await x.state.accounts.value.get(serviceAccount: dest)

        logger.debug("src: \(x.serviceIndex), dest: \(dest), amount: \(amount), gasLimit: \(gasLimit)")
        logger.debug("dest is found: \(destAccount != nil)")

        let (resultCode, additionalGas): (UInt64, Gas)

        if memo == nil {
            return .exit(.panic(.trap))
        } else if destAccount == nil {
            (resultCode, additionalGas) = (HostCallResultCode.WHO.rawValue, Gas(0))
        } else if gasLimit < destAccount!.minMemoGas {
            (resultCode, additionalGas) = (HostCallResultCode.LOW.rawValue, Gas(0))
        } else if let srcAccount, srcAccount.balance - amount < srcAccount.thresholdBalance(config: config) {
            (resultCode, additionalGas) = (HostCallResultCode.CASH.rawValue, Gas(0))
        } else {
            (resultCode, additionalGas) = (HostCallResultCode.OK.rawValue, gasLimit)
        }

        state.consumeGas(additionalGas)
        logger.debug("consumed additional \(additionalGas) gas, \(state.getGas()) left")

        guard state.getGas() >= GasInt(0) else {
            logger.debug("not enough gas for additional charge")
            return .exit(.outOfGas)
        }

        state.writeRegister(Registers.Index(raw: 7), resultCode)
        if resultCode == HostCallResultCode.OK.rawValue, var srcAccount {
            x.transfers.append(DeferredTransfers(
                sender: x.serviceIndex,
                destination: dest,
                amount: amount,
                memo: Data128(memo!)!,
                gasLimit: gasLimit,
            ))
            srcAccount.balance -= amount
            x.state.accounts.set(serviceAccount: x.serviceIndex, account: srcAccount)
        }

        return .continued
    }

    public func _callImpl(config _: ProtocolConfigRef, state _: VMState) async throws {
        // Not used - we override call() instead
    }
}

/// Eject (remove) a service account
public class Eject: HostCall {
    public static var identifier: UInt8 {
        21
    }

    public let x: AccumulateResultContext
    public let timeslot: TimeslotIndex

    public init(x: AccumulateResultContext, timeslot: TimeslotIndex) {
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
            logger.debug("Eject WHO: ejectAccount is nil or codeHash mismatch")
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.WHO.rawValue)
            return
        }

        let preimageInfo = try await x.state.accounts.value.get(
            serviceAccount: ejectIndex,
            preimageHash: Data32(preimageHash!)!,
            length: max(81, UInt32(ejectAccount!.totalByteLength)) - 81,
        )

        let minHoldSlot = max(0, Int(timeslot) - Int(minHoldPeriod))

        if ejectAccount!.itemsCount != 2 || preimageInfo == nil {
            logger.debug("Eject HUH: itemsCount != 2 or preimageInfo is nil")
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.HUH.rawValue)
        } else if preimageInfo!.count == 2, preimageInfo![1] < minHoldSlot {
            // accumulating service definitely exist
            var destAccount = try await x.state.accounts.value.get(serviceAccount: x.serviceIndex)!
            destAccount.balance += ejectAccount!.balance
            try await x.state.accounts.remove(serviceAccount: ejectIndex)
            x.state.accounts.set(serviceAccount: x.serviceIndex, account: destAccount)
            logger.debug("Eject OK: successfully ejected service account")
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.OK.rawValue)
        } else {
            logger.debug("Eject HUH: preimageInfo conditions not met")
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.HUH.rawValue)
        }
    }
}

/// Query preimage info
public class Query: HostCall {
    public static var identifier: UInt8 {
        22
    }

    public let x: AccumulateResultContext

    public init(x: AccumulateResultContext) {
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
            length: length,
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
    public static var identifier: UInt8 {
        23
    }

    public let x: AccumulateResultContext
    public let timeslot: TimeslotIndex

    public init(x: AccumulateResultContext, timeslot: TimeslotIndex) {
        self.x = x
        self.timeslot = timeslot
    }

    public func _callImpl(config: ProtocolConfigRef, state: VMState) async throws {
        let (startAddr, length): (UInt32, UInt32) = state.readRegister(Registers.Index(raw: 7), Registers.Index(raw: 8))
        let hashData = try? state.readMemory(address: startAddr, length: 32)
        let hash = Data32(hashData ?? Data())

        logger.debug("hash: \(hash?.description ?? "nil"), length: \(length)")

        guard let hash else {
            throw VMInvocationsError.panic
        }

        let preimageInfo = try await x.state.accounts.value.get(
            serviceAccount: x.serviceIndex,
            preimageHash: hash,
            length: length,
        )
        logger.debug("previous info: \(String(describing: preimageInfo))")

        let notRequestedYet = preimageInfo == nil
        let isPreviouslyAvailable = preimageInfo?.count == 2
        let canSolicit = notRequestedYet || isPreviouslyAvailable

        if !canSolicit {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.HUH.rawValue)
            return
        }

        var acc = try await x.state.accounts.value.get(serviceAccount: x.serviceIndex)

        if var tempAcc = acc {
            // update footprints for threshold balance check
            let oldValue = try await x.state.accounts.value.get(serviceAccount: x.serviceIndex, preimageHash: hash, length: length)
            if notRequestedYet {
                tempAcc.updateFootprintPreimage(oldValue: oldValue, newValue: [], length: length)
            } else if isPreviouslyAvailable, var preimageInfo {
                try preimageInfo.append(timeslot)
                tempAcc.updateFootprintPreimage(oldValue: oldValue, newValue: preimageInfo, length: length)
            }
            acc = tempAcc
        }

        if let acc, acc.balance < acc.thresholdBalance(config: config) {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.FULL.rawValue)
        } else {
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.OK.rawValue)
            if notRequestedYet {
                logger.debug("solicit new preimage")
                try await x.state.accounts.set(serviceAccount: x.serviceIndex, preimageHash: hash, length: length, value: [])
            } else if isPreviouslyAvailable, var preimageInfo {
                logger.debug("solicit existing preimage")
                try preimageInfo.append(timeslot)
                try await x.state.accounts.set(
                    serviceAccount: x.serviceIndex,
                    preimageHash: hash,
                    length: length,
                    value: preimageInfo,
                )
            }
        }
    }
}

/// Forget data made available in-core (through preimage lookups)
public class Forget: HostCall {
    public static var identifier: UInt8 {
        24
    }

    public let x: AccumulateResultContext
    public let timeslot: TimeslotIndex

    public init(x: AccumulateResultContext, timeslot: TimeslotIndex) {
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
            length: length,
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
                    value: preimageInfo,
                )
            } else if isAvailable3, var preimageInfo {
                preimageInfo = [preimageInfo[2], timeslot]
                try await x.state.accounts.set(
                    serviceAccount: x.serviceIndex,
                    preimageHash: hash,
                    length: length,
                    value: preimageInfo,
                )
            }
        }
    }
}

/// Yield accumulation hash
public class Yield: HostCall {
    public static var identifier: UInt8 {
        25
    }

    public let x: AccumulateResultContext

    public init(x: AccumulateResultContext) {
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
    public static var identifier: UInt8 {
        26
    }

    public let x: AccumulateResultContext

    public init(x: AccumulateResultContext) {
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
                serviceAccount: serviceIndex,
                preimageHash: Blake2b256.hash(preimage),
                length: length,
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
