import Blockchain
import Codec
import Foundation
import Testing
import Utils

@testable import JAMTests

struct ErasureCodingTestcase: Codable {
    let data: Data
    let shards: [Data]
}

struct ErasureTests {
    static func loadTests(variant: TestVariants) throws -> [Testcase] {
        try TestLoader.getTestcases(path: "erasure/\(variant)", extension: "bin")
    }

    func erasureTests(_ testcase: Testcase, variant: TestVariants) throws {
        let config = variant.config
        let decoder = JamDecoder(data: testcase.data, config: config)
        let testcase = try decoder.decode(ErasureCodingTestcase.self)

        let basicSize = config.value.erasureCodedPieceSize
        let recoveryCount = config.value.totalNumberOfValidators
        let originalCount = basicSize / 2

        let actualShards = try ErasureCoding.chunk(
            data: testcase.data,
            basicSize: basicSize,
            recoveryCount: recoveryCount
        )

        #expect(actualShards.count == testcase.shards.count, "Shard count mismatch")

        for (index, (actual, expected)) in zip(actualShards, testcase.shards).enumerated() {
            #expect(actual == expected, "Shard \(index) data mismatch")
        }

        let shards = actualShards.enumerated().map { index, data in
            ErasureCoding.Shard(data: data, index: UInt32(index))
        }

        let reconstructedData = try ErasureCoding.reconstruct(
            shards: Array(shards.prefix(originalCount)),
            basicSize: basicSize,
            originalCount: originalCount,
            recoveryCount: recoveryCount,
        )

        #expect(reconstructedData == testcase.data, "Reconstructed data does not match original")
    }

    @Test(arguments: try ErasureTests.loadTests(variant: .tiny))
    func tinyTests(_ testcase: Testcase) throws {
        withKnownIssue("TODO: test does not match GP", isIntermittent: true) {
            try erasureTests(testcase, variant: .tiny)
        }
    }

    @Test(arguments: try ErasureTests.loadTests(variant: .full))
    func fullTests(_ testcase: Testcase) throws {
        withKnownIssue("TODO: test does not match GP", isIntermittent: true) {
            try erasureTests(testcase, variant: .full)
        }
    }
}
