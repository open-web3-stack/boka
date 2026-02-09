import Foundation
import Networking
import TracingUtils
import Utils

private let logger = Logger(label: "CE147Handler")

/// CE 147: Bundle Request Handler
///
/// Implements JAMNP-S CE 147: Bundle request for fetching full work-package bundles from guarantors.
/// Should fallback to CE 138 if this fails.
public enum CE147Handler {
    /// Fetch a full work-package bundle from a guarantor
    ///
    /// Implements JAMNP-S CE 147: Bundle request.
    ///
    /// - Parameters:
    ///   - erasureRoot: The erasure root
    ///   - guarantorAddress: The guarantor's network address
    ///   - network: Network protocol for sending requests
    /// - Returns: The work-package bundle data
    /// - Throws: AvailabilityNetworkingError if request fails
    public static func fetchBundle(
        erasureRoot: Data32,
        from guarantorAddress: NetAddr,
        network: any AvailabilityNetworkProtocol,
    ) async throws -> Data {
        logger.debug(
            """
            Fetching bundle \(erasureRoot) from \(guarantorAddress) using CE 147
            """,
        )

        let responseData = try await sendBundleRequest(
            to: guarantorAddress,
            erasureRoot: erasureRoot,
            network: network,
        )

        let response = try BundleResponse.decode(responseData)

        logger.info(
            """
            Successfully fetched bundle (\(response.bundle.count) bytes) from \(guarantorAddress)
            """,
        )

        return response.bundle
    }

    /// Send a bundle request (CE 147)
    ///
    /// - Parameters:
    ///   - address: The guarantor's network address
    ///   - erasureRoot: The erasure root
    ///   - network: Network protocol for sending requests
    /// - Returns: Raw response data
    /// - Throws: AvailabilityNetworkingError if request fails
    private static func sendBundleRequest(
        to address: NetAddr,
        erasureRoot: Data32,
        network: any AvailabilityNetworkProtocol,
    ) async throws -> Data {
        let requestData = BundleRequest(erasureRoot: erasureRoot).encode()

        // Send request with CE 147 request type
        let requestType = ShardRequestType.fullBundle
        let requestDataWithType = Data([requestType.rawValue]) + requestData

        logger.debug("Sending CE 147 bundle request to \(address)")

        // Send request and get response
        let responseData = try await network.send(to: address, data: requestDataWithType)

        // Response should be a single Data blob
        guard let response = responseData.first else {
            logger.error("Empty response from \(address)")
            throw AvailabilityNetworkingError.decodingFailed
        }

        logger.debug("Received CE 147 response: \(response.count) bytes")
        return response
    }
}
