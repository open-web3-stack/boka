import Foundation

struct KeyValuePair<Key: Codable & Hashable & Comparable, Value: Codable>: Codable {
    var key: Key
    var value: Value
}

public struct SortedKeyValues<Key: Codable & Hashable & Comparable, Value: Codable>: Codable, CodableAlias {
    public typealias Alias = [Key: Value]

    public var alias: Alias

    public init(alias: Alias) {
        self.alias = alias
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let array = try container.decode([KeyValuePair<Key, Value>].self)

        // ensure array is sorted and unique
        var previous: KeyValuePair<Key, Value>?
        for item in array {
            guard previous == nil || item.key > previous!.key else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: container.codingPath,
                        debugDescription: "Array is not sorted"
                    )
                )
            }
            previous = item
        }

        alias = .init(uniqueKeysWithValues: array.map { ($0.key, $0.value) })
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        var array = alias.map { KeyValuePair(key: $0.key, value: $0.value) }
        array.sort { $0.key < $1.key }
        try container.encode(array)
    }
}

extension SortedKeyValues: Sendable where Key: Sendable, Value: Sendable, Alias: Sendable {}

extension SortedKeyValues: Equatable where Key: Equatable, Value: Equatable, Alias: Equatable {}
