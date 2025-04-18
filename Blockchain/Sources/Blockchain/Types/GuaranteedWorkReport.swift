import Codec
import Foundation
import Utils

public struct GuaranteedWorkReport: Sendable, Equatable, Codable, Hashable {
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

extension GuaranteedWorkReport: Hashable32 {
    public func hash() -> Data32 {
        try! JamEncoder.encode(self).blake2b256hash()
    }
}

extension GuaranteedWorkReport: Dummy {
    public typealias Config = ProtocolConfigRef
    public static func dummy(config: Config) -> GuaranteedWorkReport {
        GuaranteedWorkReport(
            workReport: WorkReport.dummy(config: config),
            slot: 0,
            signatures: []
        )
    }
}

extension GuaranteedWorkReport {
    public func asRef() -> GuaranteedWorkReportRef {
        GuaranteedWorkReportRef(self)
    }
}
