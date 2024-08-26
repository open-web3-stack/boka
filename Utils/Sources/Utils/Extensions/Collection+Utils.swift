public enum IndexOutOfBounds: Error {
    case indexOutOfBounds
}

extension Collection {
    public subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }

    public subscript(safe range: Range<Index>) -> SubSequence? {
        guard indices.contains(range.lowerBound), indices.contains(range.upperBound) || range.upperBound == endIndex else {
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

extension Collection where Index: BinaryInteger {
    public func relative(offset: Int) -> Index {
        index(startIndex, offsetBy: offset)
    }

    public func relative(range: Range<Int>) -> Range<Index> {
        index(startIndex, offsetBy: range.lowerBound) ..< index(startIndex, offsetBy: range.upperBound)
    }

    public func relative(range: PartialRangeFrom<Int>) -> Range<Index> {
        index(startIndex, offsetBy: range.lowerBound) ..< endIndex
    }

    public func relative(range: PartialRangeUpTo<Int>) -> Range<Index> {
        startIndex ..< index(startIndex, offsetBy: range.upperBound)
    }

    public func relative(range: PartialRangeThrough<Int>) -> Range<Index> {
        startIndex ..< index(startIndex, offsetBy: range.upperBound + 1)
    }

    public subscript(relative index: Int) -> Element {
        self[relative(offset: index)]
    }

    public subscript(relative range: Range<Int>) -> SubSequence {
        self[relative(range: range)]
    }

    public subscript(relative range: PartialRangeFrom<Int>) -> SubSequence {
        self[relative(range: range)]
    }

    public subscript(relative range: PartialRangeUpTo<Int>) -> SubSequence {
        self[relative(range: range)]
    }

    public subscript(relative range: PartialRangeThrough<Int>) -> SubSequence {
        self[relative(range: range)]
    }

    public subscript(safeRelative index: Int) -> Element? {
        self[safe: relative(offset: index)]
    }

    public subscript(safeRelative range: Range<Int>) -> SubSequence? {
        self[safe: relative(range: range)]
    }

    public func at(relative index: Int) throws(IndexOutOfBounds) -> Element {
        let offset = relative(offset: index)
        return try at(offset)
    }

    public func at(relative range: Range<Int>) throws(IndexOutOfBounds) -> SubSequence {
        let offset = relative(range: range)
        return try at(offset)
    }

    public func at(relative range: PartialRangeFrom<Int>) throws(IndexOutOfBounds) -> SubSequence {
        let offset = relative(range: range)
        return try at(offset)
    }

    public func at(relative range: PartialRangeUpTo<Int>) throws(IndexOutOfBounds) -> SubSequence {
        let offset = relative(range: range)
        return try at(offset)
    }

    public func at(relative range: PartialRangeThrough<Int>) throws(IndexOutOfBounds) -> SubSequence {
        let offset = relative(range: range)
        return try at(offset)
    }
}
