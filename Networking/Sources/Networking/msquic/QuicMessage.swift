import Foundation

enum QuicMessageType: String, Codable {
    case unknown
    case received
    case close
    case connected
    case shutdownComplete
    case changeStreamType
}

public struct QuicMessage: Sendable, Equatable, Codable {
    let type: QuicMessageType
    let data: Data?
}
