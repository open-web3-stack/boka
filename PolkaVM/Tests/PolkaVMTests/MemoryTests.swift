import Foundation
import Testing
import Utils

@testable import PolkaVM

enum MemoryTests {
    @Suite struct PageMapTests {
        private let config = DefaultPvmConfig()

        @Test func emptyPageMap() {
            let pageMap = PageMap(pageMap: [], config: config)
            #expect(pageMap.isReadable(pageStart: 0, pages: 1).result == false)
            #expect(pageMap.isReadable(address: 0, length: 1).result == false)
            #expect(pageMap.isReadable(address: 1, length: 1).result == false)
            #expect(pageMap.isWritable(pageStart: 0, pages: 1).result == false)
            #expect(pageMap.isWritable(address: 0, length: 1).result == false)
            #expect(pageMap.isWritable(address: 1, length: 1).result == false)
        }

        @Test func initIncompletePage() {
            let pageMap = PageMap(pageMap: [(address: 0, length: 1, access: .readOnly)], config: config)

            #expect(pageMap.isReadable(pageStart: 0, pages: 1).result == true)
            #expect(pageMap.isWritable(pageStart: 0, pages: 1).result == false)

            #expect(pageMap.isReadable(address: 0, length: 1).result == true)
            #expect(pageMap.isReadable(address: UInt32(config.pvmMemoryPageSize) - 1, length: 1).result == true)
            #expect(pageMap.isReadable(address: UInt32(config.pvmMemoryPageSize), length: 1).result == false)
        }

        @Test func updatePageMap() {
            let pageMap = PageMap(
                pageMap: [
                    (address: 0, length: UInt32(config.pvmMemoryPageSize), access: .readOnly),
                    (address: UInt32(config.pvmMemoryPageSize), length: UInt32(config.pvmMemoryPageSize), access: .readOnly),
                ],
                config: config
            )

            #expect(pageMap.isReadable(pageStart: 0, pages: 1).result == true)
            #expect(pageMap.isWritable(pageStart: 0, pages: 1).result == false)
            #expect(pageMap.isReadable(pageStart: 1, pages: 1).result == true)
            #expect(pageMap.isWritable(pageStart: 1, pages: 1).result == false)

            pageMap.update(pageIndex: 1, pages: 1, access: .readWrite)

            #expect(pageMap.isReadable(pageStart: 1, pages: 1).result == true)
            #expect(pageMap.isWritable(pageStart: 0, pages: 1).result == false)
            #expect(pageMap.isWritable(pageStart: 1, pages: 1).result == true)

            pageMap.removeAccess(address: 0, length: config.pvmMemoryPageSize)

            #expect(pageMap.isReadable(pageStart: 0, pages: 1).result == false)
            #expect(pageMap.isWritable(pageStart: 0, pages: 1).result == false)
            #expect(pageMap.isReadable(pageStart: 1, pages: 1).result == true)
        }
    }

    @Suite struct MemoryChunkTests {
        private var config = DefaultPvmConfig()

        @Test func read() throws {
            let chunk = try MemoryChunk(startAddress: 1, data: Data(repeating: 0, count: 9))
            #expect(try chunk.read(address: 1, length: 1) == Data([0]))
            #expect(try chunk.read(address: 2, length: 1) == Data([0]))
            #expect(try chunk.read(address: 2, length: 0) == Data())

            #expect(throws: MemoryError.exceedChunkBoundary(0)) { try chunk.read(address: 0, length: 1) }
            #expect(throws: MemoryError.exceedChunkBoundary(11)) { try chunk.read(address: 11, length: 0) }
        }

        @Test func write() throws {
            let chunk = try MemoryChunk(startAddress: 0, data: Data(repeating: 0, count: 3))
            try chunk.write(address: 0, values: Data([1]))
            #expect(chunk.data == Data([1, 0, 0]))
            try chunk.write(address: 1, values: Data([2]))
            #expect(chunk.data == Data([1, 2, 0]))
            try chunk.write(address: 1, values: Data([3]))
            #expect(chunk.data == Data([1, 3, 0]))

            #expect(throws: MemoryError.exceedChunkBoundary(3)) { try chunk.write(address: 3, values: Data([0])) }
            #expect(throws: MemoryError.exceedChunkBoundary(2)) { try chunk.write(address: 2, values: Data([0, 0])) }
        }

