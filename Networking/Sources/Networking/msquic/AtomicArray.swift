import Foundation

struct AtomicArray<T>: RangeReplaceableCollection {
    typealias Element = T
    typealias Index = Int
    typealias SubSequence = AtomicArray<T>
    typealias Indices = Range<Int>

    fileprivate var array: [T]
    private let queue = DispatchQueue(label: "com.atomicArray.queue", attributes: .concurrent)

    var startIndex: Int { array.startIndex }
    var endIndex: Int { array.endIndex }
    var indices: Range<Int> { array.indices }

    init() {
        array = []
    }

    init<S>(_ elements: S) where S: Sequence, AtomicArray.Element == S.Element {
        array = Array(elements)
    }

    init(repeating repeatedValue: AtomicArray.Element, count: Int) {
        array = Array(repeating: repeatedValue, count: count)
    }

    func index(after i: Int) -> Int {
        array.index(after: i)
    }

    fileprivate func _read<R>(_ block: () throws -> R) rethrows -> R {
        try queue.sync {
            try block()
        }
    }

    fileprivate func _write<R>(_ block: () throws -> R) rethrows -> R {
        try queue.sync(flags: .barrier) {
            try block()
        }
    }

    public mutating func append(_ newElement: AtomicArray.Element) {
        _write {
            array.append(newElement)
        }
    }

    public mutating func append<S>(contentsOf newElements: S) where S: Sequence, AtomicArray.Element == S.Element {
        _write {
            array.append(contentsOf: newElements)
        }
    }

    func filter(_ isIncluded: (AtomicArray.Element) throws -> Bool) rethrows -> AtomicArray {
        try _read {
            let subArray = try array.filter(isIncluded)
            return AtomicArray(subArray)
        }
    }

    public mutating func insert(_ newElement: AtomicArray.Element, at i: AtomicArray.Index) {
        _write {
            array.insert(newElement, at: i)
        }
    }

    mutating func insert<S>(contentsOf newElements: S, at i: AtomicArray.Index) where S: Collection, AtomicArray.Element == S.Element {
        _write {
            array.insert(contentsOf: newElements, at: i)
        }
    }

    mutating func popLast() -> AtomicArray.Element? {
        _write {
            array.popLast()
        }
    }

    @discardableResult mutating func remove(at i: AtomicArray.Index) -> AtomicArray.Element {
        _write {
            array.remove(at: i)
        }
    }

    mutating func removeAll() {
        _write {
            array.removeAll()
        }
    }

    mutating func removeAll(keepingCapacity keepCapacity: Bool) {
        _write {
            array.removeAll(keepingCapacity: keepCapacity)
        }
    }

    mutating func removeAll(where shouldBeRemoved: (AtomicArray.Element) throws -> Bool) rethrows {
        try _write {
            try array.removeAll(where: shouldBeRemoved)
        }
    }

    @discardableResult mutating func removeFirst() -> AtomicArray.Element {
        _write {
            array.removeFirst()
        }
    }

    mutating func removeFirst(_ k: Int) {
        _write {
            array.removeFirst(k)
        }
    }

    @discardableResult mutating func removeLast() -> AtomicArray.Element {
        _write {
            array.removeLast()
        }
    }

    mutating func removeLast(_ k: Int) {
        _write {
            array.removeLast(k)
        }
    }

    @inlinable public func forEach(_ body: (Element) throws -> Void) rethrows {
        try _read {
            try array.forEach(body)
        }
    }

    mutating func removeFirstIfExist(where shouldBeRemoved: (AtomicArray.Element) throws -> Bool) {
        _write {
            guard let index = try? array.firstIndex(where: shouldBeRemoved) else { return }
            array.remove(at: index)
        }
    }

    mutating func removeSubrange(_ bounds: Range<Int>) {
        _write {
            array.removeSubrange(bounds)
        }
    }

