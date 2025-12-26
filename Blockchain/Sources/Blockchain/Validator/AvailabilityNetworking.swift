import Foundation
import TracingUtils
import Utils

private let logger = Logger(label: "AvailabilityNetworking")

// MARK: - Network Protocol Messages for JAMNP-S CE 137/138/139/140/147/148

/// Shard request message for JAMNP-S protocols CE 137/138/139/140
///
/// Wire format:
/// - Erasure-Root (32 bytes)
/// - Shard Index (u16)
/// - [Segment Index] (optional, for CE 139/140)
public struct ShardRequest: Codable, Sendable {
    public let erasureRoot: Data32
    public let shardIndex: UInt16
    public let segmentIndices: [UInt16]?

    public init(erasureRoot: Data32, shardIndex: UInt16, segmentIndices: [UInt16]? = nil) {
        self.erasureRoot = erasureRoot
        self.shardIndex = shardIndex
        self.segmentIndices = segmentIndices
    }

    /// Encode request to wire format
    public func encode() throws -> Data {
        var data = Data()
        data.append(erasureRoot.data)
        data.append(withUnsafeBytes(of: shardIndex.littleEndian) { Data($0) })

        if let indices = segmentIndices {
            // Length prefix (u32)
            let count = UInt32(indices.count)
            data.append(withUnsafeBytes(of: count.littleEndian) { Data($0) })

            // Segment indices
            for index in indices {
                data.append(withUnsafeBytes(of: index.littleEndian) { Data($0) })
            }
        }

        return data
    }

    /// Decode request from wire format
    public static func decode(_ data: Data) throws -> ShardRequest {
        guard data.count >= 34 else {
            throw AvailabilityNetworkingError.invalidMessageLength(
                expected: 34,
                actual: data.count
            )
        }

        let erasureRoot = Data32(data[0 ..< 32])
        let shardIndex = data.withUnsafeBytes { $0.load(fromByteOffset: 32, as: UInt16.self).littleEndian }

        var segmentIndices: [UInt16]?
        var offset = 34

        if data.count > 34 {
            // Has segment indices
            guard data.count >= 38 else {
                throw AvailabilityNetworkingError.invalidMessageLength(
                    expected: 38,
                    actual: data.count
                )
            }

            let count = data.withUnsafeBytes { $0.load(fromByteOffset: 34, as: UInt32.self).littleEndian }
            offset = 38

            guard data.count >= offset + Int(count) * 2 else {
                throw AvailabilityNetworkingError.invalidMessageLength(
                    expected: offset + Int(count) * 2,
                    actual: data.count
                )
            }

            var indices: [UInt16] = []
            indices.reserveCapacity(Int(count))

            for _ in 0 ..< count {
                let index = data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: UInt16.self).littleEndian }
                indices.append(index)
                offset += 2
            }

            segmentIndices = indices
        }

        return ShardRequest(
            erasureRoot: erasureRoot,
            shardIndex: shardIndex,
            segmentIndices: segmentIndices
        )
    }
}

/// Shard response message for JAMNP-S protocols CE 137/138/139/140
///
/// Wire format:
/// - Bundle Shard (variable)
/// - [Segment Shard] (variable, optional for CE 138)
/// - AvailabilityJustification (variable)
public struct ShardResponse: Codable, Sendable {
    public let bundleShard: Data
    public let segmentShards: [Data]
    public let justification: AvailabilityJustification

    public init(bundleShard: Data, segmentShards: [Data], justification: AvailabilityJustification) {
        self.bundleShard = bundleShard
        self.segmentShards = segmentShards
        self.justification = justification
    }

    /// Encode response to wire format
    public func encode() throws -> Data {
        var data = Data()

        // Bundle shard with length prefix
        let bundleLength = UInt32(bundleShard.count)
        data.append(withUnsafeBytes(of: bundleLength.littleEndian) { Data($0) })
        data.append(bundleShard)

        // Segment shards count
        let segmentCount = UInt32(segmentShards.count)
        data.append(withUnsafeBytes(of: segmentCount.littleEndian) { Data($0) })

        // Each segment shard with length prefix
        for shard in segmentShards {
            let shardLength = UInt32(shard.count)
            data.append(withUnsafeBytes(of: shardLength.littleEndian) { Data($0) })
            data.append(shard)
        }

        // AvailabilityJustification
        try data.append(justification.encode())

        return data
    }

