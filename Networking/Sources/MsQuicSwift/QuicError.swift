import Foundation

public enum QuicError: Error, Equatable, Sendable {
    case invalidStatus(message: String, status: QuicStatus)
    case alreadyStarted
    case alreadyClosed
    case notStarted
    case invalidAddress(NetAddr)
    case unableToGetRemoteAddress
}

// App specific error codes
public struct QuicErrorCode: Sendable, Equatable {
    public let code: UInt64

    public init(_ code: UInt64) {
        self.code = code
    }

    public static let success: QuicErrorCode = .init(0)
}

extension QuicErrorCode: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: UInt64) {
        self.init(value)
    }
}
