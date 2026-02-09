import Blockchain
import Codec
import Foundation
import TracingUtils
import Utils

private let logger = Logger(label: "FuzzingClient")

public class FuzzingClient {
    public enum FuzzingClientError: Error {
        case invalidConfig
        case connectionFailed
        case handshakeFailed
        case targetNotResponding
        case stateNotSet
    }

    private let socket: FuzzingSocket
    private var connection: FuzzingSocketConnection?
    private let fuzzGenerator: any FuzzGenerator
    private let config: ProtocolConfigRef
    private let devKey: KeySet
    private let blockCount: Int
    private var currentStateRef: StateRef?

    public init(
        socketPath: String,
        config: String,
        seed: UInt64,
        blockCount: Int,
        tracesDir: String?,
    ) throws {
        switch config {
        case "tiny":
            self.config = ProtocolConfigRef.tiny
        case "full":
            self.config = ProtocolConfigRef.mainnet
        default:
            logger.error("Invalid config: \(config). Only 'tiny' or 'full' allowed.")
            throw FuzzingClientError.invalidConfig
        }

        socket = FuzzingSocket(socketPath: socketPath, config: self.config)

        if let tracesDir {
            fuzzGenerator = try FuzzGeneratorTraces(tracesDir: tracesDir)
        } else {
            fuzzGenerator = FuzzGeneratorRandom(seed: seed, config: self.config)
        }

        devKey = try DevKeyStore.getDevKey(seed: UInt32(seed % UInt64(UInt32.max)))
        self.blockCount = blockCount
        currentStateRef = nil

        logger.info("Boka fuzzer initialized with socket: \(socketPath), seed: \(seed), blockCount: \(blockCount)")
    }

    public func run() async throws {
        logger.info("🚀 Starting Boka Fuzzer")

        try connect()
        try handshake()
        try await runFuzzingSessions()

        logger.info("🎯 Fuzzing completed successfully!")

        disconnect()
    }

    public func connect() throws {
        connection = try socket.connect()
        logger.info("🔌 Connected to fuzzing target")
    }

    public func disconnect() {
        connection?.close()
        connection = nil
        logger.info("🔌 Disconnected from fuzzing target")
    }

    public func handshake() throws {
        guard let connection else {
            throw FuzzingClientError.connectionFailed
        }

        let message = FuzzingMessage.peerInfo(.init(
            name: "boka-fuzzing-fuzzer",
            fuzzFeatures: 0,
        ))
        try connection.sendMessage(message)

        if let response = try connection.receiveMessage(), case let .peerInfo(info) = response {
            logger.info("🤝 Handshake completed with \(info.appName), app version: \(info.appVersion), jam version: \(info.jamVersion)")
            logger.info("   Fuzz version: \(info.fuzzVersion)")
            let ancestryEnabled = (info.fuzzFeatures & FEATURE_ANCESTRY) != 0
            let forkEnabled = (info.fuzzFeatures & FEATURE_FORK) != 0
            logger.info("   Features: ANCESTRY=\(ancestryEnabled), FORK=\(forkEnabled)")
        } else {
            throw FuzzingClientError.targetNotResponding
        }
    }

    public func runFuzzingSessions() async throws {
        guard let connection else {
            throw FuzzingClientError.connectionFailed
        }

        for blockIndex in 0 ..< blockCount {
            let timeslot = UInt32(blockIndex)
            logger.info("📦 Processing block \(blockIndex)/\(blockCount)")

            // generate pre-state
            let (_, kv) = try await fuzzGenerator.generatePreState(timeslot: timeslot, config: config)

            // set state on target
            try await initializeState(kv: kv, connection: connection)

            // set state locally
            let rawKV = kv.map { (key: $0.key, value: $0.value) }
            let state: State
            do {
                let backend = StateBackend(InMemoryBackend(), config: config, rootHash: Data32())
                try await backend.writeRaw(rawKV)
                state = try await State(backend: backend)
            } catch {
                logger.warning("⚠️ Skipping block \(blockIndex) due to state init failure: \(error)")
                continue
            }
            currentStateRef = state.asRef()

            // generate a block
            let blockRef = try await fuzzGenerator.generateBlock(
                timeslot: timeslot,
                currentStateRef: currentStateRef!,
                config: config,
            )

            // TODO: Implement fork feature

            // import block on target
            let targetStateRoot = try importBlock(block: blockRef.value, connection: connection)

            // skip state comparison if import failed
            guard let targetStateRoot else {
                logger.warning("⚠️ Skipping block \(blockIndex + 1) due to import failure, continuing with next block")
                continue
            }

            // get expected post-state
            let (expectedStateRoot, expectedPostState) = try await fuzzGenerator.generatePostState(timeslot: timeslot, config: config)

            if targetStateRoot == expectedStateRoot {
                logger.info("✅ Target state matches expected post-state for block \(blockIndex + 1)!")
            } else {
                logger.error("❌ TARGET STATE MISMATCH (vs expected) for block \(blockIndex + 1):")
                logger.error("   Target root:   \(targetStateRoot.data.toHexString())")
                logger.error("   Expected root: \(expectedStateRoot.data.toHexString())")

                let targetState = try getState(connection: connection)

                try await generateMismatchReport(
                    blockIndex: blockIndex + 1,
                    targetState: targetState,
                    expectedState: expectedPostState,
                )

                break
            }

            logger.info("✅ Block \(blockIndex + 1) processed, target state root: \(targetStateRoot.data.toHexString())")
        }

        logger.info("🎯 Fuzzing session completed - processed \(blockCount) blocks")
    }

