// TODO: add tests

public struct LimitedSizeArray<T, TMinLength: ConstInt, TMaxLength: ConstInt> {
    private var array: [T]
    public static var minLength: Int {
        TMinLength.value
    }

    public static var maxLength: Int {
        TMaxLength.value
    }

    public init(deafultValue: T) {
        self.init(Array(repeating: deafultValue, count: Self.minLength))
    }

    public init(_ array: [T]) {
        assert(Self.minLength >= 0)
        assert(Self.maxLength >= Self.minLength)
        self.array = array

        validate()
    }

    private func validate() {
        assert(array.count >= Self.minLength)
        assert(array.count < Self.maxLength)
    }
}

extension LimitedSizeArray: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: T...) {
        self.init(elements)
    }
}

extension LimitedSizeArray: Equatable where T: Equatable {
    public static func == (
        lhs: LimitedSizeArray<T, TMinLength, TMaxLength>, rhs: LimitedSizeArray<T, TMinLength, TMaxLength>
    ) -> Bool {
        lhs.array == rhs.array
    }
}

extension LimitedSizeArray: RandomAccessCollection {
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
            array[position] = newValue
            validate()
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

public extension LimitedSizeArray {
    mutating func append(_ newElement: T) {
        array.append(newElement)
        validate()
    }

    mutating func insert(_ newElement: T, at i: Int) {
        array.insert(newElement, at: i)
        validate()
    }

    mutating func remove(at i: Int) -> T {
        defer { validate() }
        return array.remove(at: i)
    }
}

public typealias FixedSizeArray<T, TLength: ConstInt> = LimitedSizeArray<T, TLength, TLength>
