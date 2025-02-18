import Codec
import Foundation
import Testing

@testable import Utils

extension Blake2b256 {
    public static func hash(_ inputs: String...) -> Data32 {
        var hasher = Blake2b256()
        for input in inputs {
            hasher.update(Data(input.utf8))
        }
        return hasher.finalize()
    }
}

struct MerklizationTests {
    @Test
    func testHash() throws {
        let mmr = MMR([])
        #expect(mmr.superPeak() == Data32())

        let peak = Data32.random()
        let mmr1 = MMR([peak])
        #expect(mmr1.superPeak() == peak)

        let peaks = [Data32.random(), Data32.random(), Data32.random()]
        let mmr2 = MMR(peaks)
        #expect(mmr2.superPeak() == Keccak.hash("peak", Keccak.hash("peak", peaks[0], peaks[1]), peaks[2]))
    }

    @Test
    func binaryMerklize() {
        let input: [Data] = [
            Data("node1".utf8),
            Data("node2".utf8),
            Data("node3".utf8),
        ]
        let result = Merklization.binaryMerklize(input)
        let expected = Blake2b256.hash("node",
                                       Blake2b256.hash("node",
                                                       Data("node1".utf8),
                                                       Data("node2".utf8)),
                                       Data("node3".utf8))
        #expect(result == expected)
    }

    @Test
    func trace() {
        let input: [Data] = [
            Data("node1".utf8),
            Data("node2".utf8),
            Data("node3".utf8),
            Data("node4".utf8),
        ]
        let index = 2
        let result = Merklization.trace(input, index: index)
        let expected: [Either<Data, Data32>] = [
            .right(Blake2b256.hash("node", Data("node3".utf8), Data("node4".utf8))),
            .left(Data("node1".utf8)),
            .left(Data("node2".utf8)),
        ]
        #expect(result == expected)
    }

    @Test
    func constantDepthMerklize() {
        let input: [Data] = [
            Data("node1".utf8),
            Data("node2".utf8),
            Data("node3".utf8),
            Data("node4".utf8),
        ]
        let result = Merklization.constantDepthMerklize(input)

        let expected = Blake2b256.hash("node",
                                       Blake2b256.hash("node", Blake2b256.hash("leaf", "node1"), Blake2b256.hash("leaf", "node2")),
                                       Blake2b256.hash("node", Blake2b256.hash("leaf", "node3"), Blake2b256.hash("leaf", "node4")))
        #expect(result == expected)
    }

    @Test
    func generateJustification() {
        let input: [Data] = [
            Data("node1".utf8),
            Data("node2".utf8),
            Data("node3".utf8),
            Data("node4".utf8),
        ]

        let result = Merklization.generateJustification(input, size: 1, index: 1)
        let expected: [Data32] = [
            Blake2b256.hash("node", Blake2b256.hash("leaf", "node3"), Blake2b256.hash("leaf", "node4")),
        ]
        #expect(result == expected)

        let result1 = Merklization.generateJustification(input, size: 1, index: 0)
        let expected1: [Data32] = [
            Blake2b256.hash("node", Blake2b256.hash("leaf", "node1"), Blake2b256.hash("leaf", "node2")),
        ]
        #expect(result1 == expected1)

        let result2 = Merklization.generateJustification(input, size: 2, index: 0)
        let expected2: [Data32] = [
        ]
        #expect(result2 == expected2)

        let result3 = Merklization.generateJustification(input, size: 0, index: 0)
        let expected3: [Data32] = [
            Blake2b256.hash("node", Blake2b256.hash("leaf", "node1"), Blake2b256.hash("leaf", "node2")),
            Blake2b256.hash("leaf", "node3"),
        ]
        #expect(result3 == expected3)

        let result4 = Merklization.generateJustification(input, size: 0, index: 2)
        let expected4: [Data32] = [
            Blake2b256.hash("node", Blake2b256.hash("leaf", "node3"), Blake2b256.hash("leaf", "node4")),
            Blake2b256.hash("leaf", "node1"),
        ]
        #expect(result4 == expected4)
    }

    @Test
    func testLeafPage() {
        let input: [Data] = [
            Data("node1".utf8),
            Data("node2".utf8),
            Data("node3".utf8),
            Data("node4".utf8),
        ]

        let result = Merklization.leafPage(input, size: 1, index: 1)
        let expected: [Data32] = [
            Blake2b256.hash("leaf", "node3"), Blake2b256.hash("leaf", "node4"),
        ]
        #expect(result == expected)
    }

    @Test
    func emptyInput() {
        let emptyInput: [Data] = []

        let binaryResult = Merklization.binaryMerklize(emptyInput)
        let constantDepthResult = Merklization.constantDepthMerklize(emptyInput)
        let justificationResult = Merklization.generateJustification(emptyInput, size: 1, index: 0)

        #expect(binaryResult == Data32())
        #expect(constantDepthResult == Data32())
        #expect(justificationResult.isEmpty)
    }

    @Test
    func singleElementInput() {
        let singleInput: [Data] = [Data("single".utf8)]
        let binaryResult = Merklization.binaryMerklize(singleInput)
        let constantDepthResult = Merklization.constantDepthMerklize(singleInput)
        let expectedHash = Blake2b256.hash("single")
        #expect(binaryResult == expectedHash)
        #expect(constantDepthResult == Blake2b256.hash("leaf", "single"))
    }
}
