import Foundation

enum QuicMessageType: String, Codable {
    case data
    case shutdown
    case aborted
    case unknown
    case received
    case close
    case connected
    case shutdownComplete
}

public struct QuicMessage: @unchecked Sendable, Codable {
    let type: QuicMessageType
    let data: Data?

    init(type: QuicMessageType, data: Data?) {
        self.type = type
        self.data = data
    }

    enum CodingKeys: String, CodingKey {
        case type
        case data
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(data, forKey: .data)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(QuicMessageType.self, forKey: .type)
        data = try container.decode(Data?.self, forKey: .data)
    }
}
