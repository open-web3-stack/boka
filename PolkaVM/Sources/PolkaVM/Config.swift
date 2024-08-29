public protocol PvmConfig {
    // ZA = 2: The pvm dynamic address alignment factor.
    var pvmDynamicAddressAlignmentFactor: Int { get }

    // ZI = 2^24: The standard pvm program initialization input data size.
    var pvmProgramInitInputDataSize: Int { get }

    // ZP = 2^14: The standard pvm program initialization page size.
    var pvmProgramInitPageSize: Int { get }

    // ZQ = 2^16: The standard pvm program initialization segment size.
    var pvmProgramInitSegmentSize: Int { get }
}
