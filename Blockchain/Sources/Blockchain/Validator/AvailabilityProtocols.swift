import Foundation
import Networking
import Utils

// MARK: - Protocol Abstractions for Networking Types

/// Protocol for shard distribution requests (CE 137)
/// Allows Blockchain to handle requests without depending on Node module
public protocol ShardDistributionRequestProtocol {
    var erasureRoot: Data32 { get }
    var shardIndex: UInt16 { get }
}

/// Protocol for audit shard requests (CE 138)
public protocol AuditShardRequestProtocol {
    var erasureRoot: Data32 { get }
    var shardIndex: UInt16 { get }
}

/// Protocol for segment shard requests (CE 146/147/148)
public protocol SegmentShardRequestProtocol {
    var erasureRoot: Data32 { get }
    var shardIndex: UInt16 { get }
    var segmentIndices: [UInt16] { get }
}

/// Protocol for segment requests (CE 148)
public protocol SegmentRequestProtocol {
    var segmentsRoot: Data32 { get }
    var segmentIndices: [UInt16] { get }
}

// MARK: - Simple Request Implementations

/// Simple implementation of shard distribution request for internal use
public struct SimpleShardDistributionRequest: ShardDistributionRequestProtocol, Sendable {
    public let erasureRoot: Data32
    public let shardIndex: UInt16

    public init(erasureRoot: Data32, shardIndex: UInt16) {
        self.erasureRoot = erasureRoot
        self.shardIndex = shardIndex
    }
}

/// Simple implementation of audit shard request for internal use
public struct SimpleAuditShardRequest: AuditShardRequestProtocol, Sendable {
    public let erasureRoot: Data32
    public let shardIndex: UInt16

    public init(erasureRoot: Data32, shardIndex: UInt16) {
        self.erasureRoot = erasureRoot
        self.shardIndex = shardIndex
    }
}

/// Simple implementation of segment shard request for internal use
public struct SimpleSegmentShardRequest: SegmentShardRequestProtocol, Sendable {
    public let erasureRoot: Data32
    public let shardIndex: UInt16
    public let segmentIndices: [UInt16]

    public init(erasureRoot: Data32, shardIndex: UInt16, segmentIndices: [UInt16]) {
        self.erasureRoot = erasureRoot
        self.shardIndex = shardIndex
        self.segmentIndices = segmentIndices
    }
}

/// Simple implementation of segment request for internal use
public struct SimpleSegmentRequest: SegmentRequestProtocol, Sendable {
    public let segmentsRoot: Data32
    public let segmentIndices: [UInt16]

    public init(segmentsRoot: Data32, segmentIndices: [UInt16]) {
        self.segmentsRoot = segmentsRoot
        self.segmentIndices = segmentIndices
    }
}
