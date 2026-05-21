@testable import Blockchain
import Codec
import Foundation
import Testing
import Utils

struct WorkItemCodecTests {
    @Test
    func importedDataSegmentCodecsRoundTripBothRootKinds() throws {
        let segments = [
            WorkItem.ImportedDataSegment(root: .segmentRoot(data32(1)), index: 7),
            WorkItem.ImportedDataSegment(root: .workPackageHash(data32(2)), index: 9),
        ]

        for segment in segments {
            let jamDecoded = try JamDecoder.decode(
                WorkItem.ImportedDataSegment.self,
                from: JamEncoder.encode(segment),
            )
            #expect(jamDecoded == segment)

            let jsonDecoded = try JSONDecoder().decode(
                WorkItem.ImportedDataSegment.self,
                from: JSONEncoder().encode(segment),
            )
            #expect(jsonDecoded == segment)
        }
    }

    @Test
    func importedDataSegmentJsonDecodesLegacySegmentRootWithoutKind() throws {
        let segment = WorkItem.ImportedDataSegment(root: .segmentRoot(data32(3)), index: 11)
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(segment)) as? [String: Any])
        object.removeValue(forKey: "rootKind")

        let decoded = try JSONDecoder().decode(
            WorkItem.ImportedDataSegment.self,
            from: JSONSerialization.data(withJSONObject: object),
        )

        #expect(decoded == segment)
    }

    @Test
    func workItemCodecsRoundTripNestedSegments() throws {
        let item = WorkItem(
            serviceIndex: 12,
            codeHash: data32(4),
            payloadBlob: Data([1, 2, 3]),
            refineGasLimit: Gas(34),
            accumulateGasLimit: Gas(56),
            inputs: [
                WorkItem.ImportedDataSegment(root: .segmentRoot(data32(5)), index: 1),
                WorkItem.ImportedDataSegment(root: .workPackageHash(data32(6)), index: 2),
            ],
            outputs: [
                HashAndLength(hash: data32(7), length: 8),
            ],
            exportsCount: 3,
        )

        let jamDecoded = try JamDecoder.decode(WorkItem.self, from: JamEncoder.encode(item))
        #expect(jamDecoded == item)

        let jsonDecoded = try JSONDecoder().decode(WorkItem.self, from: JSONEncoder().encode(item))
        #expect(jsonDecoded == item)
    }
}
