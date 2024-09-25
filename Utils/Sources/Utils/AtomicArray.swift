import Foundation

public struct AtomicArray<T>: RangeReplaceableCollection {
    public typealias Element = T
    public typealias Index = Int
    public typealias SubSequence = AtomicArray<T>
    public typealias Indices = Range<Int>

    fileprivate var array: [T]
    private let queue = DispatchQueue(label: "com.atomicArray.queue", attributes: .concurrent)

    public var startIndex: Int { array.startIndex }
    public var endIndex: Int { array.endIndex }
    public var indices: Range<Int> { array.indices }

    public init() {
        array = []
    }

    public init<S>(_ elements: S) where S: Sequence, AtomicArray.Element == S.Element {
        array = Array(elements)
    }

    public init(repeating repeatedValue: AtomicArray.Element, count: Int) {
        array = Array(repeating: repeatedValue, count: count)
    }

    public func index(after i: Int) -> Int {
        array.index(after: i)
    }

    fileprivate func _read<R>(_ block: () throws -> R) rethrows -> R {
        var result: R!
        try queue.sync {
            result = try block()
        }
        return result
    }

    fileprivate func _write<R>(_ block: () throws -> R) rethrows -> R {
        var result: R!
        try queue.sync(flags: .barrier) {
            result = try block()
        }
        return result
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

    public func filter(_ isIncluded: (AtomicArray.Element) throws -> Bool) rethrows -> AtomicArray {
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

    public mutating func insert<S>(contentsOf newElements: S, at i: AtomicArray.Index) where S: Collection,
        AtomicArray.Element == S.Element
    {
        _write {
            array.insert(contentsOf: newElements, at: i)
        }
    }

    @discardableResult
    public mutating func popLast() -> AtomicArray.Element? {
        _write {
            array.popLast()
        }
    }

    @discardableResult
    public mutating func remove(at i: AtomicArray.Index) -> AtomicArray.Element {
        _write {
            array.remove(at: i)
        }
    }

    public mutating func removeAll() {
        _write {
            array.removeAll()
        }
    }

    public mutating func removeAll(keepingCapacity keepCapacity: Bool) {
        _write {
            array.removeAll(keepingCapacity: keepCapacity)
        }
    }

    public mutating func removeAll(where shouldBeRemoved: (AtomicArray.Element) throws -> Bool) rethrows {
        try _write {
            try array.removeAll(where: shouldBeRemoved)
        }
    }

    @discardableResult
    public mutating func removeFirst() -> AtomicArray.Element {
        _write {
            array.removeFirst()
        }
    }

    public mutating func removeFirst(_ k: Int) {
        _write {
            array.removeFirst(k)
        }
    }

    @discardableResult
    public mutating func removeLast() -> AtomicArray.Element {
        _write {
            array.removeLast()
        }
    }

    public mutating func removeLast(_ k: Int) {
        _write {
            array.removeLast(k)
        }
    }

    @inlinable
    public func forEach(_ body: (Element) throws -> Void) rethrows {
        try _read {
            try array.forEach(body)
        }
    }

    public mutating func removeFirstIfExist(where shouldBeRemoved: (AtomicArray.Element) throws -> Bool) {
        _write {
            guard let index = try? array.firstIndex(where: shouldBeRemoved) else { return }
            array.remove(at: index)
        }
    }

    public mutating func removeSubrange(_ bounds: Range<Int>) {
        _write {
            array.removeSubrange(bounds)
        }
    }

    public mutating func replaceSubrange<C, R>(_ subrange: R, with newElements: C) where C: Collection, R: RangeExpression, T == C.Element,
        AtomicArray<Element>.Index == R.Bound
    {
        _write {
            array.replaceSubrange(subrange, with: newElements)
        }
    }

    public mutating func reserveCapacity(_ n: Int) {
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

    public func getArray() -> [T] {
        _read {
            array
        }
    }

    public mutating func setArray(_ newArray: [T]) {
        _write {
            array = newArray
        }
    }

    public mutating func performRead(_ closure: ([T]) -> Void) {
        _read {
            closure(array)
        }
    }

    public mutating func performWrite(_ closure: ([T]) -> ([T])) {
        _write {
            array = closure(array)
        }
    }

    public subscript(bounds: Range<AtomicArray.Index>) -> AtomicArray.SubSequence {
        _read {
            AtomicArray(array[bounds])
        }
    }

    public subscript(bounds: AtomicArray.Index) -> AtomicArray.Element {
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

    public static func + <Other>(lhs: Other, rhs: AtomicArray) -> AtomicArray where Other: Sequence, AtomicArray.Element == Other.Element {
        AtomicArray(lhs + rhs.getArray())
    }

    public static func + <Other>(lhs: AtomicArray, rhs: Other) -> AtomicArray where Other: Sequence, AtomicArray.Element == Other.Element {
        AtomicArray(lhs.getArray() + rhs)
    }

    public static func + <Other>(lhs: AtomicArray, rhs: Other) -> AtomicArray where Other: RangeReplaceableCollection,
        AtomicArray.Element == Other.Element
    {
        AtomicArray(lhs.getArray() + rhs)
    }

    public static func + (lhs: AtomicArray<Element>, rhs: AtomicArray<Element>) -> AtomicArray {
        AtomicArray(lhs.getArray() + rhs.getArray())
    }

    public static func += <Other>(lhs: inout AtomicArray, rhs: Other) where Other: Sequence, AtomicArray.Element == Other.Element {
        lhs._write {
            lhs.array += rhs
        }
    }
}

extension AtomicArray: CustomStringConvertible {
    public var description: String {
        _read {
            "\(array)"
        }
    }
}

extension AtomicArray where Element: Equatable {
    public func split(separator: Element, maxSplits: Int, omittingEmptySubsequences: Bool) -> [ArraySlice<Element>] {
        _read {
            array.split(separator: separator, maxSplits: maxSplits, omittingEmptySubsequences: omittingEmptySubsequences)
        }
    }

    public func firstIndex(of element: Element) -> Int? {
        _read {
            array.firstIndex(of: element)
        }
    }

    public func lastIndex(of element: Element) -> Int? {
        _read {
            array.lastIndex(of: element)
        }
    }

    public func starts<PossiblePrefix>(with possiblePrefix: PossiblePrefix) -> Bool where PossiblePrefix: Sequence,
        Element == PossiblePrefix.Element
    {
        _read {
            array.starts(with: possiblePrefix)
        }
    }

    public func elementsEqual<OtherSequence>(_ other: OtherSequence) -> Bool where OtherSequence: Sequence,
        Element == OtherSequence.Element
    {
        _read {
            array.elementsEqual(other)
        }
    }

    public func contains(_ element: Element) -> Bool {
        _read {
            array.contains(element)
        }
    }

    public static func != (lhs: AtomicArray<Element>, rhs: AtomicArray<Element>) -> Bool {
        lhs._read {
            rhs._read {
                lhs.array != rhs.array
            }
        }
    }

    public static func == (lhs: AtomicArray<Element>, rhs: AtomicArray<Element>) -> Bool {
        lhs._read {
            rhs._read {
                lhs.array == rhs.array
            }
        }
    }
}
