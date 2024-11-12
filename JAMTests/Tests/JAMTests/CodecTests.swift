import Blockchain
import Codec
import Foundation
import Testing
import Utils

@testable import JAMTests

struct CodecTests {
    static func config() -> ProtocolConfigRef {
        var config = ProtocolConfigRef.mainnet.value
        config.totalNumberOfValidators = 6
        config.epochLength = 12
        config.totalNumberOfCores = 2
        return Ref(config)
    }

    static func test(_ type: (some Codable).Type, path: String) throws -> (JSON, JSON) {
        let config = config()

        let jsonData = try TestLoader.getFile(path: "codec/data/\(path)", extension: "json")
        let json = try JSONDecoder().decode(JSON.self, from: jsonData)
        let bin = try TestLoader.getFile(path: "codec/data/\(path)", extension: "bin")

        let decoded = try JamDecoder.decode(type, from: bin, withConfig: config)
        let encoded = try JamEncoder.encode(decoded)

        #expect(encoded == bin)

        let jsonEncoder = JSONEncoder()
        jsonEncoder.dataEncodingStrategy = .hex
        let reencoded = try jsonEncoder.encode(decoded)
        let redecoded = try JSONDecoder().decode(JSON.self, from: reencoded)

        let transformed = Self.transform(redecoded, value: decoded)

        return (transformed, json)
    }

    static func transform(_ json: JSON, value: Any) -> JSON {
        if case Optional<Any>.none = value {
            return .null
        }

        if json.array != nil {
            let seq = value as! any Sequence
            var idx = 0
            return seq.map { item in
                defer { idx += 1 }
                return Self.transform(json.array![idx], value: item)
            }.json
        }
        if json.dictionary == nil {
            return json
        }
        if value is ExtrinsicAvailability {
            return json["assurances"]!.array!.map { item in
                [
                    "anchor": item["parentHash"]!,
                    "bitfield": item["assurance"]!["bytes"]!,
                    "signature": item["signature"]!,
                    "validator_index": item["validatorIndex"]!,
                ].json
            }.json
        }
        if value is ExtrinsicDisputes.VerdictItem {
            return [
                "target": json["reportHash"]!,
                "age": json["epoch"]!,
                "votes": json["judgements"]!.array!.map { item in
                    [
                        "vote": item["isValid"]!,
                        "index": item["validatorIndex"]!,
                        "signature": item["signature"]!,
                    ].json
                }.json,
            ].json
        }
        if value is ExtrinsicDisputes.CulpritItem {
            return [
                "target": json["reportHash"]!,
                "key": json["validatorKey"]!,
                "signature": json["signature"]!,
            ].json
        }
        if value is ExtrinsicDisputes.FaultItem {
            return [
                "target": json["reportHash"]!,
                "vote": json["vote"]!,
                "key": json["validatorKey"]!,
                "signature": json["signature"]!,
            ].json
        }
        if value is ExtrinsicPreimages {
            return json["preimages"]!.array!.map { item in
                [
                    "blob": item["data"]!,
                    "requester": item["serviceIndex"]!,
                ].json
            }.json
        }
        if value is RefinementContext {
            return [
                "anchor": json["anchor"]!["headerHash"]!,
                "beefy_root": json["anchor"]!["beefyRoot"]!,
                "lookup_anchor": json["lookupAnchor"]!["headerHash"]!,
                "lookup_anchor_slot": json["lookupAnchor"]!["timeslot"]!,
                "prerequisite": json["prerequisiteWorkPackages"] ?? .null,
                "state_root": json["anchor"]!["stateRoot"]!,
            ].json
        }
        if value is ExtrinsicTickets {
            return json["tickets"]!.array!.map { item in
                [
                    "attempt": item["attempt"]!,
                    "signature": item["signature"]!,
                ].json
            }.json
        }
        if value is WorkResult {
            return [
                "code_hash": json["codeHash"]!,
                "gas": json["gasRatio"]!,
                "payload_hash": json["payloadHash"]!,
                "service": json["serviceIndex"]!,
                "result": json["output"]!["success"] == nil ? json["output"]! : [
                    "ok": json["output"]!["success"]!,
                ].json,
            ].json
        }
        if value is WorkItem {
            return [
                "service": json["serviceIndex"]!,
                "code_hash": json["codeHash"]!,
                "payload": json["payloadBlob"]!,
                "gas_limit": json["gasLimit"]!,
                "import_segments": json["inputs"]!.array!.map { item in
                    [
                        "tree_root": item["root"]!,
                        "index": item["index"]!,
                    ].json
                }.json,
                "extrinsic": json["outputs"]!.array!.map { item in
                    [
                        "hash": item["hash"]!,
                        "len": item["length"]!,
                    ].json
                }.json,
                "export_count": json["outputDataSegmentsCount"]!,
            ].json
        }
        if let value = value as? WorkPackage {
            return [
                "authorization": json["authorizationToken"]!,
                "auth_code_host": json["authorizationServiceIndex"]!,
                "authorizer": [
                    "code_hash": json["authorizationCodeHash"]!,
                    "params": json["parameterizationBlob"]!,
                ].json,
                "context": transform(json["context"]!, value: value.context),
                "items": transform(json["workItems"]!, value: value.workItems),
            ].json
        }
        if let value = value as? WorkReport {
            return [
                "package_spec": transform(json["packageSpecification"]!, value: value.packageSpecification),
                "context": transform(json["refinementContext"]!, value: value.refinementContext),
                "core_index": json["coreIndex"]!,
                "authorizer_hash": json["authorizerHash"]!,
                "auth_output": json["authorizationOutput"]!,
                "results": transform(json["results"]!, value: value.results),
                "segment_root_lookup": transform(json["lookup"]!, value: value.lookup),
            ].json
        }
        if value is AvailabilitySpecifications {
            return [
                "hash": json["workPackageHash"]!,
                "len": json["length"]!,
                "erasure_root": json["erasureRoot"]!,
                "exports_root": json["segmentRoot"]!,
            ].json
        }
        if let value = value as? ExtrinsicGuarantees {
            return zip(value.guarantees, json["guarantees"]!.array!).map { value, json in
                [
                    "report": transform(json["workReport"]!, value: value.workReport),
                    "slot": json["timeslot"]!,
                    "signatures": json["credential"]!.array!.map { item in
                        [
                            "validator_index": item["index"]!,
                            "signature": item["signature"]!,
                        ].json
                    }.json,
                ].json
            }.json
        }
        if let value = value as? Extrinsic {
            return [
                "tickets": transform(json["tickets"]!, value: value.tickets),
                "disputes": transform(json["judgements"]!, value: value.judgements),
                "preimages": transform(json["preimages"]!, value: value.preimages),
                "assurances": transform(json["availability"]!, value: value.availability),
                "guarantees": transform(json["reports"]!, value: value.reports),
            ].json
        }
        if let value = value as? Header {
            return [
                "parent": json["parentHash"]!,
                "parent_state_root": json["priorStateRoot"]!,
                "extrinsic_hash": json["extrinsicsHash"]!,
                "slot": json["timeslot"]!,
                "epoch_mark": json["epoch"] ?? .null,
                "tickets_mark": transform(json["winningTickets"] ?? .null, value: value.winningTickets as Any),
                "offenders_mark": transform(json["offendersMarkers"]!, value: value.offendersMarkers),
                "author_index": json["authorIndex"]!,
                "entropy_source": json["vrfSignature"]!,
                "seal": json["seal"]!,
            ].json
        }

        var dict = [String: JSON]()
        for field in Mirror(reflecting: value).children {
            if case Optional<Any>.none = field.value {
                dict[field.label!] = .null
            } else {
                if field.label == nil {
                    fatalError("unreachable: label is nil \(String(reflecting: value))")
                }
                if let jsonValue = json[field.label!] {
                    dict[field.label!] = transform(jsonValue, value: field.value)
                }
            }
        }
        return dict.json
    }

