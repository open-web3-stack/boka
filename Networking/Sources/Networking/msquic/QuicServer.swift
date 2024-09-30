import Foundation
import Logging
import msquic
import Utils

let serverLogger: Logger = .init(label: "QuicServer")

public protocol QuicServerMessageHandler: AnyObject, Sendable {
    func didReceiveMessage(messageID: Int64, message: QuicMessage) async
    func didReceiveError(messageID: Int64, error: QuicError) async
}

public actor QuicServer: Sendable {
    private var api: UnsafePointer<QuicApiTable>?
    private var registration: HQuic?
    private var configuration: HQuic?
    private var listener: QuicListener?
    private let config: QuicConfig
    private weak var messageHandler: QuicServerMessageHandler?
    private var pendingMessages: [Int64: (QuicConnection, QuicStream)]

    init(config: QuicConfig, messageHandler: QuicServerMessageHandler? = nil) async throws {
        self.config = config
        self.messageHandler = messageHandler
        pendingMessages = [:]
        var rawPointer: UnsafeRawPointer?
        let status: UInt32 = MsQuicOpenVersion(2, &rawPointer)

        if QuicStatus(status).isFailed {
            throw QuicError.invalidStatus(status: status.code)
        }
        guard
            let boundPointer: UnsafePointer<QuicApiTable> = rawPointer?.assumingMemoryBound(
                to: QuicApiTable.self
            )
        else {
            throw QuicError.getApiFailed
        }

        var registrationHandle: HQuic?
        let registrationStatus = boundPointer.pointee.RegistrationOpen(nil, &registrationHandle)
        if QuicStatus(registrationStatus).isFailed {
            throw QuicError.invalidStatus(status: registrationStatus.code)
        }
        api = boundPointer
        registration = registrationHandle
        try config.loadConfiguration(
            api: api, registration: registration, configuration: &configuration
        )
        listener = try QuicListener(
            api: api, registration: registration, configuration: configuration, config: config,
            messageHandler: self
        )
    }

    deinit {
        closeSync()
    }

    nonisolated func closeSync() {
        Task { [weak self] in
            await self?.close() // Using weak self to avoid retain cycle
            serverLogger.info("QuicServer Deinit")
        }
    }

    private func close() {
        guard let listener else { return }
        listener.close()
        self.listener = nil
        serverLogger.debug("QuicListener close")
        guard let configuration else { return }
        api?.pointee.ConfigurationClose(configuration)
        self.configuration = nil
        serverLogger.debug("configuration close")
        guard let registration else { return }
        api?.pointee.RegistrationClose(registration)
        self.registration = nil
        serverLogger.debug("registration close")
        guard let api else { return }
        MsQuicClose(api)
        self.api = nil
        serverLogger.debug("QuicServer Close")
    }

    // Respond to a message with a specific messageID using Data
    func respondTo(messageID: Int64, with data: Data, kind: StreamKind? = nil) -> QuicStatus {
        var status = QuicStatusCode.internalError.rawValue
        if let (_, stream) = pendingMessages[messageID] {
            let streamKind = kind ?? stream.kind
            status = stream.send(data: data, kind: streamKind)
            pendingMessages.removeValue(forKey: messageID)
        } else {
            serverLogger.error("Message not found")
        }
        return status
    }

    // Respond to a message with a specific messageID using Data
    func respondingTo(messageID: Int64, with data: Data, kind: StreamKind? = nil) async throws
        -> QuicMessage
    {
        guard let (_, stream) = pendingMessages[messageID] else {
            serverLogger.error("Message not found")
            throw QuicError.messageNotFound
        }

        let streamKind = kind ?? stream.kind
        pendingMessages.removeValue(forKey: messageID)

        let quicMessage = try await Task {
            try await self.sendStreamData(stream: stream, data: data, kind: streamKind)
        }.value
        return quicMessage
    }

    private nonisolated func sendStreamData(stream: QuicStream, data: Data, kind: StreamKind)
        async throws -> QuicMessage
    {
        try await stream.send(buffer: data, kind: kind)
    }
}

extension QuicServer: QuicListenerMessageHandler {
    public func didReceiveMessage(
        connection: QuicConnection, stream: QuicStream, message: QuicMessage
    ) async {
        switch message.type {
        case .received:
            let messageID = Int64(Date().timeIntervalSince1970 * 1000)
            pendingMessages[messageID] = (connection, stream)

            // Call messageHandler safely in the actor context
            Task { [weak self] in
                guard let self else { return }
                await messageHandler?.didReceiveMessage(messageID: messageID, message: message)
            }
        default:
            break
        }
    }

    public func didReceiveError(
        connection _: QuicConnection, stream _: QuicStream, error: QuicError
    ) async {
        serverLogger.error("Failed to receive message: \(error)")
    }
}
