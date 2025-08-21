import Blockchain
import Codec
import Foundation
import Utils

/// Protocol for generating fuzzing test data
public protocol FuzzGenerator {
    /// Generate initial pre-state for fuzzing
    /// - Parameters:
    ///   - timeslot: The timeslot for which to generate the state
    ///   - config: Protocol configuration
    /// - Returns: Tuple containing state root and array of fuzz key-value pairs representing the pre-state
    func generatePreState(timeslot: TimeslotIndex, config: ProtocolConfigRef) async throws
        -> (stateRoot: Data32, keyValues: [FuzzKeyValue])

    /// Generate expected post-state after block execution
    /// - Parameters:
    ///   - timeslot: The timeslot for which to generate the state
    ///   - config: Protocol configuration
    /// - Returns: Tuple containing state root and array of fuzz key-value pairs representing the expected post-state
    func generatePostState(timeslot: TimeslotIndex, config: ProtocolConfigRef) async throws
        -> (stateRoot: Data32, keyValues: [FuzzKeyValue])

    /// Generate a block for the given timeslot and state
    /// - Parameters:
    ///   - timeslot: The timeslot for which to generate the block
    ///   - currentStateRef: Current state reference
    ///   - config: Protocol configuration
    /// - Returns: A valid block reference
    func generateBlock(timeslot: UInt32, currentStateRef: StateRef, config: ProtocolConfigRef) async throws -> BlockRef
}

/// Error types for fuzz generators
public enum FuzzGeneratorError: Error {
    case stateGenerationFailed(String)
    case blockGenerationFailed(String)
    case invalidTestData(String)
}
