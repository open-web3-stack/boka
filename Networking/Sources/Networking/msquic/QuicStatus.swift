import Foundation
import msquic

extension QuicStatus {
    var isFailed: Bool {
        self > 0
    }

    var isSucceeded: Bool {
        self <= 0
    }

    var statusCode: QuicStatusCode {
        QuicStatusCode.from(rawValue: self)
    }
}

enum QuicStatusCode: QuicStatus {
    case success = 0
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

    static func from(rawValue: UInt32) -> QuicStatusCode {
        QuicStatusCode(rawValue: rawValue) ?? .unknown
    }

    static var unknown: QuicStatusCode {
        .init(rawValue: UInt32.max) ?? .internalError
    }
}
