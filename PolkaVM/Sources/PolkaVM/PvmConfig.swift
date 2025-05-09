import Foundation // For Data type

public protocol PvmConfig {
    // ZA = 2: The pvm dynamic address alignment factor.
    var pvmDynamicAddressAlignmentFactor: Int { get }

    // ZI = 2^24: The standard pvm program initialization input data size.
    var pvmProgramInitInputDataSize: Int { get }

    // ZZ = 2^16: The standard pvm program initialization zone size.
    var pvmProgramInitZoneSize: Int { get }

    // ZP = 2^12: The pvm memory page size.
    var pvmMemoryPageSize: Int { get }

    // Memory layout configurations (potentially used by JIT and StandardMemory)
    var initialHeapPages: UInt32 { get }
    var stackPages: UInt32 { get }
    var readOnlyDataSegment: Data? { get }
    var readWriteDataSegment: Data? { get }
}

// Default implementations for JIT and memory layout configurations
extension PvmConfig {
    public var initialHeapPages: UInt32 { 16 }
    public var stackPages: UInt32 { 16 }
    public var readOnlyDataSegment: Data? { nil }
    public var readWriteDataSegment: Data? { nil }
}

public struct DefaultPvmConfig: PvmConfig {
    public let pvmDynamicAddressAlignmentFactor: Int
    public let pvmProgramInitInputDataSize: Int
    public let pvmProgramInitZoneSize: Int
    public let pvmMemoryPageSize: Int

    public let pvmProgramInitRegister1Value: Int
    public let pvmProgramInitStackBaseAddress: Int
    public let pvmProgramInitInputStartAddress: Int

    public init() {
        pvmDynamicAddressAlignmentFactor = 2
        pvmProgramInitInputDataSize = 1 << 24
        pvmProgramInitZoneSize = 1 << 16
        pvmMemoryPageSize = 1 << 12

        pvmProgramInitRegister1Value = (1 << 32) - (1 << 16)
        pvmProgramInitStackBaseAddress = (1 << 32) - (2 * pvmProgramInitZoneSize) - pvmProgramInitInputDataSize
        pvmProgramInitInputStartAddress = pvmProgramInitStackBaseAddress + pvmProgramInitZoneSize
    }
}
