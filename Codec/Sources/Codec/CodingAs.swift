public protocol CodableAlias<Alias>: Codable {
    associatedtype Alias: Codable

    init(alias: Alias)
    var alias: Alias { get }
}

@propertyWrapper
public struct CodingAs<T: CodableAlias>: Codable {
    public var wrappedValue: T.Alias

    public init(wrappedValue: T.Alias) {
        self.wrappedValue = wrappedValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        wrappedValue = try container.decode(T.self).alias
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(T(alias: wrappedValue))
    }
}

extension CodingAs: Sendable where T: Sendable, T.Alias: Sendable {}

extension CodingAs: Equatable where T: Equatable, T.Alias: Equatable {}
