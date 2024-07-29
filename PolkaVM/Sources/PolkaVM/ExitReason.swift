public enum ExitReason {
    public enum PanicReason {
        case trap
        case invalidInstruction
    }

    case halt
    case panic(PanicReason)
    case outOfGas
    case hostCall(UInt32)
    case pageFault(UInt32)
}
