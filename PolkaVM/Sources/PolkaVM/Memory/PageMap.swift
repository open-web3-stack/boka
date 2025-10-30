import Foundation

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
    private var readableBits: [UInt64] = []
    private var writableBits: [UInt64] = []
    private var maxPageIndex: UInt32 = 0

    private let config: PvmConfig

    private let pageSize: UInt32
    private let pageSizeShift: UInt32

    public init(pageMap: [(address: UInt32, length: UInt32, access: PageAccess)], config: PvmConfig) {
        self.config = config
        pageSize = UInt32(config.pvmMemoryPageSize)
        pageSizeShift = UInt32(pageSize.trailingZeroBitCount)

        for entry in pageMap {
            let startIndex = entry.address >> pageSizeShift
            let pages = numberOfPagesToAccess(address: entry.address, length: Int(entry.length))
            let endIndex = startIndex + pages
            maxPageIndex = max(maxPageIndex, endIndex)
        }

        let bitsNeeded = (maxPageIndex + 63) / 64
        readableBits = Array(repeating: 0, count: Int(bitsNeeded))
        writableBits = Array(repeating: 0, count: Int(bitsNeeded))

        for entry in pageMap {
            let startIndex = entry.address >> pageSizeShift
            let pages = numberOfPagesToAccess(address: entry.address, length: Int(entry.length))
            setPageAccessRange(startIndex: startIndex, pages: pages, access: entry.access)
        }
    }

    @inline(__always)
    private func checkPagesInRange(
        pageStart: UInt32,
        pages: Int,
        bits: [UInt64],
        singlePageChecker: (UInt32) -> Bool
    ) -> (result: Bool, page: UInt32) {
        if pages == 0 {
            return (true, pageStart)
        }

        let pageEnd = pageStart + UInt32(pages)
        var currentPage = pageStart

        while currentPage < pageEnd {
            let wordIndex = Int(currentPage / 64)
            let bitIndex = Int(currentPage % 64)
            let bitsInThisWord = min(64 - bitIndex, Int(pageEnd - currentPage))

            let mask: UInt64 = if bitsInThisWord == 64 {
                UInt64.max
            } else {
                (UInt64(1) << bitsInThisWord) - 1
            }
            let shiftedMask = mask << bitIndex

            let wordValue = wordIndex < bits.count ? bits[wordIndex] : 0
            if (wordValue & shiftedMask) != shiftedMask {
                for bit in 0 ..< bitsInThisWord {
                    let pageIndex = currentPage + UInt32(bit)
                    if !singlePageChecker(pageIndex) {
                        return (false, pageIndex)
                    }
                }
            }

            currentPage += UInt32(bitsInThisWord)
        }

        return (true, pageStart)
    }

    @inline(__always)
    private func modifyBitsInRange(
        startIndex: UInt32,
        pages: UInt32,
        modifier: (Int, UInt64) -> Void
    ) {
        let endIndex = startIndex + pages
        var currentPage = startIndex

        while currentPage < endIndex {
            let wordIndex = Int(currentPage / 64)
            let bitIndex = Int(currentPage % 64)
            let bitsInThisWord = min(64 - bitIndex, Int(endIndex - currentPage))

            let mask: UInt64 = if bitsInThisWord == 64 {
                UInt64.max
            } else {
                (UInt64(1) << bitsInThisWord) - 1
            }
            let shiftedMask = mask << bitIndex

            modifier(wordIndex, shiftedMask)
            currentPage += UInt32(bitsInThisWord)
        }
    }

    private func ensureCapacity(pageIndex: UInt32) {
        if pageIndex >= maxPageIndex {
            maxPageIndex = pageIndex + 1
            let bitsNeeded = (maxPageIndex + 63) / 64
            let currentSize = readableBits.count

            if Int(bitsNeeded) > currentSize {
                readableBits.append(contentsOf: Array(repeating: 0, count: Int(bitsNeeded) - currentSize))
                writableBits.append(contentsOf: Array(repeating: 0, count: Int(bitsNeeded) - currentSize))
            }
        }
    }

    private func setPageAccessRange(startIndex: UInt32, pages: UInt32, access: PageAccess) {
        if pages == 0 { return }

        let endIndex = startIndex + pages - 1
        if endIndex >= maxPageIndex {
            ensureCapacity(pageIndex: endIndex)
        }

        modifyBitsInRange(startIndex: startIndex, pages: pages) { wordIndex, shiftedMask in
            switch access {
            case .readOnly:
                readableBits[wordIndex] |= shiftedMask
                writableBits[wordIndex] &= ~shiftedMask
            case .readWrite:
                readableBits[wordIndex] |= shiftedMask
                writableBits[wordIndex] |= shiftedMask
            }
        }
    }

    private func setPageAccess(pageIndex: UInt32, access: PageAccess) {
        ensureCapacity(pageIndex: pageIndex)

        let wordIndex = Int(pageIndex / 64)
        let bitIndex = pageIndex % 64
        let mask = UInt64(1) << bitIndex

        switch access {
        case .readOnly:
            readableBits[wordIndex] |= mask
            writableBits[wordIndex] &= ~mask
        case .readWrite:
            readableBits[wordIndex] |= mask
            writableBits[wordIndex] |= mask
        }
    }

    private func isPageReadable(pageIndex: UInt32) -> Bool {
        guard pageIndex < maxPageIndex else { return false }
        let wordIndex = Int(pageIndex / 64)
        let bitIndex = pageIndex % 64
        return (readableBits[wordIndex] & (UInt64(1) << bitIndex)) != 0
    }

    private func isPageWritable(pageIndex: UInt32) -> Bool {
        guard pageIndex < maxPageIndex else { return false }
        let wordIndex = Int(pageIndex / 64)
        let bitIndex = pageIndex % 64
        return (writableBits[wordIndex] & (UInt64(1) << bitIndex)) != 0
    }

    private func clearPageAccess(pageIndex: UInt32) {
        guard pageIndex < maxPageIndex else { return }
        let wordIndex = Int(pageIndex / 64)
        let bitIndex = pageIndex % 64
        let mask = UInt64(1) << bitIndex
        readableBits[wordIndex] &= ~mask
        writableBits[wordIndex] &= ~mask
    }

    private func numberOfPagesToAccess(address: UInt32, length: Int) -> UInt32 {
        if length == 0 {
            return 0
        }
        let addressPageIndex = address >> pageSizeShift
        let (endAddress, overflow) = address.addingReportingOverflow(UInt32(length) - 1)
        let endPageIndex = (overflow ? UInt32.max : endAddress) >> pageSizeShift
        return endPageIndex - addressPageIndex + 1
    }

    public func isReadable(pageStart: UInt32, pages: Int) -> (result: Bool, page: UInt32) {
        checkPagesInRange(
            pageStart: pageStart,
            pages: pages,
            bits: readableBits,
            singlePageChecker: isPageReadable
        )
    }

    public func isReadable(address: UInt32, length: Int) -> (result: Bool, address: UInt32) {
        let startPageIndex = address >> pageSizeShift
        let pages = numberOfPagesToAccess(address: address, length: length)
        let (result, page) = isReadable(pageStart: startPageIndex, pages: Int(pages))
        return (result, page << pageSizeShift)
    }

    public func isWritable(pageStart: UInt32, pages: Int) -> (result: Bool, page: UInt32) {
        checkPagesInRange(
            pageStart: pageStart,
            pages: pages,
            bits: writableBits,
            singlePageChecker: isPageWritable
        )
    }

    public func isWritable(address: UInt32, length: Int) -> (result: Bool, address: UInt32) {
        let startPageIndex = address >> pageSizeShift
        let pages = numberOfPagesToAccess(address: address, length: length)
        let (result, page) = isWritable(pageStart: startPageIndex, pages: Int(pages))
        return (result, page << pageSizeShift)
    }

    public func update(address: UInt32, length: Int, access: PageAccess) {
        let startPageIndex = address >> pageSizeShift
        let pages = numberOfPagesToAccess(address: address, length: length)
        setPageAccessRange(startIndex: startPageIndex, pages: pages, access: access)
    }

    public func update(pageIndex: UInt32, pages: Int, access: PageAccess) {
        if pages == 0 {
            setPageAccess(pageIndex: pageIndex, access: access)
            return
        }
        setPageAccessRange(startIndex: pageIndex, pages: UInt32(pages), access: access)
    }

    public func removeAccess(address: UInt32, length: Int) {
        let startPageIndex = address >> pageSizeShift
        let pages = numberOfPagesToAccess(address: address, length: length)

        modifyBitsInRange(startIndex: startPageIndex, pages: pages) { wordIndex, shiftedMask in
            if wordIndex < readableBits.count {
                readableBits[wordIndex] &= ~shiftedMask
                writableBits[wordIndex] &= ~shiftedMask
            }
        }
    }

    public func removeAccess(pageIndex: UInt32, pages: Int) {
        if pages == 0 {
            clearPageAccess(pageIndex: pageIndex)
            return
        }

        modifyBitsInRange(startIndex: pageIndex, pages: UInt32(pages)) { wordIndex, shiftedMask in
            if wordIndex < readableBits.count {
                readableBits[wordIndex] &= ~shiftedMask
                writableBits[wordIndex] &= ~shiftedMask
            }
        }
    }

    public func findGapOrThrow(pages: Int) throws(MemoryError) -> UInt32 {
        var currentGapStart: UInt32?
        var gapSize: UInt32 = 0

        let searchLimit = max(maxPageIndex, UInt32(pages) + maxPageIndex + 64)
        let totalWords = (searchLimit + 63) / 64

        for wordIdx in 0 ..< Int(totalWords) {
            let readableWord = wordIdx < readableBits.count ? readableBits[wordIdx] : 0
            let writableWord = wordIdx < writableBits.count ? writableBits[wordIdx] : 0
            let occupiedWord = readableWord | writableWord

            if occupiedWord == 0 {
                let pagesInWord = min(64, Int(searchLimit) - wordIdx * 64)
                if currentGapStart == nil {
                    currentGapStart = UInt32(wordIdx * 64)
                    gapSize = UInt32(pagesInWord)
                } else {
                    gapSize += UInt32(pagesInWord)
                }

                if gapSize >= pages {
                    return currentGapStart!
                }
                continue
            }

            let pagesInWord = min(64, Int(searchLimit) - wordIdx * 64)
            for bitIdx in 0 ..< pagesInWord {
                let pageIndex = UInt32(wordIdx * 64 + bitIdx)
                let hasAccess = (occupiedWord & (UInt64(1) << bitIdx)) != 0

                if !hasAccess {
                    if currentGapStart == nil {
                        currentGapStart = pageIndex
                        gapSize = 1
                    } else {
                        gapSize += 1
                    }

                    if gapSize >= pages {
                        return currentGapStart!
                    }
                } else {
                    currentGapStart = nil
                    gapSize = 0
                }
            }
        }

        throw .outOfMemory(0)
    }
}
