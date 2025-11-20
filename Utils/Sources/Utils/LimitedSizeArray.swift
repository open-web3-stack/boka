import Codec

public enum LimitedSizeArrayError: Swift.Error {
    case tooFewElements
    case tooManyElements
}

public struct LimitedSizeArray<T, TMinLength: ConstInt, TMaxLength: ConstInt> {
    public private(set) var array: [T]
    public static var minLength: Int {
        TMinLength.value
    }

    public static var maxLength: Int {
        TMaxLength.value
    }

    public init(defaultValue: T) {
        self.init(Array(repeating: defaultValue, count: Self.minLength))
    }

    public init(_ array: [T], validate: Bool = true) {
        assert(Self.minLength >= 0)
        assert(Self.maxLength >= Self.minLength)
        self.array = array

        if validate {
            self.validate()
        }
    }

    private func validate() {
        assert(array.count >= Self.minLength)
        assert(array.count <= Self.maxLength)
    }

    public func validateThrowing() throws(LimitedSizeArrayError) {
        guard array.count >= Self.minLength else {
            throw LimitedSizeArrayError.tooFewElements
        }
        guard array.count <= Self.maxLength else {
            throw LimitedSizeArrayError.tooManyElements
        }
    }
}

extension LimitedSizeArray: Sendable where T: Sendable {}

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
    public mutating func append(_ newElement: T) throws(LimitedSizeArrayError) {
        array.append(newElement)
        try validateThrowing()
    }

    public mutating func insert(_ newElement: T, at i: Int) throws(LimitedSizeArrayError) {
        array.insert(newElement, at: i)
        try validateThrowing()
    }

    public mutating func remove(at i: Int) throws(LimitedSizeArrayError) -> T {
        let ret = array.remove(at: i)
        try validateThrowing()
        return ret
    }
}

public typealias FixedSizeArray<T, TLength: ConstInt> = LimitedSizeArray<T, TLength, TLength>

extension LimitedSizeArray: Encodable where T: Encodable {
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.unkeyedContainer()
        // add length prefix for variable size array
        if TMinLength.self != TMaxLength.self, encoder.isJamCodec {
            let length = UInt32(array.count)
            try container.encode(contentsOf: length.encode(method: .variableWidth))
        }
        for item in array {
            try container.encode(item)
        }
    }
}

extension LimitedSizeArray: Decodable where T: Decodable {
    public init(from decoder: any Decoder) throws {
        var arr = [T]()
        var container = try decoder.unkeyedContainer()
        var length = TMaxLength.value

        if TMinLength.self != TMaxLength.self, decoder.isJamCodec {
            // read length prefix for variable size array
            let value = try IntegerCodec.decode { try container.decode(UInt8.self) }
            guard let value, let intValue = Int(exactly: value) else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: container.codingPath,
                        debugDescription: "Unable to decode length"
                    )
                )
            }
            length = intValue
        }

        for _ in 0 ..< length {
            try arr.append(container.decode(T.self))
        }

        self.init(arr, validate: false)
    }
}

extension LimitedSizeArray: EncodedSize where T: EncodedSize {
    public var encodedSize: Int {
        if TMinLength.self == TMaxLength.self {
            if let hint = T.encodeedSizeHint {
                return count * hint
            }
        }
        return array.encodedSize
    }

    public static var encodeedSizeHint: Int? {
        if TMinLength.self == TMaxLength.self {
            if let hint = T.encodeedSizeHint {
                return hint * TMinLength.value
            }
        }
        return nil
    }
}

extension LimitedSizeArray: HasConfig where T: HasConfig {
    public typealias Config = T.Config
}
