import Atomics
import Foundation
import Logging
import msquic
import Utils

let serverLogger: Logger = .init(label: "QuicServer")

public protocol QuicServerMessageHandler: AnyObject {
    func didReceiveMessage(quicServer: QuicServer, messageID: Int64, message: QuicMessage)
    func didReceiveError(quicServer: QuicServer, messageID: Int64, error: QuicError)
}

public final class QuicServer: @unchecked Sendable {
    private var api: UnsafePointer<QuicApiTable>?
    private var registration: HQuic?
    private var configuration: HQuic?
    private var listener: QuicListener?
    private let config: QuicConfig
    private weak var messageHandler: QuicServerMessageHandler?
    private var pendingMessages: AtomicDictionary<Int64, (QuicConnection, QuicStream)>

    init(config: QuicConfig, messageHandler: QuicServerMessageHandler? = nil) throws {
        self.config = config
        self.messageHandler = messageHandler
        pendingMessages = .init()
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
        try loadConfiguration()
        listener = QuicListener(
            api: api, registration: registration, configuration: configuration, config: config,
            messageHandler: self
        )
        try start()
    }

    deinit {
        close()
        serverLogger.trace("QuicServer Deinit")
    }

    private func start() throws {
        try listener?.openListener(port: config.port)
    }

    func close() {
        if listener != nil {
            listener?.close()
            listener = nil
        }
        if configuration != nil {
            api?.pointee.ConfigurationClose(configuration)
            configuration = nil
        }
        if registration != nil {
            api?.pointee.RegistrationClose(registration)
            registration = nil
        }
        if api != nil {
            MsQuicClose(api)
            api = nil
        }
        serverLogger.info("QuicServer Close")
    }

    // Respond to a message with a specific messageID using Data
    func respondTo(messageID: Int64, with data: Data, kind: StreamKind? = nil) -> QuicStatus {
        var status = QuicStatusCode.internalError.rawValue
        if let (_, stream) = pendingMessages[messageID] {
            let streamKind = kind ?? stream.kind
            status = stream.send(buffer: data, kind: streamKind)
            _ = pendingMessages.removeValue(forKey: messageID)
        } else {
            peerLogger.error("Message not found")
        }
        return status
    }

    // Respond to a message with a specific messageID using Data
    func respondTo(messageID: Int64, with data: Data, kind: StreamKind? = nil) async throws {
        if let (_, stream) = pendingMessages[messageID] {
            let streamKind = kind ?? stream.kind
            let quicMessage = try await stream.send(buffer: data, kind: streamKind)
            peerLogger.info("Message sent: \(quicMessage)")
            _ = pendingMessages.removeValue(forKey: messageID)
        } else {
            peerLogger.error("Message not found")
            throw QuicError.messageNotFound
        }
    }
}

extension QuicServer: QuicListenerMessageHandler {
    public func didReceiveMessage(
        connection: QuicConnection, stream: QuicStream, message: QuicMessage
    ) {
        switch message.type {
        case .received:
            processPendingMessage(connection: connection, stream: stream, message: message)
        default:
            break
        }
    }

    public func didReceiveError(
        connection _: QuicConnection, stream _: QuicStream, error: QuicError
    ) {
        logger.error("Failed to receive message: \(error)")
    }

    private func processPendingMessage(
        connection: QuicConnection, stream: QuicStream, message: QuicMessage
    ) {
        let messageID = Int64(Date().timeIntervalSince1970 * 1000)
        pendingMessages[messageID] = (connection, stream)
        messageHandler?.didReceiveMessage(quicServer: self, messageID: messageID, message: message)
    }
}

extension QuicServer {
    private func loadConfiguration() throws {
        try config.loadConfiguration(api: api, registration: registration, configuration: &configuration)
    }
}
