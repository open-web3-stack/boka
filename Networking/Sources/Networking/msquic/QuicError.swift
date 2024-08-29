enum QuicError: Swift.Error {
    case invalidStatus(status: QuicStatusCode)
    case invalidAlpn
    case getApiFailed
    case getRegistrationFailed
}
