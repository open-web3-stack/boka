import Foundation
@testable import PolkaVM
import Testing

/// Tests for JIT memory layout rebasing
///
/// Verify that:
/// - Zone extraction works correctly
/// - Address translation is accurate
/// - Total size is significantly less than 4GB
@Suite
struct JITMemoryLayoutTests {
    // MARK: - Zone Extraction Tests

    @Test
    func extractZonesFromSimpleProgram() throws {
        // Create a simple program with minimal memory
        let code = ProgramBlobBuilder.createProgramCodeBlob([]) // Empty code
        let program = ProgramBlobBuilder.createStandardProgram(
            programCode: code,
            readOnlyData: Data([0x01, 0x02, 0x03]),
            readWriteData: Data([0x04, 0x05]),
            heapPages: 0,
            stackSize: 4096,
        )

        let standardProgram = try StandardProgram(blob: program, argumentData: nil)
        let layout = try JITMemoryLayout(standardProgram: standardProgram)

        // Should have 4 zones: readOnly, heap, stack, argument
        #expect(layout.zones.count == 4)

        // Verify zones are in order
        var previousOffset: UInt32 = 0
        for zone in layout.zones {
            #expect(zone.baseOffset >= previousOffset)
            previousOffset = zone.baseOffset
        }
    }

    @Test
    func firstZoneStartsAtOffsetZero() throws {
        let code = ProgramBlobBuilder.createProgramCodeBlob([])
        let program = ProgramBlobBuilder.createStandardProgram(
            programCode: code,
            readOnlyData: Data([0x01]),
            readWriteData: Data(),
            heapPages: 0,
            stackSize: 4096,
        )

        let standardProgram = try StandardProgram(blob: program, argumentData: nil)
        let layout = try JITMemoryLayout(standardProgram: standardProgram)

        #expect(layout.zones.first?.baseOffset == 0)
    }

    // MARK: - Address Translation Tests

    @Test
    func translateReadOnlyZoneAddress() throws {
        let code = ProgramBlobBuilder.createProgramCodeBlob([])
        let program = ProgramBlobBuilder.createStandardProgram(
            programCode: code,
            readOnlyData: Data([0xAA, 0xBB, 0xCC]),
            readWriteData: Data(),
            heapPages: 0,
            stackSize: 4096,
        )

        let standardProgram = try StandardProgram(blob: program, argumentData: nil)
        let layout = try JITMemoryLayout(standardProgram: standardProgram)

        let config = DefaultPvmConfig()
        let readOnlyBase = UInt32(config.pvmProgramInitZoneSize)

        // Translate read-only address
        if let offset = layout.translate(readOnlyBase) {
            #expect(offset == 0)
        } else {
            Issue.record("Failed to translate read-only address")
        }
    }

    @Test
    func translateHeapZoneAddress() throws {
        let readOnlyData = Data([0x01, 0x02, 0x03])
        let heapData = Data([0xAA, 0xBB, 0xCC])

        let code = ProgramBlobBuilder.createProgramCodeBlob([])
        let program = ProgramBlobBuilder.createStandardProgram(
            programCode: code,
            readOnlyData: readOnlyData,
            readWriteData: heapData,
            heapPages: 0,
            stackSize: 4096,
        )

        let standardProgram = try StandardProgram(blob: program, argumentData: nil)
        let layout = try JITMemoryLayout(standardProgram: standardProgram)

        let config = DefaultPvmConfig()
        let heapBase = 2 * UInt32(config.pvmProgramInitZoneSize) +
            StandardProgram.alignToZoneSize(size: UInt32(readOnlyData.count), config: config)

        // Translate heap address
        if let offset = layout.translate(heapBase) {
            // Heap should come after read-only zone
            #expect(offset > 0)
        } else {
            Issue.record("Failed to translate heap address")
        }
    }

    @Test
    func translateStackZoneAddress() throws {
        let code = ProgramBlobBuilder.createProgramCodeBlob([])
        let program = ProgramBlobBuilder.createStandardProgram(
            programCode: code,
            readOnlyData: Data([0x01]),
            readWriteData: Data(),
            heapPages: 0,
            stackSize: 4096,
        )

        let standardProgram = try StandardProgram(blob: program, argumentData: nil)
        let layout = try JITMemoryLayout(standardProgram: standardProgram)

        let config = DefaultPvmConfig()
        let stackBase = UInt32(config.pvmProgramInitStackBaseAddress) - 4096

        // Translate stack address
        if let offset = layout.translate(stackBase) {
            // Stack should be at some offset
            #expect(offset >= 0)
        } else {
            Issue.record("Failed to translate stack address")
        }
    }

