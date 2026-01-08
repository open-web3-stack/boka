import Blockchain
import Codec
import Foundation
import Networking
import Utils

/// CE 146: Work-package bundle submission
///
/// Submission of a complete work-package bundle from a builder to a guarantor.
///
/// Note that the bundle parts are sent in separate messages to allow for authorizing
/// the work-package before reading the rest of the bundle.
///
/// Protocol:
/// ```
/// Builder -> Guarantor
/// --> Core Index ++ Segments-Root Mappings
/// --> Work-Package
/// --> [Extrinsic] (Message size should equal sum of extrinsic data lengths)
/// --> [Segment] (All imported segments)
/// --> [Import-Proof] (Import proofs for all imported segments)
/// --> FIN
/// <-- FIN
/// ```
public struct WorkPackageBundleSubmissionMessage: Codable, Sendable {
    public struct SegmentRootMapping: Codable, Sendable {
        public let workPackageHash: Data32
        public let segmentsRoot: Data32

        public init(workPackageHash: Data32, segmentsRoot: Data32) {
            self.workPackageHash = workPackageHash
            self.segmentsRoot = segmentsRoot
        }
    }

    /// Core index of the builder
    public let coreIndex: UInt16

    /// Mappings of work-package hashes to segments roots
    public let segmentsRootMappings: [SegmentRootMapping]

    /// The complete work-package
    public let workPackage: Data

    /// Extrinsics data (concatenated)
    public let extrinsics: Data

    /// All imported segments
    public let segments: [Data4104]

    /// Import proofs for all imported segments
    public let importProofs: [Data32]

    public init(
        coreIndex: UInt16,
        segmentsRootMappings: [SegmentRootMapping],
        workPackage: Data,
        extrinsics: Data,
        segments: [Data4104],
        importProofs: [Data32]
    ) {
        self.coreIndex = coreIndex
        self.segmentsRootMappings = segmentsRootMappings
        self.workPackage = workPackage
        self.extrinsics = extrinsics
        self.segments = segments
        self.importProofs = importProofs
    }
}

// MARK: - CE Message Protocol

extension WorkPackageBundleSubmissionMessage: CEMessage {
    public func encode() throws -> [Data] {
        var messages: [Data] = []

        // Message 1: Core Index ++ Segments-Root Mappings
        var encoder1 = JamEncoder()
        try encoder1.encode(coreIndex)
        try encoder1.encode(UInt32(segmentsRootMappings.count))
        for mapping in segmentsRootMappings {
            try encoder1.encode(mapping.workPackageHash)
            try encoder1.encode(mapping.segmentsRoot)
        }
        messages.append(encoder1.data)

        // Message 2: Work-Package
        messages.append(workPackage)

        // Message 3: [Extrinsic]
        messages.append(extrinsics)

        // Message 4: [Segment]
        var encoder4 = JamEncoder()
        try encoder4.encode(UInt32(segments.count))
        for segment in segments {
            try encoder4.encode(segment)
        }
        messages.append(encoder4.data)

        // Message 5: [Import-Proof]
        var encoder5 = JamEncoder()
        try encoder5.encode(UInt32(importProofs.count))
        for proof in importProofs {
            try encoder5.encode(proof)
        }
        messages.append(encoder5.data)

        return messages
    }

    public static func decode(data: [Data], config: ProtocolConfigRef) throws -> WorkPackageBundleSubmissionMessage {
        guard data.count == 5 else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: [],
                debugDescription: "Expected 5 messages, got \(data.count)"
            ))
        }

        // Decode message 1: Core Index ++ Segments-Root Mappings
        let decoder1 = JamDecoder(data: data[0], config: config)
        let coreIndex = try decoder1.decode(UInt16.self)
        let mappingsCount = try decoder1.decode(UInt32.self)
        var segmentsRootMappings: [SegmentRootMapping] = []
        for _ in 0 ..< mappingsCount {
            let workPackageHash = try decoder1.decode(Data32.self)
            let segmentsRoot = try decoder1.decode(Data32.self)
            segmentsRootMappings.append(SegmentRootMapping(
                workPackageHash: workPackageHash,
                segmentsRoot: segmentsRoot
            ))
        }

        // Message 2: Work-Package (raw data)
        let workPackage = data[1]

        // Message 3: [Extrinsic] (raw data)
        let extrinsics = data[2]

        // Decode message 4: [Segment]
        let decoder4 = JamDecoder(data: data[3], config: config)
        let segmentsCount = try decoder4.decode(UInt32.self)
        var segments: [Data4104] = []
        for _ in 0 ..< segmentsCount {
            let segment = try decoder4.decode(Data4104.self)
            segments.append(segment)
        }

        // Decode message 5: [Import-Proof]
        let decoder5 = JamDecoder(data: data[4], config: config)
        let proofsCount = try decoder5.decode(UInt32.self)
        var importProofs: [Data32] = []
        for _ in 0 ..< proofsCount {
            let proof = try decoder5.decode(Data32.self)
            importProofs.append(proof)
        }

        return WorkPackageBundleSubmissionMessage(
            coreIndex: coreIndex,
            segmentsRootMappings: segmentsRootMappings,
            workPackage: workPackage,
            extrinsics: extrinsics,
            segments: segments,
            importProofs: importProofs
        )
    }
}
