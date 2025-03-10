import Blockchain
import Codec
import Foundation

public struct GuaranteedWorkReportMessage: Codable, Sendable, Equatable, Hashable {
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
