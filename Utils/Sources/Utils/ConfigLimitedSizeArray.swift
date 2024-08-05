import ScaleCodec

// TODO: add tests

public struct ConfigLimitedSizeArray<T, TMinLength: ReadInt, TMaxLength: ReadInt>
    where TMinLength.TConfig == TMaxLength.TConfig
{
    public private(set) var array: [T]

    public let minLength: Int
    public let maxLength: Int

    public init(config: TMinLength.TConfig, defaultValue: T) {
        let minLength = TMinLength.read(config: config)
        let maxLength = TMaxLength.read(config: config)

        self.init(Array(repeating: defaultValue, count: minLength), minLength: minLength, maxLength: maxLength)
    }

    // require minLength to be zero
    public init(config: TMinLength.TConfig) {
        let minLength = TMinLength.read(config: config)
        let maxLength = TMaxLength.read(config: config)

        self.init([], minLength: minLength, maxLength: maxLength)
    }

    public init(config: TMinLength.TConfig, array: [T]) {
        let minLength = TMinLength.read(config: config)
        let maxLength = TMaxLength.read(config: config)

        self.init(array, minLength: minLength, maxLength: maxLength)
    }

    private init(_ array: [T], minLength: Int, maxLength: Int) {
        assert(minLength >= 0)
        assert(maxLength >= minLength)

        self.array = array
        self.minLength = minLength
        self.maxLength = maxLength

        validate()
    }

    private func validate() {
        assert(array.count >= minLength, "count \(array.count) >= minLength \(minLength)")
        assert(array.count <= maxLength, "count \(array.count) <= maxLength \(maxLength)")
    }
}

extension ConfigLimitedSizeArray: Equatable where T: Equatable {}

extension ConfigLimitedSizeArray: Sendable where T: Sendable {}

extension ConfigLimitedSizeArray: RandomAccessCollection {
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

    public subscript(position: UInt32) -> T {
        get {
            array[Int(position)]
        }
        set {
            array[Int(position)] = newValue
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

extension ConfigLimitedSizeArray {
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

public typealias ConfigFixedSizeArray<T, TLength: ReadInt> = ConfigLimitedSizeArray<T, TLength, TLength>

extension ConfigLimitedSizeArray {
    public init<D: ScaleCodec.Decoder>(
        config: TMinLength.TConfig,
        from decoder: inout D,
        decodeItem: @escaping (inout D) throws -> T
    ) throws {
        let minLength = TMinLength.read(config: config)
        let maxLength = TMaxLength.read(config: config)

        if minLength == maxLength {
            // fixed size array
            try self.init(decoder.decode(.fixed(UInt(minLength), decodeItem)), minLength: minLength, maxLength: maxLength)
        } else {
            // variable size array
            try self.init(decoder.decode(.array(decodeItem)), minLength: minLength, maxLength: maxLength)
        }
    }
}

// not ScaleCodec.Decodable because we need to have the config to know the size limit
extension ConfigLimitedSizeArray where T: ScaleCodec.Decodable {
    public init(config: TMinLength.TConfig, from decoder: inout some ScaleCodec.Decoder) throws {
        let minLength = TMinLength.read(config: config)
        let maxLength = TMaxLength.read(config: config)

        if minLength == maxLength {
            // fixed size array
            try self.init(decoder.decode(.fixed(UInt(minLength))), minLength: minLength, maxLength: maxLength)
        } else {
            // variable size array
            try self.init(decoder.decode(), minLength: minLength, maxLength: maxLength)
        }
    }
}

extension ConfigLimitedSizeArray: ScaleCodec.Encodable where T: ScaleCodec.Encodable {
    public func encode(in encoder: inout some ScaleCodec.Encoder) throws {
        if minLength == maxLength {
            // fixed size array
            try encoder.encode(array, .fixed(UInt(minLength)))
        } else {
            // variable size array
            try encoder.encode(array)
        }
    }
}