    /// Decode response from wire format
    public static func decode(_ data: Data) throws -> ShardResponse {
        guard data.count >= 4 else {
            throw AvailabilityNetworkingError.invalidMessageLength(
                expected: 4,
                actual: data.count
            )
        }

        var offset = 0

        // Bundle shard length
        let bundleLength = data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: UInt32.self).littleEndian }
        offset += 4

        guard data.count >= offset + Int(bundleLength) else {
            throw AvailabilityNetworkingError.invalidMessageLength(
                expected: offset + Int(bundleLength),
                actual: data.count
            )
        }

        let bundleShard = Data(data[offset ..< offset + Int(bundleLength)])
        offset += Int(bundleLength)

        // Segment count
        guard data.count >= offset + 4 else {
            throw AvailabilityNetworkingError.invalidMessageLength(
                expected: offset + 4,
                actual: data.count
            )
        }

        let segmentCount = data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: UInt32.self).littleEndian }
        offset += 4

        var segmentShards: [Data] = []
        segmentShards.reserveCapacity(Int(segmentCount))

        for _ in 0 ..< segmentCount {
            guard data.count >= offset + 4 else {
                throw AvailabilityNetworkingError.invalidMessageLength(
                    expected: offset + 4,
                    actual: data.count
                )
            }

            let shardLength = data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: UInt32.self).littleEndian }
            offset += 4

            guard data.count >= offset + Int(shardLength) else {
                throw AvailabilityNetworkingError.invalidMessageLength(
                    expected: offset + Int(shardLength),
                    actual: data.count
                )
            }

            let shard = Data(data[offset ..< offset + Int(shardLength)])
            segmentShards.append(shard)
            offset += Int(shardLength)
        }

        // AvailabilityJustification
        let justification = try AvailabilityJustification.decode(Data(data[offset ..< data.count]))

        return ShardResponse(
            bundleShard: bundleShard,
            segmentShards: segmentShards,
            justification: justification
        )
    }
}

/// Merkle proof justification for JAMNP-S protocols
///
/// Per JAMNP-S spec, AvailabilityJustification = [0 ++ Hash OR 1 ++ Hash ++ Hash OR 2 ++ Segment Shard]
/// Each discriminator is a single byte
public enum AvailabilityJustification: Codable, Sendable {
    /// 0 ++ Hash - Leaf node, no sibling needed
    case leaf

    /// 1 ++ Hash ++ Hash - Branch node with left and right siblings
    case branch(left: Data32, right: Data32)

    /// 2 ++ Segment Shard - Actual segment shard data
    case segmentShard(Data)

    /// Co-path sequence for multi-level proofs
    case copath([AvailabilityJustificationStep])

    public enum AvailabilityJustificationStep: Codable, Sendable {
        case left(Data32) // Sibling on the left
        case right(Data32) // Sibling on the right
    }

    /// Encode justification to wire format
    public func encode() throws -> Data {
        var data = Data()

        switch self {
        case .leaf:
            // Discriminator 0
            data.append(UInt8(0))

        case let .branch(left, right):
            // Discriminator 1
            data.append(UInt8(1))
            data.append(left.data)
            data.append(right.data)

        case let .segmentShard(shard):
            // Discriminator 2
            data.append(UInt8(2))
            // Length prefix
            let length = UInt32(shard.count)
            data.append(withUnsafeBytes(of: length.littleEndian) { Data($0) })
            data.append(shard)

        case let .copath(steps):
            // Encode as sequence of steps
            for step in steps {
                switch step {
                case let .left(hash):
                    data.append(UInt8(0))
                    data.append(hash.data)
                case let .right(hash):
                    data.append(UInt8(1))
                    data.append(hash.data)
                }
            }
        }

        return data
    }

