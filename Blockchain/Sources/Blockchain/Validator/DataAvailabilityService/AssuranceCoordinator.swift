import Codec
import Foundation
import TracingUtils
import Utils

private let logger = Logger(label: "AssuranceCoordinator")

/// Coordinator for assurance distribution and verification (CE 141)
///
/// Handles distributing work assurances to validators and verifying
/// incoming assurances from validators
public actor AssuranceCoordinator {
    private let dataProvider: BlockchainDataProvider
    private let config: ProtocolConfigRef

    public init(dataProvider: BlockchainDataProvider, config: ProtocolConfigRef) {
        self.dataProvider = dataProvider
        self.config = config
    }

    /// Distribute assurances to validators
    /// - Parameters:
    ///   - assurances: The assurances to distribute
    ///   - parentHash: The parent hash of the block
    ///   - validators: The validators to distribute to
    /// - Returns: Success status of the distribution
    public func distributeAssurances(
        assurances: ExtrinsicAvailability.AssurancesList,
        parentHash: Data32,
        validators _: [ValidatorIndex]
    ) async throws -> Bool {
        // CE 141: Distribute assurances to validators
        // 1. Verify the assurances are valid
        let state = try await dataProvider.getState(hash: dataProvider.bestHead.hash)
        let currentValidators = state.value.currentValidators

        for assurance in assurances {
            // Check validator index is within range
            guard assurance.validatorIndex < UInt32(currentValidators.count) else {
                throw DataAvailabilityError.invalidWorkReport
            }

            // Verify the parent hash matches
            guard assurance.parentHash == parentHash else {
                throw DataAvailabilityError.invalidWorkReport
            }

            // Verify the signature
            let validatorKey = currentValidators[Int(assurance.validatorIndex)]
            guard let publicKey = try? Ed25519.PublicKey(from: validatorKey.ed25519) else {
                throw DataAvailabilityError.invalidWorkReport
            }

            // Create the message: $jam_available || blake(encode(parentHash, bitfield))
            // Per spec eq:assurance-sig, the message is $jam_available || blake(encode(parentHash, assurance))
            let bitfieldData = try JamEncoder.encode(assurance.assurance)
            let payload = try JamEncoder.encode(parentHash, bitfieldData)
            let message = try JamEncoder.encode(UInt8(0x01), payload.blake2b256hash())
            let signatureMessage = Data("\u{0E}$jam_available".utf8) + message

            guard publicKey.verify(signature: assurance.signature, message: signatureMessage) else {
                throw DataAvailabilityError.invalidWorkReport
            }
        }

        // 2-3. TODO: Distribute assurances to validators and track distribution status
        // This requires network layer integration

        // 4. Return success status
        return true
    }

    /// Verify assurances from validators
    /// - Parameters:
    ///   - assurances: The assurances to verify
    ///   - parentHash: The parent hash of the block
    /// - Returns: The valid assurances
    public func verifyAssurances(
        assurances: ExtrinsicAvailability.AssurancesList,
        parentHash: Data32
    ) async throws -> ExtrinsicAvailability.AssurancesList {
        // Verify assurances from validators
        let state = try await dataProvider.getState(hash: dataProvider.bestHead.hash)
        let currentValidators = state.value.currentValidators

        var validItems: [ExtrinsicAvailability.AssuranceItem] = []

        for assurance in assurances {
            // 1. Verify the assurance is for the correct parent hash
            guard assurance.parentHash == parentHash else {
                logger.warning("Assurance parent hash mismatch: expected \(parentHash), got \(assurance.parentHash)")
                continue
            }

            // Check validator index is within range
            guard assurance.validatorIndex < UInt32(currentValidators.count) else {
                logger.warning("Invalid validator index in assurance: \(assurance.validatorIndex)")
                continue
            }

            // 2. Verify each assurance signature
            let validatorKey = currentValidators[Int(assurance.validatorIndex)]
            guard let publicKey = try? Ed25519.PublicKey(from: validatorKey.ed25519) else {
                logger.warning("Failed to create public key for validator \(assurance.validatorIndex)")
                continue
            }

            // Create the message: $jam_available || blake(encode(parentHash, bitfield))
            // Per spec eq:assurance-sig, the message is $jam_available || blake(encode(parentHash, assurance))
            let bitfieldData = try JamEncoder.encode(assurance.assurance)
            let payload = try JamEncoder.encode(parentHash, bitfieldData)
            let message = try JamEncoder.encode(UInt8(0x01), payload.blake2b256hash())
            let signatureMessage = Data("\u{0E}$jam_available".utf8) + message

            guard publicKey.verify(signature: assurance.signature, message: signatureMessage) else {
                logger.warning("Invalid signature for validator \(assurance.validatorIndex)")
                continue
            }

            // Add to valid assurances
            validItems.append(assurance)
        }

        // Create a new AssurancesList with only the valid items
        var validAssurances = try ExtrinsicAvailability.AssurancesList(config: config)
        for item in validItems {
            try validAssurances.append(item)
        }

        // 3. Return the valid assurances
        logger.info("Verified \(validItems.count)/\(assurances.count) assurances")
        return validAssurances
    }
}
