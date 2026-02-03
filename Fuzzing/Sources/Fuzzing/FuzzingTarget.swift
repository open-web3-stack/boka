import Blockchain
import Codec
import Foundation
import TracingUtils
import Utils

private let logger = Logger(label: "FuzzingTarget")

public class FuzzingTarget {
    public enum FuzzingTargetError: Error {
        case invalidConfig
        case stateNotSet
    }

    private let socket: FuzzingSocket
    private let runtime: Runtime
    private let config: ProtocolConfigRef
    private var currentStateRef: StateRef? // the latest STF result
    private var baseStateRef: StateRef? // fork base state (changes on chain extensions)
    private var negotiatedFeatures: UInt32 = 0

    public init(socketPath: String, config: String) throws {
        switch config {
        case "tiny":
            self.config = ProtocolConfigRef.tiny
        case "full":
            self.config = ProtocolConfigRef.mainnet
        default:
            logger.error("Invalid config: \(config). Only 'tiny' or 'full' allowed.")
            throw FuzzingTargetError.invalidConfig
        }

        runtime = Runtime(config: self.config)
        currentStateRef = nil
        baseStateRef = nil
        socket = FuzzingSocket(socketPath: socketPath, config: self.config)

        logger.info("Boka Fuzzing Target initialized on socket \(socketPath)")
    }

    public func run() async throws {
        try socket.create()

        logger.info("Fuzzing target listening for connections")

        while true {
            do {
                logger.info("Waiting for new connection")
                let connection = try socket.acceptConnection()

                try await handleFuzzer(connection: connection)

                connection.close()
                logger.info("Connection closed, waiting for next connection")
            } catch {
                logger.error("Error handling connection: \(error)")
            }
        }
    }

    private func handleFuzzer(connection: FuzzingSocketConnection) async throws {
        logger.info("New fuzzer connected")

        var messageCount = 0
        while true {
            guard let message = try connection.receiveMessage() else { break }
            messageCount += 1
            logger.info("✉️  Message #\(messageCount)")
            try await handleMessage(message: message, connection: connection)
        }
    }

    private func handleMessage(message: FuzzingMessage, connection: FuzzingSocketConnection) async throws {
        switch message {
        case let .peerInfo(peerInfo):
            try await handleHandShake(peerInfo: peerInfo, connection: connection)

        case let .initialize(initialize):
            try await handleInitialize(initialize: initialize, connection: connection)

        case let .importBlock(block):
            try await handleImportBlock(block: block, connection: connection)

        case let .getState(headerHash):
            try await handleGetState(headerHash: headerHash, connection: connection)

        case .state, .stateRoot, .error:
            logger.warning("Received response message \(message), ignored")
        }
    }

    private func handleHandShake(peerInfo: FuzzPeerInfo, connection: FuzzingSocketConnection) async throws {
        logger.info("Handshake from: \(peerInfo.appName), App Version: \(peerInfo.appVersion), Jam Version: \(peerInfo.jamVersion)")
        logger.info("   Fuzz version: \(peerInfo.fuzzVersion)")

        // fuzzer features
        let ancestryEnabled = (peerInfo.fuzzFeatures & FEATURE_ANCESTRY) != 0
        let forkEnabled = (peerInfo.fuzzFeatures & FEATURE_FORK) != 0
        logger.info("   Fuzzer features: ANCESTRY=\(ancestryEnabled), FORK=\(forkEnabled)")

        let targetPeerInfo = FuzzPeerInfo(
            name: "boka-fuzzing-target",
            fuzzFeatures: FEATURE_ANCESTRY | FEATURE_FORK,
        )
        // our features
        let ourAncestryEnabled = (targetPeerInfo.fuzzFeatures & FEATURE_ANCESTRY) != 0
        let ourForkEnabled = (targetPeerInfo.fuzzFeatures & FEATURE_FORK) != 0
        logger.info("   Our features: ANCESTRY=\(ourAncestryEnabled), FORK=\(ourForkEnabled)")

        // negotiated features (intersection of fuzzer and target features)
        negotiatedFeatures = peerInfo.fuzzFeatures & targetPeerInfo.fuzzFeatures
        let negotiatedAncestryEnabled = (negotiatedFeatures & FEATURE_ANCESTRY) != 0
        let negotiatedForkEnabled = (negotiatedFeatures & FEATURE_FORK) != 0
        logger.info("   Negotiated features: ANCESTRY=\(negotiatedAncestryEnabled), FORK=\(negotiatedForkEnabled)")

        let message = FuzzingMessage.peerInfo(targetPeerInfo)
        try connection.sendMessage(message)

        logger.info("Handshake completed")
    }

