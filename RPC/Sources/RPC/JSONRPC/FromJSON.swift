import Foundation
import Utils

enum FromJSONError: Error {
    case null
    case unexpectedJSON
}

public protocol FromJSON {
    init(from: JSON?) throws
}

public enum VoidRequest: FromJSON {
    case void

    public init(from _: JSON?) throws {
        // ignore
        self = .void
    }
}

extension Optional: FromJSON where Wrapped: FromJSON {
    public init(from json: JSON?) throws {
        guard let json else {
            self = .none
            return
        }
        switch json {
        case .null:
            self = .none
        default:
            self = try .some(Wrapped(from: json))
        }
    }
}

extension BinaryInteger where Self: FromJSON {
    public init(from json: JSON?) throws {
        guard let json else {
            throw FromJSONError.null
        }
        switch json {
        case let .number(n):
            self.init(n)
        default:
            throw FromJSONError.unexpectedJSON
        }
    }
}

extension Int8: FromJSON {}
extension Int16: FromJSON {}
extension Int32: FromJSON {}
extension Int64: FromJSON {}
extension Int: FromJSON {}
extension UInt8: FromJSON {}
extension UInt16: FromJSON {}
extension UInt32: FromJSON {}
extension UInt64: FromJSON {}
extension UInt: FromJSON {}

extension Data: FromJSON {
    public init(from json: JSON?) throws {
        guard let json else {
            throw FromJSONError.null
        }
        switch json {
        case let .string(str):
            self = try Data(fromHexString: str).unwrap()
        default:
            throw FromJSONError.unexpectedJSON
        }
    }
}

extension FixedSizeData: FromJSON {
    public init(from json: JSON?) throws {
        guard let json else {
            throw FromJSONError.null
        }
        switch json {
        case let .string(str):
            self = try FixedSizeData(fromHexString: str).unwrap()
        default:
            throw FromJSONError.unexpectedJSON
        }
    }
}

extension Array: FromJSON where Element: FromJSON {
    public init(from json: JSON?) throws {
        guard let json else {
            throw FromJSONError.null
        }
        switch json {
        case let .array(arr):
            self = try arr.map { try Element(from: $0) }
        default:
            throw FromJSONError.unexpectedJSON
        }
    }
}
