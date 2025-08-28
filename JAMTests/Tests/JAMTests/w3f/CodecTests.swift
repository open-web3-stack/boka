import Blockchain
import Codec
import Foundation
import Testing
import Utils

@testable import JAMTests

struct CodecTests {
    static func test(_ type: (some Codable).Type, path: String, variant: TestVariants) throws -> (JSON, JSON) {
        let config = variant.config

        let jsonData = try TestLoader.getFile(path: "codec/\(variant)/\(path)", extension: "json")
        let json = try JSONDecoder().decode(JSON.self, from: jsonData)
        let bin = try TestLoader.getFile(path: "codec/\(variant)/\(path)", extension: "bin")

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

    func testBothVariants(_ type: (some Codable).Type, path: String) throws {
        // Test with tiny variant
        let (actualTiny, expectedTiny) = try Self.test(type, path: path, variant: .tiny)
        #expect(actualTiny == expectedTiny)

        // Test with full variant
        let (actualFull, expectedFull) = try Self.test(type, path: path, variant: .full)
        #expect(actualFull == expectedFull)
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
                "state_root": json["anchor"]!["stateRoot"]!,
                "beefy_root": json["anchor"]!["beefyRoot"]!,
                "lookup_anchor": json["lookupAnchor"]!["headerHash"]!,
                "lookup_anchor_slot": json["lookupAnchor"]!["timeslot"]!,
                "prerequisites": json["prerequisiteWorkPackages"] ?? .null,
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
        if value is WorkDigest {
            return [
                "service_id": json["serviceIndex"]!,
                "code_hash": json["codeHash"]!,
                "payload_hash": json["payloadHash"]!,
                "accumulate_gas": json["gasLimit"]!,
                "result": json["result"]!["success"] == nil ? json["result"]! : [
                    "ok": json["result"]!["success"]!,
                ].json,
                "refine_load": [
                    "gas_used": json["gasUsed"]!,
                    "imports": json["importsCount"]!,
                    "exports": json["exportsCount"]!,
                    "extrinsic_count": json["extrinsicsCount"]!,
                    "extrinsic_size": json["extrinsicsSize"]!,
                ].json,
            ].json
        }
        if value is WorkItem {
            return [
                "service": json["serviceIndex"]!,
                "code_hash": json["codeHash"]!,
                "refine_gas_limit": json["refineGasLimit"]!,
                "accumulate_gas_limit": json["accumulateGasLimit"]!,
                "export_count": json["exportsCount"]!,
                "payload": json["payloadBlob"]!,
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
            ].json
        }
        if let value = value as? WorkPackage {
            return [
                "auth_code_host": json["authorizationServiceIndex"]!,
                "auth_code_hash": json["authorizationCodeHash"]!,
                "context": transform(json["context"]!, value: value.context),
                "authorization": json["authorizationToken"]!,
                "authorizer_config": json["configurationBlob"]!,
                "items": transform(json["workItems"]!, value: value.workItems),
            ].json
        }
        if let value = value as? WorkReport {
            return [
                "package_spec": transform(json["packageSpecification"]!, value: value.packageSpecification),
                "context": transform(json["refinementContext"]!, value: value.refinementContext),
                "core_index": json["coreIndex"]!,
                "authorizer_hash": json["authorizerHash"]!,
                "auth_output": json["authorizerTrace"]!,
                "results": transform(json["digests"]!, value: value.digests),
                "segment_root_lookup": transform(json["lookup"]!, value: value.lookup),
                "auth_gas_used": json["authGasUsed"]!,
            ].json
        }
        if value is AvailabilitySpecifications {
            return [
                "hash": json["workPackageHash"]!,
                "length": json["length"]!,
                "erasure_root": json["erasureRoot"]!,
                "exports_root": json["segmentRoot"]!,
                "exports_count": json["segmentCount"]!,
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
                "preimages": transform(json["preimages"]!, value: value.preimages),
                "guarantees": transform(json["reports"]!, value: value.reports),
                "assurances": transform(json["availability"]!, value: value.availability),
                "disputes": transform(json["disputes"]!, value: value.disputes),
            ].json
        }
        if let value = value as? Header {
            return [
                "parent": json["parentHash"]!,
                "parent_state_root": json["priorStateRoot"]!,
                "extrinsic_hash": json["extrinsicsHash"]!,
                "slot": json["timeslot"]!,
                "epoch_mark": transform(json["epoch"] ?? .null, value: value.epoch as Any),
                "tickets_mark": transform(json["winningTickets"] ?? .null, value: value.winningTickets as Any),
                "author_index": json["authorIndex"]!,
                "entropy_source": json["vrfSignature"]!,
                "offenders_mark": transform(json["offendersMarkers"]!, value: value.offendersMarkers),
                "seal": json["seal"]!,
            ].json
        }
        if value is EpochMarker {
            return [
                "entropy": json["entropy"]!,
                "tickets_entropy": json["ticketsEntropy"]!,
                "validators": json["validators"]!,
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
        try testBothVariants(ExtrinsicAvailability.self, path: "assurances_extrinsic")
    }

    @Test
    func block() throws {
        try testBothVariants(Block.self, path: "block")
    }

    @Test
    func disputes_extrinsic() throws {
        try testBothVariants(ExtrinsicDisputes.self, path: "disputes_extrinsic")
    }

    @Test
    func extrinsic() throws {
        try testBothVariants(Extrinsic.self, path: "extrinsic")
    }

    @Test
    func guarantees_extrinsic() throws {
        try testBothVariants(ExtrinsicGuarantees.self, path: "guarantees_extrinsic")
    }

    @Test
    func header_0() throws {
        try testBothVariants(Header.self, path: "header_0")
    }

    @Test
    func header_1() throws {
        try testBothVariants(Header.self, path: "header_1")
    }

    @Test
    func preimages_extrinsic() throws {
        try testBothVariants(ExtrinsicPreimages.self, path: "preimages_extrinsic")
    }

    @Test
    func refine_context() throws {
        try testBothVariants(RefinementContext.self, path: "refine_context")
    }

    @Test
    func tickets_extrinsic() throws {
        try testBothVariants(ExtrinsicTickets.self, path: "tickets_extrinsic")
    }

    @Test
    func work_item() throws {
        try testBothVariants(WorkItem.self, path: "work_item")
    }

    @Test
    func work_package() throws {
        try testBothVariants(WorkPackage.self, path: "work_package")
    }

    @Test
    func work_report() throws {
        try testBothVariants(WorkReport.self, path: "work_report")
    }

    @Test
    func work_result_0() throws {
        try testBothVariants(WorkDigest.self, path: "work_result_0")
    }

    @Test
    func work_result_1() throws {
        try testBothVariants(WorkDigest.self, path: "work_result_1")
    }
}
