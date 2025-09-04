import Foundation

/// MemoryZone is an isolated memory area, used for stack, heap, arguments, etc.
class MemoryZone {
    private let config: PvmConfig
    public let startAddress: UInt32
    public private(set) var endAddress: UInt32

    // TODO: could be optimized by using a more efficient data structure
    public private(set) var chunks: [MemoryChunk] = []

    public init(startAddress: UInt32, endAddress: UInt32, chunks: [MemoryChunk]) throws(MemoryError) {
        guard startAddress <= endAddress, (chunks.isSorted { $0.endAddress < $1.startAddress }) else {
            throw .invalidZone(startAddress)
        }

        if let last = chunks.last, endAddress < last.endAddress {
            throw .invalidZone(startAddress)
        }

        self.startAddress = startAddress
        self.endAddress = endAddress
        self.chunks = chunks
        config = DefaultPvmConfig()
    }

    // binary search for the index containing the address or index to be inserted
    private func searchChunk(for address: UInt32) -> (index: Int, found: Bool) {
        var low = 0
        var high = chunks.endIndex
        while low < high {
            let mid = low + (high - low) / 2
            if chunks[mid].startAddress <= address, address < chunks[mid].endAddress {
                return (mid, true)
            } else if chunks[mid].startAddress > address {
                high = mid
            } else {
                low = mid + 1
            }
        }
        return (low, false)
    }

    /// Insert or update the chunks, overwrite overlapping data.
    ///
    /// Note this method assumes chunks are sorted by address.
    private func insertOrUpdate(address chunkStart: UInt32, data: Data) throws {
        let chunkEnd = chunkStart + UInt32(data.count)
        guard chunkEnd >= chunkStart else { throw MemoryError.outOfMemory(chunkEnd) }

        // fast search for exact chunk match
        let (chunkIndex, found) = searchChunk(for: chunkStart)
        if found, chunkIndex < chunks.count {
            let chunk = chunks[chunkIndex]
            if chunkStart >= chunk.startAddress, chunkEnd <= chunk.endAddress {
                try chunk.write(address: chunkStart, values: data)
                return
            }
        }

        // insert new chunk at the end
        if chunkStart >= chunks.last?.endAddress ?? UInt32.max {
            let chunk = try MemoryChunk(startAddress: chunkStart, data: data)
            if chunks.last?.endAddress == chunkStart {
                try chunks.last?.append(chunk: chunk)
                return
            } else {
                chunks.append(chunk)
                return
            }
        }

        // find overlapping chunks
        var firstIndex = searchChunk(for: chunkStart).index
        if firstIndex > 0, chunks[firstIndex - 1].endAddress > chunkStart {
            firstIndex -= 1
        }
        var lastIndex = firstIndex
        while lastIndex < chunks.count, chunks[lastIndex].startAddress < chunkEnd {
            lastIndex += 1
        }

        // no overlaps
        if firstIndex == lastIndex {
            try chunks.insert(MemoryChunk(startAddress: chunkStart, data: data), at: firstIndex)
            return
        }

        // have overlaps
        // calculate overlapping chunk boundaries
        let startAddr = min(chunks[firstIndex].startAddress, chunkStart)
        let endAddr = max(chunks[lastIndex - 1].endAddress, chunkEnd)
        let newChunk = try MemoryChunk(startAddress: startAddr, data: Data())
        try newChunk.zeroExtend(until: endAddr)
        // merge overlapping part into a new chunk
        for i in firstIndex ..< lastIndex {
            try newChunk.write(address: chunks[i].startAddress, values: chunks[i].data)
        }
        // overwrite overlapping part with input data
        try newChunk.write(address: chunkStart, values: data)
        // replace overlapping chunks
        if lastIndex - firstIndex == 1 {
            // replacing exactly one chunk
            chunks[firstIndex] = newChunk
        } else {
            // replacing multiple chunks with one
            // remove old chunks in reverse order to avoid shifting
            for i in stride(from: lastIndex - 1, through: firstIndex + 1, by: -1) {
                chunks.remove(at: i)
            }
            chunks[firstIndex] = newChunk
        }
    }

    public func read(address: UInt32, length: Int) throws -> Data {
        guard length > 0 else { return Data() }
        let readEnd = address &+ UInt32(length)
        guard readEnd >= address else { throw MemoryError.outOfMemory(readEnd) }
        guard endAddress >= readEnd else { throw MemoryError.exceedZoneBoundary(endAddress) }

        let (startIndex, _) = searchChunk(for: address)

        var res = Data(count: length)
        var resOffset = 0
        var curAddr = address
        var curChunkIndex = startIndex

        res.withUnsafeMutableBytes { resBuffer in
            let resPtr = resBuffer.bindMemory(to: UInt8.self).baseAddress!

            while curAddr < readEnd, curChunkIndex < chunks.endIndex {
                let chunk = chunks[curChunkIndex]

                // handle gap before chunk
                if curAddr < chunk.startAddress {
                    let gapSize = min(chunk.startAddress - curAddr, readEnd - curAddr)
                    // zero-fill gap using unsafe operations
                    memset(resPtr.advanced(by: resOffset), 0, Int(gapSize))
                    resOffset += Int(gapSize)
                    curAddr += gapSize
                    continue
                }

                // handle chunk content
                if curAddr >= chunk.endAddress {
                    curChunkIndex += 1
                    continue
                }

                let chunkOffset = Int(curAddr - chunk.startAddress)
                let bytesToRead = min(chunk.data.count - chunkOffset, Int(readEnd - curAddr))

                // direct memory copy using unsafe operations
                chunk.data.withUnsafeBytes { chunkBuffer in
                    let chunkPtr = chunkBuffer.bindMemory(to: UInt8.self).baseAddress!
                    memcpy(resPtr.advanced(by: resOffset), chunkPtr.advanced(by: chunkOffset), bytesToRead)
                }

                resOffset += bytesToRead
                curAddr += UInt32(bytesToRead)
                curChunkIndex += 1
            }

            // handle remaining space after last chunk
            if curAddr < readEnd {
                let remainingSize = Int(readEnd - curAddr)
                memset(resPtr.advanced(by: resOffset), 0, remainingSize)
            }
        }

        return res
    }

