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
    case unknown // For handling unknown error types

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
        case unknown // For handling unknown error types
    }

    // Encode the QuicError to a Codable format
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

    // Decode the QuicError from a Codable format
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
    // Initialize ErrorType from QuicError
    init(from error: QuicError) {
        switch error {
        case .invalidStatus:
            self = .invalidStatus
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
        case .unknown:
            self = .unknown
        }
    }

    // Convert ErrorType back to QuicError
    func toQuicError() -> QuicError {
        switch self {
        case .invalidStatus:
            .invalidStatus(status: .unknown) // Provide a default status
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
        case .unknown:
            .unknown
        }
    }
}
