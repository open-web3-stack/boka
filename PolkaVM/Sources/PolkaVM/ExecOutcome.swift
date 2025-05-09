public enum ExitReason: Equatable {
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

    // TODO: Review and refine these integer codes for JIT communication.
    // Especially for cases with associated values, a more complex ABI might be needed
    // if the associated values must be passed back from JIT.
    public func toInt32() -> Int32 {
        switch self {
        case .halt: 0
        case let .panic(reason):
            switch reason {
            case .trap: 1
            case .invalidInstructionIndex: 2
            case .invalidDynamicJump: 3
            case .invalidBranch: 4
            }
        case .outOfGas: 5
        case .hostCall: 6 // Associated value (UInt32) is lost in this simple conversion
        case .pageFault: 7 // Associated value (UInt32) is lost
        }
    }

    public static func fromInt32(_ rawValue: Int32) -> ExitReason? {
        switch rawValue {
        case 0: .halt
        case 1: .panic(.trap)
        case 2: .panic(.invalidInstructionIndex)
        case 3: .panic(.invalidDynamicJump)
        case 4: .panic(.invalidBranch)
        case 5: .outOfGas
        // Cases 6 and 7 would need to decide on default associated values or be unrepresentable here
        // For now, let's make them unrepresentable to highlight the issue.
        // case 6: return .hostCall(0) // Placeholder default ID
        // case 7: return .pageFault(0) // Placeholder default address
        default: nil // Unknown code
        }
    }
}

public enum ExecOutcome {
    case continued // continue is a reserved keyword
    case exit(ExitReason)
}