    public func write(address: UInt32, values: Data) throws {
        try insertOrUpdate(address: address, data: values)
    }

    public func incrementEnd(size increment: UInt32) throws(MemoryError) {
        guard endAddress <= UInt32.max - increment else {
            throw .outOfMemory(endAddress)
        }
        endAddress += increment
    }

    public func zero(pageIndex: UInt32, pages: Int) throws {
        try insertOrUpdate(
            address: pageIndex * UInt32(config.pvmMemoryPageSize),
            data: Data(repeating: 0, count: Int(pages * config.pvmMemoryPageSize))
        )
    }
}

class MemoryChunk {
    public private(set) var startAddress: UInt32
    public var endAddress: UInt32 {
        startAddress + UInt32(data.count)
    }

    public private(set) var data: Data

    public init(startAddress: UInt32, data: Data) throws(MemoryError) {
        let endAddress = startAddress + UInt32(data.count)
        guard startAddress <= endAddress, endAddress - startAddress >= UInt32(data.count) else {
            throw .invalidChunk(startAddress)
        }
        self.startAddress = startAddress
        self.data = data
    }

    // append another adjacent chunk
    public func append(chunk: MemoryChunk) throws(MemoryError) {
        guard endAddress == chunk.startAddress else {
            throw .notAdjacent(chunk.startAddress)
        }
        guard chunk.endAddress <= UInt32.max else {
            throw .outOfMemory(endAddress)
        }
        data.append(chunk.data)
    }

    public func zeroExtend(until address: UInt32) throws(MemoryError) {
        guard address <= UInt32.max else {
            throw .outOfMemory(endAddress)
        }
        data.append(Data(repeating: 0, count: Int(address - startAddress) - data.count))
    }

    public func read(address: UInt32, length: Int) throws(MemoryError) -> Data {
        guard startAddress <= address, address + UInt32(length) <= endAddress else {
            throw .exceedChunkBoundary(address)
        }

        let offset = Int(address - startAddress) + data.startIndex

        return data[offset ..< (offset + length)]
    }

    public func write(address: UInt32, values: Data) throws(MemoryError) {
        guard startAddress <= address, address + UInt32(values.count) <= endAddress else {
            throw .exceedChunkBoundary(address)
        }

        let offset = Int(address - startAddress)

        if values.count > 0 {
            data.withUnsafeMutableBytes { dataBuffer in
                values.withUnsafeBytes { valuesBuffer in
                    let dataPtr = dataBuffer.bindMemory(to: UInt8.self).baseAddress!
                    let valuesPtr = valuesBuffer.bindMemory(to: UInt8.self).baseAddress!
                    memcpy(dataPtr.advanced(by: offset), valuesPtr, values.count)
                }
            }
        }
    }
}

/// General Program Memory
public class GeneralMemory: Memory {
    private let config: PvmConfig
    public let pageMap: PageMap

    // general memory has a single zone
    private let zone: MemoryZone

    public init(pageMap: [(address: UInt32, length: UInt32, writable: Bool)], chunks: [(address: UInt32, data: Data)]) throws {
        let config = DefaultPvmConfig()
        self.pageMap = PageMap(
            pageMap: pageMap.map { (address: $0.address, length: $0.length, access: $0.writable ? .readWrite : .readOnly) },
            config: config
        )

        let memoryChunks = try chunks.map { chunk in
            try MemoryChunk(startAddress: chunk.address, data: chunk.data)
        }

        zone = try MemoryZone(startAddress: 0, endAddress: UInt32.max, chunks: memoryChunks)
        self.config = config
    }

    public func read(address: UInt32) throws -> UInt8 {
        try ensureReadable(address: address, length: 1)
        return try zone.read(address: address, length: 1).first ?? 0
    }

    public func read(address: UInt32, length: Int) throws -> Data {
        try ensureReadable(address: address, length: length)
        return try zone.read(address: address, length: length)
    }

    public func write(address: UInt32, value: UInt8) throws {
        try ensureWritable(address: address, length: 1)
        try zone.write(address: address, values: Data([value]))
    }

    public func write(address: UInt32, values: Data) throws {
        try ensureWritable(address: address, length: values.count)
        try zone.write(address: address, values: values)
    }

    public func pages(pageIndex: UInt32, pages: Int, variant: UInt64) throws {
        if variant == 0 {
            pageMap.removeAccess(pageIndex: pageIndex, pages: pages)
        } else if variant == 1 || variant == 3 {
            pageMap.update(pageIndex: pageIndex, pages: pages, access: .readOnly)
        } else if variant == 2 || variant == 4 {
            pageMap.update(pageIndex: pageIndex, pages: pages, access: .readWrite)
        }

        if variant < 3 {
            try zone.zero(pageIndex: pageIndex, pages: pages)
        }
    }

    public func sbrk(_ size: UInt32) throws(MemoryError) -> UInt32 {
        let pages = (Int(size) + config.pvmMemoryPageSize - 1) / config.pvmMemoryPageSize
        let page = try pageMap.findGapOrThrow(pages: pages)
        pageMap.update(pageIndex: page, pages: pages, access: .readWrite)

        return page * UInt32(config.pvmMemoryPageSize)
    }
}
