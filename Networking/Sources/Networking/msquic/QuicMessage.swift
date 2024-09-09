import Foundation

enum QuicMessageType {
    case data
    case shutdown
    case aborted
    case unknown
    case received
    case connect
}

struct QuicMessage {
    let type: QuicMessageType
    let data: Data?
}
