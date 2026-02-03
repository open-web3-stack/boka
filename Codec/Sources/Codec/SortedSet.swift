import Foundation

public struct SortedSet<T: Codable & Hashable & Comparable>: Codable, CodableAlias {
    public typealias Alias = Set<T>

    public var alias: Alias

    public init(alias: Alias) {
        self.alias = alias
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let array = try container.decode([T].self)

        // ensure array is sorted and unique
        var previous: T?
        for item in array {
            guard previous == nil || item > previous! else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: container.codingPath,
                        debugDescription: "Array is not sorted",
                    ),
                )
            }
            previous = item
        }

        alias = Set(array)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        var array = Array(alias)
        array.sort()
        try container.encode(array)
    }
}

extension SortedSet: Sendable where T: Sendable, Alias: Sendable {}

extension SortedSet: Equatable where T: Equatable, Alias: Equatable {}
