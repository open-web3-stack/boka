// TODO: add tests
public struct SortedArray<T: Comparable>: SortedContainer {
    public private(set) var array: [T]

    public init(_ unsorted: [T]) {
        array = unsorted
        array.sort()
    }

    public init(sorted: [T]) throws(SortedContainerError) {
        array = sorted

        guard array.isSorted() else {
            throw SortedContainerError.invalidData
        }
    }

    public init(sortedUnchecked: [T] = []) {
        array = sortedUnchecked
    }

    public mutating func insert(_ element: T) {
        array.insert(element, at: insertIndex(element))
    }

    public mutating func append(contentsOf other: some SortedContainer<T>) {
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
