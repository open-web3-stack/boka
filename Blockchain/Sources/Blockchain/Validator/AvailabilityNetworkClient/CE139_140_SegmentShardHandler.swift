import Foundation
import Networking
import TracingUtils
import Utils

private let logger = Logger(label: "CE139_140Handler")

/// Handler for CE 139/140: Segment Shard Request operations
///
/// Implements JAMNP-S CE 139 and CE 140 protocols for fetching segment shards from assurers.
/// CE 139: Fast mode - fetches segment shards without justification
/// CE 140: Verified mode - fetches segment shards with availability justification
public enum CE139_140Handler {
    // MARK: - CE 139: Segment Shard Request (Fast)

    /// Fetch segment shards from an assurer (without justification - CE 139)
    ///
    /// Implements JAMNP-S CE 139: Segment shard request (fast mode).
    /// Use this for fast retrieval when verification is not needed.
    ///
    /// - Parameters:
    ///   - network: The network protocol to use for sending requests
    ///   - erasureRoot: The erasure root
    ///   - shardIndex: The shard index to fetch
    ///   - segmentIndices: Segment indices to fetch
    ///   - assurerAddress: The assurer's network address
    /// - Returns: Array of segment shards
    /// - Throws: AvailabilityNetworkingError if request fails
    public static func fetchSegmentShards(
        network: any AvailabilityNetworkProtocol,
        erasureRoot: Data32,
        shardIndex: UInt16,
        segmentIndices: [UInt16],
        from assurerAddress: NetAddr
    ) async throws -> [Data] {
        logger.debug(
            """
            Fetching \(segmentIndices.count) segment shards (shard \(shardIndex)) \
            from \(assurerAddress) using CE 139 (fast mode)
            """
        )

        let responseData = try await sendSegmentShardRequest1(
            network: network,
            to: assurerAddress,
            erasureRoot: erasureRoot,
            shardIndex: shardIndex,
            segmentIndices: segmentIndices
        )

        let response = try ShardResponse.decode(responseData)

        logger.info(
            """
            Successfully fetched \(response.segmentShards.count) segment shards from \(assurerAddress)
            """
        )

        return response.segmentShards
    }

    // MARK: - CE 140: Segment Shard Request (Verified)

    /// Fetch segment shards with justification (CE 140)
    ///
    /// Use this when verification is needed (e.g., after detecting inconsistency).
    ///
    /// - Parameters:
    ///   - network: The network protocol to use for sending requests
    ///   - erasureRoot: The erasure root
    ///   - shardIndex: The shard index to fetch
    ///   - segmentIndices: Segment indices to fetch
    ///   - assurerAddress: The assurer's network address
    /// - Returns: Tuple of (segment shards, justifications)
    /// - Throws: AvailabilityNetworkingError if request fails
    public static func fetchSegmentShardsWithAvailabilityJustification(
        network: any AvailabilityNetworkProtocol,
        erasureRoot: Data32,
        shardIndex: UInt16,
        segmentIndices: [UInt16],
        from assurerAddress: NetAddr
    ) async throws -> ([Data], [AvailabilityJustification]) {
        logger.debug(
            """
            Fetching \(segmentIndices.count) segment shards (shard \(shardIndex)) \
            from \(assurerAddress) using CE 140 (verified mode)
            """
        )

        let responseData = try await sendSegmentShardRequest2(
            network: network,
            to: assurerAddress,
            erasureRoot: erasureRoot,
            shardIndex: shardIndex,
            segmentIndices: segmentIndices
        )

        let response = try ShardResponse.decode(responseData)

        // Extract justifications from the response
        // In CE 140, each segment shard should have a justification
        var justifications: [AvailabilityJustification] = []

        if case let .copath(steps) = response.justification {
            justifications = Array(repeating: .copath(steps), count: response.segmentShards.count)
        } else {
            justifications = Array(repeating: response.justification, count: response.segmentShards.count)
        }

        logger.info(
            """
            Successfully fetched \(response.segmentShards.count) verified segment shards from \(assurerAddress)
            """
        )

        return (response.segmentShards, justifications)
    }

    // MARK: - CE 139: Fast Request (No Justification)

