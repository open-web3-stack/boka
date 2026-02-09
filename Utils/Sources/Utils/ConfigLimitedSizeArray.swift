import Codec

// TODO: consider using a circular buffer instead of a regular array to reduce memory usage

public enum ConfigLimitedSizeArrayError: Swift.Error {
    case tooManyElements
    case tooFewElements
    case invalidMinLength
    case invalidMaxLength
    case invalidIndex
}

public struct ConfigLimitedSizeArray<T, TMinLength: ReadInt, TMaxLength: ReadInt>
    where TMinLength.TConfig == TMaxLength.TConfig
{
    public private(set) var array: [T]

    public let minLength: Int
    public let maxLength: Int

    public init(config: TMinLength.TConfig, defaultValue: T) throws(ConfigLimitedSizeArrayError) {
        let minLength = TMinLength.read(config: config)
        let maxLength = TMaxLength.read(config: config)

        try self.init(Array(repeating: defaultValue, count: minLength), minLength: minLength, maxLength: maxLength)
    }

    /// require minLength to be zero
    public init(config: TMinLength.TConfig) throws(ConfigLimitedSizeArrayError) {
        let minLength = TMinLength.read(config: config)
        let maxLength = TMaxLength.read(config: config)

        try self.init([], minLength: minLength, maxLength: maxLength)
    }

    public init(config: TMinLength.TConfig, array: [T]) throws(ConfigLimitedSizeArrayError) {
        let minLength = TMinLength.read(config: config)
        let maxLength = TMaxLength.read(config: config)

        try self.init(array, minLength: minLength, maxLength: maxLength)
    }

    private init(_ array: [T], minLength: Int, maxLength: Int, validate: Bool = true) throws(ConfigLimitedSizeArrayError) {
        guard minLength >= 0 else {
            throw ConfigLimitedSizeArrayError.invalidMinLength
        }
        guard maxLength >= minLength else {
            throw ConfigLimitedSizeArrayError.invalidMaxLength
        }

        self.array = array
        self.minLength = minLength
        self.maxLength = maxLength

        if validate {
            try validateThrowing()
        }
    }

    private func validate() {
        assert(array.count >= minLength, "count \(array.count) >= minLength \(minLength)")
        assert(array.count <= maxLength, "count \(array.count) <= maxLength \(maxLength)")
    }

    public func validateThrowing() throws(ConfigLimitedSizeArrayError) {
        guard array.count >= minLength else {
            throw ConfigLimitedSizeArrayError.tooFewElements
        }
        guard array.count <= maxLength else {
            throw ConfigLimitedSizeArrayError.tooManyElements
        }
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

    public subscript(position: UInt) -> T {
        get {
            array[Int(position)]
        }
        set {
            array[Int(position)] = newValue
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

    public subscript(position: UInt16) -> T {
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
    public mutating func append(_ newElement: T) throws(ConfigLimitedSizeArrayError) {
        array.append(newElement)
        try validateThrowing()
    }

    /// append element and pop the first element if needed
    public mutating func safeAppend(_ newElement: T) {
        if array.count == maxLength {
            array.removeFirst()
        }
        array.append(newElement)
    }

    public mutating func insert(_ newElement: T, at i: Int) throws(ConfigLimitedSizeArrayError) {
        if i < 0 || i > array.count {
            throw ConfigLimitedSizeArrayError.invalidIndex
        }
        array.insert(newElement, at: i)
        try validateThrowing()
    }

    public mutating func remove(at i: Int) throws -> T {
        if i < 0 || i >= array.count {
            throw ConfigLimitedSizeArrayError.invalidIndex
        }
        let res = array.remove(at: i)
        try validateThrowing()
        return res
    }

    public mutating func mutate<R>(_ fn: (inout [T]) -> R) throws(ConfigLimitedSizeArrayError) -> R {
        let ret = fn(&array)
        try validateThrowing()
        return ret
    }
}

extension ConfigLimitedSizeArray: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        array.description
    }

    public var debugDescription: String {
        "ConfigLimitedSizeArray<\(T.self), \(minLength), \(maxLength)>(\(description))"
    }
}

public typealias ConfigFixedSizeArray<T, TLength: ReadInt> = ConfigLimitedSizeArray<T, TLength, TLength>

extension ConfigLimitedSizeArray: Decodable where T: Decodable {
    public enum DecodeError: Swift.Error {
        case missingConfig
    }

    public init(from decoder: any Decoder) throws {
        guard let config = decoder.getConfig(TMinLength.TConfig.self) else {
            throw DecodeError.missingConfig
        }

        let minLength = TMinLength.read(config: config)
        let maxLength = TMaxLength.read(config: config)

        if TMinLength.self == TMaxLength.self {
            // fixed size array
            var container = try decoder.unkeyedContainer()

            var arr = [T]()
            arr.reserveCapacity(minLength)
            for _ in 0 ..< minLength {
                try arr.append(container.decode(T.self))
            }
            try self.init(arr, minLength: minLength, maxLength: maxLength, validate: false)
        } else {
            // variable size array
            var container = try decoder.unkeyedContainer()
            if decoder.isJamCodec {
                let array = try container.decode([T].self)
                try self.init(array, minLength: minLength, maxLength: maxLength, validate: false)
            } else {
                var array = [T]()
                while !container.isAtEnd {
                    try array.append(container.decode(T.self))
                }
                try self.init(array, minLength: minLength, maxLength: maxLength, validate: false)
            }
        }
    }
}

extension ConfigLimitedSizeArray: Encodable where T: Encodable {
    public func encode(to encoder: any Encoder) throws {
        if TMinLength.self == TMaxLength.self {
            // fixed size array
            var container = encoder.unkeyedContainer()
            for item in array {
                try container.encode(item)
            }
        } else {
            // variable size array
            var container = encoder.singleValueContainer()
            try container.encode(array)
        }
    }
}

extension ConfigLimitedSizeArray: EncodedSize where T: EncodedSize {
    public var encodedSize: Int {
        if TMinLength.self == TMaxLength.self {
            if let hint = T.encodeedSizeHint {
                return count * hint
            }
        }
        return array.encodedSize
    }

    public static var encodeedSizeHint: Int? {
        nil
    }
}

extension ConfigLimitedSizeArray: HasConfig where T: HasConfig {
    public typealias Config = T.Config
}
