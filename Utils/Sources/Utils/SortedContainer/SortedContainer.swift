public enum SortedContainerError: Swift.Error {
    case invalidData
}

public protocol SortedContainer<T>: Equatable {
    associatedtype T: Comparable

    var array: [T] { get }

    mutating func insert(_ element: T)
}

extension SortedContainer {
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

    public func contains(_ element: T) -> Bool {
        let idx = insertIndex(element)
        return idx < array.count && array[idx] == element
    }

    public mutating func append(contentsOf newElements: some Collection<T>) {
        for element in newElements {
            insert(element)
        }
    }

    public var count: Int {
        array.count
    }
}
