import Codec
import Foundation
import PolkaVM
import Utils

// MARK: - General

/// Get gas remaining
public class GasFn: HostCallFunction {
    public static var identifier: UInt8 { 0 }
    public static var gasCost: UInt64 { 10 }

    public typealias Input = Void
    public typealias Output = Void

    public static func call(state: VMState, input _: Input) throws -> Output {
        guard hasEnoughGas(state: state) else {
            return
        }
        state.consumeGas(gasCost)

        state.writeRegister(Registers.Index(raw: 0), UInt32(bitPattern: Int32(state.getGas() & 0xFFFF_FFFF)))
        state.writeRegister(Registers.Index(raw: 1), UInt32(bitPattern: Int32(state.getGas() >> 32)))
    }
}

/// Lookup a preimage from a service account
public class Lookup: HostCallFunction {
    public static var identifier: UInt8 { 1 }
    public static var gasCost: UInt64 { 10 }

    public typealias Input = (ServiceAccount, ServiceIndex, [ServiceIndex: ServiceAccount])
    public typealias Output = Void

    public static func call(state: VMState, input: Input) throws -> Output {
        guard hasEnoughGas(state: state) else {
            return
        }
        state.consumeGas(gasCost)

        let (serviceAccount, serviceIndex, serviceAccounts) = input

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
public class Read: HostCallFunction {
    public static var identifier: UInt8 { 2 }
    public static var gasCost: UInt64 { 10 }

    public typealias Input = (ServiceAccount, ServiceIndex, [ServiceIndex: ServiceAccount])
    public typealias Output = Void

    public static func call(state: VMState, input: Input) throws -> Output {
        guard hasEnoughGas(state: state) else {
            return
        }
        state.consumeGas(gasCost)

        let (serviceAccount, serviceIndex, serviceAccounts) = input

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
public class Write: HostCallFunction {
    public static var identifier: UInt8 { 3 }
    public static var gasCost: UInt64 { 10 }

    public typealias Input = (ProtocolConfigRef, ServiceAccount, ServiceIndex)
    public typealias Output = ServiceAccount

    public static func call(state: VMState, input: Input) throws -> Output {
        let (config, serviceAccount, serviceIndex) = input
        guard hasEnoughGas(state: state) else {
            return serviceAccount
        }

        state.consumeGas(gasCost)

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
            return account
        } else if let account, account.thresholdBalance(config: config) > account.balance {
            state.writeRegister(Registers.Index(raw: 0), HostCallResultCode.FULL.rawValue)
            return serviceAccount
        } else {
            state.writeRegister(Registers.Index(raw: 0), HostCallResultCode.OOB.rawValue)
            return serviceAccount
        }
    }
}

/// Get information details about a service account
public class Info: HostCallFunction {
    public static var identifier: UInt8 { 4 }
    public static var gasCost: UInt64 { 10 }

    public typealias Input = (
        config: ProtocolConfigRef,
        account: ServiceAccount,
        serviceIndex: ServiceIndex,
        serviceAccounts: [ServiceIndex: ServiceAccount],
        // only used in accumulation x.n
        newServiceAccounts: [ServiceIndex: ServiceAccount]
    )
    public typealias Output = Void

    public static func call(state: VMState, input: Input) throws -> Output {
        guard hasEnoughGas(state: state) else {
            return
        }
        state.consumeGas(gasCost)

        let (config, serviceAccount, serviceIndex, serviceAccounts, newServiceAccounts) = input

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
public class Empower: HostCallFunction {
    public static var identifier: UInt8 { 5 }
    public static var gasCost: UInt64 { 10 }

    public typealias Input = (x: AccumlateResultContext, y: AccumlateResultContext)
    public typealias Output = Void

    public static func call(state: VMState, input: Input) throws -> Output {
        guard hasEnoughGas(state: state) else {
            return
        }
        state.consumeGas(gasCost)

        let (x, _) = input

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
