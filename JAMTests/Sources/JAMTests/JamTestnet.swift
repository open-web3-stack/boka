import Blockchain
import Codec
import Foundation
import Utils

struct JamTestnetTestcase: Codable {
    var preState: TestState
    var block: Block
    var postState: TestState
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
    // TODO: if they have diff format, need to move this to client specific test files
    // var keyvals: [[Data]]

    func toKV() -> [Data32: Data] {
        // keyvals are array of 4 item arrays, we only need first 2 item of each array
        let kvTuples = keyvals.map { (Data32($0[0])!, $0[1]) }
        return kvTuples.reduce(into: [:]) { $0[$1.0] = $1.1 }
    }

    func toState(config: ProtocolConfigRef) throws -> State {
        // TODO: remove
        print(keyvals.map(\.array)
            .map {
                "\($0[0].toHexString()) \($0[1].toHexString()) \(String(data: $0[2], encoding: .utf8) ?? "") \(String(data: $0[3], encoding: .utf8) ?? "")"
            })
        print(root)

        let kv = toKV()

        let backend = StateBackend(InMemoryBackend(), config: config, rootHash: root)

        // TODO: some state items are nil initially, so getter cannot assume they all are not nil
        let layer = StateLayer(rawKV: kv)

        return State(backend: backend, layer: layer)
    }
}

enum JamTestnet {
    static func loadTests(path: String, src: TestsSource) throws -> [Testcase] {
        try TestLoader.getTestcases(path: path, extension: "bin", src: src)
    }

    static func decodeTestcase(_ input: Testcase, config: ProtocolConfigRef = TestVariants.tiny.config) throws -> JamTestnetTestcase {
        try JamDecoder.decode(JamTestnetTestcase.self, from: input.data, withConfig: config)
    }

    static func runSTF(
        _ testcase: JamTestnetTestcase,
        config: ProtocolConfigRef = TestVariants.tiny.config
    ) async throws -> Result<StateRef, Error> {
        let runtime = Runtime(config: config)

        let result = await Result {
            let context = Runtime.ApplyContext(timeslot: testcase.block.header.timeslot, stateRoot: testcase.preState.root)
            let stateRef = try testcase.preState.toState(config: config).asRef()
            return try await runtime.apply(block: testcase.block.asRef(), state: stateRef, context: context)
        }

        return result
    }
}
