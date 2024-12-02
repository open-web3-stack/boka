import erasure_coding
import Foundation
import Testing

@testable import Utils

// somehow without this the GH Actions CI fails
extension Foundation.Bundle: @unchecked @retroactive Sendable {}

enum TestLoader {
    static func getTestFiles(path: String, extension ext: String) throws -> [(path: String, description: String)] {
        let prefix = Bundle.module.resourcePath! + "/TestData/\(path)"
        let files = try FileManager.default.contentsOfDirectory(atPath: prefix)
        var filtered = files.filter { $0.hasSuffix(".\(ext)") }
        filtered.sort()
        return filtered.map { (path: prefix + "/" + $0, description: $0) }
    }
}

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

struct ErasureCodeTests {
    static func loadTests() throws -> [ECTestCase] {
        let tests = try TestLoader.getTestFiles(path: "ec", extension: "json")
        return try tests.map {
            let data = try Data(contentsOf: URL(fileURLWithPath: $0.path))
            let decoder = JSONDecoder()
            return try decoder.decode(ECTestCase.self, from: data)
        }
    }

    @Test
    func constructWithSegments() throws {
        let segments: [Segment] = []
        let encoder = SubShardEncoder()
        let result = encoder.construct(segments: segments)
        if case let .failure(constructFailed) = result {
            #expect(constructFailed == ErasureCodeError.constructFailed)
        }
    }

    @Test
    func constructWithIncorrectSegmentSize() throws {
        let incorrectData = Data(repeating: 0xFF, count: Int(SEGMENT_SIZE) - 1)
        #expect(Segment(data: incorrectData, index: 0) == nil)
    }

    @Test(arguments: try loadTests())
    func testReconstruct(testCase: ECTestCase) throws {
        // Convert segment_ec data back to bytes and prepare subshards
        var subshards: [SubShardTuple] = []
        for (segmentIdx, segment) in testCase.segment.segments.enumerated() {
            for (chunkIdx, chunk) in segment.segmentEc.enumerated() {
                let chunkBytes = Data(fromHexString: chunk)!

                if chunkIdx >= 684 {
                    var subshard: [UInt8] = Array(repeating: 0, count: Int(SUBSHARD_SIZE))
                    subshard[0 ..< chunkBytes.count] = [UInt8](chunkBytes)[...]
                    subshards.append(SubShardTuple(
                        seg_index: UInt8(segmentIdx),
                        chunk_index: ChunkIndex(chunkIdx),
                        subshard: (
                            subshard[0],
                            subshard[1],
                            subshard[2],
                            subshard[3],
                            subshard[4],
                            subshard[5],
                            subshard[6],
                            subshard[7],
                            subshard[8],
                            subshard[9],
                            subshard[10],
                            subshard[11]
                        )
                    ))
                }
            }
        }

        // Initialize decoder, call reconstruct
        let decoder = SubShardDecoder()
        let result = decoder.reconstruct(subshards: subshards)

        switch result {
        case let .success(decoded):
            #expect(decoded.numDecoded == 1)
            let segmentTuples = decoded.segments
            #expect(segmentTuples.count == 1)
            let segment = segmentTuples[0].segment
            let originalDataBytes = Data(fromHexString: testCase.data)!
            let segmentData = Data(UnsafeBufferPointer(start: segment.data, count: Int(SEGMENT_SIZE)))
            #expect(segmentData[0 ..< 342] == originalDataBytes[0 ..< 342])
        case let .failure(error):
            Issue.record("Expected success, got \(error)")
        }
    }

    @Test func testSplitJoin() {
        let testData = Data("Hello, world!".utf8)
        let paddedTestData = testData + Data(repeating: 0, count: Int(SEGMENT_SIZE) - (testData.count % Int(SEGMENT_SIZE)))

        let splited = split(data: testData)
        let joined = join(segments: splited)

        #expect(joined == paddedTestData)
    }
}
