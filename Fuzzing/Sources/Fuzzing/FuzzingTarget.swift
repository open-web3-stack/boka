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
    private var currentStateRef: StateRef?

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
        socket = FuzzingSocket(socketPath: socketPath, config: self.config)

        logger.info("Boka Fuzzing Target initialized on socket \(socketPath)")
    }

    public func run() async throws {
        try socket.create()

        let connection = try socket.acceptConnection()

        try await handleFuzzer(connection: connection)

        connection.close()
        logger.info("Connection closed")
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

        case let .importBlock(block):
            try await handleImportBlock(block: block, connection: connection)

        case let .setState(setState):
            try await handleSetState(setState: setState, connection: connection)

        case let .getState(headerHash):
            try await handleGetState(headerHash: headerHash, connection: connection)

        case .state, .stateRoot:
            logger.warning("Received response message (ignored)")
        }
    }

    private func handleHandShake(peerInfo: FuzzPeerInfo, connection: FuzzingSocketConnection) async throws {
        logger.info("Handshake from: \(peerInfo.name), App Version: \(peerInfo.appVersion), Jam Version: \(peerInfo.jamVersion)")
        let message = FuzzingMessage.peerInfo(FuzzPeerInfo(name: "boka-fuzzing-target"))
        try connection.sendMessage(message)
        logger.info("Handshake completed")
    }

    private func handleImportBlock(block: Block, connection: FuzzingSocketConnection) async throws {
        logger.info("IMPORT BLOCK: \(block.header.hash().description)")
        logger.info("Block number: \(block.header.timeslot)")

        do {
            guard let stateRef = currentStateRef else { throw FuzzingTargetError.stateNotSet }

            let blockRef = try block.asRef().toValidated(config: config)
            let newStateRef = try await runtime.apply(block: blockRef, state: stateRef)

            currentStateRef = newStateRef

            logger.info("IMPORT BLOCK completed")
            let stateRoot = await currentStateRef?.value.stateRoot ?? Data32()
            let response = FuzzingMessage.stateRoot(stateRoot)
            try connection.sendMessage(response)
        } catch {
            logger.error("❌ Failed to import block: \(error)")
            let stateRoot = await currentStateRef?.value.stateRoot ?? Data32()
            let response = FuzzingMessage.stateRoot(stateRoot)
            try connection.sendMessage(response)
        }
    }

    private func handleSetState(setState: FuzzSetState, connection: FuzzingSocketConnection) async throws {
        logger.info("SET STATE: \(setState.state.count) key-value pairs")

        do {
            // set state
            let rawKV = setState.state.map { (key: $0.key, value: $0.value) }
            let backend = StateBackend(InMemoryBackend(), config: config, rootHash: Data32())
            try await backend.writeRaw(rawKV)
            let state = try await State(backend: backend)
            let stateRef = state.asRef()

            // check state root
            let root = await stateRef.value.stateRoot
            logger.info("State root: \(root)")

            currentStateRef = stateRef

            logger.info("SET STATE completed")
            let response = FuzzingMessage.stateRoot(root)
            try connection.sendMessage(response)
        } catch {
            logger.error("❌ Failed to set state: \(error)")
            let stateRoot = await currentStateRef?.value.stateRoot ?? Data32()
            let response = FuzzingMessage.stateRoot(stateRoot)
            try connection.sendMessage(response)
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
