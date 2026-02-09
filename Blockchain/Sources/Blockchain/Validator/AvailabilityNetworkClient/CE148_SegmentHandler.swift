import Foundation
import Networking
import TracingUtils
import Utils

private let logger = Logger(label: "CE148Handler")

/// CE 148: Segment Request Handler
///
/// Implements JAMNP-S CE 148: Segment request protocol.
/// Provides static methods for fetching reconstructed segments from guarantors.
public enum CE148Handler {
    /// Fetch reconstructed segments from a guarantor
    ///
    /// Implements JAMNP-S CE 148: Segment request.
    /// Should fallback to CE 139/140 if this fails.
    ///
    /// - Parameters:
    ///   - network: The network protocol for sending requests
    ///   - segmentsRoot: The segments root
    ///   - segmentIndices: Segment indices to fetch
    ///   - guarantorAddress: The guarantor's network address
    /// - Returns: Tuple of (segments, import proofs)
    /// - Throws: AvailabilityNetworkingError if request fails
    public static func fetchSegments(
        network: any AvailabilityNetworkProtocol,
        segmentsRoot: Data32,
        segmentIndices: [UInt16],
        from guarantorAddress: NetAddr,
    ) async throws -> ([Data4104], [[Data32]]) {
        let request = SegmentRequest(segmentsRoot: segmentsRoot, segmentIndices: segmentIndices)
        let requestData = try request.encode()

        logger.debug(
            """
            Fetching \(segmentIndices.count) segments from \(guarantorAddress) using CE 148
            """,
        )

        do {
            let responseData = try await sendSegmentRequest(
                network: network,
                to: guarantorAddress,
                data: requestData,
            )

            let response = try SegmentResponse.decode(responseData)

            logger.info(
                """
                Successfully fetched \(response.segments.count) segments from \(guarantorAddress)
                """,
            )

            return (response.segments, response.importProofs)
        } catch {
            logger.warning(
                """
                Failed to fetch segments via CE 148, would need to fallback to CE 139/140: \(error)
                """,
            )
            throw error
        }
    }

    /// Send a segment request to a guarantor
    ///
    /// - Parameters:
    ///   - network: The network protocol for sending requests
    ///   - address: The guarantor's network address
    ///   - data: The encoded request data
    /// - Returns: The response data
    /// - Throws: AvailabilityNetworkingError if request fails
    private static func sendSegmentRequest(
        network: any AvailabilityNetworkProtocol,
        to address: NetAddr,
        data: Data,
    ) async throws -> Data {
        logger.debug("Sending CE 148 segment request to \(address)")

        // Send request and get response
        let responseData = try await network.send(to: address, data: data)

        // Response should be a single Data blob
        guard let response = responseData.first else {
            logger.error("Empty response from \(address)")
            throw AvailabilityNetworkingError.decodingFailed
        }

        logger.debug("Received response: \(response.count) bytes")
        return response
    }
}
