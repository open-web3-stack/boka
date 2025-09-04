import Foundation
import LRUCache

public enum PageAccess {
    case readOnly
    case readWrite

    public func isReadable() -> Bool {
        switch self {
        case .readOnly:
            true
        case .readWrite:
            true
        }
    }

    public func isWritable() -> Bool {
        switch self {
        case .readWrite:
            true
        default:
            false
        }
    }
}

public class PageMap {
    private var pageTable: [UInt32: PageAccess] = [:]
    private let config: PvmConfig

    // cache page size and its bit shift for fast div/mul
    private let pageSize: UInt32
    private let pageSizeShift: UInt32

    // cache for multi page queries
    // if the result is false, the page is the fault page, otherwise the page is the first page
    private let isReadableCache: LRUCache<Range<UInt32>, (result: Bool, page: UInt32)>
    private let isWritableCache: LRUCache<Range<UInt32>, (result: Bool, page: UInt32)>

    public init(pageMap: [(address: UInt32, length: UInt32, access: PageAccess)], config: PvmConfig) {
        self.config = config
        pageSize = UInt32(config.pvmMemoryPageSize)
        pageSizeShift = UInt32(pageSize.trailingZeroBitCount)
        isReadableCache = .init(totalCostLimit: 0, countLimit: 1024)
        isWritableCache = .init(totalCostLimit: 0, countLimit: 1024)

        for entry in pageMap {
            let startIndex = entry.address >> pageSizeShift
            let pages = numberOfPagesToAccess(address: entry.address, length: Int(entry.length))

            for i in startIndex ..< startIndex + pages {
                pageTable[i] = entry.access
            }
        }
    }

    private func numberOfPagesToAccess(address: UInt32, length: Int) -> UInt32 {
        if length == 0 {
            return 0
        }
        let addressPageIndex = address >> pageSizeShift
        let endPageIndex = (address + UInt32(length) - 1) >> pageSizeShift
        return endPageIndex - addressPageIndex + 1
    }

    /// If the pages are readable, return (true, pageStart)
    ///
    /// If the pages are not readable, return (false, faultPageIndex).
    public func isReadable(pageStart: UInt32, pages: Int) -> (result: Bool, page: UInt32) {
        if pages == 0 {
            return (pageTable[pageStart]?.isReadable() ?? false, pageStart)
        }
        let pageRange = pageStart ..< pageStart + UInt32(pages)
        let cacheValue = isReadableCache.value(forKey: pageRange)
        if let cacheValue {
            return cacheValue
        }

        var result = true
        var page = pageStart
        for i in pageRange {
            let curResult = pageTable[i]?.isReadable() ?? false
            if !curResult {
                result = false
                page = i
                break
            }
        }
        isReadableCache.setValue((result, page), forKey: pageRange)
        return (result, page)
    }

    /// If the pages are writable, return (true, address)
    ///
    /// If the pages are not writable, return (false, faultPage start address).
    public func isReadable(address: UInt32, length: Int) -> (result: Bool, address: UInt32) {
        let startPageIndex = address >> pageSizeShift
        let pages = numberOfPagesToAccess(address: address, length: length)
        let (result, page) = isReadable(pageStart: startPageIndex, pages: Int(pages))
        return (result, page << pageSizeShift)
    }

    /// If the pages are writable, return (true, pageStart)
    ///
    /// If the pages are not writable, return (false, faultPageIndex).
    public func isWritable(pageStart: UInt32, pages: Int) -> (result: Bool, page: UInt32) {
        if pages == 0 {
            return (pageTable[pageStart]?.isWritable() ?? false, pageStart)
        }
        let pageRange = pageStart ..< pageStart + UInt32(pages)
        let cacheValue = isWritableCache.value(forKey: pageRange)
        if let cacheValue {
            return cacheValue
        }

        var result = true
        var page = pageStart
        for i in pageRange {
            let curResult = pageTable[i]?.isWritable() ?? false
            if !curResult {
                result = false
                page = i
                break
            }
        }
        isWritableCache.setValue((result, page), forKey: pageRange)
        return (result, page)
    }

    /// If the pages are writable, return (true, address)
    ///
    /// If the pages are not writable, return (false, faultPage start address).
    public func isWritable(address: UInt32, length: Int) -> (result: Bool, address: UInt32) {
        let startPageIndex = address >> pageSizeShift
        let pages = numberOfPagesToAccess(address: address, length: length)
        let (result, page) = isWritable(pageStart: startPageIndex, pages: Int(pages))
        return (result, page << pageSizeShift)
    }

    public func update(address: UInt32, length: Int, access: PageAccess) {
        let startPageIndex = address >> pageSizeShift
        let pages = numberOfPagesToAccess(address: address, length: length)
        let pageRange = startPageIndex ..< startPageIndex + pages

        for i in pageRange {
            pageTable[i] = access
        }

        isReadableCache.removeAllValues()
        isWritableCache.removeAllValues()
    }

    public func update(pageIndex: UInt32, pages: Int, access: PageAccess) {
        if pages == 0 {
            pageTable[pageIndex] = access
            return
        }
        for i in pageIndex ..< pageIndex + UInt32(pages) {
            pageTable[i] = access
        }
        isReadableCache.removeAllValues()
        isWritableCache.removeAllValues()
    }

    public func removeAccess(address: UInt32, length: Int) {
        let startPageIndex = address >> pageSizeShift
        let pages = numberOfPagesToAccess(address: address, length: length)
        let pageRange = startPageIndex ..< startPageIndex + UInt32(pages)

        for i in pageRange {
            pageTable.removeValue(forKey: i)
        }
        isReadableCache.removeAllValues()
        isWritableCache.removeAllValues()
    }

    public func removeAccess(pageIndex: UInt32, pages: Int) {
        if pages == 0 {
            pageTable.removeValue(forKey: pageIndex)
            return
        }
        for i in pageIndex ..< pageIndex + UInt32(pages) {
            pageTable.removeValue(forKey: i)
        }
        isReadableCache.removeAllValues()
        isWritableCache.removeAllValues()
    }

    // find an inaccessible gap in page map if any
    // return the first page index of the gap
    public func findGapOrThrow(pages: Int) throws(MemoryError) -> UInt32 {
        let sortedKeys = pageTable.keys.sorted()

        for i in 0 ..< sortedKeys.count {
            let current = sortedKeys[i]
            let next = sortedKeys[i + 1]

            if next - current >= pages {
                return current + 1
            }
        }

        throw .outOfMemory(0)
    }
}
