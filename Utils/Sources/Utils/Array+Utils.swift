extension Array where Element: Comparable {
    public func isSorted(by comparer: (Element, Element) -> Bool = { $0 < $1 }) -> Bool {
        var previous: Element?
        for element in self {
            if let previous {
                if !comparer(previous, element), previous != element {
                    return false
                }
            }
            previous = element
        }
        return true
    }

    /// Insert the elements of the given sequence to the array, in sorted order.
    ///
    /// - Parameter elements: The elements to insert.
    /// - Parameter comparer: The comparison function to use to determine the order of the elements.
    /// - Complexity: O(*n*), where *n* is the number of elements in the sequence.
    ///
    /// - Note: The elements of the sequence must be comparable.
    /// - Invariant: The array and elements must be sorted according to the given comparison function.
    public mutating func insertSorted(_ elements: any Sequence<Element>, by comparer: (Element, Element) throws -> Bool = { $0 < $1 }) rethrows {
        reserveCapacity(count + elements.underestimatedCount)
        var startIdx = 0
        for element in elements {
            if let idx = try self[startIdx...].firstIndex(where: { try !comparer($0, element) }) {
                insert(element, at: idx)
                startIdx = idx + 1
            } else {
                append(element)
                startIdx = endIndex
            }
        }
    }
}
