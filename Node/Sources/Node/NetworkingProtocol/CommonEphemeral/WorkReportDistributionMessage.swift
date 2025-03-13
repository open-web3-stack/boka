import Blockchain
import Codec
import Foundation

public struct WorkReportDistributionMessage: Codable, Sendable, Equatable, Hashable {
    public let workReport: WorkReport
    public let slot: UInt32
    public let signatures: [ValidatorSignature]

    public init(
        workReport: WorkReport,
        slot: UInt32,
        signatures: [ValidatorSignature]
    ) {
        self.workReport = workReport
        self.slot = slot
        self.signatures = signatures
    }
}

extension WorkReportDistributionMessage: CEMessage {
    public func encode() throws -> [Data] {
        try [JamEncoder.encode(self)]
    }

    public static func decode(data: [Data], config: ProtocolConfigRef) throws -> WorkReportDistributionMessage {
        guard data.count == 1, let data = data.first else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: [],
                debugDescription: "unexpected data"
            ))
        }
        return try JamDecoder.decode(WorkReportDistributionMessage.self, from: data, withConfig: config)
    }
}