        @Test func append() throws {
            let chunk1 = try MemoryChunk(startAddress: 0, data: Data([1, 2, 3, 0, 0]))
            let chunk2 = try MemoryChunk(startAddress: 5, data: Data([5, 6, 7]))
            try chunk1.append(chunk: chunk2)
            #expect(chunk1.data == Data([1, 2, 3, 0, 0, 5, 6, 7]))
            #expect(chunk2.data == Data([5, 6, 7]))
            #expect(chunk1.endAddress == 8)

            let chunk3 = try MemoryChunk(startAddress: 10, data: Data([4, 5, 6, 0, 0]))
            #expect(throws: MemoryError.notAdjacent(10)) { try chunk1.append(chunk: chunk3) }
        }

        @Test func zeroExtend() throws {
            let chunk1 = try MemoryChunk(startAddress: 0, data: Data([1, 2, 3]))
            try chunk1.zeroExtend(until: 5)
            #expect(chunk1.data == Data([1, 2, 3, 0, 0]))
            #expect(chunk1.endAddress == 5)
        }
    }

    @Suite struct MemoryZoneTests {
        private var config = DefaultPvmConfig()

        @Test func invalidZone() throws {
            #expect(throws: MemoryError.invalidZone(10)) { try MemoryZone(startAddress: 10, endAddress: 9, chunks: []) }
            #expect(throws: MemoryError.invalidZone(0)) { try MemoryZone(
                startAddress: 0,
                endAddress: 0,
                chunks: [MemoryChunk(startAddress: 0, data: Data([0]))]
            ) }
            #expect(throws: MemoryError.invalidZone(0)) { try MemoryZone(
                startAddress: 0,
                endAddress: 1,
                chunks: [MemoryChunk(startAddress: 0, data: Data([0, 0]))]
            ) }
        }

        @Test func incrementEnd() throws {
            let zone = try MemoryZone(startAddress: 0, endAddress: UInt32.max - 5, chunks: [])
            try zone.incrementEnd(size: 5)
            #expect(zone.endAddress == UInt32.max)

            #expect(throws: MemoryError.outOfMemory(UInt32.max)) { try zone.incrementEnd(size: 5) }
        }

        @Test func read() throws {
            let zone = try MemoryZone(startAddress: 0, endAddress: 10, chunks: [
                MemoryChunk(startAddress: 0, data: Data([0, 0])),
                MemoryChunk(startAddress: 5, data: Data([0, 1])),
                MemoryChunk(startAddress: 8, data: Data([2])),
            ])
            #expect(try zone.read(address: 0, length: 1) == Data([0]))
            #expect(try zone.read(address: 2, length: 1) == Data([0]))
            #expect(try zone.read(address: 0, length: 2) == Data([0, 0]))
            #expect(try zone.read(address: 2, length: 0) == Data())
            #expect(try zone.read(address: 2, length: 2) == Data([0, 0]))
            #expect(try zone.read(address: 4, length: 2) == Data([0, 0]))
            #expect(try zone.read(address: 4, length: 3) == Data([0, 0, 1]))
            #expect(try zone.read(address: 4, length: 4) == Data([0, 0, 1, 0]))
            #expect(try zone.read(address: 4, length: 5) == Data([0, 0, 1, 0, 2]))
            #expect(try zone.read(address: 4, length: 6) == Data([0, 0, 1, 0, 2, 0]))
            #expect(try zone.read(address: 5, length: 1) == Data([0]))
            #expect(try zone.read(address: 5, length: 4) == Data([0, 1, 0, 2]))
            #expect(try zone.read(address: 9, length: 1) == Data([0]))
            #expect(throws: MemoryError.exceedZoneBoundary(10)) { try zone.read(address: 9, length: 2) == Data([0]) }
        }

        @Test func write() throws {
            let zone = try MemoryZone(startAddress: 0, endAddress: 10, chunks: [
                MemoryChunk(startAddress: 0, data: Data([0, 0])),
                MemoryChunk(startAddress: 5, data: Data([0, 1])),
                MemoryChunk(startAddress: 8, data: Data([2])),
            ])

            try zone.write(address: 0, values: Data([1]))
            #expect(try zone.read(address: 0, length: 1) == Data([1]))

            try zone.write(address: 0, values: Data([1, 2, 3]))
            #expect(try zone.read(address: 0, length: 5) == Data([1, 2, 3, 0, 0]))

            try zone.write(address: 3, values: Data([4, 5, 6]))
            #expect(try zone.read(address: 0, length: 10) == Data([1, 2, 3, 4, 5, 6, 1, 0, 2, 0]))

            #expect(zone.chunks.count == 3)
            try zone.write(address: 2, values: Data([3, 4, 5, 6, 7, 8, 9]))
            #expect(zone.chunks.count == 1)
            #expect(try zone.read(address: 0, length: 10) == Data([1, 2, 3, 4, 5, 6, 7, 8, 9, 0]))
        }

        @Test func zero() throws {
            let zone = try MemoryZone(startAddress: 0, endAddress: 4096, chunks: [
                MemoryChunk(startAddress: 0, data: Data([0, 0])),
                MemoryChunk(startAddress: 5, data: Data([0, 1])),
                MemoryChunk(startAddress: 8, data: Data([2])),
            ])

            try zone.zero(pageIndex: 0, pages: 1)
            #expect(try zone.read(address: 0, length: 4096) == Data(repeating: 0, count: 4096))
        }
    }

    @Suite struct StandardMemoryTests {
        let config = DefaultPvmConfig()
        let memory: StandardMemory

        let readOnlyStart: UInt32
        let readOnlyEnd: UInt32
        let heapStart: UInt32
        let heapEnd: UInt32
        let stackStart: UInt32
        let stackEnd: UInt32
        let argumentStart: UInt32
        let argumentEnd: UInt32

        init() throws {
            let readOnlyData = Data([1, 2, 3])
            let readWriteData = Data([4, 5, 6])
            let argumentData = Data([7, 8, 9])
            memory = try StandardMemory(
                readOnlyData: readOnlyData,
                readWriteData: readWriteData,
                argumentData: argumentData,
                heapEmptyPagesSize: 100 * UInt32(config.pvmMemoryPageSize),
                stackSize: 1024
            )
            readOnlyStart = UInt32(config.pvmProgramInitZoneSize)
            readOnlyEnd = UInt32(config.pvmProgramInitZoneSize) + UInt32(config.pvmMemoryPageSize)
            heapStart = 2 * UInt32(config.pvmProgramInitZoneSize) + UInt32(config.pvmProgramInitZoneSize)
            heapEnd = heapStart + UInt32(config.pvmMemoryPageSize) + 100 * UInt32(config.pvmMemoryPageSize)
            stackStart = UInt32(config.pvmProgramInitStackBaseAddress) - UInt32(config.pvmMemoryPageSize)
            stackEnd = UInt32(config.pvmProgramInitStackBaseAddress)
            argumentStart = UInt32(config.pvmProgramInitInputStartAddress)
            argumentEnd = UInt32(config.pvmProgramInitInputStartAddress) + UInt32(config.pvmMemoryPageSize)
        }

        @Test func read() throws {
            // readonly
            #expect(throws: MemoryError.notReadable(0)) { try memory.read(address: 0) }
            #expect(throws: MemoryError.notReadable(readOnlyStart - 4096)) { try memory.read(address: readOnlyStart - 1) }
            #expect(memory.isReadable(address: 0, length: config.pvmProgramInitZoneSize) == false)
            #expect(try memory.read(address: readOnlyStart, length: 4) == Data([1, 2, 3, 0]))
            #expect(try memory.read(address: readOnlyStart, length: 4) == Data([1, 2, 3, 0]))
            #expect(throws: MemoryError.notReadable(readOnlyEnd)) { try memory.read(
                address: readOnlyEnd,
                length: Int(heapStart - readOnlyEnd)
            ) }

            // heap
            #expect(memory.isReadable(address: heapStart - 1, length: 1) == false)
            #expect(memory.isReadable(address: heapStart, length: Int(heapEnd - heapStart)) == true)
            #expect(try memory.read(address: heapStart, length: 4) == Data([4, 5, 6, 0]))
            #expect(try memory.read(address: heapEnd - 3, length: 3) == Data([0, 0, 0]))

            // stack
            #expect(memory.isReadable(address: stackStart - 1, length: 1) == false)
            #expect(memory.isReadable(address: stackStart, length: Int(stackEnd - stackStart)) == true)
            #expect(try memory.read(address: stackStart, length: 2) == Data([0, 0]))
            #expect(try memory.read(address: stackEnd - 3, length: 3) == Data([0, 0, 0]))

            // argument
            #expect(memory.isReadable(address: argumentStart - 1, length: 1) == false)
            #expect(memory.isReadable(address: argumentStart, length: Int(argumentEnd - argumentStart)) == true)
            #expect(try memory.read(address: argumentStart, length: 4) == Data([7, 8, 9, 0]))
            #expect(try memory.read(address: argumentEnd - 3, length: 3) == Data([0, 0, 0]))
            #expect(throws: MemoryError.notReadable(argumentEnd)) { try memory.read(address: argumentEnd, length: 1) }
        }

        @Test func write() throws {
            // readonly
            #expect(throws: MemoryError.notWritable(0)) { try memory.write(address: 0, value: 0) }
            #expect(throws: MemoryError.notWritable(readOnlyStart - 4096)) { try memory.write(address: readOnlyStart - 1, value: 0) }
            #expect(memory.isWritable(address: 0, length: config.pvmProgramInitZoneSize) == false)
            #expect(throws: MemoryError.notWritable(readOnlyStart)) { try memory.write(address: readOnlyStart, value: 4) }
            #expect(try memory.read(address: readOnlyStart, length: 4) == Data([1, 2, 3, 0]))

            // heap
            #expect(memory.isWritable(address: heapStart - 1, length: 1) == false)
            #expect(memory.isWritable(address: heapStart, length: Int(heapEnd - heapStart)) == true)
            try memory.write(address: heapStart, value: 44)
            #expect(try memory.read(address: heapStart, length: 4) == Data([44, 5, 6, 0]))
            try memory.write(address: heapEnd - 1, value: 1)
            #expect(try memory.read(address: heapEnd - 2, length: 2) == Data([0, 1]))

            // stack
            #expect(memory.isWritable(address: stackStart - 1, length: 1) == false)
            #expect(memory.isWritable(address: stackStart, length: Int(stackEnd - stackStart)) == true)
            try memory.write(address: stackStart, value: 1)
            #expect(try memory.read(address: stackStart, length: 2) == Data([1, 0]))
            try memory.write(address: stackEnd - 2, values: Data([1, 2]))
            #expect(try memory.read(address: stackEnd - 4, length: 4) == Data([0, 0, 1, 2]))

            // argument
            #expect(memory.isReadable(address: argumentStart - 1, length: 1) == false)
            #expect(memory.isReadable(address: argumentStart, length: Int(argumentEnd - argumentStart)) == true)
            #expect(memory.isReadable(address: argumentEnd, length: Int(UInt32.max - argumentEnd)) == false)
            #expect(throws: MemoryError.notWritable(argumentStart)) { try memory.write(address: argumentStart, value: 4) }
        }

        @Test func sbrk() throws {
            let pageSize = UInt32(config.pvmMemoryPageSize)

            let initialHeapEnd = try memory.sbrk(0)

            let allocSize: UInt32 = pageSize + (pageSize / 4) // 1.25 pages worth
            let newHeapEnd = try memory.sbrk(allocSize)

            #expect(newHeapEnd == initialHeapEnd)

            let finalBoundary = initialHeapEnd + allocSize
            let start = initialHeapEnd / pageSize
            let end = (finalBoundary + pageSize - 1) / pageSize
            let pages = end - start

            #expect(memory.isWritable(address: initialHeapEnd, length: Int(allocSize)) == true)

            let lastPageStart = (end - 1) * pageSize
            #expect(memory.isWritable(address: lastPageStart, length: Int(pageSize)) == true)

            try memory.write(address: initialHeapEnd, value: 42)
            try memory.write(address: finalBoundary - 1, value: 43)

            #expect(try memory.read(address: initialHeapEnd) == 42)
            #expect(try memory.read(address: finalBoundary - 1) == 43)
        }
    }

    @Suite struct GeneralMemoryTests {
        let config = DefaultPvmConfig()
        let memory: GeneralMemory

        init() throws {
            memory = try GeneralMemory(
                pageMap: [
                    (address: 0, length: UInt32(config.pvmMemoryPageSize), writable: true),
                    (address: UInt32(config.pvmMemoryPageSize), length: UInt32(config.pvmMemoryPageSize), writable: false),
                    (address: UInt32(config.pvmMemoryPageSize) * 4, length: UInt32(config.pvmMemoryPageSize) / 2, writable: true),
                ],
                chunks: [
                    (address: 0, data: Data([1, 2, 3, 4])),
                    (address: 4, data: Data([5, 6, 7])),
                    (address: 2048, data: Data([1, 2, 3])),
                    (address: UInt32(config.pvmMemoryPageSize), data: Data([1, 2, 3])),
                ]
            )
        }

        @Test func pageMap() throws {
            #expect(memory.isReadable(pageStart: 0, pages: 1) == true)
            #expect(memory.isReadable(pageStart: 1, pages: 1) == true)
            #expect(memory.isReadable(pageStart: 2, pages: 1) == false)
            #expect(memory.isReadable(pageStart: 4, pages: 1) == true)

            #expect(memory.isWritable(pageStart: 0, pages: 1) == true)
            #expect(memory.isWritable(pageStart: 1, pages: 1) == false)
            #expect(memory.isWritable(pageStart: 2, pages: 1) == false)
            #expect(memory.isWritable(pageStart: 4, pages: 1) == true)
        }

        @Test func read() throws {
            #expect(try memory.read(address: 0, length: 4) == Data([1, 2, 3, 4]))
            #expect(try memory.read(address: 1024, length: 4) == Data([0, 0, 0, 0]))
            #expect(try memory.read(address: 2048, length: 2) == Data([1, 2]))
            #expect(try memory.read(address: 2048, length: 10) == Data([1, 2, 3, 0, 0, 0, 0, 0, 0, 0]))
        }

        @Test func write() throws {
            try memory.write(address: 2, values: Data([9, 8]))
            #expect(try memory.read(address: 0, length: 4) == Data([1, 2, 9, 8]))
            #expect(throws: MemoryError.notWritable(4096)) { try memory.write(address: 4096, values: Data([0])) }
        }

        @Test func sbrk() throws {
            let oldEnd = try memory.sbrk(512)

            #expect(oldEnd == UInt32(config.pvmMemoryPageSize))
            #expect(memory.isWritable(address: oldEnd, length: config.pvmMemoryPageSize) == true)
            #expect(memory.isWritable(address: 0, length: Int(oldEnd)) == true)

            try memory.write(address: oldEnd, values: Data([1, 2, 3]))
            #expect(try memory.read(address: oldEnd - 1, length: 5) == Data([0, 1, 2, 3, 0]))
        }

        @Test func pages() throws {
            // Test zero with read-write access (variant = 2)
            #expect(try memory.read(address: 4096, length: 3) == Data([1, 2, 3]))
            try memory.pages(pageIndex: 1, pages: 1, variant: 2)
            #expect(try memory.read(address: 4096, length: 3) == Data([0, 0, 0]))

            // Test zero with read-only access (variant = 1)
            #expect(memory.isReadable(address: 4096 * 2, length: 3) == false)
            try memory.pages(pageIndex: 2, pages: 1, variant: 1)
            #expect(memory.isReadable(address: 4096 * 2, length: 4096) == true)
            #expect(memory.isWritable(address: 4096 * 2, length: 4096) == false)

            // Test void (remove access, variant = 0)
            #expect(try memory.read(address: 4096, length: 3) == Data([0, 0, 0]))
            try memory.pages(pageIndex: 1, pages: 1, variant: 0)
            #expect(memory.isReadable(address: 4096, length: 4096) == false)

            #expect(memory.isReadable(address: 4096 * 4, length: 3) == true)
            #expect(memory.isWritable(address: 4096 * 4, length: 3) == true)
            try memory.pages(pageIndex: 4, pages: 1, variant: 0)
            #expect(memory.isReadable(address: 4096 * 4, length: 4096) == false)
            #expect(memory.isWritable(address: 4096 * 4, length: 4096) == false)
        }
    }
}
