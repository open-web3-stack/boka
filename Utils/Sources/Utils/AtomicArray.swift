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

    fileprivate func read<R>(_ block: () throws -> R) rethrows -> R {
        try queue.sync {
            try block()
        }
    }

    fileprivate func write<R>(_ block: () throws -> R) rethrows -> R {
        try queue.sync(flags: .barrier) {
            try block()
        }
    }

    public mutating func append(_ newElement: AtomicArray.Element) {
        write {
            array.append(newElement)
        }
    }

    public mutating func append<S>(contentsOf newElements: S) where S: Sequence, AtomicArray.Element == S.Element {
        write {
            array.append(contentsOf: newElements)
        }
    }

    public func filter(_ isIncluded: (AtomicArray.Element) throws -> Bool) rethrows -> AtomicArray {
        try read {
            let subArray = try array.filter(isIncluded)
            return AtomicArray(subArray)
        }
    }

    public mutating func insert(_ newElement: AtomicArray.Element, at i: AtomicArray.Index) {
        write {
            array.insert(newElement, at: i)
        }
    }

    public mutating func insert<S>(contentsOf newElements: S, at i: AtomicArray.Index) where S: Collection,
        AtomicArray.Element == S.Element
    {
        write {
            array.insert(contentsOf: newElements, at: i)
        }
    }

    @discardableResult
    public mutating func popLast() -> AtomicArray.Element? {
        write {
            array.popLast()
        }
    }

    @discardableResult
    public mutating func remove(at i: AtomicArray.Index) -> AtomicArray.Element {
        write {
            array.remove(at: i)
        }
    }

    public mutating func removeAll() {
        write {
            array.removeAll()
        }
    }

    public mutating func removeAll(keepingCapacity keepCapacity: Bool) {
        write {
            array.removeAll(keepingCapacity: keepCapacity)
        }
    }

    public mutating func removeAll(where shouldBeRemoved: (AtomicArray.Element) throws -> Bool) rethrows {
        try write {
            try array.removeAll(where: shouldBeRemoved)
        }
    }

    @discardableResult
    public mutating func removeFirst() -> AtomicArray.Element {
        write {
            array.removeFirst()
        }
    }

    public mutating func removeFirst(_ k: Int) {
        write {
            array.removeFirst(k)
        }
    }

    @discardableResult
    public mutating func removeLast() -> AtomicArray.Element {
        write {
            array.removeLast()
        }
    }

    public mutating func removeLast(_ k: Int) {
        write {
            array.removeLast(k)
        }
    }

    public func forEach(_ body: (Element) throws -> Void) rethrows {
        try read {
            try array.forEach(body)
        }
    }

    public mutating func removeFirstIfExist(where shouldBeRemoved: (AtomicArray.Element) throws -> Bool) {
        write {
            guard let index = try? array.firstIndex(where: shouldBeRemoved) else { return }
            array.remove(at: index)
        }
    }

    public mutating func removeSubrange(_ bounds: Range<Int>) {
        write {
            array.removeSubrange(bounds)
        }
    }

    public mutating func replaceSubrange<C, R>(_ subrange: R, with newElements: C) where C: Collection, R: RangeExpression, T == C.Element,
        AtomicArray<Element>.Index == R.Bound
    {
        write {
            array.replaceSubrange(subrange, with: newElements)
        }
    }

    public mutating func reserveCapacity(_ n: Int) {
        write {
            array.reserveCapacity(n)
        }
    }

    public var count: Int {
        read {
            array.count
        }
    }

    public var isEmpty: Bool {
        read {
            array.isEmpty
        }
    }

    public var first: AtomicArray.Element? {
        read {
            array.first
        }
    }

    public func getArray() -> [T] {
        read {
            array
        }
    }

    public mutating func setArray(_ newArray: [T]) {
        write {
            array = newArray
        }
    }

    public mutating func performRead(_ closure: ([T]) -> Void) {
        read {
            closure(array)
        }
    }

    public mutating func performWrite(_ closure: ([T]) -> ([T])) {
        write {
            array = closure(array)
        }
    }

    public subscript(bounds: Range<AtomicArray.Index>) -> AtomicArray.SubSequence {
        read {
            AtomicArray(array[bounds])
        }
    }

    public subscript(bounds: AtomicArray.Index) -> AtomicArray.Element {
        get {
            read {
                array[bounds]
            }
        }
        set(value) {
            write {
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
        lhs.write {
            lhs.array += rhs
        }
    }
}

extension AtomicArray: CustomStringConvertible {
    public var description: String {
        read {
            "\(array)"
        }
    }
}

extension AtomicArray where Element: Equatable {
    public func split(separator: Element, maxSplits: Int, omittingEmptySubsequences: Bool) -> [ArraySlice<Element>] {
        read {
            array.split(separator: separator, maxSplits: maxSplits, omittingEmptySubsequences: omittingEmptySubsequences)
        }
    }

    public func firstIndex(of element: Element) -> Int? {
        read {
            array.firstIndex(of: element)
        }
    }

    public func lastIndex(of element: Element) -> Int? {
        read {
            array.lastIndex(of: element)
        }
    }

    public func starts<PossiblePrefix>(with possiblePrefix: PossiblePrefix) -> Bool where PossiblePrefix: Sequence,
        Element == PossiblePrefix.Element
    {
        read {
            array.starts(with: possiblePrefix)
        }
    }

    public func elementsEqual<OtherSequence>(_ other: OtherSequence) -> Bool where OtherSequence: Sequence,
        Element == OtherSequence.Element
    {
        read {
            array.elementsEqual(other)
        }
    }

    public func contains(_ element: Element) -> Bool {
        read {
            array.contains(element)
        }
    }

    public static func != (lhs: AtomicArray<Element>, rhs: AtomicArray<Element>) -> Bool {
        lhs.read {
            rhs.read {
                lhs.array != rhs.array
            }
        }
    }

    public static func == (lhs: AtomicArray<Element>, rhs: AtomicArray<Element>) -> Bool {
        lhs.read {
            rhs.read {
                lhs.array == rhs.array
            }
        }
    }
}
