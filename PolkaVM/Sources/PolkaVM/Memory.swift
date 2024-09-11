import Foundation

public class MemorySection {
    /// lowest address bound
    public let startAddressBound: UInt32
    /// highest address bound
    public let endAddressBound: UInt32
    /// is the section writable
    public let isWritable: Bool
    /// allocated data
    fileprivate var data: Data

    /// current data end address, also the start address of empty space
    public var currentEnd: UInt32 {
        startAddressBound + UInt32(data.count)
    }

    public init(startAddressBound: UInt32, endAddressBound: UInt32, data: Data, isWritable: Bool) {
        self.startAddressBound = startAddressBound
        self.endAddressBound = endAddressBound
        self.data = data
        self.isWritable = isWritable
    }
}

extension MemorySection {
    public func read(address: UInt32, length: Int) throws(Memory.Error) -> Data {
        guard startAddressBound <= address, address + UInt32(length) < endAddressBound else {
            throw Memory.Error.pageFault(address)
        }
        let start = address - startAddressBound
        let end = start + UInt32(length)

        let validCount = min(end, UInt32(data.count))
        let dataToRead = data[start ..< validCount]

        let zeroCount = max(0, Int(end - validCount))
        let zeros = Data(repeating: 0, count: zeroCount)

        return dataToRead + zeros
    }

    public func write(address: UInt32, values: some Sequence<UInt8>) throws(Memory.Error) {
        let valuesData = Data(values)
        guard isWritable else {
            throw Memory.Error.notWritable(address)
        }
        guard startAddressBound <= address, address + UInt32(valuesData.count) < endAddressBound else {
            throw Memory.Error.notWritable(address)
        }

        let start = address - startAddressBound
        let end = start + UInt32(valuesData.count)
        guard end < data.count else {
            throw Memory.Error.notWritable(address)
        }

        data[start ..< end] = valuesData
    }
}

public class Memory {
    public enum Error: Swift.Error {
        case pageFault(UInt32)
        case notWritable(UInt32)
        case outOfMemory(UInt32)

        public var address: UInt32 {
            switch self {
            case let .pageFault(address):
                address
            case let .notWritable(address):
                address
            case let .outOfMemory(address):
                address
            }
        }
    }

    // standard program sections
    private var readOnly: MemorySection?
    private var heap: MemorySection?
    private var stack: MemorySection?
    private var argument: MemorySection?

    // general program sections
    private var memorySections: [MemorySection] = []

    /// General program init with a fixed page map and some initial data
    public init(pageMap: [(address: UInt32, length: UInt32, writable: Bool)], chunks: [(address: UInt32, data: Data)]) {
        readOnly = nil
        heap = nil
        stack = nil
        argument = nil
        memorySections = []

        let sortedPageMap = pageMap.sorted(by: { $0.address < $1.address })
        let sortedChunks = chunks.sorted(by: { $0.address < $1.address })

        for (address, length, writable) in sortedPageMap {
            var data = Data(repeating: 0, count: Int(length))
            if sortedChunks.count != 0 {
                let chunkIndex = Memory.binarySearch(array: sortedChunks.map(\.address), value: address)
                let chunk = sortedChunks[chunkIndex]
                if address <= chunk.address, chunk.address + UInt32(chunk.data.count) <= address + length {
                    data = chunk.data
                }
            }
            let section = MemorySection(
                startAddressBound: address,
                endAddressBound: address + length,
                data: data,
                isWritable: writable
            )
            memorySections.append(section)
        }
    }

    /// Standard Program init
    ///
    /// Init with some read only data, writable data and argument data
    public init(readOnlyData: Data, readWriteData: Data, argumentData: Data, heapEmptyPagesSize: UInt32, stackSize: UInt32) {
        let config = DefaultPvmConfig()
        let P = StandardProgram.alignToPageSize
        let Q = StandardProgram.alignToSegmentSize
        let ZQ = UInt32(config.pvmProgramInitSegmentSize)
        let readOnlyLen = UInt32(readOnlyData.count)
        let readWriteLen = UInt32(readWriteData.count)
        let argumentDataLen = UInt32(argumentData.count)

        let heapStart = 2 * ZQ + Q(readOnlyLen, config)
        let stackPageAlignedSize = P(stackSize, config)

        readOnly = MemorySection(
            startAddressBound: ZQ,
            endAddressBound: ZQ + P(readOnlyLen, config),
            data: readWriteData,
            isWritable: false
        )
        heap = MemorySection(
            startAddressBound: heapStart,
            endAddressBound: heapStart + P(readWriteLen, config) + heapEmptyPagesSize,
            data: readWriteData,
            isWritable: true
        )
        stack = MemorySection(
            startAddressBound: UInt32(config.pvmProgramInitStackBaseAddress) - stackPageAlignedSize,
            endAddressBound: UInt32(config.pvmProgramInitStackBaseAddress),
            // TODO: check is this necessary
            data: Data(repeating: 0, count: Int(stackPageAlignedSize)),
            isWritable: true
        )
        argument = MemorySection(
            startAddressBound: UInt32(config.pvmProgramInitInputStartAddress),
            endAddressBound: UInt32(config.pvmProgramInitInputStartAddress) + P(argumentDataLen, config),
            data: argumentData,
            isWritable: false
        )
    }

    /// if value not in array, return the index of the previous element or 0
    static func binarySearch(array: [UInt32], value: UInt32) -> Int {
        var low = 0
        var high = array.count - 1
        while low <= high {
            let mid = (low + high) / 2
            if array[mid] < value {
                low = mid + 1
            } else if array[mid] > value {
                high = mid - 1
            } else {
                return mid
            }
        }
        return max(0, low - 1)
    }

    private func getSection(forAddress address: UInt32) throws(Error) -> MemorySection {
        if memorySections.count != 0 {
            return memorySections[Memory.binarySearch(array: memorySections.map(\.startAddressBound), value: address)]
        } else if let readOnly {
            if address >= readOnly.startAddressBound, address < readOnly.endAddressBound {
                return readOnly
            }
        } else if let heap {
            if address >= heap.startAddressBound, address < heap.endAddressBound {
                return heap
            }
        } else if let stack {
            if address >= stack.startAddressBound, address < stack.endAddressBound {
                return stack
            }
        } else if let argument {
            if address >= argument.startAddressBound, address < argument.endAddressBound {
                return argument
            }
        }
        throw Error.pageFault(address)
    }

    public func read(address: UInt32) throws(Error) -> UInt8 {
        try getSection(forAddress: address).read(address: address, length: 1).first ?? 0
    }

    public func read(address: UInt32, length: Int) throws -> Data {
        try getSection(forAddress: address).read(address: address, length: length)
    }

    public func write(address: UInt32, value: UInt8) throws(Error) {
        try getSection(forAddress: address).write(address: address, values: Data([value]))
    }

    public func write(address: UInt32, values: some Sequence<UInt8>) throws(Error) {
        try getSection(forAddress: address).write(address: address, values: values)
    }

    public func sbrk(_ increment: UInt32) throws -> UInt32 {
        var section: MemorySection
        if let heap {
            section = heap
        } else if memorySections.count != 0 {
            section = memorySections.last!
        } else {
            throw Error.pageFault(0)
        }

        let oldSectionEnd = section.currentEnd
        guard section.isWritable, oldSectionEnd + increment < section.endAddressBound else {
            throw Error.outOfMemory(oldSectionEnd)
        }
        section.data.append(Data(repeating: 0, count: Int(increment)))
        return oldSectionEnd
    }
}

extension Memory {
    public class Readonly {
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
}
