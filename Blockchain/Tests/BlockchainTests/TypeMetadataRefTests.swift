@testable import Blockchain
import Codec
import Foundation
import Testing
import Utils

struct TypeMetadataRefTests {
    @Test
    func metadataDescriptionIncludesOptionalFieldsWhenPresent() {
        let metadata = Metadata(
            formatVersion: 1,
            programName: Data("validator".utf8),
            version: Data("1.2.3".utf8),
            license: Data("Apache-2.0".utf8),
            authors: [Data("Alice".utf8), Data("Bob".utf8)],
        )

        #expect(metadata.description == "validator v1.2.3 (Apache-2.0) by Alice, Bob")
    }

    @Test
    func metadataDescriptionOmitsEmptyOptionalFields() {
        let metadata = Metadata(
            formatVersion: 1,
            programName: Data("minimal".utf8),
            version: Data("0.1.0".utf8),
            license: Data(),
            authors: [],
        )

        #expect(metadata.description == "minimal v0.1.0")
    }

    @Test
    func codeAndMetaSplitsMetadataAndCodeBlob() throws {
        let metadata = Metadata(
            formatVersion: 1,
            programName: Data("accumulate".utf8),
            version: Data("2.0.0".utf8),
            license: Data("MIT".utf8),
            authors: [Data("Runtime Team".utf8)],
        )
        let codeBlob = Data([1, 3, 3, 7])

        let parsed = try CodeAndMeta(data: encodeCodeAndMeta(metadata: metadata, codeBlob: codeBlob))

        #expect(parsed.metadata == metadata)
        #expect(parsed.codeBlob == codeBlob)
    }

    @Test
    func codeAndMetaRejectsMissingMetadataLength() {
        do {
            _ = try CodeAndMeta(data: Data())
            Issue.record("Expected invalid metadata length")
        } catch CodeAndMeta.Error.invalidMetadataLength {
        } catch {
            Issue.record("Expected invalid metadata length, got \(error)")
        }
    }

    @Test
    func guaranteedWorkReportRefExposesWrappedReportFieldsAndHash() {
        let report = makeGuaranteedWorkReport()
        let ref = report.asRef()

        #expect(ref.workReport == report.workReport)
        #expect(ref.slot == report.slot)
        #expect(ref.signatures == report.signatures)
        #expect(ref.hash == report.hash())
        #expect(ref.description == "GuaranteedWorkReport(hash: \(report.workReport.hash()), timeslot: \(report.slot))")
    }

    @Test
    func guaranteedWorkReportRefCodecsRoundTripWrappedValue() throws {
        let config = ProtocolConfigRef.tiny
        let report = makeGuaranteedWorkReport(config: config)
        let ref = report.asRef()

        let jamDecoded = try JamDecoder.decode(
            GuaranteedWorkReportRef.self,
            from: JamEncoder.encode(ref),
            withConfig: config,
        )
        #expect(jamDecoded.value == report)
        #expect(jamDecoded.hash == report.hash())

        let jsonEncoder = JSONEncoder()
        jsonEncoder.userInfo[.config] = config
        let jsonEncoded = try jsonEncoder.encode(ref)

        let jsonDecoder = JSONDecoder()
        jsonDecoder.userInfo[.config] = config
        let jsonDecoded = try jsonDecoder.decode(GuaranteedWorkReportRef.self, from: jsonEncoded)
        #expect(jsonDecoded.value == report)
        #expect(jsonDecoded.hash == report.hash())
    }

    private func encodeCodeAndMeta(metadata: Metadata, codeBlob: Data) throws -> Data {
        let metadataData = try JamEncoder.encode(metadata)
        var data = Data(UInt(metadataData.count).encode(method: .variableWidth))
        data.append(metadataData)
        data.append(codeBlob)
        return data
    }

    private func makeGuaranteedWorkReport() -> GuaranteedWorkReport {
        makeGuaranteedWorkReport(config: .tiny)
    }

    private func makeGuaranteedWorkReport(config: ProtocolConfigRef) -> GuaranteedWorkReport {
        GuaranteedWorkReport(
            workReport: WorkReport.dummy(config: config),
            slot: 42,
            signatures: [
                ValidatorSignature(validatorIndex: 7, signature: data64(8)),
                ValidatorSignature(validatorIndex: 9, signature: data64(10)),
            ],
        )
    }
}
