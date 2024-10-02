struct RandomnessSequence: Sequence {
    let data: Data32
    func makeIterator() -> RandomnessIterator {
        RandomnessIterator(data: data, index: 0, source: data)
    }
}

struct RandomnessIterator: IteratorProtocol {
    let data: Data32
    var index: Int
    var source: Data32

    mutating func next() -> UInt32? {
        let idx = index % 8
        if idx == 0 {
            // update source
            source = Blake2b256.hash(data, UInt32(index / 8).encode())
        }
        index += 1
        return source.data[4 * idx ..< 4 * (idx + 1)].decode(UInt32.self)
    }
}

extension Array {
    /// Insert the elements of the given sequence to the array, in sorted order.
    ///
    /// - Parameter elements: The elements to insert.
    /// - Parameter comparer: The comparison function to use to determine the order of the elements.
    /// - Complexity: O(*n*), where *n* is the number of elements in the sequence.
    ///
    /// - Note: The elements of the sequence must be comparable.
    /// - Invariant: The array and elements must be sorted according to the given comparison function.
    public mutating func insertSorted(_ elements: any Sequence<Element>, by comparer: (Element, Element) throws -> Bool) rethrows {
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

    // requires randomness have at least count elements
    private mutating func shuffle(randomness: some Sequence<UInt32>) {
        var iter = randomness.makeIterator()
        // TODO: confirm this is matching to the defs in GP
        for i in stride(from: count - 1, through: 1, by: -1) {
            let j = Int((iter.next() ?? 0) % UInt32(i + 1))
            guard i != j else {
                continue
            }
            swapAt(i, j)
        }
    }

    public mutating func shuffle(randomness: Data32) {
        shuffle(randomness: RandomnessSequence(data: randomness))
    }
}

extension Array where Element: Comparable {
    /// Insert the elements of the given sequence to the array, in sorted order.
    ///
    /// - Parameter elements: The elements to insert.
    /// - Parameter comparer: The comparison function to use to determine the order of the elements.
    /// - Complexity: O(*n*), where *n* is the number of elements in the sequence.
    ///
    /// - Note: The elements of the sequence must be comparable.
    /// - Invariant: The array and elements must be sorted according to the given comparison function.
    public mutating func insertSorted(_ elements: any Sequence<Element>) {
        insertSorted(elements) { $0 < $1 }
    }
}
