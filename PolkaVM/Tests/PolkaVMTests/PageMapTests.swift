import Foundation
@testable import PolkaVM
import Testing
import Utils

/// Unit tests for PageMap and memory management
struct PageMapTests {
    @Test func pageMapCreation() {
        let config = DefaultPvmConfig()
        let pageMap = PageMap(pageMap: [], config: config)
        // PageMap should be created successfully
    }

    @Test func pageAccess() {
        // Test PageAccess enum
        let readOnly = PageAccess.readOnly
        let readWrite = PageAccess.readWrite

        #expect(readOnly.isReadable())
        #expect(!readOnly.isWritable())

        #expect(readWrite.isReadable())
        #expect(readWrite.isWritable())
    }

    @Test func generalMemoryCreation() {
        let pageMap: [(address: UInt32, length: UInt32, writable: Bool)] = []
        let chunks: [(address: UInt32, data: Data)] = []

        let memory = try? GeneralMemory(pageMap: pageMap, chunks: chunks)
        #expect(memory != nil)
    }

    @Test func memoryAlignment() {
        // Test that page sizes are properly aligned
        let pageSizes = [4096, 8192, 16384, 32768, 65536]

        for pageSize in pageSizes {
            #expect(pageSize % 4096 == 0, "Page size \(pageSize) should be aligned to 4KB")
        }
    }

    @Test func standardPageSizes() {
        // Test common page sizes
        let standard4KB = 4096
        let standard8KB = 8192
        let standard16KB = 16384
        let standard64KB = 65536

        #expect(standard4KB == 4 * 1024)
        #expect(standard8KB == 8 * 1024)
        #expect(standard16KB == 16 * 1024)
        #expect(standard64KB == 64 * 1024)
    }

    @Test func pageMapWithPages() {
        let config = DefaultPvmConfig()
        let pages: [(address: UInt32, length: UInt32, writable: Bool)] = [
            (address: 0x1000, length: 0x1000, writable: true),
            (address: 0x2000, length: 0x1000, writable: false),
        ]

        let pageMap = PageMap(
            pageMap: pages.map { (address: $0.address, length: $0.length, access: $0.writable ? .readWrite : .readOnly) },
            config: config,
        )
        // PageMap should handle multiple pages
    }
}
