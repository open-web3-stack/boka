public enum ExitReason {
    public enum HaltReason {
        case trap
        case invalidInstruction
    }

    case halt(HaltReason)
    case panic
    case outOfGas
    case hostCall(UInt32)
    case pageFault(UInt32)
}
