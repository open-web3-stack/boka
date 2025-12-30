import Foundation
import Networking
import TracingUtils
import Utils

private let logger = Logger(label: "NetworkRequestHelper")

/// Helper service for network request parsing and execution
///
/// Handles parsing of validator network addresses from metadata,
/// validation of IP addresses, and concurrent fetching from validators
public actor NetworkRequestHelper {
    private let dataProvider: BlockchainDataProvider
    private let networkClient: AvailabilityNetworkClient?

    public init(dataProvider: BlockchainDataProvider, networkClient: AvailabilityNetworkClient?) {
        self.dataProvider = dataProvider
        self.networkClient = networkClient
    }

    /// Fetch data from a specific validator
    /// - Parameters:
    ///   - validatorIndex: The validator index to fetch from
    ///   - requestData: The request data to send
    /// - Returns: The response data
    /// - Throws: DataAvailabilityError if the request fails
    public func fetchFromValidator(
        validator validatorIndex: ValidatorIndex,
        requestData: Data
    ) async throws -> Data {
        // Ensure network client is available
        guard let networkClient else {
            logger.error("Network client not available for validator request")
            throw DataAvailabilityError.retrievalError
        }

        // Get validator's network address from on-chain state
        let state = try await dataProvider.getState(hash: dataProvider.bestHead.hash)
        let validators = state.value.currentValidators

        // Check validator index is valid
        guard validatorIndex < UInt32(validators.count) else {
            logger.error("Validator index \(validatorIndex) out of range (0..<\(validators.count))")
            throw DataAvailabilityError.retrievalError
        }

        // Get the validator's network address from metadata
        let validator = validators[Int(validatorIndex)]
        let networkAddress = try extractNetworkAddress(from: validator.metadata.data)

        // Send request via network client
        logger.debug("Sending request to validator \(validatorIndex) at \(networkAddress)")

        do {
            guard let networkProtocol = await networkClient.getNetwork() else {
                logger.error("Network protocol not available in network client")
                throw DataAvailabilityError.retrievalError
            }

            let responses = try await networkProtocol.send(to: networkAddress, data: requestData)

            // Return first response (most protocols return single response)
            guard let response = responses.first else {
                logger.error("No response from validator \(validatorIndex)")
                throw DataAvailabilityError.retrievalError
            }

            return response
        } catch {
            logger.error("Failed to fetch from validator \(validatorIndex): \(error)")
            throw DataAvailabilityError.retrievalError
        }
    }

    /// Extract network address from validator metadata
    /// - Parameter metadata: Validator metadata bytes
    /// - Returns: Network address
    /// - Throws: DataAvailabilityError if extraction fails
    private func extractNetworkAddress(from metadata: Data) throws -> NetAddr {
        // Metadata format: multiaddr encoded as UTF-8 string
        // GP spec multiaddr format: /ip4/<ip>/tcp/<port> or /ip6/<ip>/tcp/<port>
        // See: https://github.com/multiformats/multiaddr
        //
        // Supported formats:
        // - Multiaddr: /ip4/127.0.0.1/tcp/1234
        // - Multiaddr: /ip6/::1/tcp/1234
        // - Direct: 127.0.0.1:1234
        // - Direct: [::1]:1234 (IPv6 with brackets)

        guard let metadataString = String(data: metadata, encoding: .utf8) else {
            logger.error("Failed to decode metadata as UTF-8 string. Hex: \(metadata.toHexString())")
            throw DataAvailabilityError.invalidMetadata("Invalid UTF-8 encoding")
        }

        let trimmed = metadataString.trimmingCharacters(in: .whitespacesAndNewlines)

        // Try multiaddr format first
        if trimmed.hasPrefix("/") {
            if let addr = try parseMultiaddr(trimmed) {
                logger.debug("Parsed multiaddr: \(trimmed) -> \(addr)")
                return addr
            }
            logger.warning("Failed to parse multiaddr format: \(trimmed)")
        }

        // Try direct format (ip:port)
        if let addr = parseDirectAddress(trimmed) {
            logger.debug("Parsed direct address format: \(trimmed) -> \(addr)")
            return addr
        }

        logger.error("Failed to parse network address from metadata: \(trimmed)")
        throw DataAvailabilityError.invalidMetadata("Unable to parse address: '\(trimmed)'")
    }

    /// Parse multiaddr format (e.g., /ip4/127.0.0.1/tcp/1234)
    private func parseMultiaddr(_ addr: String) throws -> NetAddr? {
        let parts = addr.components(separatedBy: "/").filter { !$0.isEmpty }

        guard parts.count >= 4 else {
            logger.debug("Multiaddr too short: \(addr)")
            return nil
        }

        var ipAddress: String?
        var port: UInt16?
        var index = 0

        while index < parts.count {
            let part = parts[index]

            switch part {
            case "ip4":
                guard index + 1 < parts.count else {
                    logger.debug("Multiaddr ip4 missing address")
                    return nil
                }
                let candidateIP = parts[index + 1]
                guard isValidIPv4(candidateIP) else {
                    logger.debug("Invalid IPv4 address: \(candidateIP)")
                    return nil
                }
                ipAddress = candidateIP
                index += 2

            case "ip6":
                guard index + 1 < parts.count else {
                    logger.debug("Multiaddr ip6 missing address")
                    return nil
                }
                let candidateIP = parts[index + 1]
                guard isValidIPv6(candidateIP) else {
                    logger.debug("Invalid IPv6 address: \(candidateIP)")
                    return nil
                }
                ipAddress = candidateIP
                index += 2

            case "tcp", "udp":
                guard index + 1 < parts.count else {
                    logger.debug("Multiaddr \(part) missing port")
                    return nil
                }
                guard let portNum = UInt16(parts[index + 1]) else {
                    logger.debug("Invalid port number: \(parts[index + 1])")
                    return nil
                }
                // Validate port range (1-65535, 0 is reserved)
                guard portNum > 0 else {
                    logger.debug("Port must be > 0: \(portNum)")
                    return nil
                }
                port = portNum
                index += 2

            default:
                // Unknown protocol component - skip
                index += 1
            }
        }

        // Validate we have both components
        guard let ip = ipAddress, let p = port else {
            logger.debug("Multiaddr missing required components (ip=\(ipAddress != nil), port=\(port != nil))")
            return nil
        }

        // Try to create NetAddr
        guard let addr = NetAddr(ipAddress: ip, port: p) else {
            logger.debug("NetAddr creation failed for \(ip):\(p)")
            return nil
        }

        return addr
    }

    /// Parse direct address format (e.g., 127.0.0.1:1234 or [::1]:1234)
    private func parseDirectAddress(_ addr: String) -> NetAddr? {
        // Try NetAddr's built-in parser first
        if let netAddr = NetAddr(address: addr) {
            return netAddr
        }

        // Manual parsing for better error handling
        // Handle IPv6 with brackets: [::1]:1234
        if addr.hasPrefix("["), let closingBracket = addr.firstIndex(of: "]") {
            let ipEnd = addr.index(after: closingBracket)
            guard ipEnd < addr.endIndex, addr[ipEnd] == ":" else {
                logger.debug("IPv6 address missing port separator")
                return nil
            }

            let ipString = String(addr[addr.index(after: addr.startIndex) ..< closingBracket])
            let portString = String(addr[ipEnd...].dropFirst())

            guard isValidIPv6(ipString), let port = UInt16(portString), port > 0 else {
                return nil
            }

            return NetAddr(ipAddress: ipString, port: port)
        }

        // Handle IPv4: 127.0.0.1:1234
        if let colonIndex = addr.lastIndex(of: ":") {
            let ipString = String(addr[..<colonIndex])
            let portString = String(addr[addr.index(after: colonIndex)...])

            guard isValidIPv4(ipString), let port = UInt16(portString), port > 0 else {
                return nil
            }

            return NetAddr(ipAddress: ipString, port: port)
        }

        return nil
    }

    /// Validate IPv4 address format
    private func isValidIPv4(_ addr: String) -> Bool {
        let octets = addr.split(separator: ".")
        guard octets.count == 4 else { return false }

        for octet in octets {
            guard UInt8(octet) != nil else { return false }
            // Additional check to reject leading zeros (except "0" itself)
            if octet.count > 1, octet.hasPrefix("0") {
                return false
            }
        }

        return true
    }

    /// Validate IPv6 address format (basic validation)
    private func isValidIPv6(_ addr: String) -> Bool {
        // Basic validation: must contain colons, not empty
        guard !addr.isEmpty, addr.contains(":") else { return false }

        // Reject invalid characters
        let validChars = CharacterSet(charactersIn: "0123456789abcdefABCDEF:.")
        guard addr.unicodeScalars.allSatisfy({ validChars.contains($0) }) else {
            return false
        }

        // Must have at least 2 colons for compressed form (::1)
        // or 7 colons for full form (2001:db8::1)
        let colonCount = addr.components(separatedBy: ":").count - 1
        guard colonCount >= 2 else { return false }

        return true
    }

    /// Fetch shards from multiple validators concurrently
    ///
    /// **Note**: This is a simplified implementation. For production use with shard
    /// assignment and controlled concurrency, use `AvailabilityNetworkClient.fetchFromValidatorsConcurrently`
    /// which has the optimized implementation with JAMNP-S shard assignment logic.
    ///
    /// - Parameters:
    ///   - validatorIndices: The validators to fetch from
    ///   - shardRequest: The shard request data
    /// - Returns: The collected shard responses
    /// - Throws: DataAvailabilityError if insufficient validators respond
    public func fetchFromValidatorsConcurrently(
        validators validatorIndices: [ValidatorIndex],
        shardRequest: Data
    ) async throws -> [(validator: ValidatorIndex, data: Data)] {
        // Fetch from validators concurrently with timeout
        // We need at least minimumValidatorResponses validators to respond for successful reconstruction
        let requiredResponses = DataAvailabilityConstants.minimumValidatorResponses

        logger.debug("Fetching from \(validatorIndices.count) validators concurrently (need \(requiredResponses) responses)")

        var responses: [(validator: ValidatorIndex, data: Data)] = []

        await withTaskGroup(of: (ValidatorIndex, Data?).self) { group in
            for validator in validatorIndices {
                group.addTask { [weak self] in
                    guard let self else {
                        return (validator, nil)
                    }
                    do {
                        let data = try await fetchFromValidator(validator: validator, requestData: shardRequest)
                        return (validator, data)
                    } catch {
                        logger.warning("Failed to fetch from validator \(validator): \(error)")
                        return (validator, nil)
                    }
                }
            }

            for await (validator, data) in group {
                if let data {
                    responses.append((validator, data))
                    logger.debug("Received response from validator \(validator) (\(responses.count)/\(requiredResponses))")

                    // Early exit if we have enough responses
                    if responses.count >= requiredResponses {
                        group.cancelAll()
                        break
                    }
                }
            }
        }

        guard responses.count >= requiredResponses else {
            logger.error("Insufficient validator responses: \(responses.count)/\(requiredResponses)")
            throw DataAvailabilityError.retrievalError
        }

        logger.info("Successfully fetched data from \(responses.count) validators")
        return responses
    }
}
