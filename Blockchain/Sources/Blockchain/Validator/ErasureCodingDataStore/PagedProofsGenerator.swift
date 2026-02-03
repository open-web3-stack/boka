import Codec
import Foundation
import Utils

/// Actor for generating Paged-Proofs metadata for D³L segments
///
/// Per GP spec (work_packages_and_reports.tex eq:pagedproofs):
/// Groups segments into pages of 64, generates Merkle justification paths
/// and subtree pages for efficient segment justification
public actor PagedProofsGenerator {
    private let config: ProtocolConfigRef

    public init(config: ProtocolConfigRef) {
        self.config = config
    }

    /// Generate Paged-Proofs metadata for exported segments
    ///
    /// - Parameter segments: Array of exported segments
    /// - Returns: Paged-Proofs metadata as Data
    public func generateMetadata(segments: [Data4104]) throws -> Data {
        guard !segments.isEmpty else {
            return Data()
        }

        // Per GP spec: Page size is 64 segments
        let pageSize = 64
        let pageCount = (segments.count + pageSize - 1) / pageSize

        // Calculate the segments root (constant-depth Merkle tree)
        let segmentsRoot = Merklization.constantDepthMerklize(segments.map(\.data))

        var pages: [Data] = []

        for pageIndex in 0 ..< pageCount {
            let startIdx = pageIndex * pageSize
            let endIdx = min(startIdx + pageSize, segments.count)
            let pageSegments = Array(segments[startIdx ..< endIdx])

            // For each page, generate:
            // 1. Merkle justification paths for each segment in the page (depth 6)
            // 2. Merkle subtree page for the page

            let pageMetadata = try generatePageMetadata(
                pageSegments: pageSegments,
                pageIndex: pageIndex,
                segmentsRoot: segmentsRoot,
                totalSegments: segments.count,
            )

            pages.append(pageMetadata)
        }

        // Encode pages using JamEncoder
        return try JamEncoder.encode(pageCount, segmentsRoot, pages)
    }

    /// Generate metadata for a single page of segments
    ///
    /// - Parameters:
    ///   - pageSegments: Segments in this page
    ///   - pageIndex: Index of the page
    ///   - segmentsRoot: Root of all segments
    ///   - totalSegments: Total number of segments
    /// - Returns: Page metadata as Data
    ///
    /// TODO: This method only generates Merkle proofs from segment to page root (depth 6).
    /// For complete verification, we need to also generate the path from page root to global root.
    /// This requires calculating the Merkle tree of all page roots and generating the co-path
    /// from this page's root to the global segmentsRoot. The current implementation only
    /// provides proofs valid within a page, not the complete proof to the global root.
    private func generatePageMetadata(
        pageSegments: [Data4104],
        pageIndex: Int,
        segmentsRoot _: Data32,
        totalSegments _: Int,
    ) throws -> Data {
        // Per GP spec: depth 6 for 64 segments per page
        let merkleDepth: UInt8 = 6

        // For each segment in the page, generate its Merkle justification path
        var justificationPaths: [[Data32]] = []
        for localIndex in pageSegments.indices {
            _ = pageIndex * 64 + localIndex

            // Generate Merkle proof path from segment to root
            let path = Merklization.trace(
                pageSegments.map(\.data),
                index: localIndex,
                hasher: Blake2b256.self,
            )

            // Convert PathElements to Data32 hashes
            var pathHashes: [Data32] = []
            for element in path {
                switch element {
                case let .left(data):
                    // Convert Data to Data32
                    guard let hash = Data32(data) else {
                        throw ErasureCodingStoreError.proofGenerationFailed
                    }
                    pathHashes.append(hash)
                case let .right(hash):
                    pathHashes.append(hash)
                }
            }

            justificationPaths.append(pathHashes)
        }

        // Calculate the Merkle subtree page for this page
        // This is a Merkle tree of the 64 segments in the page
        let pageHashes = pageSegments.map { $0.data.blake2b256hash() }
        let subtreeRoot = Merklization.binaryMerklize(pageHashes.map(\.data))

        // Encode page metadata:
        // - Merkle depth (6)
        // - Justification paths for each segment
        // - Subtree root
        return try JamEncoder.encode(
            merkleDepth,
            justificationPaths.count,
            justificationPaths,
            subtreeRoot,
        )
    }

    /// Verify a segment's Paged-Proofs justification
    ///
    /// - Parameters:
    ///   - segment: The segment to verify
    ///   - pageIndex: Page containing the segment
    ///   - localIndex: Index within the page
    ///   - proof: Merkle proof path
    ///   - segmentsRoot: Expected root
    /// - Returns: True if the segment is valid
    public func verifyProof(
        segment: Data4104,
        pageIndex: Int,
        localIndex: Int,
        proof: [Data32],
        segmentsRoot: Data32,
    ) -> Bool {
        // Calculate segment hash
        let segmentHash = segment.data.blake2b256hash()

        // Start with segment hash
        var currentValue = segmentHash

        // Traverse the Merkle proof
        for (level, proofElement) in proof.enumerated() {
            // Combine localIndex bits (levels 0-5) with pageIndex bits (levels 6+)
            // This creates the complete global index path through the Merkle tree
            let bitSet: Int = if level < 6 {
                // Levels 0-5: within page (64 segments per page)
                (localIndex >> level) & 1
            } else {
                // Levels 6+: across pages
                (pageIndex >> (level - 6)) & 1
            }

            if bitSet == 0 {
                // Current value is on the left
                let combined = currentValue.data + proofElement.data
                currentValue = combined.blake2b256hash()
            } else {
                // Current value is on the right
                let combined = proofElement.data + currentValue.data
                currentValue = combined.blake2b256hash()
            }
        }

        // Final value should match segmentsRoot
        return currentValue == segmentsRoot
    }
}
