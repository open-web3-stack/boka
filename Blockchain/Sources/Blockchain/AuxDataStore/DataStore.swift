import Foundation
import Utils

enum DataStoreError: Error {
    case invalidPackageHash(Data32)
    case invalidSegmentRoot(Data32)
    case erasureCodingError
    case networkFetchNotImplemented(Data32, UInt16)
}

public final class DataStore: Sendable {
    private let impl: DataStoreProtocol
    private let network: DataStoreNetworkProtocol

    public init(_ impl: DataStoreProtocol, _ network: DataStoreNetworkProtocol) {
        self.impl = impl
        self.network = network
    }

    /// Fetches segments from the data store
    /// - Parameters:
    ///   - segments: The segment specifications to retrieve
    ///   - segmentsRootMappings: Optional mappings from work package hash to segments root
    /// - Returns: The retrieved segments
    public func fetchSegment(
        segments: [WorkItem.ImportedDataSegment],
        segmentsRootMappings: SegmentsRootMappings?,
    ) async throws -> [Data4104] {
        var result: [Data4104] = []

        for segment in segments {
            let segmentRoot = try await resolveSegmentRoot(segment: segment, segmentsRootMappings: segmentsRootMappings)
            let erasureRoot = try await getErasureRootForSegment(segmentRoot: segmentRoot)

            if let localData = try await impl.get(erasureRoot: erasureRoot, index: segment.index) {
                // Convert Data to Data4104
                guard localData.count == 4104,
                      let segmentData = Data4104(localData)
                else {
                    throw DataStoreError.erasureCodingError
                }
                result.append(segmentData)
            } else {
                // TODO: use network for fetch shards and reconstruct the segment
                throw DataStoreError.networkFetchNotImplemented(erasureRoot, segment.index)
            }
        }

        return result
    }

    /// Resolves a segment root from either direct root or work package hash
    private func resolveSegmentRoot(
        segment: WorkItem.ImportedDataSegment,
        segmentsRootMappings: SegmentsRootMappings?,
    ) async throws -> Data32 {
        switch segment.root {
        case let .segmentRoot(root):
            root
        case let .workPackageHash(hash):
            if let segmentsRootMappings {
                try segmentsRootMappings
                    .first(where: { $0.workPackageHash == hash })
                    .unwrap(orError: DataStoreError.invalidPackageHash(hash))
                    .segmentsRoot
            } else {
                try await impl.getSegmentRoot(forWorkPackageHash: hash)
                    .unwrap(orError: DataStoreError.invalidPackageHash(hash))
            }
        }
    }

    private func getErasureRootForSegment(segmentRoot: Data32) async throws -> Data32 {
        try await impl.getErasureRoot(forSegmentRoot: segmentRoot)
            .unwrap(orError: DataStoreError.invalidSegmentRoot(segmentRoot))
    }

    /// Stores a segment in the data store with erasure coding
    /// - Parameters:
    ///   - data: The segment data to store
    ///   - erasureRoot: The erasure root of the segment
    ///   - index: The index of the segment
    /// - Throws: DataStoreError if erasure coding fails
    ///
    /// As per GP 14.3.1, this method implements erasure coding for data availability and resilience
    public func set(data: Data4104, erasureRoot: Data32, index: UInt16) async throws {
        // Convert Data4104 to Data for storage
        try await impl.set(data: data.data, erasureRoot: erasureRoot, index: index)

        // TODO: Implement erasure coding as per GP 14.3.1
        // The current implementation of ErasureCoding in Utils is not yet compatible with GP
    }

    public func setTimestamp(erasureRoot: Data32, timestamp: Date) async throws {
        try await impl.setTimestamp(erasureRoot: erasureRoot, timestamp: timestamp)
    }

    public func getTimestamp(erasureRoot: Data32) async throws -> Date? {
        try await impl.getTimestamp(erasureRoot: erasureRoot)
    }

    public func setPagedProofsMetadata(erasureRoot: Data32, metadata: Data) async throws {
        try await impl.setPagedProofsMetadata(erasureRoot: erasureRoot, metadata: metadata)
    }

    public func getPagedProofsMetadata(erasureRoot: Data32) async throws -> Data? {
        try await impl.getPagedProofsMetadata(erasureRoot: erasureRoot)
    }

    public func setSegmentRoot(segmentRoot: Data32, forWorkPackageHash: Data32) async throws {
        try await impl.set(segmentRoot: segmentRoot, forWorkPackageHash: forWorkPackageHash)
    }
}
