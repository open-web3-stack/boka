import Foundation
import Utils

enum FromJSONError: Error {
    case null
    case unexpectedJSON
}

protocol FromJSON {
    init(from: JSON?) throws
}

enum VoidRequest: FromJSON {
    case void

    init(from _: JSON?) throws {
        // ignore
        self = .void
    }
}

extension Optional: FromJSON where Wrapped: FromJSON {
    init(from json: JSON?) throws {
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
    init(from json: JSON?) throws {
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
    init(from json: JSON?) throws {
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

extension Data32: FromJSON {
    init(from json: JSON?) throws {
        guard let json else {
            throw FromJSONError.null
        }
        switch json {
        case let .string(str):
            self = try Data32(fromHexString: str).unwrap()
        default:
            throw FromJSONError.unexpectedJSON
        }
    }
}
