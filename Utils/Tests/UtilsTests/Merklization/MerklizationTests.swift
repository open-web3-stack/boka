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
        var mmr = MMR([])
        let emptyHash = try JamEncoder.encode(mmr).keccakHash()
        #expect(mmr.hash() == emptyHash)
    }

    @Test
    func binaryMerklize() {
        let input: [Data] = [
            Data("node1".utf8),
            Data("node2".utf8),
            Data("node3".utf8),
        ]
        let result = Merklization.binaryMerklize(input)
        print("result = \(result)")
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
        let index = 2
        let result = Merklization.generateJustification(input, index: index)

        let expected: [Data32] = [
            Blake2b256.hash("node", Blake2b256.hash("leaf", "node3"), Blake2b256.hash("leaf", "node4")),
        ]

        #expect(result.first == expected.first)
    }

    @Test
    func emptyInput() {
        let emptyInput: [Data] = []

        let binaryResult = Merklization.binaryMerklize(emptyInput)
        let constantDepthResult = Merklization.constantDepthMerklize(emptyInput)
        let justificationResult = Merklization.generateJustification(emptyInput, index: 0)

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
