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
        (4, 2, 5),
        (16, 2, 5),
        (32, 2, 5),
        (64, 4, 6),
        (100, 5, 10),
        (312, 12, 16),
        (512, 8, 10),
        (1024, 8, 14),
        (4104, 12, 18),
    ] as [(Int, Int, Int)])
    func testEncodeRecover(testCase: (Int, Int, Int)) throws {
        let dataLength = testCase.0
        let originalCount = testCase.1
        let recoveryCount = testCase.2
        let shardSize = (dataLength + originalCount - 1) / originalCount

        let originalData = Data((0 ..< dataLength).map { UInt8(($0 * 15) % 256) })

        let originalShards = createShards(from: originalData, count: originalCount)

        let recovery = try ErasureCoding.encode(original: originalShards, recoveryCount: recoveryCount)

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
        let joined = ErasureCoding.join(arr: split)

        var paddedData = testData
        let remainder = paddedData.count % n
        if remainder != 0 {
            paddedData.append(Data(repeating: 0, count: n - remainder))
        }

        #expect(joined == paddedData)
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
        (12, 4, 5),
        (64, 4, 9),
        (36, 12, 16),
        (312, 12, 16),
        (512, 8, 10),
        (1024, 8, 14),
        (4104, 4, 6), // tiny
        (4104, 8, 12), // small
        (4104, 12, 18), // medium
        (4104, 684, 1023), // full
    ] as [(Int, Int, Int)])
    func testChunkReconstruct(testCase: (Int, Int, Int)) throws {
        let dataLength = testCase.0
        let basicSize = testCase.1
        let originalCount = basicSize / 2
        let recoveryCount = testCase.2

        let originalData = Data((0 ..< dataLength).map { UInt8(($0 * 15) % 256) })

        let recovery = try ErasureCoding.chunk(data: originalData, basicSize: basicSize, recoveryCount: recoveryCount)

        #expect(recovery.count == recoveryCount)

        var partialRecovery = [ErasureCoding.Shard]()
        for i in recoveryCount - originalCount ..< recoveryCount {
            partialRecovery.append(.init(data: recovery[i], index: UInt32(i)))
        }
        let recovered2 = try ErasureCoding.reconstruct(
            shards: partialRecovery, basicSize: basicSize, originalCount: originalCount, recoveryCount: recoveryCount
        )
        #expect(recovered2 == originalData)
    }

    @Test func testRecoverWithParityOnly() throws {
        let dataLength = 32
        let originalCount = 2
        let recoveryCount = 5
        let shardSize = (dataLength + originalCount - 1) / originalCount

        let originalData = Data((0 ..< dataLength).map { UInt8($0 % 256) })
        let originalShards = createShards(from: originalData, count: originalCount)

        let encoded = try ErasureCoding.encode(original: originalShards, recoveryCount: recoveryCount)

        var parityOnly: [ErasureCoding.InnerShard] = []
        for i in originalCount ..< recoveryCount {
            try parityOnly.append(.init(data: encoded[i], index: UInt32(i)))
        }

        let recovered = try ErasureCoding.recover(
            originalCount: originalCount,
            recoveryCount: recoveryCount,
            recovery: parityOnly,
            shardSize: shardSize
        )

        let recoveredData = recovered.reduce(Data(), +)
        #expect(recoveredData == originalData)
    }
}
