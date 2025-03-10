import Foundation

/// A validator's signature over a work-report hash.
public struct ValidatorSignature: Codable, Sendable, Equatable, Hashable {
    /// The index of the validator in the current validator set.
    public let validatorIndex: ValidatorIndex

    /// The Ed25519 signature over the work-report hash.
    public let signature: Ed25519Signature

    public init(validatorIndex: ValidatorIndex, signature: Ed25519Signature) {
        self.validatorIndex = validatorIndex
        self.signature = signature
    }
}
