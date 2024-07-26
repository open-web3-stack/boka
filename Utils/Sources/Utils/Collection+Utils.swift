public enum IndexOutOfBounds: Error {
    case indexOutOfBounds
}

extension Collection {
    public subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }

    public subscript(safe range: Range<Index>) -> SubSequence? {
        guard indices.contains(range.lowerBound), indices.contains(range.upperBound) else {
            return nil
        }
        return self[range]
    }

    public func at(_ index: Index) throws(IndexOutOfBounds) -> Element {
        guard let element = self[safe: index] else {
            throw IndexOutOfBounds.indexOutOfBounds
        }
        return element
    }

    public func at(_ range: Range<Index>) throws(IndexOutOfBounds) -> SubSequence {
        guard let subSequence = self[safe: range] else {
            throw IndexOutOfBounds.indexOutOfBounds
        }
        return subSequence
    }
}