    private func initializeState(kv: [FuzzKeyValue], connection: FuzzingSocketConnection) async throws {
        logger.info("🏗️ INITIALIZE STATE")

        let dummyHeader = Header.dummy(config: config)
        let ancestry: [AncestryItem] = []
        let initializeMessage = FuzzingMessage.initialize(FuzzInitialize(header: dummyHeader, state: kv, ancestry: ancestry))
        try connection.sendMessage(initializeMessage)

        if let response = try connection.receiveMessage(), case let .stateRoot(root) = response {
            logger.info("🏗️ INITIALIZE STATE success, root: \(root.data.toHexString())")
        } else {
            throw FuzzingClientError.targetNotResponding
        }
    }

    private func importBlock(block: Block, connection: FuzzingSocketConnection) throws -> Data32? {
        logger.info("📦 IMPORT BLOCK")

        let importMessage = FuzzingMessage.importBlock(block)
        try connection.sendMessage(importMessage)

        if let response = try connection.receiveMessage() {
            switch response {
            case let .stateRoot(root):
                logger.info("📦 IMPORT BLOCK success, new state root: \(root.data.toHexString())")
                return root
            case let .error(errorMsg):
                logger.error("📦 IMPORT BLOCK failed: \(errorMsg)")
                return nil
            default:
                throw FuzzingClientError.targetNotResponding
            }
        } else {
            throw FuzzingClientError.targetNotResponding
        }
    }

    private func getState(connection: FuzzingSocketConnection) throws -> [FuzzKeyValue] {
        logger.info("🔍 GET STATE")

        let getStateMessage = FuzzingMessage.getState(Data32())
        try connection.sendMessage(getStateMessage)

        if let response = try connection.receiveMessage(), case let .state(keyValues) = response {
            logger.info("📋 GET STATE success: \(keyValues.count) key-value pairs")
            return keyValues
        } else {
            throw FuzzingClientError.targetNotResponding
        }
    }

    private func generateMismatchReport(
        blockIndex: Int,
        targetState: [FuzzKeyValue],
        expectedState: [FuzzKeyValue],
    ) async throws {
        logger.info("📊 Generating mismatch report for block \(blockIndex) (target vs expected)")

        var targetMap: [String: String] = [:]
        var duplicateTargetKeys: [String] = []
        for kv in targetState {
            let keyHex = kv.key.data.toDebugHexString()
            let valueHex = kv.value.toDebugHexString()
            if targetMap[keyHex] != nil {
                duplicateTargetKeys.append(keyHex)
                logger.warning("Duplicate key in target state: \(keyHex)")
            }
            targetMap[keyHex] = valueHex
        }

        var expectedMap: [String: String] = [:]
        var duplicateExpectedKeys: [String] = []
        for kv in expectedState {
            let keyHex = kv.key.data.toDebugHexString()
            let valueHex = kv.value.toDebugHexString()
            if expectedMap[keyHex] != nil {
                duplicateExpectedKeys.append(keyHex)
                logger.warning("Duplicate key in expected state: \(keyHex)")
            }
            expectedMap[keyHex] = valueHex
        }

        let allKeys = Set(targetMap.keys).union(Set(expectedMap.keys))
        var differences: [String] = []

        for key in allKeys.sorted() {
            let targetValue = targetMap[key]
            let expectedValue = expectedMap[key]

            if targetValue != expectedValue {
                let targetStr = targetValue ?? "<missing>"
                let expectedStr = expectedValue ?? "<missing>"
                differences.append("Key \(key):\n  Target:   \(targetStr)\n  Expected: \(expectedStr)")
            }
        }

        logger.error("📊 STATE DIFF REPORT (Block \(blockIndex)) - Target vs Expected:")
        logger.error("   Total differences: \(differences.count)")
        logger.error("   Target state keys: \(targetMap.count)")
        logger.error("   Expected state keys: \(expectedMap.count)")

        if !duplicateTargetKeys.isEmpty {
            logger.error("   Duplicate keys in target: \(duplicateTargetKeys.count)")
        }
        if !duplicateExpectedKeys.isEmpty {
            logger.error("   Duplicate keys in expected: \(duplicateExpectedKeys.count)")
        }

        for diff in differences {
            logger.error("   \(diff)")
        }
    }
}
