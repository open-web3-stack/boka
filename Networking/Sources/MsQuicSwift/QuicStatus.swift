import Foundation

public enum QuicStatus: Equatable, Sendable, Codable, RawRepresentable {
    case code(QuicStatusCode)
    case unknown(UInt32)

    public init(rawValue: UInt32) {
        if let code = QuicStatusCode(rawValue: rawValue) {
            self = .code(code)
        } else {
            self = .unknown(rawValue)
        }
    }

    public var rawValue: UInt32 {
        switch self {
        case let .code(code):
            code.rawValue
        case let .unknown(value):
            value
        }
    }
}

extension QuicStatus {
    public var isSucceeded: Bool {
        switch self {
        case let .code(code):
            Int32(bitPattern: code.rawValue) <= 0
        case .unknown:
            false
        }
    }

    func requireSucceeded(_ message: String) throws(QuicError) {
        if !isSucceeded {
            throw QuicError.invalidStatus(message: message, status: self)
        }
    }
}

public enum QuicStatusCode: UInt32, Equatable, Sendable, Codable {
    case success = 0
    case cont = 0xFFFF_FFFD // continue
    case pending = 0xFFFF_FFFE
    case notFound = 2
    case outOfMemory = 12
    case invalidParameter = 22
    case invalidState = 1

    #if os(macOS)
        case notSupported = 102
        case bufferTooSmall = 84
        case handshakeFailure = 53
        case aborted = 89
        case addressInUse = 48
        case invalidAddress = 47
        case connectionTimeout = 60
        case connectionIdle = 101
        case connectionRefused = 61
        case protocolError = 100
        case verNegError = 43
        case unreachable = 65
        case userCanceled = 105
        case alpnNegFailure = 42
        case alpnInUse = 41
    #else
        case notSupported = 95
        case bufferTooSmall = 75
        case handshakeFailure = 103
        case aborted = 125
        case addressInUse = 98
        case invalidAddress = 97
        case connectionTimeout = 110
        case connectionIdle = 62
        case connectionRefused = 111
        case protocolError = 71
        case verNegError = 93
        case unreachable = 113
        case userCanceled = 130
        case alpnNegFailure = 92
        case alpnInUse = 91
    #endif

    case internalError = 5
    case tlsError = 126
    case streamLimitReached = 86

    case closeNotify = 0xBEBC300
    case badCert = 0xBEBC32A
    case unsupportedCert = 0xBEBC32B
    case revokedCert = 0xBEBC32C
    case expiredCert = 0xBEBC32D
    case unknownCert = 0xBEBC32E
    case requiredCert = 0xBEBC374
}
