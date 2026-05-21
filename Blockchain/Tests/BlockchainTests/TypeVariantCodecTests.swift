@testable import Blockchain
import Codec
import Foundation
import Testing
import Utils

struct TypeVariantCodecTests {
    @Test
    func boundaryNodeJamCodecRoundTripsAllVariants() throws {
        try assertBoundaryNodeJamRoundTrip(.branch(BranchNode(
            children: [data32(1), nil, data32(2)],
            value: Data([3, 4]),
        )))
        try assertBoundaryNodeJamRoundTrip(.ext(ExtensionNode(
            prefix: Data([5, 6]),
            child: data32(7),
        )))
        try assertBoundaryNodeJamRoundTrip(.leaf(LeafNode(
            key: data31(8),
            value: Data([9, 10]),
        )))
    }

    @Test
    func boundaryNodeJsonCodecRoundTripsAllVariants() throws {
        try assertBoundaryNodeJsonRoundTrip(.branch(BranchNode(
            children: [nil, data32(11)],
            value: nil,
        )))
        try assertBoundaryNodeJsonRoundTrip(.ext(ExtensionNode(
            prefix: Data([12]),
            child: data32(13),
        )))
        try assertBoundaryNodeJsonRoundTrip(.leaf(LeafNode(
            key: data31(14),
            value: Data([15, 16]),
        )))
    }

    @Test
    func boundaryNodeRejectsInvalidVariants() throws {
        #expect(throws: DecodingError.self) {
            _ = try JamDecoder.decode(BoundaryNode.self, from: Data([9]))
        }

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(BoundaryNode.self, from: Data("{}".utf8))
        }
    }

    @Test
    func evidenceCodecsRoundTripVariants() throws {
        let first = Evidence.firstTranche(Data96(repeating: 17))
        try assertJamRoundTrip(first)
        try assertJsonRoundTrip(first)

        let announcement = Announcement(
            workReports: [.init(coreIndex: 18, workReportHash: data32(19))],
            signature: data64(20),
        )
        let subsequent = Evidence.subsequentTranche([
            .init(
                bandersnatchSig: Data96(repeating: 21),
                noShows: [.init(validatorIndex: 22, previousAnnouncement: announcement)],
            ),
        ])
        try assertJamRoundTrip(subsequent)
        try assertJsonRoundTrip(subsequent)
    }

    @Test
    func evidenceRejectsInvalidVariants() throws {
        #expect(throws: DecodingError.self) {
            _ = try JamDecoder.decode(Evidence.self, from: Data([7]))
        }

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(Evidence.self, from: Data("{}".utf8))
        }
    }

    @Test
    func justificationCodecsRoundTripVariants() throws {
        let values: [Justification] = [
            .singleHash(data32(23)),
            .doubleHash(data32(24), data32(25)),
            .segmentShard(Data([26, 27, 28])),
            .copath([.left(data32(29)), .right(data32(30))]),
        ]

        for value in values {
            try assertJamRoundTrip(value)
            try assertJsonRoundTrip(value)
        }
    }

    @Test
    func justificationRejectsInvalidVariants() throws {
        #expect(throws: DecodingError.self) {
            _ = try JamDecoder.decode(Justification.self, from: Data([8]))
        }

        #expect(throws: DecodingError.self) {
            _ = try JamDecoder.decode(JustificationStep.self, from: JamEncoder.encode(UInt8(2), data32(31)))
        }

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(Justification.self, from: Data("{\"doubleHash\":[]}".utf8))
        }

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(Justification.self, from: Data("{}".utf8))
        }
    }

    private func assertJamRoundTrip<T: Codable & Equatable>(_ value: T) throws {
        let decoded = try JamDecoder.decode(T.self, from: JamEncoder.encode(value))
        #expect(decoded == value)
    }

    private func assertJsonRoundTrip<T: Codable & Equatable>(_ value: T) throws {
        let encoded = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(T.self, from: encoded)
        #expect(decoded == value)
    }

    private func assertBoundaryNodeJamRoundTrip(_ value: BoundaryNode) throws {
        let decoded = try JamDecoder.decode(BoundaryNode.self, from: JamEncoder.encode(value))
        assertBoundaryNode(decoded, equals: value)
    }

    private func assertBoundaryNodeJsonRoundTrip(_ value: BoundaryNode) throws {
        let encoded = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(BoundaryNode.self, from: encoded)
        assertBoundaryNode(decoded, equals: value)
    }

    private func assertBoundaryNode(_ actual: BoundaryNode, equals expected: BoundaryNode) {
        switch (actual, expected) {
        case let (.branch(actual), .branch(expected)):
            #expect(actual.children == expected.children)
            #expect(actual.value == expected.value)
        case let (.ext(actual), .ext(expected)):
            #expect(actual.prefix == expected.prefix)
            #expect(actual.child == expected.child)
        case let (.leaf(actual), .leaf(expected)):
            #expect(actual.key == expected.key)
            #expect(actual.value == expected.value)
        default:
            Issue.record("Expected \(expected), got \(actual)")
        }
    }
}
