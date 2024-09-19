import Foundation
import PolkaVM
import Utils

public class GasFn: HostCallFunction {
    public static var identifier: UInt8 { 0 }
    public static var gasCost: UInt64 { 10 }

    public typealias Input = Void
    public typealias Output = Void

    public static func call(state: VMState, input _: Input) throws -> Output {
        guard hasEnoughGas(state: state) else {
            throw VMInvocationsError.outOfGas
        }
        state.writeRegister(Registers.Index(raw: 0), UInt32(bitPattern: Int32(state.getGas() & 0xFFFF_FFFF)))
        state.writeRegister(Registers.Index(raw: 1), UInt32(bitPattern: Int32(state.getGas() >> 32)))
    }
}

public class Lookup: HostCallFunction {
    public static var identifier: UInt8 { 1 }
    public static var gasCost: UInt64 { 10 }

    public typealias Input = (ServiceAccount, ServiceIndex, [ServiceIndex: ServiceAccount])
    public typealias Output = Void

    public static func call(state: VMState, input: Input) throws -> Output {
        guard hasEnoughGas(state: state) else {
            throw VMInvocationsError.outOfGas
        }
        let (serviceAccount, serviceIndex, serviceAccounts) = input

        var account: ServiceAccount?
        let reg0 = state.readRegister(Registers.Index(raw: 0))
        if reg0 == serviceIndex || reg0 == Int32.max {
            account = serviceAccount
        } else {
            account = serviceAccounts[reg0]
        }

        let regs = state.readRegisters(in: 1 ..< 4)

        var preimageHash: Data32?
        do {
            preimageHash = try Blake2b256.hash(state.readMemory(address: regs[0], length: 32))
        } catch {
            preimageHash = nil
        }

        let value: Data? = if let account, let preimageHash, account.preimages.keys.contains(preimageHash) {
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
