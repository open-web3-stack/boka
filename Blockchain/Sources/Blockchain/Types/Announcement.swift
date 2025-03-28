import Codec
import Utils

public struct Announcement: Codable, Sendable, Equatable, Hashable {
    public struct WorkReportIdentifier: Codable, Sendable, Equatable, Hashable {
        public let coreIndex: CoreIndex
        public let workReportHash: Data32

        public init(coreIndex: CoreIndex, workReportHash: Data32) {
            self.coreIndex = coreIndex
            self.workReportHash = workReportHash
        }
    }

    public let workReports: [WorkReportIdentifier]
    public let signature: Ed25519Signature

    public init(
        workReports: [WorkReportIdentifier],
        signature: Ed25519Signature
    ) {
        self.workReports = workReports
        self.signature = signature
    }
}

extension Announcement {
    public func encode() throws -> [Data] {
        let encoder = JamEncoder()

        // len ++ [Core Index ++ Work-Report Hash] ++ Signature
        try encoder.encode(UInt32(workReports.count))

        for report in workReports {
            try encoder.encode(report.coreIndex)
            try encoder.encode(report.workReportHash)
        }

        try encoder.encode(signature)
        return [encoder.data]
    }

    public static func decode(data: [Data], config: ProtocolConfigRef) throws -> Announcement {
        guard let data = data.first else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: [],
                debugDescription: "Missing announcement data"
            ))
        }

        let decoder = JamDecoder(data: data, config: config)
        let count = try decoder.decode(UInt32.self)

        var workReports = [WorkReportIdentifier]()
        for _ in 0 ..< count {
            try workReports.append(WorkReportIdentifier(
                coreIndex: decoder.decode(CoreIndex.self),
                workReportHash: decoder.decode(Data32.self)
            ))
        }

        return try Announcement(
            workReports: workReports,
            signature: decoder.decode(Ed25519Signature.self)
        )
    }
}