    mutating func replaceSubrange<C, R>(_ subrange: R, with newElements: C) where C: Collection, R: RangeExpression, T == C.Element,
        AtomicArray<Element>.Index == R.Bound
    {
        _write {
            array.replaceSubrange(subrange, with: newElements)
        }
    }

    mutating func reserveCapacity(_ n: Int) {
        _write {
            array.reserveCapacity(n)
        }
    }

    public var count: Int {
        _read {
            array.count
        }
    }

    public var isEmpty: Bool {
        _read {
            array.isEmpty
        }
    }

    public var first: AtomicArray.Element? {
        _read {
            array.first
        }
    }

    // Single action

    func get() -> [T] {
        _read {
            array
        }
    }

    mutating func set(array: [T]) {
        _write {
            self.array = array
        }
    }

    // Multi actions

    mutating func get(closure: ([T]) -> Void) {
        _read {
            closure(array)
        }
    }

    mutating func set(closure: ([T]) -> ([T])) {
        _write {
            array = closure(array)
        }
    }

    subscript(bounds: Range<AtomicArray.Index>) -> AtomicArray.SubSequence {
        _read {
            AtomicArray(array[bounds])
        }
    }

    subscript(bounds: AtomicArray.Index) -> AtomicArray.Element {
        get {
            _read {
                array[bounds]
            }
        }
        set(value) {
            _write {
                array[bounds] = value
            }
        }
    }

    static func + <Other>(lhs: Other, rhs: AtomicArray) -> AtomicArray where Other: Sequence, AtomicArray.Element == Other.Element {
        AtomicArray(lhs + rhs.get())
    }

    static func + <Other>(lhs: AtomicArray, rhs: Other) -> AtomicArray where Other: Sequence, AtomicArray.Element == Other.Element {
        AtomicArray(lhs.get() + rhs)
    }

    static func + <Other>(lhs: AtomicArray, rhs: Other) -> AtomicArray where Other: RangeReplaceableCollection,
        AtomicArray.Element == Other.Element
    {
        AtomicArray(lhs.get() + rhs)
    }

    static func + (lhs: AtomicArray<Element>, rhs: AtomicArray<Element>) -> AtomicArray {
        AtomicArray(lhs.get() + rhs.get())
    }

    static func += <Other>(lhs: inout AtomicArray, rhs: Other) where Other: Sequence, AtomicArray.Element == Other.Element {
        lhs._write {
            lhs.array += rhs
        }
    }
}

extension AtomicArray: CustomStringConvertible {
    var description: String {
        _read {
            "\(array)"
        }
    }
}

extension AtomicArray where Element: Equatable {
    func split(separator: Element, maxSplits: Int, omittingEmptySubsequences: Bool) -> [ArraySlice<Element>] {
        _read {
            array.split(separator: separator, maxSplits: maxSplits, omittingEmptySubsequences: omittingEmptySubsequences)
        }
    }

    func firstIndex(of element: Element) -> Int? {
        _read {
            array.firstIndex(of: element)
        }
    }

    func lastIndex(of element: Element) -> Int? {
        _read {
            array.lastIndex(of: element)
        }
    }

    func starts<PossiblePrefix>(with possiblePrefix: PossiblePrefix) -> Bool where PossiblePrefix: Sequence,
        Element == PossiblePrefix.Element
    {
        _read {
            array.starts(with: possiblePrefix)
        }
    }

    func elementsEqual<OtherSequence>(_ other: OtherSequence) -> Bool where OtherSequence: Sequence, Element == OtherSequence.Element {
        _read {
            array.elementsEqual(other)
        }
    }

    func contains(_ element: Element) -> Bool {
        _read {
            array.contains(element)
        }
    }

    static func != (lhs: AtomicArray<Element>, rhs: AtomicArray<Element>) -> Bool {
        lhs._read {
            rhs._read {
                lhs.array != rhs.array
            }
        }
    }

    static func == (lhs: AtomicArray<Element>, rhs: AtomicArray<Element>) -> Bool {
        lhs._read {
            rhs._read {
                lhs.array == rhs.array
            }
        }
    }
}
