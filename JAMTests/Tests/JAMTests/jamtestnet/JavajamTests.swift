import Blockchain
import Foundation
import Testing
import Utils

@testable import JAMTests

struct JavajamTests {
    @Test(arguments: try JamTestnet.loadTests(path: "stf/state_transitions", src: .javajam))
    func stfTests(_ input: Testcase) async throws {
        if input.description.starts(with: "3373062") { return } // problematic initial recent history

        try await TraceTest.test(input)
    }

    @Test(arguments: try JamTestnet.loadTests(path: "erasure_coding", src: .javajam, ext: "json"))
    func erasureCodingTests(_ input: Testcase) async throws {
        struct ECTestCase: Codable {
            let data: String
            let shards: [String]
        }

        let isTiny = input.description.contains("tiny")
        let config = isTiny ? TestVariants.tiny.config : TestVariants.full.config

        let decoder = JSONDecoder()
        let testCase = try decoder.decode(ECTestCase.self, from: input.data)

        let originalData = if testCase.data.hasPrefix("0x") {
            Data(fromHexString: String(testCase.data.dropFirst(2)))!
        } else {
            Data(fromHexString: testCase.data)!
        }

        let recoveryShards = testCase.shards.enumerated().map { index, hexString -> ErasureCoding.Shard in
            return .init(data: Data(fromHexString: hexString)!, index: UInt32(index))
        }

        let basicSize = config.value.erasureCodedPieceSize
        let originalCount = basicSize / 2
        let recoveryCount = config.value.totalNumberOfValidators

        #expect(recoveryShards.count == recoveryCount)

        withKnownIssue("TODO: does not match GP", isIntermittent: true) {
            let recoveredData = try ErasureCoding.reconstruct(
                shards: recoveryShards,
                basicSize: basicSize,
                originalCount: originalCount,
                recoveryCount: recoveryCount
            )

            #expect(recoveredData == originalData, "reconstructed data should match original data")

            let generatedShards = try ErasureCoding.chunk(
                data: originalData,
                basicSize: basicSize,
                recoveryCount: recoveryCount
            )

            #expect(generatedShards.count == recoveryCount, "should generate expected number of recovery shards")

            for (index, shard) in recoveryShards.enumerated() where index < generatedShards.count {
                #expect(generatedShards[index] == shard.data, "generated shard at index \(index) should match test data")
            }
        }
    }
}