    @Test
    func returnNilForInvalidAddress() throws {
        let code = ProgramBlobBuilder.createProgramCodeBlob([])
        let program = ProgramBlobBuilder.createStandardProgram(
            programCode: code,
            readOnlyData: Data([0x01]),
            readWriteData: Data(),
            heapPages: 0,
            stackSize: 4096,
        )

        let standardProgram = try StandardProgram(blob: program, argumentData: nil)
        let layout = try JITMemoryLayout(standardProgram: standardProgram)

        // Try to translate an invalid address (middle of nowhere)
        let invalidAddress: UInt32 = 0x0080_0000 // 8MB - unlikely to be in any zone
        let offset = layout.translate(invalidAddress)

        #expect(offset == nil)
    }

    // MARK: - Memory Size Tests

    @Test
    func totalSizeIsMuchLessThan4GB() throws {
        let code = ProgramBlobBuilder.createProgramCodeBlob([])
        let program = ProgramBlobBuilder.createStandardProgram(
            programCode: code,
            readOnlyData: Data([0x01, 0x02, 0x03]),
            readWriteData: Data([0x04, 0x05]),
            heapPages: 0,
            stackSize: 4096,
        )

        let standardProgram = try StandardProgram(blob: program, argumentData: nil)
        let layout = try JITMemoryLayout(standardProgram: standardProgram)

        // 4GB is 0xFF000000 (4,278,190,080 bytes)
        // Our rebased layout should be < 1MB for typical programs
        let fourGB: UInt32 = 0xFF00_0000

        #expect(layout.totalSize < fourGB)
        #expect(layout.totalSize < 1_048_576) // Less than 1MB
    }

    @Test
    func totalSizeAccountsForAllZones() throws {
        let code = ProgramBlobBuilder.createProgramCodeBlob([])
        let program = ProgramBlobBuilder.createStandardProgram(
            programCode: code,
            readOnlyData: Data([0x01]),
            readWriteData: Data(),
            heapPages: 0,
            stackSize: 4096,
        )

        let standardProgram = try StandardProgram(blob: program, argumentData: nil)
        let layout = try JITMemoryLayout(standardProgram: standardProgram)

        // Total size should be >= sum of all zone sizes
        let sumOfZoneSizes = layout.zones.reduce(0) { $0 + $1.size }

        #expect(layout.totalSize >= sumOfZoneSizes)
    }

    // MARK: - Zone Lookup Tests

    @Test
    func findZoneForValidAddress() throws {
        let code = ProgramBlobBuilder.createProgramCodeBlob([])
        let program = ProgramBlobBuilder.createStandardProgram(
            programCode: code,
            readOnlyData: Data([0x01, 0x02, 0x03]),
            readWriteData: Data(),
            heapPages: 0,
            stackSize: 4096,
        )

        let standardProgram = try StandardProgram(blob: program, argumentData: nil)
        let layout = try JITMemoryLayout(standardProgram: standardProgram)

        let config = DefaultPvmConfig()
        let readOnlyBase = UInt32(config.pvmProgramInitZoneSize)

        // Find zone for read-only address
        let zone = layout.zone(for: readOnlyBase)

        #expect(zone != nil)
        #expect(zone?.contains(readOnlyBase) == true)
    }

    @Test
    func returnNilForAddressNotInAnyZone() throws {
        let code = ProgramBlobBuilder.createProgramCodeBlob([])
        let program = ProgramBlobBuilder.createStandardProgram(
            programCode: code,
            readOnlyData: Data([0x01]),
            readWriteData: Data(),
            heapPages: 0,
            stackSize: 4096,
        )

        let standardProgram = try StandardProgram(blob: program, argumentData: nil)
        let layout = try JITMemoryLayout(standardProgram: standardProgram)

        // Try to find zone for invalid address
        let zone = layout.zone(for: 0x0080_0000)

        #expect(zone == nil)
    }

    // MARK: - Data Preservation Tests

    @Test
    func zoneDataIsPreservedDuringExtraction() throws {
        let readOnlyData = Data([0xAA, 0xBB, 0xCC, 0xDD])
        let heapData = Data([0x11, 0x22, 0x33])

        let code = ProgramBlobBuilder.createProgramCodeBlob([])
        let program = ProgramBlobBuilder.createStandardProgram(
            programCode: code,
            readOnlyData: readOnlyData,
            readWriteData: heapData,
            heapPages: 0,
            stackSize: 4096,
        )

        let standardProgram = try StandardProgram(blob: program, argumentData: nil)
        let layout = try JITMemoryLayout(standardProgram: standardProgram)

        // Find read-only zone and verify data
        let readOnlyZone = layout.zones.first { $0.originalBase == UInt32(DefaultPvmConfig().pvmProgramInitZoneSize) }

        if let zone = readOnlyZone {
            #expect(zone.data == readOnlyData)
        } else {
            Issue.record("Read-only zone not found")
        }
    }
}
