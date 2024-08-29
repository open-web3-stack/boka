enum QuicError: Error, Equatable {
    case invalidStatus(status: QuicStatusCode)
    case invalidAlpn
    case getApiFailed
    case getRegistrationFailed
}
