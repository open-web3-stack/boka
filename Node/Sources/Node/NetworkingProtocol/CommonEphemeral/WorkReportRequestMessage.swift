import Blockchain
import Codec
import Foundation
import Utils

public struct WorkReportRequestMessage: Codable, Sendable, Equatable, Hashable {
    public var workReportHash: Data32

    public init(workReportHash: Data32) {
        self.workReportHash = workReportHash
    }
}

extension WorkReportRequestMessage: CEMessage {
    public func encode() throws -> [Data] {
        try [JamEncoder.encode(self)]
    }

    public static func decode(data: [Data], config: ProtocolConfigRef) throws -> WorkReportRequestMessage {
        guard let data = data.first else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: [],
                debugDescription: "unexpected data \(data)"
            ))
        }
        return try JamDecoder.decode(WorkReportRequestMessage.self, from: data, withConfig: config)
    }
}
