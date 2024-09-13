import Foundation

enum QuicMessageType {
    case data
    case shutdown
    case aborted
    case unknown
    case received
    case connect
    case connected
    case shutdownComplete
}

public struct QuicMessage: @unchecked Sendable {
    let type: QuicMessageType
    let data: Data?
}
