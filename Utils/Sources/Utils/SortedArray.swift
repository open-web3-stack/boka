public enum SortedArrayError: Swift.Error {
    case invalidData
}

public struct SortedArray<T: Comparable> {
    public private(set) var array: [T]

    public init(unsorted: [T]) {
        array = unsorted
        array.sort()
    }

    public init(sorted: [T]) throws(SortedArrayError) {
        array = sorted

        guard array.isSorted() else {
            throw SortedArrayError.invalidData
        }
    }

    public init(sortedUnchecked: [T] = []) {
        array = sortedUnchecked
    }

    /// Use binary search to find the index of the first element equal to or greater than the given element.
    public func insertIndex(_ element: T, begin: Int = 0, end: Int? = nil) -> Int {
        var low = begin
        var high = end ?? array.count
        while low < high {
            let mid = (low + high) / 2
            if array[mid] < element {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low
    }

    public mutating func insert(_ element: T) {
        array.insert(element, at: insertIndex(element))
    }

    public mutating func append(contentsOf newElements: some Collection<T>) {
        for element in newElements {
            insert(element)
        }
    }

    public mutating func append(contentsOf other: SortedArray<T>) {
        var begin = 0
        for element in other.array {
            let idx = insertIndex(element, begin: begin)
            array.insert(element, at: idx)
            begin = idx + 1
        }
    }

    public mutating func remove(at index: Int) {
        array.remove(at: index)
    }

    public mutating func removeAll() {
        array.removeAll()
    }

    public mutating func remove(where predicate: (T) throws -> Bool) rethrows {
        try array.removeAll(where: predicate)
    }

    public var count: Int {
        array.count
    }
}

extension SortedArray: Encodable where T: Encodable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(array)
    }
}

extension SortedArray: Decodable where T: Decodable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let array = try container.decode([T].self)
        try self.init(sorted: array)
    }
}

extension SortedArray: Sendable where T: Sendable {}