    private func handleImportBlock(block: Block, connection: FuzzingSocketConnection) async throws {
        logger.info("IMPORT BLOCK: \(block.header.hash().description)")
        logger.info("Block slot: \(block.header.timeslot)")

        do {
            guard let currentStateRef else { throw FuzzingTargetError.stateNotSet }

            let workingStateRef: StateRef

            if (negotiatedFeatures & FEATURE_FORK) != 0 {
                // has fork feature
                guard let baseStateRef else { throw FuzzingTargetError.stateNotSet }

                let baseParent = baseStateRef.value.lastBlockHash
                let currentParent = currentStateRef.value.lastBlockHash

                if block.header.parentHash == currentParent, currentParent != baseParent {
                    // extends from current - advance base to current
                    self.baseStateRef = currentStateRef
                }

                // operate on a copy of base state
                workingStateRef = try await createStateCopy(from: self.baseStateRef!)
            } else {
                // no fork feature
                workingStateRef = currentStateRef
            }

            let newStateRef = try await runtime.apply(block: block.asRef(), state: workingStateRef)

            self.currentStateRef = newStateRef

            logger.info("IMPORT BLOCK completed")
            let stateRoot = await newStateRef.value.stateRoot
            logger.info("State root: \(stateRoot)")
            let response = FuzzingMessage.stateRoot(stateRoot)
            try connection.sendMessage(response)
        } catch {
            logger.error("❌ Failed to import block: \(error)")
            let errorMsg = "Chain error: block import failure: \(error)"
            let response = FuzzingMessage.error(errorMsg)
            try connection.sendMessage(response)
        }
    }

    private func createStateCopy(from stateRef: StateRef) async throws -> StateRef {
        let keyValuePairs = try await stateRef.value.backend.getKeys(nil, nil, nil)
        let newBackend = StateBackend(InMemoryBackend(), config: config, rootHash: Data32())
        try await newBackend.writeRaw(keyValuePairs.map { (key: Data31($0.key)!, value: $0.value as Data?) })
        let newState = try await State(backend: newBackend)
        return newState.asRef()
    }

    private func handleInitialize(initialize: FuzzInitialize, connection: FuzzingSocketConnection) async throws {
        logger.info("INITIALIZE STATE: \(initialize.state.count) key-value pairs")
        logger.info("   Header: \(initialize.header.hash())")
        logger.info("   Ancestry: \(initialize.ancestry.count) items")

        do {
            if (negotiatedFeatures & FEATURE_ANCESTRY) != 0 {
                runtime.ancestry = try .init(config: config, array: initialize.ancestry)
                logger.info("   Ancestry feature enabled, set \(initialize.ancestry.count) ancestry items")
            } else {
                runtime.ancestry = nil
                logger.info("   Ancestry feature disabled")
            }

            // set state
            let rawKV = initialize.state.map { (key: $0.key, value: $0.value) }
            let backend = StateBackend(InMemoryBackend(), config: config, rootHash: Data32())
            try await backend.writeRaw(rawKV)
            let state = try await State(backend: backend)
            let stateRef = state.asRef()

            // check state root
            let root = await stateRef.value.stateRoot
            logger.info("State root: \(root)")

            currentStateRef = stateRef

            // create base state copy if fork feature is enabled
            if (negotiatedFeatures & FEATURE_FORK) != 0 {
                baseStateRef = try await createStateCopy(from: stateRef)
            } else {
                baseStateRef = nil
            }

            logger.info("INITIALIZE STATE completed")
            let response = FuzzingMessage.stateRoot(root)
            try connection.sendMessage(response)
        } catch {
            logger.error("❌ Failed to initialize state: \(error)")
            if let currentStateRef {
                let response = await FuzzingMessage.stateRoot(currentStateRef.value.stateRoot)
                try connection.sendMessage(response)
            } else {
                logger.error("No head state root available")
                throw error
            }
        }
    }

    private func handleGetState(headerHash: FuzzGetState, connection: FuzzingSocketConnection) async throws {
        logger.info("GET STATE request for header: \(headerHash)")

        do {
            guard let currentStateRef else { throw FuzzingTargetError.stateNotSet }

            // Get all key-value pairs from the state backend
            let keyValuePairs = try await currentStateRef.value.backend.getKeys(nil, nil, nil)
            let fuzzKeyValues: [FuzzKeyValue] = keyValuePairs.map { FuzzKeyValue(key: Data31($0.key)!, value: $0.value) }

            logger.info("GET STATE completed: \(fuzzKeyValues.count) key-value pairs found")
            let response = FuzzingMessage.state(fuzzKeyValues)
            try connection.sendMessage(response)
        } catch {
            logger.error("❌ Failed to get state: \(error)")
            let response = FuzzingMessage.state([])
            try connection.sendMessage(response)
        }
    }
}
