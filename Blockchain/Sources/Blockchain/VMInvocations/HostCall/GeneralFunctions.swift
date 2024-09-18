import PolkaVM

public class GasFn: HostCallFunction {
    public static var identifier: UInt8 { 0 }
    public static var gasCost: UInt64 { 10 }

    public typealias Invariant = Void
    public typealias Mutable = Void

    public static func call(state: VMState, invariant _: Invariant) throws {
        guard hasEnoughGas(state: state) else {
            throw VMInvocationsError.outOfGas
        }
        state.writeRegister(Registers.Index(raw: 0), UInt32(bitPattern: Int32(state.getGas() & 0xFFFF_FFFF)))
        state.writeRegister(Registers.Index(raw: 1), UInt32(bitPattern: Int32(state.getGas() >> 32)))
    }

    public static func call(state: VMState, invariant: Invariant, mutable _: inout Mutable) throws {
        try call(state: state, invariant: invariant)
    }
}

public class Lookup: HostCallFunction {
    public static var identifier: UInt8 { 1 }
    public static var gasCost: UInt64 { 10 }

    public typealias Invariant = (ServiceIndex, [ServiceIndex: ServiceAccount])
    public typealias Mutable = ServiceAccount

    public static func call(state: VMState, invariant _: Invariant, mutable _: inout Mutable) throws {
        guard hasEnoughGas(state: state) else {
            throw VMInvocationsError.outOfGas
        }
        // let (serviceAccount, serviceIndex, serviceAccounts) = input

        var account: ServiceAccount?
        let reg0 = state.readRegister(Registers.Index(raw: 0))
        if reg0 == 0 || reg0 == Int32.max {
            account = serviceAccount
        } else {
            account = serviceAccounts[serviceIndex]
        }

        let regs = state.readRegisters(in: 1 ..< 4)
    }
}
