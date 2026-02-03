struct RandomnessSequence: Sequence {
    let data: Data32
    func makeIterator() -> RandomnessIterator {
        RandomnessIterator(data: data, index: 0)
    }
}

struct RandomnessIterator: IteratorProtocol {
    let data: Data32
    var index: Int
    var source: Data32 = .init()

    mutating func next() -> UInt32? {
        let idx = index % 8
        if idx == 0 {
            // update source
            source = Blake2b256.hash(data, UInt32(index / 8).encode())
        }
        index += 1
        let offset = 4 * idx
        return source.data[offset ..< offset + 4].decode(UInt32.self)
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

    /// requires randomness have at least count elements
    private mutating func shuffle(randomness: some Sequence<UInt32>) {
        if count <= 1 {
            return
        }
        var copy = self
        var iter = randomness.makeIterator()
        for i in 0 ..< count {
            let r0 = Int((iter.next() ?? 0) % UInt32(count - i))
            self[i] = copy[r0]
            copy[r0] = copy[count - i - 1]
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

extension Array {
    public func ofType<T>(_: T.Type) -> [T] {
        compactMap { $0 as? T }
    }
}
