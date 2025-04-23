import Codec
import Foundation
import Utils

public final class GuaranteedWorkReportRef: RefWithHash<GuaranteedWorkReport>, @unchecked Sendable {
    public var workReport: WorkReport { value.workReport }
    public var slot: UInt32 { value.slot }
    public var signatures: [ValidatorSignature] { value.signatures }
    override public var description: String {
        "GuaranteedWorkReport(hash: \(workReport.hash()), timeslot: \(slot))"
    }
}

extension GuaranteedWorkReportRef: Codable {
    public convenience init(from decoder: Decoder) throws {
        try self.init(.init(from: decoder))
    }

    public func encode(to encoder: Encoder) throws {
        try value.encode(to: encoder)
    }
}
