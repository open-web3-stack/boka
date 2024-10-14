public enum ExitReason {
    public enum PanicReason {
        case trap
        case invalidInstructionIndex
        case invalidDynamicJump
        case invalidBranch
    }

    case halt
    case panic(PanicReason)
    case outOfGas
    case hostCall(UInt32)
    case pageFault(UInt32)
}

public enum ExecOutcome {
    case continued // continue is a reserved keyword
    case exit(ExitReason)
}