    /// Decode justification from wire format
    public static func decode(_ data: Data) throws -> AvailabilityJustification {
        guard !data.isEmpty else {
            throw AvailabilityNetworkingError.invalidAvailabilityJustification
        }

        let discriminator = data[0]

        switch discriminator {
        case 0:
            // Leaf
            return .leaf

        case 1:
            // Branch: 1 ++ Hash ++ Hash
            guard data.count == 1 + 32 + 32 else {
                throw AvailabilityNetworkingError.invalidAvailabilityJustification
            }
            let left = Data32(data[1 ..< 33])
            let right = Data32(data[33 ..< 65])
            return .branch(left: left, right: right)

        case 2:
            // Segment Shard: 2 ++ length ++ data
            guard data.count >= 5 else {
                throw AvailabilityNetworkingError.invalidAvailabilityJustification
            }
            let length = data.withUnsafeBytes { $0.load(fromByteOffset: 1, as: UInt32.self).littleEndian }
            let expectedLength = 1 + 4 + Int(length)
            guard data.count >= expectedLength else {
                throw AvailabilityNetworkingError.invalidAvailabilityJustification
            }
            let shard = Data(data[5 ..< 5 + Int(length)])
            return .segmentShard(shard)

        default:
            // Co-path sequence
            var steps: [AvailabilityJustificationStep] = []
            var offset = 0

            while offset < data.count {
                let disc = data[offset]
                offset += 1

                guard offset + 32 <= data.count else {
                    throw AvailabilityNetworkingError.invalidAvailabilityJustification
                }

                let hash = Data32(data[offset ..< offset + 32])
                offset += 32

                if disc == 0 {
                    steps.append(.left(hash))
                } else if disc == 1 {
                    steps.append(.right(hash))
                } else {
                    throw AvailabilityNetworkingError.invalidAvailabilityJustification
                }
            }

            return .copath(steps)
        }
    }
}

/// Bundle request for JAMNP-S protocol CE 147
public struct BundleRequest: Codable, Sendable {
    public let erasureRoot: Data32

    public init(erasureRoot: Data32) {
        self.erasureRoot = erasureRoot
    }

    public func encode() -> Data {
        erasureRoot.data
    }

    public static func decode(_ data: Data) throws -> BundleRequest {
        guard data.count == 32 else {
            throw AvailabilityNetworkingError.invalidMessageLength(
                expected: 32,
                actual: data.count
            )
        }
        return BundleRequest(erasureRoot: Data32(data))
    }
}

/// Bundle response for JAMNP-S protocol CE 147
public struct BundleResponse: Codable, Sendable {
    public let bundle: Data

    public init(bundle: Data) {
        self.bundle = bundle
    }

    public func encode() throws -> Data {
        var data = Data()
        let length = UInt32(bundle.count)
        data.append(withUnsafeBytes(of: length.littleEndian) { Data($0) })
        data.append(bundle)
        return data
    }

    public static func decode(_ data: Data) throws -> BundleResponse {
        guard data.count >= 4 else {
            throw AvailabilityNetworkingError.invalidMessageLength(
                expected: 4,
                actual: data.count
            )
        }

        let length = data.withUnsafeBytes { $0.load(fromByteOffset: 0, as: UInt32.self).littleEndian }
        guard data.count >= 4 + Int(length) else {
            throw AvailabilityNetworkingError.invalidMessageLength(
                expected: 4 + Int(length),
                actual: data.count
            )
        }

        let bundle = Data(data[4 ..< 4 + Int(length)])
        return BundleResponse(bundle: bundle)
    }
}

/// Segment request for JAMNP-S protocol CE 148
public struct SegmentRequest: Codable, Sendable {
    public let segmentsRoot: Data32
    public let segmentIndices: [UInt16]

    public init(segmentsRoot: Data32, segmentIndices: [UInt16]) {
        self.segmentsRoot = segmentsRoot
        self.segmentIndices = segmentIndices
    }

    public func encode() throws -> Data {
        var data = Data()
        data.append(segmentsRoot.data)

        // Length prefix
        let count = UInt32(segmentIndices.count)
        data.append(withUnsafeBytes(of: count.littleEndian) { Data($0) })

        // Indices
        for index in segmentIndices {
            data.append(withUnsafeBytes(of: index.littleEndian) { Data($0) })
        }

        return data
    }

    public static func decode(_ data: Data) throws -> SegmentRequest {
        guard data.count >= 36 else {
            throw AvailabilityNetworkingError.invalidMessageLength(
                expected: 36,
                actual: data.count
            )
        }

        let segmentsRoot = Data32(data[0 ..< 32])
        let count = data.withUnsafeBytes { $0.load(fromByteOffset: 32, as: UInt32.self).littleEndian }

        let expectedLength = 36 + Int(count) * 2
        guard data.count >= expectedLength else {
            throw AvailabilityNetworkingError.invalidMessageLength(
                expected: expectedLength,
                actual: data.count
            )
        }

        var indices: [UInt16] = []
        indices.reserveCapacity(Int(count))
        var offset = 36

        for _ in 0 ..< count {
            let index = data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: UInt16.self).littleEndian }
            indices.append(index)
            offset += 2
        }

        return SegmentRequest(segmentsRoot: segmentsRoot, segmentIndices: indices)
    }
}

