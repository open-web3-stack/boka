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

struct KeyVal: Codable {
    var key: Data31
    var value: Data
}

struct TestState: Codable {
    var root: Data32
    var keyvals: [KeyVal]

    func toDict() -> [Data31: Data] {
        var dict: [Data31: Data] = [:]
        for arr in keyvals {
            dict[arr.key] = arr.value
        }
        return dict
    }

    func toState(config: ProtocolConfigRef = TestVariants.tiny.config) async throws -> State {
        var raw: [(key: Data31, value: Data)] = []

        for keyval in keyvals {
            raw.append((key: keyval.key, value: keyval.value))
        }

        let backend = StateBackend(InMemoryBackend(), config: config, rootHash: root)

        try await backend.writeRaw(raw)

        return try await State(backend: backend)
    }
}

enum JamTestnet {
    static func loadTests(path: String, src: TestsSource, ext: String = "bin") throws -> [Testcase] {
        // filter genesis which has no tests
        try TestLoader.getTestcases(path: path, extension: ext, src: src).filter { $0.description != "genesis.bin" }
    }

    static func decodeTestcase(_ input: Testcase, config: ProtocolConfigRef = TestVariants.tiny.config) throws -> JamTestnetTestcase {
        // NOTE: some tests have trailing bytes
        try JamDecoder.decode(JamTestnetTestcase.self, from: input.data, withConfig: config, allowTrailingBytes: true)
    }

    static func runSTF(
        _ testcase: JamTestnetTestcase,
        config: ProtocolConfigRef = TestVariants.tiny.config
    ) async throws -> Result<StateRef, Error> {
        let runtime = Runtime(config: config)
        let blockRef = testcase.block.asRef()
        let stateRef = try await testcase.preState.toState(config: config).asRef()

        let result = await Result {
            try await runtime.apply(block: blockRef, state: stateRef)
        }

        return result
    }
}
