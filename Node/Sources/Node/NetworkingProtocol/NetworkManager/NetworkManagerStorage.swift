import Blockchain
import Foundation
import Networking
import Utils

// MARK: - Network Manager Storage

/// Thread-safe storage for NetworkManager peer ID mappings
public actor NetworkManagerStorage {
    private var peerIdByPublicKey: [Data32: PeerId] = [:]
    private var currentValidatorKeys: Set<Data32> = []

    public init() {}

    /// Get peer ID by public key
    /// - Parameter publicKey: The validator's public key
    /// - Returns: The peer ID if found
    public func getPeerId(publicKey: Data32) -> PeerId? {
        peerIdByPublicKey[publicKey]
    }

    /// Set the peer ID mappings
    /// - Parameter dict: Dictionary mapping public keys to peer IDs
    public func set(_ dict: [Data32: PeerId]) {
        peerIdByPublicKey = dict
    }

    /// Update validator peer mappings from onchain state
    ///
    /// This method is called twice per epoch (once for current validators, once for next validators).
    /// To prevent memory leaks, it tracks the current validator set and removes stale entries
    /// between updates.
    ///
    /// - Parameter validators: ConfigFixedSizeArray of validators from onchain state
    public func updateValidatorPeerMappings(validators: ConfigFixedSizeArray<ValidatorKey, ProtocolConfig.TotalNumberOfValidators>) async {
        // Build set of new validator keys
        let newValidatorKeys = Set(validators.array.map(\.ed25519))

        // If this is the first call in a pair, store the keys and add mappings
        if currentValidatorKeys.isEmpty {
            currentValidatorKeys = newValidatorKeys
            for validator in validators.array {
                if let addr = NetAddr(address: validator.metadataString) {
                    peerIdByPublicKey[validator.ed25519] = PeerId(
                        publicKey: validator.ed25519.data,
                        address: addr
                    )
                }
            }
        } else {
            // Second call: merge in new validators, then remove any that aren't in either set
            for validator in validators.array {
                if let addr = NetAddr(address: validator.metadataString) {
                    peerIdByPublicKey[validator.ed25519] = PeerId(
                        publicKey: validator.ed25519.data,
                        address: addr
                    )
                }
            }

            // Remove stale validators (not in current or next set)
            let allActiveKeys = currentValidatorKeys.union(newValidatorKeys)
            peerIdByPublicKey = peerIdByPublicKey.filter { allActiveKeys.contains($0.key) }

            // Reset for next epoch
            currentValidatorKeys = []
        }
    }
}