/// Segment response for JAMNP-S protocol CE 148
public struct SegmentResponse: Codable, Sendable {
    public let segments: [Data4104]
    public let importProofs: [[Data32]]

    public init(segments: [Data4104], importProofs: [[Data32]]) {
        self.segments = segments
        self.importProofs = importProofs
    }

    public func encode() throws -> Data {
        var data = Data()

        // Segment count
        let count = UInt32(segments.count)
        data.append(withUnsafeBytes(of: count.littleEndian) { Data($0) })

        // Each segment
        for segment in segments {
            data.append(segment.data)
        }

        // Import proofs
        for proof in importProofs {
            // Proof length
            let proofLength = UInt32(proof.count)
            data.append(withUnsafeBytes(of: proofLength.littleEndian) { Data($0) })

            // Each hash in proof
            for hash in proof {
                data.append(hash.data)
            }
        }

        return data
    }

    public static func decode(_ data: Data) throws -> SegmentResponse {
        guard data.count >= 4 else {
            throw AvailabilityNetworkingError.invalidMessageLength(
                expected: 4,
                actual: data.count
            )
        }

        var offset = 0

        // Segment count
        let count = data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: UInt32.self).littleEndian }
        offset += 4

        let expectedSegmentsLength = offset + Int(count) * 4104
        guard data.count >= expectedSegmentsLength else {
            throw AvailabilityNetworkingError.invalidMessageLength(
                expected: expectedSegmentsLength,
                actual: data.count
            )
        }

        var segments: [Data4104] = []
        segments.reserveCapacity(Int(count))

        for _ in 0 ..< count {
            let segmentData = Data(data[offset ..< offset + 4104])
            guard let segment = Data4104(segmentData) else {
                throw AvailabilityNetworkingError.invalidSegmentLength
            }
            segments.append(segment)
            offset += 4104
        }

        var importProofs: [[Data32]] = []

        while offset < data.count {
            guard offset + 4 <= data.count else {
                break
            }

            let proofLength = data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: UInt32.self).littleEndian }
            offset += 4

            let expectedProofLength = offset + Int(proofLength) * 32
            guard data.count >= expectedProofLength else {
                throw AvailabilityNetworkingError.invalidMessageLength(
                    expected: expectedProofLength,
                    actual: data.count
                )
            }

            var proof: [Data32] = []
            proof.reserveCapacity(Int(proofLength))

            for _ in 0 ..< proofLength {
                let hash = Data32(data[offset ..< offset + 32])
                proof.append(hash)
                offset += 32
            }

            importProofs.append(proof)
        }

        return SegmentResponse(segments: segments, importProofs: importProofs)
    }
}

// MARK: - Errors

public enum AvailabilityNetworkingError: Error {
    case invalidMessageLength(expected: Int, actual: Int)
    case invalidAvailabilityJustification
    case invalidSegmentLength
    case encodingFailed
    case decodingFailed
    case peerManagerUnavailable
    case unsupportedProtocol
}

// MARK: - Protocol Request Types

/// Request type discriminator for different JAMNP-S protocols
public enum ShardRequestType: UInt8, Sendable {
    /// CE 138: Audit shard request (single bundle shard)
    case auditShard = 138

    /// CE 139: Segment shards without justification
    case segmentShardsFast = 139

    /// CE 140: Segment shards with justification
    case segmentShardsVerified = 140

    /// CE 147: Full bundle request
    case fullBundle = 147

    /// CE 148: Reconstructed segments
    case reconstructedSegments = 148
}

/// Node role for routing requests per JAMNP-S spec
public enum NodeRole: UInt8, Sendable {
    case auditor = 0
    case guarantor = 1
    case assurer = 2
    case builder = 3
}

// MARK: - Message Size Limits

/// Message size limits per JAMNP-S specification
public enum MessageSizeLimits {
    /// Maximum message size for shard responses (1 MB)
    public static let maxShardResponseSize = 1024 * 1024

    /// Maximum segment shards per CE 139/140 stream (2 * W_M, where W_M = 3072)
    public static let maxSegmentShardsPerStream = 2 * 3072

    /// Maximum segments per CE 148 stream (W_M = 3072)
    public static let maxSegmentsPerStream = 3072

    /// Maximum batch size for concurrent requests
    public static let maxConcurrentRequests = 100
}
