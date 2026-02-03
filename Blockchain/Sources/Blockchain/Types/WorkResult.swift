import Codec
import Foundation

public enum WorkResultError: Error, CaseIterable {
    case outOfGas
    case panic
    /// (circledcirc) the number of exports made was invalidly reported
    case badExports
    /// (circleddash) oversize reports
    case overSize
    /// (BAD) the service's code was not available for lookup in state at the posterior state of the lookup-anchor block
    case invalidCode
    /// (BIG) code larger than MaxServiceCodeSize
    case codeTooLarge
}

public struct WorkResult: Sendable, Equatable {
    public var result: Result<Data, WorkResultError>

    public init(_ result: Result<Data, WorkResultError>) {
        self.result = result
    }
}

extension WorkResult: Codable {
    enum CodingKeys: String, CodingKey {
        case success
        case outOfGas
        case panic
        case badExports
        case overSize
        case invalidCode
        case codeTooLarge
    }

    public init(from decoder: Decoder) throws {
        if decoder.isJamCodec {
            var container = try decoder.unkeyedContainer()
            let variant = try container.decode(UInt8.self)
            switch variant {
            case 0:
                self = try .init(.success(container.decode(Data.self)))
            case 1:
                self = .init(.failure(.outOfGas))
            case 2:
                self = .init(.failure(.panic))
            case 3:
                self = .init(.failure(.badExports))
            case 4:
                self = .init(.failure(.overSize))
            case 5:
                self = .init(.failure(.invalidCode))
            case 6:
                self = .init(.failure(.codeTooLarge))
            default:
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: decoder.codingPath,
                        debugDescription: "Invalid WorkResultError: unknown variant \(variant)",
                    ),
                )
            }
        } else {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if container.contains(.success) {
                self = try .init(.success(container.decode(Data.self, forKey: .success)))
            } else if container.contains(.outOfGas) {
                self = .init(.failure(.outOfGas))
            } else if container.contains(.panic) {
                self = .init(.failure(.panic))
            } else if container.contains(.badExports) {
                self = .init(.failure(.badExports))
            } else if container.contains(.overSize) {
                self = .init(.failure(.overSize))
            } else if container.contains(.invalidCode) {
                self = .init(.failure(.invalidCode))
            } else if container.contains(.codeTooLarge) {
                self = .init(.failure(.codeTooLarge))
            } else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: container.codingPath,
                        debugDescription: "Not valid key founded",
                    ),
                )
            }
        }
    }

    public func encode(to encoder: Encoder) throws {
        if encoder.isJamCodec {
            var container = encoder.unkeyedContainer()
            switch result {
            case let .success(success):
                try container.encode(UInt8(0))
                try container.encode(success)
            case let .failure(failure):
                switch failure {
                case .outOfGas:
                    try container.encode(UInt8(1))
                case .panic:
                    try container.encode(UInt8(2))
                case .badExports:
                    try container.encode(UInt8(3))
                case .overSize:
                    try container.encode(UInt8(4))
                case .invalidCode:
                    try container.encode(UInt8(5))
                case .codeTooLarge:
                    try container.encode(UInt8(6))
                }
            }
        } else {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch result {
            case let .success(success):
                try container.encode(success, forKey: .success)
            case let .failure(failure):
                switch failure {
                case .outOfGas:
                    try container.encodeNil(forKey: .outOfGas)
                case .panic:
                    try container.encodeNil(forKey: .panic)
                case .badExports:
                    try container.encodeNil(forKey: .badExports)
                case .overSize:
                    try container.encodeNil(forKey: .overSize)
                case .invalidCode:
                    try container.encodeNil(forKey: .invalidCode)
                case .codeTooLarge:
                    try container.encodeNil(forKey: .codeTooLarge)
                }
            }
        }
    }
}

extension WorkResult: EncodedSize {
    public var encodedSize: Int {
        switch result {
        case let .success(success):
            success.encodedSize + 1
        case .failure:
            1
        }
    }

    public static var encodeedSizeHint: Int? {
        nil
    }
}
