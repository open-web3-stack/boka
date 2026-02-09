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
        signature: Ed25519Signature,
    ) {
        self.workReports = workReports
        self.signature = signature
    }
}
