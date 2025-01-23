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

extension ExitReason: Equatable {
    public static func == (lhs: ExitReason, rhs: ExitReason) -> Bool {
        switch (lhs, rhs) {
        case (.halt, .halt):
            true
        case (.outOfGas, .outOfGas):
            true
        case let (.panic(l), .panic(r)):
            l == r
        case let (.hostCall(l), .hostCall(r)):
            l == r
        case let (.pageFault(l), .pageFault(r)):
            l == r
        default:
            false
        }
    }
}

extension ExecOutcome: Equatable {
    public static func == (lhs: ExecOutcome, rhs: ExecOutcome) -> Bool {
        switch (lhs, rhs) {
        case (.continued, .continued):
            true
        case let (.exit(l), .exit(r)):
            l == r
        default:
            false
        }
    }
}
