public class Gas: HostCallFunction {
    public static var identifier: UInt8 { 0 }
    public static var gasCost: UInt8 { 10 }

    public typealias Input = Void

    public typealias Output = Void

    public static func call(state: VMState, input _: Input) -> Output {
        state.writeRegister(Registers.Index(raw: 0), UInt32(bitPattern: Int32(state.getGas() & 0xFFFF_FFFF)))
        state.writeRegister(Registers.Index(raw: 1), UInt32(bitPattern: Int32(state.getGas() >> 32)))
    }
}
