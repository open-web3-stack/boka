import erasure_coding
import Foundation
import Testing

@testable import Utils

func createShards(from data: Data, count: Int) -> [Data] {
    let shardSize = (data.count + count - 1) / count

    var shards = [Data]()
    for i in 0 ..< count {
        let startIndex = i * shardSize
        let endIndex = min(startIndex + shardSize, data.count)
        if startIndex < data.count {
            var shard = data[startIndex ..< endIndex]
            if shard.count < shardSize {
                shard.append(Data(count: shardSize - shard.count))
            }
            shards.append(shard)
        }
    }
    return shards
}

@Suite struct ErasureCodingUnitTests {
    @Test(arguments: [
        (64, 4, 6),
        (100, 5, 10),
        (512, 8, 10),
        (1024, 8, 14),
        (4096, 12, 20),
    ] as [(Int, Int, Int)])
    func testEncodeRecover(testCase: (Int, Int, Int)) throws {
        let dataLength = testCase.0
        let originalCount = testCase.1
        let recoveryCount = testCase.2
        let shardSize = (dataLength + originalCount - 1) / originalCount

        let originalData = Data((0 ..< dataLength).map { UInt8(($0 * 15) % 256) })

        let original = createShards(from: originalData, count: originalCount)

        let recovery = try ErasureCoding.encode(original: original, recoveryCount: recoveryCount)

        #expect(recovery.count == recoveryCount)

        var partialRecovery = [ErasureCoding.InnerShard]()

        for i in recoveryCount - originalCount ..< recoveryCount {
            try partialRecovery.append(.init(data: recovery[i], index: UInt32(i)))
        }

        let recoveredShards = try ErasureCoding.recover(
            originalCount: originalCount,
            recoveryCount: recoveryCount,
            recovery: partialRecovery,
            shardSize: shardSize
        )

        let recoveredData = recoveredShards.reduce(Data(), +)

        #expect(recoveredData == originalData)
    }

    @Test func testNotEnoughShardsToRecover() throws {
        let dataLength = 100
        let originalCount = 5
        let recoveryCount = 8
        let shardSize = (dataLength + originalCount - 1) / originalCount

        let originalData = Data((0 ..< dataLength).map { UInt8(($0 * 17) % 256) })

        let original = createShards(from: originalData, count: originalCount)

        let recovery = try ErasureCoding.encode(original: original, recoveryCount: recoveryCount)

        var partialRecovery = [ErasureCoding.InnerShard]()

        for i in 0 ..< 2 {
            try partialRecovery.append(.init(data: recovery[i], index: UInt32(i)))
        }

        #expect(throws: ErasureCoding.Error.recoveryFailed(4)) {
            _ = try ErasureCoding.recover(
                originalCount: originalCount,
                recoveryCount: recoveryCount,
                recovery: partialRecovery,
                shardSize: shardSize
            )
        }
    }

    @Test func testSplitJoin() throws {
        let testData = Data("hello world, this is a test".utf8)
        let n = 4

        let split = ErasureCoding.split(data: testData, n: n)
        let joined = ErasureCoding.join(arr: split, n: n)

        var paddedData = testData
        let remainder = paddedData.count % n
        if remainder != 0 {
            paddedData.append(Data(repeating: 0, count: n - remainder))
        }

        #expect(joined == paddedData)
    }

    @Test func testUnzipLace() throws {
        let testData = Data("hello world, this is a test".utf8)
        let n = 4

        let unzipped = ErasureCoding.unzip(data: testData, n: n)
        let laced = ErasureCoding.lace(arr: unzipped, n: n)

        var lacedPadded = testData
        let remainder = lacedPadded.count % n
        if remainder != 0 {
            lacedPadded.append(Data(repeating: 0, count: n - remainder))
        }

        #expect(laced == lacedPadded)
    }

    @Test func testTranspose() throws {
        let testData = [
            [1, 2, 3, 4],
            [5, 6, 7, 8],
            [9, 10, 11, 12],
            [13, 14, 15, 16],
        ]

        let transposed = ErasureCoding.transpose(testData)
        let transposedBack = ErasureCoding.transpose(transposed)

        #expect(testData == transposedBack)
    }

    @Test(arguments: [
        // (64, 4, 9),
        // (512, 8, 10),
        // (1024, 8, 14),
        // (4104, 4, 6), // tiny
        // (4104, 8, 12), // small
        (300, 12, 16),
        // (300, 8, 16),
        // (4104, 12, 18), // medium
        // (4104, 684, 1023), // full
    ] as [(Int, Int, Int)])
    func testChunkReconstruct(testCase: (Int, Int, Int)) throws {
        let dataLength = testCase.0
        let originalCount = testCase.1
        let recoveryCount = testCase.2

        let originalData = Data((0 ..< dataLength).map { UInt8(($0 * 15) % 256) })

        let recovery = try ErasureCoding.chunk(data: originalData, originalCount: originalCount, recoveryCount: recoveryCount)

        #expect(recovery.count == recoveryCount)

        var partialRecovery = [ErasureCoding.Shard]()

        for i in recoveryCount - originalCount ..< recoveryCount {
            partialRecovery.append(.init(data: recovery[i], index: UInt32(i)))
        }

        let recovered = try ErasureCoding.reconstruct(
            shards: partialRecovery, originalCount: originalCount, recoveryCount: recoveryCount
        )

        #expect(recovered == originalData)
    }
}

@Suite struct ErasureCodingWithTestData {
    struct ECTestCase: Codable {
        let data: String
        let segment: ECSegment
    }

    struct ECSegment: Codable {
        let segments: [SegmentElement]
    }

    struct SegmentElement: Codable {
        let segmentEc: [String]

        enum CodingKeys: String, CodingKey {
            case segmentEc = "segment_ec"
        }
    }

    enum TestLoader {
        static func getTestFiles(path: String, extension ext: String) throws -> [(path: String, description: String)] {
            let prefix = Bundle.module.resourcePath! + "/TestData/\(path)"
            let files = try FileManager.default.contentsOfDirectory(atPath: prefix)
            var filtered = files.filter { $0.hasSuffix(".\(ext)") }
            filtered.sort()
            return filtered.map { (path: prefix + "/" + $0, description: $0) }
        }
    }

    static func loadTests() throws -> [ECTestCase] {
        let tests = try TestLoader.getTestFiles(path: "ec", extension: "json")
        return try tests.map {
            let data = try Data(contentsOf: URL(fileURLWithPath: $0.path))
            let decoder = JSONDecoder()
            return try decoder.decode(ECTestCase.self, from: data)
        }
    }

    // TODO: figure out how to reconstruct test data

    // @Test(arguments: try loadTests())
    // func testReconstruct(testCase: ECTestCase) throws {
    //     let data = Data(fromHexString: testCase.data)!
    //     let recovery = testCase.segment.segments.map(\.segmentEc)[0].map { Data(fromHexString: $0)! }
    //     let originalCount = 684
    //     let recoveryCount = 1026
    //     var partialRecovery = [ErasureCoding.Shard]()

    //     for i in recoveryCount - originalCount ..< recoveryCount {
    //         partialRecovery.append(.init(data: recovery[i], index: UInt32(i)))
    //     }

    //     let recovered = try ErasureCoding.reconstruct(
    //         shards: partialRecovery,
    //         originalCount: originalCount,
    //         recoveryCount: recoveryCount
    //     )

    //     #expect(recovered == data)
    // }
}
