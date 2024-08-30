extension Sequence {
    public func isSorted(by comparer: (Element, Element) throws -> Bool) rethrows -> Bool {
        var previous: Element?
        for element in self {
            if let previous {
                guard try !comparer(element, previous) else {
                    return false
                }
            }
            previous = element
        }
        return true
    }

    public func isSortedAndUnique(by comparer: (Element, Element) throws -> Bool) rethrows -> Bool {
        var previous: Element?
        for element in self {
            if let previous {
                guard try comparer(previous, element) else {
                    return false
                }
            }
            previous = element
        }
        return true
    }
}

extension Sequence where Element: Comparable {
    public func isSorted() -> Bool {
        isSorted { $0 < $1 }
    }

    public func isSortedAndUnique() -> Bool {
        isSortedAndUnique { $0 < $1 }
    }
}
