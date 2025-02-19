public enum HostCallResultCode: UInt64 {
    /// NONE = 2^64 − 1: The return value indicating an item does not exist.
    case NONE = 0xFFFF_FFFF_FFFF_FFFF
    /// WHAT = 2^64 − 2: Name unknown.
    case WHAT = 0xFFFF_FFFF_FFFF_FFFE
    /// OOB = 2^64 − 3: The inner pvm memory index provided for reading/writing is not accessible.
    case OOB = 0xFFFF_FFFF_FFFF_FFFD
    /// WHO = 2^64 − 4: Index unknown.
    case WHO = 0xFFFF_FFFF_FFFF_FFFC
    /// FULL = 2^64 − 5: Storage full.
    case FULL = 0xFFFF_FFFF_FFFF_FFFB
    /// CORE = 2^64 − 6: Core index unknown.
    case CORE = 0xFFFF_FFFF_FFFF_FFFA
    /// CASH = 2^64 − 7: Insufficient funds.
    case CASH = 0xFFFF_FFFF_FFFF_FFF9
    /// LOW = 2^64 − 8: Gas limit too low.
    case LOW = 0xFFFF_FFFF_FFFF_FFF8
    /// HUH = 2^64 − 10: The item is already solicited or cannot be forgotten.
    case HUH = 0xFFFF_FFFF_FFFF_FFF6
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
    /// OOG = 4: The invocation completed by running out of gas.
    case OOG = 4
}
