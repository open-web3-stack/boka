/// JIT Memory Layout
///
/// Rebases PolkaVM's sparse memory model into a contiguous flat buffer
/// for efficient JIT compilation and execution.
///
/// PolkaVM Memory Layout (sparse):
/// - Read-only zone: 0x00010000 (65536)
/// - Heap zone: 0x00020000+ (variable)
/// - Stack zone: 0xFF000000-0xFF800000 (~4GB)
/// - Argument zone: 0xFF800000+
///
/// JIT Memory Layout (contiguous):
/// - Read-only zone: offset 0x00000000
/// - Heap zone: offset 0x00010000
/// - Stack zone: offset 0x00020000
/// - Argument zone: offset 0x00030000
///
/// This reduces memory from 4GB to ~256KB for typical programs.
import Foundation

struct JITMemoryLayout {
    /// A contiguous memory zone
    struct Zone {
        let baseOffset: UInt32 // Offset in contiguous buffer
        let originalBase: UInt32 // Original PolkaVM address
        let size: UInt32
        let data: Data

        /// Check if an address belongs to this zone
        func contains(_ address: UInt32) -> Bool {
            address >= originalBase && address < (originalBase + size)
        }

        /// Translate PolkaVM address to contiguous offset
        func translate(_ address: UInt32) -> UInt32 {
            baseOffset + (address - originalBase)
        }
    }

    /// All zones in contiguous order
    let zones: [Zone]

    /// Total size of contiguous buffer
    let totalSize: UInt32

    /// Create memory layout from StandardProgram
    ///
    /// - Parameter standardProgram: Program to extract memory layout from
    /// - Throws: If memory access fails or zones cannot be extracted
    init(standardProgram: StandardProgram) throws {
        let config = DefaultPvmConfig()

        // Access StandardMemory's zone information
        guard let memory = standardProgram.initialMemory as? StandardMemory else {
            throw JITMemoryLayoutError.memoryLayoutExtractionFailed("Not StandardMemory")
        }

        var extractedZones: [Zone] = []
        var currentOffset: UInt32 = 0

        // Zone 1: Read-only zone
        let readOnlyInfo = memory.readOnlyZoneInfo
        let readOnlyZone = Zone(
            baseOffset: currentOffset,
            originalBase: readOnlyInfo.startAddress,
            size: readOnlyInfo.endAddress - readOnlyInfo.startAddress,
            data: readOnlyInfo.data
        )
        extractedZones.append(readOnlyZone)
        currentOffset = Self.alignToZoneSize(size: currentOffset + readOnlyZone.size, config: config)

        // Zone 2: Heap zone
        let heapInfo = memory.heapZoneInfo
        let heapZone = Zone(
            baseOffset: currentOffset,
            originalBase: heapInfo.startAddress,
            size: heapInfo.endAddress - heapInfo.startAddress,
            data: heapInfo.data
        )
        extractedZones.append(heapZone)
        currentOffset = Self.alignToZoneSize(size: currentOffset + heapZone.size, config: config)

        // Zone 3: Stack zone
        let stackInfo = memory.stackZoneInfo
        let stackZone = Zone(
            baseOffset: currentOffset,
            originalBase: stackInfo.startAddress,
            size: stackInfo.endAddress - stackInfo.startAddress,
            data: stackInfo.data
        )
        extractedZones.append(stackZone)
        currentOffset = Self.alignToZoneSize(size: currentOffset + stackZone.size, config: config)

        // Zone 4: Argument zone
        let argumentInfo = memory.argumentZoneInfo
        let argumentZone = Zone(
            baseOffset: currentOffset,
            originalBase: argumentInfo.startAddress,
            size: argumentInfo.endAddress - argumentInfo.startAddress,
            data: argumentInfo.data
        )
        extractedZones.append(argumentZone)

        // Calculate total size
        let calculatedTotalSize = Self.alignToZoneSize(size: currentOffset + argumentZone.size, config: config)

        // Initialize all stored properties
        zones = extractedZones
        totalSize = calculatedTotalSize
    }

    /// Translate PolkaVM address to contiguous buffer offset
    ///
    /// - Parameter address: Original PolkaVM address
    /// - Returns: Contiguous buffer offset, or nil if address not in any zone
    func translate(_ address: UInt32) -> UInt32? {
        for zone in zones {
            if zone.contains(address) {
                return zone.translate(address)
            }
        }
        return nil
    }

    /// Get zone containing an address
    ///
    /// - Parameter address: PolkaVM address
    /// - Returns: Zone containing the address, or nil if not found
    func zone(for address: UInt32) -> Zone? {
        zones.first { $0.contains(address) }
    }

    // MARK: - Private Helpers

    private static func alignToPageSize(size: UInt32, config: PvmConfig) -> UInt32 {
        StandardProgram.alignToPageSize(size: size, config: config)
    }

    private static func alignToZoneSize(size: UInt32, config: PvmConfig) -> UInt32 {
        StandardProgram.alignToZoneSize(size: size, config: config)
    }
}

// MARK: - Errors

enum JITMemoryLayoutError: Swift.Error {
    case memoryLayoutExtractionFailed(String)
    case addressTranslationFailed(UInt32)
    case zoneNotFound(UInt32)
}
