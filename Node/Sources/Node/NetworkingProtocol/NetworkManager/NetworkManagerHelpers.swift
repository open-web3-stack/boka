import Foundation
import TracingUtils

private let logger = Logger(label: "NetworkManagerHelpers")

// MARK: - Constants

public let MAX_BLOCKS_PER_REQUEST: UInt32 = 50

// MARK: - Enums

/// Target for broadcasting messages
public enum BroadcastTarget {
    case safroleStep1Validator
    case currentValidators
}

/// Network manager errors
public enum NetworkManagerError: Error {
    case peerNotFound
    case unimplemented(String)
}

// MARK: - Error Handling

/// Handle request errors with consistent logging and empty response
/// - Parameters:
///   - error: The error that occurred
///   - messageType: Description of the message type for logging
/// - Returns: Empty array to signal failure
public func handleRequestError(_ error: Error, messageType: String) -> [Data] {
    logger.error("\(messageType) failed: \(error)")
    return []
}
