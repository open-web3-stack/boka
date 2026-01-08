import Foundation
import Networking
import TracingUtils
import Utils

private let logger = Logger(label: "CE138Handler")

/// Handler for CE 138: Audit Shard Request operations
///
/// Implements JAMNP-S CE 138 protocol for fetching individual audit shards from assurers.
public enum CE138Handler {
    /// Fetch a single audit shard from an assurer
    ///
    /// Implements JAMNP-S CE 138: Audit shard request.
    ///
    /// - Parameters:
    ///   - network: The network protocol to use for sending requests
    ///   - erasureRoot: The erasure root
    ///   - shardIndex: The shard index to fetch
    ///   - assurerAddress: The assurer's network address
    /// - Returns: Tuple of (bundle shard, justification)
    /// - Throws: AvailabilityNetworkingError if request fails
    public static func fetchAuditShard(
        network: any AvailabilityNetworkProtocol,
        erasureRoot: Data32,
        shardIndex: UInt16,
        from assurerAddress: NetAddr
    ) async throws -> (Data, AvailabilityJustification) {
        logger.debug(
            """
            Fetching audit shard \(shardIndex) from \(assurerAddress)
            """
        )

        let responseData = try await sendAuditShardRequest(
            network: network,
            to: assurerAddress,
            erasureRoot: erasureRoot,
            shardIndex: shardIndex
        )

        let response = try ShardResponse.decode(responseData)

        // Verify we got a bundle shard
        guard !response.bundleShard.isEmpty else {
            throw AvailabilityNetworkingError.decodingFailed
        }

        // AvailabilityJustification should be the co-path from erasure-root to the shard
        let justification = response.justification

        logger.info(
            """
            Successfully fetched audit shard \(shardIndex) from \(assurerAddress)
            """
        )

        return (response.bundleShard, justification)
    }

    /// Send an audit shard request (CE 138)
    ///
    /// - Parameters:
    ///   - network: The network protocol to use for sending requests
    ///   - address: The target address
    ///   - erasureRoot: The erasure root
    ///   - shardIndex: The shard index to fetch
    /// - Returns: Response data
    /// - Throws: AvailabilityNetworkingError if request fails
    private static func sendAuditShardRequest(
        network: any AvailabilityNetworkProtocol,
        to address: NetAddr,
        erasureRoot: Data32,
        shardIndex: UInt16
    ) async throws -> Data {
        let requestData = try ShardRequest(
            erasureRoot: erasureRoot,
            shardIndex: shardIndex,
            segmentIndices: nil
        ).encode()

        // Send the request via network
        logger.debug("Sending audit shard request (CE 138) to \(address)")

        let responseData = try await network.send(to: address, data: requestData)

        // Response should be a single Data blob
        guard let response = responseData.first else {
            logger.error("Empty response from \(address)")
            throw AvailabilityNetworkingError.decodingFailed
        }

        logger.debug("Received audit shard response: \(response.count) bytes")
        return response
    }
}
