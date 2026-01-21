public enum ExitReason: Equatable, Sendable {
    public enum PanicReason: Sendable {
        case trap
        case invalidInstructionIndex
        case invalidDynamicJump
        case invalidBranch
        // JIT-specific panic reasons
        case jitCompilationFailed
        case jitMemoryError
        case jitExecutionError
        case jitInvalidFunctionPointer
    }

    case halt
    case panic(PanicReason)
    case outOfGas
    case hostCall(UInt32)
    case pageFault(UInt32)
    case fallback(pc: UInt32, registers: [UInt64], gasUsed: UInt64)

    // TODO: Review and refine these integer codes for JIT communication.
    // Especially for cases with associated values, a more complex ABI might be needed
    // if the associated values must be passed back from JIT.
    public func toUInt64() -> UInt64 {
        switch self {
        case .halt: 0
        case let .panic(reason):
            switch reason {
            case .trap: 1
            case .invalidInstructionIndex: 2
            case .invalidDynamicJump: 3
            case .invalidBranch: 4
            case .jitCompilationFailed: 10
            case .jitMemoryError: 11
            case .jitExecutionError: 12
            case .jitInvalidFunctionPointer: 13
            }
        case .outOfGas: 5
        case let .hostCall(id): 6 + UInt64(id) << 32
        case let .pageFault(address): 7 + UInt64(address) << 32
        case .fallback: 8  // Fallback - register state will be extracted separately
        }
    }

    public static func fromUInt64(_ rawValue: UInt64) -> ExitReason {
        switch rawValue & 0xFF {
        case 0: return .halt
        case 1: return .panic(.trap)
        case 2: return .panic(.invalidInstructionIndex)
        case 3: return .panic(.invalidDynamicJump)
        case 4: return .panic(.invalidBranch)
        case 5: return .outOfGas
        case 6: return .hostCall(UInt32(rawValue >> 32))
        case 7: return .pageFault(UInt32(rawValue >> 32))
        case 8: return .fallback(pc: 0, registers: [], gasUsed: 0)  // Placeholder - actual values extracted from registers
        // JIT-specific panic reasons
        case 10: return .panic(.jitCompilationFailed)
        case 11: return .panic(.jitMemoryError)
        case 12: return .panic(.jitExecutionError)
        case 13: return .panic(.jitInvalidFunctionPointer)
        default:
            print("Unknown exit reason: \(rawValue)")
            return .halt
        }
    }
}

public enum ExecOutcome: Sendable {
    case continued // continue is a reserved keyword
    case exit(ExitReason)
}
