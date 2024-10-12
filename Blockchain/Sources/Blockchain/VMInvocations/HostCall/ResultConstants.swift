public enum HostCallResultCode: UInt32 {
    /// NONE = 2^32 − 1: The return value indicating an item does not exist.
    case NONE = 0xFFFF_FFFF
    /// WHAT = 2^32 − 2: Name unknown.
    case WHAT = 0xFFFF_FFFE
    /// OOB = 2^32 − 3: The return value for when a memory index is provided for reading/writing which is not accessible.
    case OOB = 0xFFFF_FFFD
    /// WHO = 2^32 − 4: Index unknown.
    case WHO = 0xFFFF_FFFC
    /// FULL = 2^32 − 5: Storage full.
    case FULL = 0xFFFF_FFFB
    /// CORE = 2^32 − 6: Core index unknown.
    case CORE = 0xFFFF_FFFA
    /// CASH = 2^32 − 7: Insufficient funds.
    case CASH = 0xFFFF_FFF9
    /// LOW = 2^32 − 8: Gas limit too low.
    case LOW = 0xFFFF_FFF8
    /// HIGH = 2^32 − 9: Gas limit too high.
    case HIGH = 0xFFFF_FFF7
    /// HUH = 2^32 − 10: The item is already solicited or cannot be forgotten.
    case HUH = 0xFFFF_FFF6
    /// OK = 0: The return value indicating general success.
    case OK = 0
}

// Inner pvm invocations have their own set of result codes👇
public enum HostCallResultCodeInner: UInt32 {
    /// HALT = 0: The invocation completed and halted normally.
    case HALT = 0
    /// PANIC = 1: The invocation completed with a panic.
    case PANIC = 1
    /// FAULT = 2: The invocation completed with a page fault.
    case FAULT = 2
    /// HOST = 3: The invocation completed with a host-call fault.
    case HOST = 3
}
