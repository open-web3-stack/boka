import Foundation

public enum QuicError: Error, Equatable, Sendable, Codable {
    case invalidStatus(status: QuicStatusCode)
    case invalidAlpn
    case getApiFailed
    case getRegistrationFailed
    case getConnectionFailed
    case getStreamFailed
    case getClientFailed
    case messageNotFound
    case sendFailed

    enum CodingKeys: String, CodingKey {
        case type
        case status
    }

    enum ErrorType: String, Codable {
        case invalidStatus
        case invalidAlpn
        case getApiFailed
        case getRegistrationFailed
        case getConnectionFailed
        case getStreamFailed
        case getClientFailed
        case messageNotFound
        case sendFailed
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .invalidStatus(status):
            try container.encode(ErrorType.invalidStatus, forKey: .type)
            try container.encode(status, forKey: .status)
        default:
            let type = ErrorType(from: self)
            try container.encode(type, forKey: .type)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ErrorType.self, forKey: .type)

        switch type {
        case .invalidStatus:
            let status = try container.decode(QuicStatusCode.self, forKey: .status)
            self = .invalidStatus(status: status)
        default:
            self = type.toQuicError()
        }
    }
}

extension QuicError.ErrorType {
    init(from error: QuicError) {
        switch error {
        case .invalidAlpn:
            self = .invalidAlpn
        case .getApiFailed:
            self = .getApiFailed
        case .getRegistrationFailed:
            self = .getRegistrationFailed
        case .getConnectionFailed:
            self = .getConnectionFailed
        case .getStreamFailed:
            self = .getStreamFailed
        case .getClientFailed:
            self = .getClientFailed
        case .messageNotFound:
            self = .messageNotFound
        case .sendFailed:
            self = .sendFailed
        default:
            fatalError("Unhandled case: \(error)")
        }
    }

    func toQuicError() -> QuicError {
        switch self {
        case .invalidAlpn:
            .invalidAlpn
        case .getApiFailed:
            .getApiFailed
        case .getRegistrationFailed:
            .getRegistrationFailed
        case .getConnectionFailed:
            .getConnectionFailed
        case .getStreamFailed:
            .getStreamFailed
        case .getClientFailed:
            .getClientFailed
        case .messageNotFound:
            .messageNotFound
        case .sendFailed:
            .sendFailed
        default:
            fatalError("Unhandled case: \(self)")
        }
    }
}
