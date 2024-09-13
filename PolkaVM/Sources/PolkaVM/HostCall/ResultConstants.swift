public enum HostCallResultConstants {
    /// NONE = 2^32 − 1: The return value indicating an item does not exist.
    public static let NONE: UInt32 = 0xFFFF_FFFF
    /// WHAT = 2^32 − 2: Name unknown.
    public static let WHAT: UInt32 = 0xFFFF_FFFE
    /// OOB = 2^32 − 3: The return value for when a memory index is provided for reading/writing which is not accessible.
    public static let OOB: UInt32 = 0xFFFF_FFFD
    /// WHO = 2^32 − 4: Index unknown.
    public static let WHO: UInt32 = 0xFFFF_FFFC
    /// FULL = 2^32 − 5: Storage full.
    public static let FULL: UInt32 = 0xFFFF_FFFB
    /// CORE = 2^32 − 6: Core index unknown.
    public static let CORE: UInt32 = 0xFFFF_FFFA
    /// CASH = 2^32 − 7: Insuﬀicient funds.
    public static let CASH: UInt32 = 0xFFFF_FFF9
    /// LOW = 2^32 − 8: Gas limit too low.
    public static let LOW: UInt32 = 0xFFFF_FFF8
    /// HIGH = 2^32 − 9: Gas limit too high.
    public static let HIGH: UInt32 = 0xFFFF_FFF7
    /// HUH = 2^32 − 10: The item is already solicited or cannot be forgotten.
    public static let HUH: UInt32 = 0xFFFF_FFF6
    /// OK = 0: The return value indicating general success.
    public static let OK = 0

    // Inner pvm invocations have their own set of result codes👇

    /// HALT = 0: The invocation completed and halted normally.
    public static let HALT: UInt32 = 0
    /// PANIC = 1: The invocation completed with a panic.
    public static let PANIC: UInt32 = 1
    /// FAULT = 2: The invocation completed with a page fault.
    public static let FAULT: UInt32 = 2
    /// HOST = 3: The invocation completed with a host-call fault.
    public static let HOST: UInt32 = 3
}
