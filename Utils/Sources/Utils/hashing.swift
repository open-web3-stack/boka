import Blake2
import Foundation

/// Computes a Blake2b 256-bit hash of the input data and returns the result as a `Data32`.
///
/// - Parameter: The input data to hash.
/// - Throws: An error if the hashing process fails.
/// - Returns: A `Data32` containing the hash result.
public func blake2b256(_ data: Data) throws -> Data32 {
    let hash = try Blake2b.hash(size: 32, data: data)
    let data32 = Data32(hash)!
    return data32
}
