import Utils

enum DataStoreError: Error {
    case invalidPackageHash(Data32)
    case invalidSegmentRoot(Data32)
}

public final class DataStore: Sendable {
    private let impl: DataStoreProtocol
    private let network: DataStoreNetworkProtocol

    public init(_ impl: DataStoreProtocol, _ network: DataStoreNetworkProtocol) {
        self.impl = impl
        self.network = network
    }

    public func fetchSegment(segments: [WorkItem.ImportedDataSegment]) async throws -> [Data4104] {
        var result: [Data4104] = []

        for segment in segments {
            let segmentRoot = switch segment.root {
            case let .segmentRoot(root):
                root
            case let .workPackageHash(hash):
                try await impl.getSegmentRoot(forWorkPackageHash: hash).unwrap(orError: DataStoreError.invalidPackageHash(hash))
            }
            let erasureRoot = try await impl.getEasureRoot(forSegmentRoot: segmentRoot)
                .unwrap(orError: DataStoreError.invalidSegmentRoot(segmentRoot))

            if let localData = try await impl.get(erasureRoot: erasureRoot, index: segment.index) {
                result.append(localData)
            } else {
                // TODO: use network for fetch shards and reconstruct the segment
                fatalError("not implemented")
            }
        }

        return result
    }

    public func set(data: Data4104, erasureRoot: Data32, index: UInt16) async throws {
        try await impl.set(data: data, erasureRoot: erasureRoot, index: index)

        // TODO; erasure code the data and store each chunk
        // so assurer can query them later with CE137
    }
}
