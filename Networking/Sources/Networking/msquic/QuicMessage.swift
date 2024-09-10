import Foundation

enum QuicMessageType {
    case data
    case shutdown
    case aborted
    case unknown
    case received
    case connect
    case connected
}

public struct QuicMessage {
    let type: QuicMessageType
    let data: Data?
}
