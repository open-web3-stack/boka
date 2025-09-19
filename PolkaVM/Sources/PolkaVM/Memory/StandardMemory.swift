import Foundation

/// Standard Program Memory
public final class StandardMemory: Memory {
    public let pageMap: PageMap
    private let config: PvmConfig

    private class Zone {
        let startAddress: UInt32
        var endAddress: UInt32
        var data: Data

        init(startAddress: UInt32, endAddress: UInt32, data: Data) {
            self.startAddress = startAddress
            self.endAddress = endAddress
            self.data = data
        }

        func contains(_ address: UInt32) -> Bool {
            address >= startAddress && address < endAddress
        }

        func offset(for address: UInt32) -> Int {
            Int(address - startAddress)
        }
    }

    private var readOnlyZone: Zone
    private var heapZone: Zone
    private var stackZone: Zone
    private var argumentZone: Zone

    public init(readOnlyData: Data, readWriteData: Data, argumentData: Data, heapEmptyPagesSize: UInt32, stackSize: UInt32) throws {
        let config = DefaultPvmConfig()
        let P = StandardProgram.alignToPageSize
        let Z = StandardProgram.alignToZoneSize
        let ZZ = UInt32(config.pvmProgramInitZoneSize)

        let readOnlyLen = UInt32(readOnlyData.count)
        let readWriteLen = UInt32(readWriteData.count)

        let heapStart = 2 * ZZ + Z(readOnlyLen, config)
        let heapDataPagesLen = P(readWriteLen, config)

        let stackPageAlignedSize = P(stackSize, config)
        let stackStartAddr = UInt32(config.pvmProgramInitStackBaseAddress) - stackPageAlignedSize

        let argumentDataLen = UInt32(argumentData.count)

        readOnlyZone = Zone(
            startAddress: ZZ,
            endAddress: ZZ + P(readOnlyLen, config),
            data: readOnlyData
        )

        var heapData = readWriteData
        let totalHeapSize = Int(heapDataPagesLen + heapEmptyPagesSize)
        if heapData.count < totalHeapSize {
            let oldSize = heapData.count
            let additionalSize = totalHeapSize - oldSize

            // Resize and zero-fill efficiently
            heapData.count = totalHeapSize
            heapData.withUnsafeMutableBytes { bytes in
                let zeroPtr = bytes.baseAddress!.advanced(by: oldSize)
                memset(zeroPtr, 0, additionalSize)
            }
        }
        heapZone = Zone(
            startAddress: heapStart,
            endAddress: heapStart + heapDataPagesLen + heapEmptyPagesSize,
            data: heapData
        )

        stackZone = Zone(
            startAddress: stackStartAddr,
            endAddress: UInt32(config.pvmProgramInitStackBaseAddress),
            data: {
                var stackData = Data(count: Int(stackPageAlignedSize))
                _ = stackData.withUnsafeMutableBytes { bytes in
                    memset(bytes.baseAddress!, 0, Int(stackPageAlignedSize))
                }
                return stackData
            }()
        )

        argumentZone = Zone(
            startAddress: UInt32(config.pvmProgramInitInputStartAddress),
            endAddress: UInt32(config.pvmProgramInitInputStartAddress) + P(argumentDataLen, config),
            data: argumentData
        )

        pageMap = PageMap(pageMap: [
            (ZZ, P(readOnlyLen, config), .readOnly),
            (heapStart, heapDataPagesLen + heapEmptyPagesSize, .readWrite),
            (stackStartAddr, stackPageAlignedSize, .readWrite),
            (UInt32(config.pvmProgramInitInputStartAddress), P(argumentDataLen, config), .readOnly),
        ], config: config)

        self.config = config
    }

    private func getZone(for address: UInt32) throws -> Zone {
        if address >= stackZone.startAddress, address < stackZone.endAddress {
            return stackZone
        } else if address >= heapZone.startAddress, address < heapZone.endAddress {
            return heapZone
        } else if address >= readOnlyZone.startAddress, address < readOnlyZone.endAddress {
            return readOnlyZone
        } else if address >= argumentZone.startAddress, address < argumentZone.endAddress {
            return argumentZone
        }
        throw MemoryError.zoneNotFound(address)
    }

    private func pad(zone: Zone, requiredSize: Int) {
        if requiredSize > zone.data.count {
            let oldSize = zone.data.count
            let additionalSize = requiredSize - oldSize

            zone.data.count = requiredSize

            zone.data.withUnsafeMutableBytes { bytes in
                let zeroPtr = bytes.baseAddress!.advanced(by: oldSize)
                memset(zeroPtr, 0, additionalSize)
            }
        }
    }

    public func read(address: UInt32) throws -> UInt8 {
        try ensureReadable(address: address, length: 1)
        let zone = try getZone(for: address)
        let offset = zone.offset(for: address)

        guard offset < zone.data.count else {
            return 0
        }

        return zone.data[relative: offset]
    }

    public func read(address: UInt32, length: Int) throws -> Data {
        guard length > 0 else { return Data() }
        try ensureReadable(address: address, length: length)
        let zone = try getZone(for: address)
        let offset = zone.offset(for: address)

        if offset + length <= zone.data.count {
            return zone.data.subdata(in: zone.data.startIndex + offset ..< (zone.data.startIndex + offset + length))
        }

        var result = Data(count: length)
        let availableBytes = max(0, zone.data.count - offset)
        let bytesToCopy = min(length, availableBytes)

        if bytesToCopy > 0 {
            result.withUnsafeMutableBytes { resultBytes in
                zone.data.withUnsafeBytes { zoneBytes in
                    let sourcePtr = zoneBytes.baseAddress!.advanced(by: offset)
                    memcpy(resultBytes.baseAddress!, sourcePtr, bytesToCopy)
                }
            }
        }

        return result
    }

    public func write(address: UInt32, value: UInt8) throws {
        try ensureWritable(address: address, length: 1)
        let zone = try getZone(for: address)
        let offset = zone.offset(for: address)
        pad(zone: zone, requiredSize: offset + 1)
        zone.data[zone.data.startIndex + offset] = value
    }

    public func write(address: UInt32, values: Data) throws {
        guard !values.isEmpty else { return }
        try ensureWritable(address: address, length: values.count)
        let zone = try getZone(for: address)
        let offset = zone.offset(for: address)

        pad(zone: zone, requiredSize: offset + values.count)
        zone.data.withUnsafeMutableBytes { destBytes in
            values.withUnsafeBytes { sourceBytes in
                let destPtr = destBytes.baseAddress!.advanced(by: offset)
                let sourcePtr = sourceBytes.baseAddress!
                memcpy(destPtr, sourcePtr, values.count)
            }
        }
    }

    public func sbrk(_ size: UInt32) throws(MemoryError) -> UInt32 {
        // NOTE: sbrk will be removed from GP
        // NOTE: this impl aligns with w3f traces test vector README

        let prevHeapEnd = heapZone.endAddress
        if size == 0 {
            return prevHeapEnd
        }

        let nextPageBoundary = StandardProgram.alignToPageSize(size: prevHeapEnd, config: config)
        heapZone.endAddress += size

        if heapZone.endAddress > nextPageBoundary {
            let finalBoundary = heapZone.endAddress
            let start = nextPageBoundary / UInt32(config.pvmMemoryPageSize)
            let end = finalBoundary / UInt32(config.pvmMemoryPageSize)
            let count = Int(end - start + 1)
            pageMap.update(pageIndex: start, pages: count, access: .readWrite)
        }

        return prevHeapEnd
    }
}
