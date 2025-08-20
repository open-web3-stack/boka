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
    private let runtime: Runtime
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
        runtime = Runtime(config: self.config)
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

        let message = FuzzingMessage.peerInfo(.init(name: "boka-fuzzing-fuzzer"))
        try connection.sendMessage(message)

        if let response = try connection.receiveMessage(), case let .peerInfo(info) = response {
            logger.info("🤝 Handshake completed with \(info.name), app version: \(info.appVersion), jam version: \(info.jamVersion)")
        } else {
            throw FuzzingClientError.targetNotResponding
        }
    }

    public func runFuzzingSessions() async throws {
        guard let connection else {
            throw FuzzingClientError.connectionFailed
        }

        for blockIndex in 0 ..< blockCount {
            let timeslot = UInt32(blockIndex + 1)
            logger.info("📦 Processing block \(blockIndex + 1)/\(blockCount) for timeslot \(timeslot)")

            // generate state
            let kv = try await fuzzGenerator.generateState(timeslot: timeslot, config: config)

            // set state locally
            let rawKV = kv.map { (key: $0.key, value: $0.value) }
            let backend = StateBackend(InMemoryBackend(), config: config, rootHash: Data32())
            try await backend.writeRaw(rawKV)
            let state = try await State(backend: backend)
            currentStateRef = state.asRef()

            // set state on target
            try await setState(kv: kv, connection: connection)

            // generate a block
            let blockRef = try await fuzzGenerator.generateBlock(
                timeslot: timeslot,
                currentStateRef: currentStateRef!,
                config: config
            )

            // import block locally
            do {
                currentStateRef = try await runtime.apply(block: blockRef, state: currentStateRef!)
            } catch {
                logger.error("❌ Failed to import block locally: \(error)")
                // state remains unchanged, continue with current state
            }
            let currentStateRoot = await currentStateRef!.value.stateRoot

            // import block on target
            let targetStateRoot = try importBlock(block: blockRef.value, connection: connection)

            if currentStateRoot == targetStateRoot {
                logger.info("✅ State roots match for block \(blockIndex + 1)!")
            } else {
                logger.error("❌ STATE ROOT MISMATCH for block \(blockIndex + 1):")
                logger.error("   Fuzzer:  \(currentStateRoot.data.toHexString())")
                logger.error("   Target:  \(targetStateRoot.data.toHexString())")

                let targetState = try getState(connection: connection)

                try await generateMismatchReport(
                    blockIndex: blockIndex + 1,
                    targetState: targetState,
                    localStateRef: currentStateRef!
                )

                break
            }
        }

        logger.info("🎯 Fuzzing session completed - processed \(blockCount) blocks")
    }

    private func setState(kv: [FuzzKeyValue], connection: FuzzingSocketConnection) async throws {
        logger.info("🏗️ SET STATE")

        let dummyHeader = Header.dummy(config: config)
        let setStateMessage = FuzzingMessage.setState(FuzzSetState(header: dummyHeader, state: kv))
        try connection.sendMessage(setStateMessage)

        if let response = try connection.receiveMessage(), case let .stateRoot(root) = response {
            logger.info("🏗️ SET STATE success, root: \(root.data.toHexString())")
        } else {
            throw FuzzingClientError.targetNotResponding
        }
    }

    private func importBlock(block: Block, connection: FuzzingSocketConnection) throws -> Data32 {
        logger.info("📦 IMPORT BLOCK")

        let importMessage = FuzzingMessage.importBlock(block)
        try connection.sendMessage(importMessage)

        if let response = try connection.receiveMessage(), case let .stateRoot(root) = response {
            logger.info("📦 IMPORT BLOCK success, new state root: \(root.data.toHexString())")
            return root
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
        localStateRef: StateRef,
    ) async throws {
        logger.info("📊 Generating mismatch report for block \(blockIndex)")

        let keyValuePairs = try await localStateRef.value.backend.getKeys(nil, nil, nil)
        let localState: [FuzzKeyValue] = keyValuePairs.map { FuzzKeyValue(key: Data31($0.key)!, value: $0.value) }

        let targetMap = Dictionary(uniqueKeysWithValues: targetState.map { (kv: FuzzKeyValue) in
            (kv.key.data.toHexString(), kv.value.toHexString())
        })
        let localMap = Dictionary(uniqueKeysWithValues: localState.map { (kv: FuzzKeyValue) in
            (kv.key.data.toHexString(), kv.value.toHexString())
        })

        let allKeys = Set(targetMap.keys).union(Set(localMap.keys))
        var differences: [String] = []

        for key in allKeys.sorted() {
            let targetValue = targetMap[key]
            let localValue = localMap[key]

            if targetValue != localValue {
                let targetStr = targetValue ?? "<missing>"
                let localStr = localValue ?? "<missing>"
                differences.append("Key \(key):\n  Target: \(targetStr)\n  Local:  \(localStr)")
            }
        }

        logger.error("📊 STATE DIFF REPORT (Block \(blockIndex)):")
        logger.error("   Total differences: \(differences.count)")
        logger.error("   Target state keys: \(targetMap.count)")
        logger.error("   Local state keys: \(localMap.count)")

        for diff in differences {
            logger.error("   \(diff)")
        }
    }
}
