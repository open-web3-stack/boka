import Foundation
import Testing
import Utils

@testable import PolkaVM

enum MemoryTests {
    @Suite struct PageMapTests {
        private let config = DefaultPvmConfig()

        @Test func emptyPageMap() {
            let pageMap = PageMap(pageMap: [], config: config)
            #expect(pageMap.isReadable(pageStart: 0, pages: 1) == false)
            #expect(pageMap.isReadable(address: 0, length: 0) == false)
            #expect(pageMap.isReadable(address: 0, length: 1) == false)
            #expect(pageMap.isReadable(address: 1, length: 1) == false)
            #expect(pageMap.isWritable(pageStart: 0, pages: 1) == false)
            #expect(pageMap.isWritable(address: 0, length: 0) == false)
            #expect(pageMap.isWritable(address: 0, length: 1) == false)
            #expect(pageMap.isWritable(address: 1, length: 1) == false)
        }

        @Test func initIncompletePage() {
            let pageMap = PageMap(pageMap: [(address: 0, length: 1, access: .readOnly)], config: config)

            #expect(pageMap.isReadable(pageStart: 0, pages: 1) == true)
            #expect(pageMap.isWritable(pageStart: 0, pages: 1) == false)

            #expect(pageMap.isReadable(address: 0, length: 1) == true)
            #expect(pageMap.isReadable(address: UInt32(config.pvmMemoryPageSize) - 1, length: 1) == true)
            #expect(pageMap.isReadable(address: UInt32(config.pvmMemoryPageSize), length: 1) == false)
        }

        @Test func updatePageMap() {
            let pageMap = PageMap(
                pageMap: [
                    (address: 0, length: UInt32(config.pvmMemoryPageSize), access: .readOnly),
                    (address: UInt32(config.pvmMemoryPageSize), length: UInt32(config.pvmMemoryPageSize), access: .readOnly),
                ],
                config: config
            )

            #expect(pageMap.isReadable(pageStart: 0, pages: 1) == true)
            #expect(pageMap.isWritable(pageStart: 0, pages: 1) == false)
            #expect(pageMap.isReadable(pageStart: 1, pages: 1) == true)
            #expect(pageMap.isWritable(pageStart: 1, pages: 1) == false)

            pageMap.update(pageIndex: 1, pages: 1, access: .readWrite)

            #expect(pageMap.isReadable(pageStart: 1, pages: 1) == true)
            #expect(pageMap.isWritable(pageStart: 0, pages: 1) == false)
            #expect(pageMap.isWritable(pageStart: 1, pages: 1) == true)

            pageMap.update(address: 0, length: config.pvmMemoryPageSize, access: .noAccess)

            #expect(pageMap.isReadable(pageStart: 0, pages: 1) == false)
            #expect(pageMap.isWritable(pageStart: 0, pages: 1) == false)
            #expect(pageMap.isReadable(pageStart: 1, pages: 1) == true)
        }
    }

    @Suite struct MemoryChunkTests {
        private var config = DefaultPvmConfig()
    }

    @Suite struct StandardMemoryTests {
        private var config = DefaultPvmConfig()
    }

    @Suite struct GeneralMemoryTests {}
}
