import Blockchain
import Codec
import Foundation
import Utils

/// A guaranteed work-report ready for distribution via CE 135.
public struct GuaranteedWorkReportMessage: Codable, Sendable, Equatable, Hashable {
    /// The work-report containing the computation results.
    public let workReport: WorkReport

    /// The slot for which the work-report is valid.
    public let slot: UInt32

    /// A list of validator indices and their corresponding signatures.
    /// Each signature is an Ed25519 signature over the work-report hash.
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

public struct ValidatorSignature: Codable, Sendable, Equatable, Hashable {
    public let validatorIndex: ValidatorIndex

    public let signature: Ed25519Signature

    public init(validatorIndex: ValidatorIndex, signature: Ed25519Signature) {
        self.validatorIndex = validatorIndex
        self.signature = signature
    }
}
