import Foundation

public enum MemoryError: Error, Equatable {
    case zoneNotFound(UInt32)
    case chunkNotFound(UInt32)
    case invalidZone(UInt32)
    case exceedZoneBoundary(UInt32)
    case invalidChunk(UInt32)
    case exceedChunkBoundary(UInt32)
    case notReadable(UInt32)
    case notWritable(UInt32)
    case outOfMemory(UInt32)
    case notAdjacent(UInt32)

    private static let pageSize = UInt32(DefaultPvmConfig().pvmMemoryPageSize)

    /// align to page start address
    private func alignToPageStart(address: UInt32) -> UInt32 {
        (address / Self.pageSize) * Self.pageSize
    }

    public var address: UInt32 {
        switch self {
        case let .zoneNotFound(address):
            alignToPageStart(address: address)
        case let .chunkNotFound(address):
            alignToPageStart(address: address)
        case let .invalidZone(address):
            alignToPageStart(address: address)
        case let .exceedZoneBoundary(address):
            alignToPageStart(address: address)
        case let .invalidChunk(address):
            alignToPageStart(address: address)
        case let .exceedChunkBoundary(address):
            alignToPageStart(address: address)
        case let .notReadable(address):
            alignToPageStart(address: address)
        case let .notWritable(address):
            alignToPageStart(address: address)
        case let .outOfMemory(address):
            alignToPageStart(address: address)
        case let .notAdjacent(address):
            alignToPageStart(address: address)
        }
    }
}

public protocol Memory {
    var pageMap: PageMap { get }

    func isReadable(address: UInt32, length: Int) -> Bool
    func isWritable(address: UInt32, length: Int) -> Bool
    func isReadable(pageStart: UInt32, pages: Int) -> Bool
    func isWritable(pageStart: UInt32, pages: Int) -> Bool

    func read(address: UInt32) throws -> UInt8
    func read(address: UInt32, length: Int) throws -> Data
    func write(address: UInt32, value: UInt8) throws
    func write(address: UInt32, values: Data) throws

    func sbrk(_ increment: UInt32) throws -> UInt32
}

extension Memory {
    public func isReadable(address: UInt32, length: Int) -> Bool {
        if length == 0 { return true }
        return pageMap.isReadable(address: address, length: length).result
    }

    public func isReadable(pageStart: UInt32, pages: Int) -> Bool {
        pageMap.isReadable(pageStart: pageStart, pages: pages).result
    }

    public func ensureReadable(address: UInt32, length: Int) throws(MemoryError) {
        let (result, address) = pageMap.isReadable(address: address, length: length)
        guard result else {
            throw .notReadable(address)
        }
    }

    public func isWritable(address: UInt32, length: Int) -> Bool {
        if length == 0 { return true }
        return pageMap.isWritable(address: address, length: length).result
    }

    public func isWritable(pageStart: UInt32, pages: Int) -> Bool {
        pageMap.isWritable(pageStart: pageStart, pages: pages).result
    }

    public func ensureWritable(address: UInt32, length: Int) throws(MemoryError) {
        let (result, address) = pageMap.isWritable(address: address, length: length)
        guard result else {
            throw .notWritable(address)
        }
    }
}

public class ReadonlyMemory {
    private let memory: Memory

    public init(_ memory: Memory) {
        self.memory = memory
    }

    public func read(address: UInt32) throws -> UInt8 {
        try memory.read(address: address)
    }

    public func read(address: UInt32, length: Int) throws -> Data {
        try memory.read(address: address, length: length)
    }
}
