import Blockchain
import Codec
import Foundation
import Utils

struct JamTestnetTestcase: Codable {
    var preState: TestState
    var block: Block
    var postState: TestState
    // NOTE: jamduna has a field for accumulate root, others don't have this
    // var r: Data32
}

extension ProtocolConfig {
    public enum Int4: ReadInt {
        public typealias TConfig = ProtocolConfigRef
        public static func read(config _: ProtocolConfigRef) -> Int {
            4
        }
    }
}

struct TestState: Codable {
    var root: Data32
    var keyvals: [ConfigFixedSizeArray<Data, ProtocolConfig.Int4>]

    func toDict() -> [Data32: Data] {
        // keyvals are array of 4 item arrays, we only need first 2 item of each array
        let tuples = keyvals.map { (Data32($0[0])!, $0[1]) }
        return tuples.reduce(into: [:]) { $0[$1.0] = $1.1 }
    }

    // extract from string like "s=0|h=0x8c30f2c101674af1da31769e96ce72e81a4a44c89526d7d3ff0a1a511d5f3c9f l=25|t=[0] tlen=1"
    func extractDetails(from input: String) -> [String: String] {
        var result = [String: String]()
        let components = input.split(separator: "|")
        for component in components {
            let subComponents = component.split(separator: " ")
            for subComponent in subComponents {
                let pair = subComponent.split(separator: "=", maxSplits: 1).map(String.init)
                if pair.count == 2 {
                    result[pair[0]] = pair[1]
                }
            }
        }
        return result
    }

    func toState(config: ProtocolConfigRef) throws -> State {
        var changes: [(key: any StateKey, value: Codable & Sendable)] = []

        for arr in keyvals {
            let key: any StateKey
            let value: Codable & Sendable

            guard let str = String(data: arr[2], encoding: .utf8) else {
                fatalError("invalid description")
            }
            guard let detail = String(data: arr[3], encoding: .utf8) else {
                fatalError("invalid detail")
            }

            switch str {
            case "c1":
                key = StateKeys.CoreAuthorizationPoolKey()
                value = try JamDecoder.decode(StateKeys.CoreAuthorizationPoolKey.Value.self, from: arr[1], withConfig: config)
            case "c2":
                key = StateKeys.AuthorizationQueueKey()
                value = try JamDecoder.decode(StateKeys.AuthorizationQueueKey.Value.self, from: arr[1], withConfig: config)
            case "c3":
                key = StateKeys.RecentHistoryKey()
                value = try JamDecoder.decode(StateKeys.RecentHistoryKey.Value.self, from: arr[1], withConfig: config)
            case "c4":
                key = StateKeys.SafroleStateKey()
                value = try JamDecoder.decode(StateKeys.SafroleStateKey.Value.self, from: arr[1], withConfig: config)
            case "c5":
                key = StateKeys.JudgementsKey()
                value = try JamDecoder.decode(StateKeys.JudgementsKey.Value.self, from: arr[1], withConfig: config)
            case "c6":
                key = StateKeys.EntropyPoolKey()
                value = try JamDecoder.decode(StateKeys.EntropyPoolKey.Value.self, from: arr[1], withConfig: config)
            case "c7":
                key = StateKeys.ValidatorQueueKey()
                value = try JamDecoder.decode(StateKeys.ValidatorQueueKey.Value.self, from: arr[1], withConfig: config)
            case "c8":
                key = StateKeys.CurrentValidatorsKey()
                value = try JamDecoder.decode(StateKeys.CurrentValidatorsKey.Value.self, from: arr[1], withConfig: config)
            case "c9":
                key = StateKeys.PreviousValidatorsKey()
                value = try JamDecoder.decode(StateKeys.PreviousValidatorsKey.Value.self, from: arr[1], withConfig: config)
            case "c10":
                key = StateKeys.ReportsKey()
                value = try JamDecoder.decode(StateKeys.ReportsKey.Value.self, from: arr[1], withConfig: config)
            case "c11":
                key = StateKeys.TimeslotKey()
                value = try JamDecoder.decode(StateKeys.TimeslotKey.Value.self, from: arr[1], withConfig: config)
            case "c12":
                key = StateKeys.PrivilegedServicesKey()
                value = try JamDecoder.decode(StateKeys.PrivilegedServicesKey.Value.self, from: arr[1], withConfig: config)
            case "c13":
                key = StateKeys.ActivityStatisticsKey()
                value = try JamDecoder.decode(StateKeys.ActivityStatisticsKey.Value.self, from: arr[1], withConfig: config)
            case "c14":
                key = StateKeys.AccumulationQueueKey()
                value = try JamDecoder.decode(StateKeys.AccumulationQueueKey.Value.self, from: arr[1], withConfig: config)
            case "c15":
                key = StateKeys.AccumulationHistoryKey()
                value = try JamDecoder.decode(StateKeys.AccumulationHistoryKey.Value.self, from: arr[1], withConfig: config)
            case "service_account":
                let details = extractDetails(from: detail)
                key = StateKeys.ServiceAccountKey(index: UInt32(details["s"]!)!)
                value = try JamDecoder.decode(StateKeys.ServiceAccountKey.Value.self, from: arr[1], withConfig: config)
            case "account_storage":
                let details = extractDetails(from: detail)
                key = StateKeys.ServiceAccountStorageKey(
                    index: UInt32(details["s"]!)!,
                    key: Data32(fromHexString: String(details["k"]!.suffix(64)))!
                )
                value = try JamDecoder.decode(StateKeys.ServiceAccountStorageKey.Value.self, from: arr[1], withConfig: config)
            case "account_preimage":
                let details = extractDetails(from: detail)
                key = StateKeys.ServiceAccountPreimagesKey(
                    index: UInt32(details["s"]!)!,
                    hash: Data32(fromHexString: String(details["h"]!.suffix(64)))!
                )
                value = arr[1]
            case "account_lookup":
                let details = extractDetails(from: detail)
                key = StateKeys.ServiceAccountPreimageInfoKey(
                    index: UInt32(details["s"]!)!,
                    hash: Data32(fromHexString: String(details["h"]!.suffix(64)))!,
                    length: UInt32(details["l"]!)!
                )
                value = try JamDecoder.decode(StateKeys.ServiceAccountPreimageInfoKey.Value.self, from: arr[1], withConfig: config)
            default:
                fatalError("invalid key")
            }
            changes.append((key, value))
        }

        let backend = StateBackend(InMemoryBackend(), config: config, rootHash: root)

        let layer = StateLayer(changes: changes)

        return State(backend: backend, layer: layer)
    }
}

enum JamTestnet {
    static func loadTests(path: String, src: TestsSource) throws -> [Testcase] {
        try TestLoader.getTestcases(path: path, extension: "bin", src: src)
    }

    static func decodeTestcase(_ input: Testcase, config: ProtocolConfigRef = TestVariants.tiny.config) throws -> JamTestnetTestcase {
        try JamDecoder.decode(JamTestnetTestcase.self, from: input.data, withConfig: config, allowTrailingBytes: true)
    }

    static func runSTF(
        _ testcase: JamTestnetTestcase,
        config: ProtocolConfigRef = TestVariants.tiny.config
    ) async throws -> Result<StateRef, Error> {
        let runtime = Runtime(config: config)

        let result = await Result {
            // NOTE: skip block validate first, some tests does not ensure this
            let blockRef = try testcase.block.asRef().toValidated(config: config)
            let stateRef = try testcase.preState.toState(config: config).asRef()
            return try await runtime.apply(block: blockRef, state: stateRef)
        }

        return result
    }
}