    @Test
    func assurances_extrinsic() throws {
        let (actual, expected) = try Self.test(ExtrinsicAvailability.self, path: "assurances_extrinsic")
        #expect(actual == expected)
    }

    @Test
    func block() throws {
        withKnownIssue("waiting for refine_context.prerequisite updates", isIntermittent: true) {
            let (actual, expected) = try Self.test(Block.self, path: "block")
            #expect(actual == expected)
        }
    }

    @Test
    func disputes_extrinsic() throws {
        let (actual, expected) = try Self.test(ExtrinsicDisputes.self, path: "disputes_extrinsic")
        #expect(actual == expected)
    }

    @Test
    func extrinsic() throws {
        withKnownIssue("waiting for refine_context.prerequisite updates", isIntermittent: true) {
            let (actual, expected) = try Self.test(Extrinsic.self, path: "extrinsic")
            #expect(actual == expected)
        }
    }

    @Test
    func guarantees_extrinsic() throws {
        withKnownIssue("waiting for refine_context.prerequisite updates", isIntermittent: true) {
            let (actual, expected) = try Self.test(ExtrinsicGuarantees.self, path: "guarantees_extrinsic")
            #expect(actual == expected)
        }
    }

    @Test
    func header_0() throws {
        let (actual, expected) = try Self.test(Header.self, path: "header_0")
        #expect(actual == expected)
    }

    @Test
    func header_1() throws {
        let (actual, expected) = try Self.test(Header.self, path: "header_1")
        #expect(actual == expected)
    }

    @Test
    func preimages_extrinsic() throws {
        let (actual, expected) = try Self.test(ExtrinsicPreimages.self, path: "preimages_extrinsic")
        #expect(actual == expected)
    }

    @Test
    func refine_context() throws {
        withKnownIssue("waiting for refine_context.prerequisite updates", isIntermittent: true) {
            let (actual, expected) = try Self.test(RefinementContext.self, path: "refine_context")
            #expect(actual == expected)
        }
    }

    @Test
    func tickets_extrinsic() throws {
        let (actual, expected) = try Self.test(ExtrinsicTickets.self, path: "tickets_extrinsic")
        #expect(actual == expected)
    }

    @Test
    func work_item() throws {
        let (actual, expected) = try Self.test(WorkItem.self, path: "work_item")
        #expect(actual == expected)
    }

    @Test
    func work_package() throws {
        withKnownIssue("waiting for refine_context.prerequisite updates", isIntermittent: true) {
            let (actual, expected) = try Self.test(WorkPackage.self, path: "work_package")
            #expect(actual == expected)
        }
    }

    @Test
    func work_report() throws {
        withKnownIssue("waiting for refine_context.prerequisite updates", isIntermittent: true) {
            let (actual, expected) = try Self.test(WorkReport.self, path: "work_report")
            #expect(actual == expected)
        }
    }

    @Test
    func work_result_0() throws {
        let (actual, expected) = try Self.test(WorkResult.self, path: "work_result_0")
        #expect(actual == expected)
    }

    @Test
    func work_result_1() throws {
        let (actual, expected) = try Self.test(WorkResult.self, path: "work_result_1")
        #expect(actual == expected)
    }
}
