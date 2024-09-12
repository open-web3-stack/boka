public enum QuicError: Error, Equatable, Sendable {
    case invalidStatus(status: QuicStatusCode)
    case invalidAlpn
    case getApiFailed
    case getRegistrationFailed
    case getConnectionFailed
    case getStreamFailed
}
