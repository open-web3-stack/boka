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

        @Test func invalidChunk() throws {
            #expect(throws: MemoryError.invalidChunk(10)) { try MemoryChunk(startAddress: 10, endAddress: 9, data: Data([])) }
            #expect(throws: MemoryError.invalidChunk(0)) { try MemoryChunk(startAddress: 0, endAddress: 0, data: Data([0])) }
            #expect(throws: MemoryError.invalidChunk(0)) { try MemoryChunk(startAddress: 0, endAddress: 1, data: Data([0, 0])) }
        }

        @Test func read() throws {
            let chunk = try MemoryChunk(startAddress: 1, endAddress: 10, data: Data())
            #expect(try chunk.read(address: 1, length: 1) == Data([0]))
            #expect(try chunk.read(address: 2, length: 1) == Data([0]))
            #expect(try chunk.read(address: 2, length: 0) == Data())

            #expect(throws: MemoryError.exceedChunkBoundary(0)) { try chunk.read(address: 0, length: 1) }
            #expect(throws: MemoryError.exceedChunkBoundary(11)) { try chunk.read(address: 11, length: 0) }
        }

        @Test func write() throws {
            let chunk = try MemoryChunk(startAddress: 0, endAddress: 10, data: Data())
            try chunk.write(address: 0, values: Data([1]))
            #expect(chunk.data == Data([1]))
            try chunk.write(address: 1, values: Data([2]))
            #expect(chunk.data == Data([1, 2]))
            try chunk.write(address: 1, values: Data([3]))
            #expect(chunk.data == Data([1, 3]))

            #expect(throws: MemoryError.exceedChunkBoundary(11)) { try chunk.write(address: 11, values: Data([0])) }
            #expect(throws: MemoryError.exceedChunkBoundary(9)) { try chunk.write(address: 9, values: Data([0, 0])) }
        }

        @Test func incrementEnd() throws {
            let chunk = try MemoryChunk(startAddress: 0, endAddress: UInt32.max - 5, data: Data())
            try chunk.incrementEnd(size: 5)
            #expect(chunk.endAddress == UInt32.max)

            #expect(throws: MemoryError.outOfMemory(UInt32.max)) { try chunk.incrementEnd(size: 5) }
        }

        @Test func merge() throws {
            let chunk1 = try MemoryChunk(startAddress: 0, endAddress: 5, data: Data([1, 2, 3]))
            let chunk2 = try MemoryChunk(startAddress: 5, endAddress: 8, data: Data([5, 6, 7]))
            try chunk1.merge(chunk: chunk2)
            #expect(chunk1.data == Data([1, 2, 3, 0, 0, 5, 6, 7]))
            #expect(chunk2.data == Data([5, 6, 7]))
            #expect(chunk1.endAddress == 8)

            let chunk3 = try MemoryChunk(startAddress: 10, endAddress: 15, data: Data([4, 5, 6]))
            #expect(throws: MemoryError.notContiguous(10)) { try chunk1.merge(chunk: chunk3) }
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
            #expect(throws: MemoryError.notReadable(readOnlyStart - 1)) { try memory.read(address: readOnlyStart - 1) }
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
            #expect(throws: MemoryError.notWritable(readOnlyStart - 1)) { try memory.write(address: readOnlyStart - 1, value: 0) }
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
            #expect(memory.isReadable(address: heapEnd, length: config.pvmMemoryPageSize) == false)
            #expect(try memory.sbrk(100) == heapEnd)
            #expect(memory.isReadable(address: heapEnd, length: config.pvmMemoryPageSize) == true)
            #expect(memory.isWritable(address: heapEnd, length: config.pvmMemoryPageSize) == true)
            #expect(try memory.sbrk(UInt32(config.pvmMemoryPageSize)) == heapEnd + UInt32(config.pvmMemoryPageSize))
            #expect(memory.isWritable(address: heapEnd, length: config.pvmMemoryPageSize * 2) == true)
            #expect(memory.isWritable(address: heapEnd, length: config.pvmMemoryPageSize * 2 + 1) == false)
        }
    }

    @Suite struct GeneralMemoryTests {
        let config = DefaultPvmConfig()
        let memory: GeneralMemory

        init() throws {
            memory = try GeneralMemory(
                pageMap: [
                    (address: 0, length: UInt32(config.pvmMemoryPageSize), writable: true),
                    (address: UInt32(config.pvmMemoryPageSize) + 2, length: UInt32(config.pvmMemoryPageSize), writable: false),
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
            #expect(throws: MemoryError.chunkNotFound(1024)) { try memory.read(address: 1024, length: 4) }
            #expect(try memory.read(address: 2048, length: 2) == Data([1, 2]))
            #expect(throws: MemoryError.exceedChunkBoundary(2048)) { try memory.read(address: 2048, length: 10) }
        }

        @Test func write() throws {
            try memory.write(address: 2, values: Data([9, 8]))
            #expect(try memory.read(address: 0, length: 4) == Data([1, 2, 9, 8]))
            #expect(throws: MemoryError.notWritable(4096)) { try memory.write(address: 4096, values: Data([0])) }
        }

        @Test func sbrk() throws {
            let oldEnd = try memory.sbrk(512)

            #expect(memory.isWritable(address: oldEnd, length: 512) == true)
            #expect(memory.isWritable(address: 0, length: Int(oldEnd)) == true)

            try memory.write(address: oldEnd, values: Data([1, 2, 3]))
            #expect(try memory.read(address: oldEnd - 1, length: 5) == Data([7, 1, 2, 3, 0]))
        }

        @Test func zero() throws {
            #expect(try memory.read(address: 4096, length: 3) == Data([1, 2, 3]))
            try memory.zero(pageIndex: 1, pages: 1)
            #expect(try memory.read(address: 4096, length: 3) == Data([0, 0, 0]))

            #expect(memory.isReadable(address: 4096 * 2, length: 3) == false)
            try memory.zero(pageIndex: 2, pages: 1)
            #expect(memory.isReadable(address: 4096 * 2, length: 4096) == true)
            #expect(memory.isWritable(address: 4096 * 2, length: 4096) == true)
        }

        @Test func void() throws {
            #expect(try memory.read(address: 4096, length: 3) == Data([1, 2, 3]))
            try memory.void(pageIndex: 1, pages: 1)
            #expect(memory.isReadable(address: 4096, length: 4096) == false)

            #expect(memory.isReadable(address: 4096 * 4, length: 3) == true)
            #expect(memory.isWritable(address: 4096 * 4, length: 3) == true)
            try memory.void(pageIndex: 4, pages: 1)
            #expect(memory.isReadable(address: 4096 * 4, length: 4096) == false)
            #expect(memory.isWritable(address: 4096 * 4, length: 4096) == false)
        }
    }
}
