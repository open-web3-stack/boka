import Foundation

/// This module implements the standard method for deriving validator secret key seeds
public enum JIP5SeedDerive {
    /// Derives Ed25519 and Bandersnatch secret key seeds from a master seed
    ///
    /// - Parameter seed: The 32-byte master seed
    /// - Returns: A tuple containing (ed25519SecretSeed, bandersnatchSecretSeed)
    public static func deriveKeySeeds(from seed: Data32) -> (ed25519: Data32, bandersnatch: Data32) {
        let ed25519Prefix = "jam_val_key_ed25519"
        let bandersnatchPrefix = "jam_val_key_bandersnatch"

        let ed25519Input = Data(ed25519Prefix.utf8) + seed.data
        let ed25519SecretSeed = ed25519Input.blake2b256hash()

        let bandersnatchInput = Data(bandersnatchPrefix.utf8) + seed.data
        let bandersnatchSecretSeed = bandersnatchInput.blake2b256hash()

        return (ed25519: ed25519SecretSeed, bandersnatch: bandersnatchSecretSeed)
    }

    /// Creates a trivial seed from a 32-bit unsigned integer for testing purposes
    ///
    /// Implements: trivial_seed(i) = repeat_8_times(encode_as_32bit_le(i))
    ///
    /// - Parameter i: The 32-bit unsigned integer
    /// - Returns: A 32-byte seed with the integer repeated 8 times in little-endian format
    public static func trivialSeed(_ i: UInt32) -> Data32 {
        var seedData = Data(capacity: 32)
        let littleEndianBytes = i.littleEndian.encode()

        for _ in 0 ..< 8 {
            seedData.append(contentsOf: littleEndianBytes)
        }

        return Data32(seedData)!
    }
}
