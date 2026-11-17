@testable import Blockchain
import Foundation
import Testing
import Utils

struct WorkReportReconstructionTests {
    private func processor() -> WorkReportProcessor {
        let backend = InMemoryDataStoreBackend()
        return WorkReportProcessor(dataStore: DataStore(backend, backend), erasureCodingDataStore: nil, config: .dev)
    }

    @Test(arguments: [6, 9, 1023])
    func reconstructsFromRecoveryShardsUsingTheReportCount(validators: Int) async throws {
        let required = ErasureCodingService.originalShards(validators: validators)
        let width = 2 * required
        let data = Data((0 ..< width * 2).map { UInt8(truncatingIfNeeded: $0) })
        let encoded = try ErasureCoding.chunk(data: data, basicSize: width, recoveryCount: validators)
        // Use the last R shards, not the original systematic shard prefix.
        let shards = (validators - required ..< validators).map { (index: UInt16($0), data: encoded[$0]) }
        let result = try await processor().reconstructData(shards: shards, originalLength: data.count, validatorCount: validators)
        #expect(result == data)
        await #expect(throws: DataAvailabilityError.self) {
            try await processor().reconstructData(shards: Array(shards.dropLast()), originalLength: data.count, validatorCount: validators)
        }
    }

    @Test(arguments: [0, 5, 7, 1026])
    func rejectsInvalidCodingCounts(validators: Int) async throws {
        await #expect(throws: DataAvailabilityError.self) {
            try await processor().reconstructData(shards: [], originalLength: 1, validatorCount: validators)
        }
    }
}