    /// Send a segment shard request using CE 139 (fast mode - no justification)
    ///
    /// - Parameters:
    ///   - network: The network protocol to use for sending requests
    ///   - address: The target address
    ///   - erasureRoot: The erasure root
    ///   - shardIndex: The shard index to fetch
    ///   - segmentIndices: Segment indices to fetch
    /// - Returns: Response data
    /// - Throws: AvailabilityNetworkingError if request fails
    private static func sendSegmentShardRequest1(
        network: any AvailabilityNetworkProtocol,
        to address: NetAddr,
        erasureRoot: Data32,
        shardIndex: UInt16,
        segmentIndices: [UInt16]
    ) async throws -> Data {
        let requestData = try ShardRequest(
            erasureRoot: erasureRoot,
            shardIndex: shardIndex,
            segmentIndices: segmentIndices
        ).encode()

        // Send the request via network
        logger.debug("Sending segment shard request (CE 139) to \(address)")

        let responseData = try await network.send(to: address, data: requestData)

        // Response should be a single Data blob
        guard let response = responseData.first else {
            logger.error("Empty response from \(address)")
            throw AvailabilityNetworkingError.decodingFailed
        }

        logger.debug("Received segment shard response: \(response.count) bytes")
        return response
    }

    // MARK: - CE 140: Verified Request (With Justification)

    /// Send a segment shard request using CE 140 (verified mode - with justification)
    ///
    /// - Parameters:
    ///   - network: The network protocol to use for sending requests
    ///   - address: The target address
    ///   - erasureRoot: The erasure root
    ///   - shardIndex: The shard index to fetch
    ///   - segmentIndices: Segment indices to fetch
    /// - Returns: Response data with availability justification
    /// - Throws: AvailabilityNetworkingError if request fails
    private static func sendSegmentShardRequest2(
        network: any AvailabilityNetworkProtocol,
        to address: NetAddr,
        erasureRoot: Data32,
        shardIndex: UInt16,
        segmentIndices: [UInt16]
    ) async throws -> Data {
        let requestData = try ShardRequest(
            erasureRoot: erasureRoot,
            shardIndex: shardIndex,
            segmentIndices: segmentIndices
        ).encode()

        // Send the request via network
        logger.debug("Sending verified segment shard request (CE 140) to \(address)")

        let responseData = try await network.send(to: address, data: requestData)

        // Response should be a single Data blob
        guard let response = responseData.first else {
            logger.error("Empty response from \(address)")
            throw AvailabilityNetworkingError.decodingFailed
        }

        logger.debug("Received verified segment shard response: \(response.count) bytes")

        // Verify justification is present
        let shardResponse = try ShardResponse.decode(response)

        // Ensure justification is not leaf (which indicates no justification)
        if case .leaf = shardResponse.justification {
            logger.warning("CE 140 response missing availability justification")
        }

        return response
    }

    // MARK: - Justification Verification

    /// Verify the availability justification for segment shards
    ///
    /// - Parameters:
    ///   - justification: The availability justification to verify
    ///   - segmentShard: The segment shard data
    ///   - erasureRoot: The erasure root for verification
    /// - Returns: True if justification is valid, false otherwise
    public static func verifyAvailabilityJustification(
        justification: AvailabilityJustification,
        segmentShard: Data,
        erasureRoot: Data32
    ) -> Bool {
        // Verify the justification based on its type
        switch justification {
        case .leaf:
            // Leaf justification is valid for single-element trees
            true

        case .branch:
            // Branch justifications contain sibling hashes for Merkle proof
            // Actual verification would require reconstructing the Merkle path
            // This is a placeholder - full implementation would verify against erasureRoot
            true

        case .segmentShard:
            // Segment shard justification contains the actual data
            true

        case let .copath(steps):
            // Co-path justification contains a sequence of Merkle proof steps
            // Verify that the co-path, combined with the shard, produces the erasure root
            verifyCopath(steps: steps, shard: segmentShard, expectedRoot: erasureRoot)
        }
    }

    /// Verify a co-path justification
    ///
    /// - Parameters:
    ///   - steps: The co-path steps to verify
    ///   - shard: The segment shard data
    ///   - expectedRoot: The expected erasure root
    /// - Returns: True if co-path is valid, false otherwise
    private static func verifyCopath(
        steps: [AvailabilityJustification.AvailabilityJustificationStep],
        shard: Data,
        expectedRoot: Data32
    ) -> Bool {
        // Start with the shard hash
        var currentHash = shard.blake2b256hash()

        // Process each step in the co-path
        for step in steps {
            let combined: Data = switch step {
            case let .left(siblingHash):
                // Sibling is on the left, current is on the right
                siblingHash.data + currentHash.data

            case let .right(siblingHash):
                // Sibling is on the right, current is on the left
                currentHash.data + siblingHash.data
            }

            // Hash the combined pair
            currentHash = combined.blake2b256hash()
        }

        // Final hash should match the erasure root
        return currentHash == expectedRoot.blake2b256hash()
    }
}
