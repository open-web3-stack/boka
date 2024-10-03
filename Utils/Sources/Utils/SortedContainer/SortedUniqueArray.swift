// TODO: add tests
public struct SortedUniqueArray<T: Comparable>: SortedContainer {
    public private(set) var array: [T]

    public init(_ unchecked: [T]) {
        array = unchecked
        array.sort()

        for i in (1 ..< array.count).reversed() where array[i] == array[i - 1] {
            array.remove(at: i)
        }
    }

    public init(sorted: [T]) throws(SortedContainerError) {
        array = sorted

        guard array.isSortedAndUnique() else {
            throw SortedContainerError.invalidData
        }
    }

    public init(sortedUnchecked: [T] = []) {
        array = sortedUnchecked
    }

    public mutating func insert(_ element: T) {
        let index = insertIndex(element)
        if index < array.count, array[index] == element {
            return
        }
        array.insert(element, at: index)
    }

    public mutating func append(contentsOf other: some SortedContainer<T>) {
        var begin = 0
        for element in other.array {
            let idx = insertIndex(element, begin: begin)
            if idx > array.count || array[idx] != element {
                array.insert(element, at: idx)
            }
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

extension SortedUniqueArray: Encodable where T: Encodable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(array)
    }
}

extension SortedUniqueArray: Decodable where T: Decodable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let array = try container.decode([T].self)
        try self.init(sorted: array)
    }
}

extension SortedUniqueArray: Sendable where T: Sendable {}
