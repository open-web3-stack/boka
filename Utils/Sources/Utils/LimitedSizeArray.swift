import ScaleCodec

// TODO: add tests

public struct LimitedSizeArray<T, TMinLength: ConstInt, TMaxLength: ConstInt> {
    private var array: [T]
    public static var minLength: Int {
        TMinLength.value
    }

    public static var maxLength: Int {
        TMaxLength.value
    }

    public init(defaultValue: T) {
        self.init(Array(repeating: defaultValue, count: Self.minLength))
    }

    public init(_ array: [T]) {
        assert(Self.minLength >= 0)
        assert(Self.maxLength >= Self.minLength)
        self.array = array

        validate()
    }

    private func validate() {
        assert(array.count >= Self.minLength)
        assert(array.count <= Self.maxLength)
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

extension LimitedSizeArray {
    public mutating func append(_ newElement: T) {
        array.append(newElement)
        validate()
    }

    public mutating func insert(_ newElement: T, at i: Int) {
        array.insert(newElement, at: i)
        validate()
    }

    public mutating func remove(at i: Int) -> T {
        defer { validate() }
        return array.remove(at: i)
    }
}

public typealias FixedSizeArray<T, TLength: ConstInt> = LimitedSizeArray<T, TLength, TLength>

extension LimitedSizeArray: ScaleCodec.Codable where T: ScaleCodec.Codable {
    public init(from decoder: inout some ScaleCodec.Decoder) throws {
        if TMinLength.value == TMaxLength.value {
            // fixed size array
            try self.init(decoder.decode(.fixed(UInt(TMinLength.value))))
        } else {
            // variable size array
            try self.init(decoder.decode())
        }
    }

    public func encode(in encoder: inout some ScaleCodec.Encoder) throws {
        if TMinLength.value == TMaxLength.value {
            // fixed size array
            try encoder.encode(array, .fixed(UInt(TMinLength.value)))
        } else {
            // variable size array
            try encoder.encode(array)
        }
    }
}
