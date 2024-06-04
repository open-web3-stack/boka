// @TODO: add tests

public struct SizeLimitedArray<T> {
    private var array: [T]
    public private(set) var minLength: Int
    public private(set) var maxLength: Int

    public init(deafultValue: T, minLength: Int = 0, maxLength: Int = Int.max) {
        assert(minLength >= 0)
        assert(maxLength >= minLength)
        array = Array(repeating: deafultValue, count: minLength)
        self.minLength = minLength
        self.maxLength = maxLength
    }

    public init(deafultValue: T, length: Int) {
        self.init(deafultValue: deafultValue, minLength: length, maxLength: length)
    }

    public init(array: [T], minLength: Int = 0, maxLength: Int = Int.max) {
        assert(minLength >= 0)
        assert(maxLength >= minLength)
        assert(array.count >= minLength)
        assert(array.count <= maxLength)
        self.array = array
        self.minLength = minLength
        self.maxLength = maxLength
    }

    public init(array: [T], length: Int) {
        self.init(array: array, minLength: length, maxLength: length)
    }
}

extension SizeLimitedArray: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: T...) {
        self.init(array: elements, length: elements.count)
    }
}

extension SizeLimitedArray: Equatable where T: Equatable {
    public static func == (lhs: SizeLimitedArray<T>, rhs: SizeLimitedArray<T>) -> Bool {
        lhs.array == rhs.array
    }
}

extension SizeLimitedArray: RandomAccessCollection {
    public typealias Element = T
    public typealias Index = Int

    public var startIndex: Int {
        0
    }

    public var endIndex: Int {
        array.count
    }

    public subscript(position: Int) -> T {
        get {
            array[position]
        }
        set {
            assert(position >= 0 && position < maxLength)
            array[position] = newValue
        }
    }

    public func index(after i: Int) -> Int {
        i + 1
    }

    public func index(before i: Int) -> Int {
        i - 1
    }

    public func index(_ i: Int, offsetBy distance: Int) -> Int {
        i + distance
    }

    public func index(_ i: Int, offsetBy distance: Int, limitedBy limit: Int) -> Int? {
        i + distance < limit ? i + distance : nil
    }

    public func distance(from start: Int, to end: Int) -> Int {
        end - start
    }

    public func index(from start: Int) -> Int {
        start
    }

    public func formIndex(after i: inout Int) {
        i += 1
    }

    public func formIndex(before i: inout Int) {
        i -= 1
    }
}

public extension SizeLimitedArray {
    mutating func append(_ newElement: T) {
        assert(array.count < maxLength)
        array.append(newElement)
    }

    mutating func insert(_ newElement: T, at i: Int) {
        assert(i >= 0 && i <= maxLength)
        array.insert(newElement, at: i)
    }

    mutating func remove(at i: Int) -> T {
        assert(i >= 0 && i < maxLength)
        return array.remove(at: i)
    }
}
