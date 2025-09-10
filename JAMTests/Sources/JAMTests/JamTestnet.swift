import Blockchain
import Codec
import Foundation
import Utils

public struct JamTestnetTestcase: Codable, Sendable {
    public var preState: TestState
    public var block: Block
    public var postState: TestState
}

extension ProtocolConfig {
    public enum Int4: ReadInt {
        public typealias TConfig = ProtocolConfigRef
        public static func read(config _: ProtocolConfigRef) -> Int {
            4
        }
    }
}

public struct KeyVal: Codable, Sendable {
    public var key: Data31
    public var value: Data
}

public struct TestState: Codable, Sendable {
    public var root: Data32
    public var keyvals: [KeyVal]

    public func toDict() -> [Data31: Data] {
        var dict: [Data31: Data] = [:]
        for arr in keyvals {
            dict[arr.key] = arr.value
        }
        return dict
    }

    public func toState(config: ProtocolConfigRef = TestVariants.tiny.config) async throws -> State {
        var raw: [(key: Data31, value: Data)] = []

        for keyval in keyvals {
            raw.append((key: keyval.key, value: keyval.value))
        }

        let backend = StateBackend(InMemoryBackend(), config: config, rootHash: root)

        try await backend.writeRaw(raw)

        return try await State(backend: backend)
    }
}

public enum JamTestnet {
    public static func loadTests(path: String, src: TestsSource, ext: String = "bin") throws -> [Testcase] {
        // filter genesis which has no tests
        try TestLoader.getTestcases(path: path, extension: ext, src: src).filter { $0.description != "genesis.bin" }
    }

    public static func decodeTestcase(
        _ input: Testcase,
        config: ProtocolConfigRef = TestVariants.tiny.config
    ) throws -> JamTestnetTestcase {
        // NOTE: some tests have trailing bytes
        try JamDecoder.decode(JamTestnetTestcase.self, from: input.data, withConfig: config, allowTrailingBytes: true)
    }

    public static func runSTF(
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
