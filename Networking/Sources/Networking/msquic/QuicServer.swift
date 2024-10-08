import Foundation
import Logging
import msquic
import Utils

let serverLogger: Logger = .init(label: "QuicServer")

public protocol QuicServerMessageHandler: AnyObject, Sendable {
    func didReceiveMessage(server: QuicServer, messageID: String, message: QuicMessage) async
    func didReceiveError(server: QuicServer, messageID: String, error: QuicError) async
}

public actor QuicServer: Sendable, QuicListenerMessageHandler {
    private var api: UnsafePointer<QuicApiTable>
    private var registration: HQuic?
    private var configuration: HQuic?
    private var listener: QuicListener?
    private let config: QuicConfig
    private weak var messageHandler: QuicServerMessageHandler?
    private var pendingMessages: [String: (QuicConnection, QuicStream)]

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
            api: boundPointer, registration: registration, configuration: configuration, config: config,
            messageHandler: self
        )
    }

    public func close() async {
        if let listener {
            await listener.close()
            self.listener = nil
        }
        if let configuration {
            api.pointee.ConfigurationClose(configuration)
            self.configuration = nil
        }
        if let registration {
            api.pointee.RegistrationClose(registration)
            self.registration = nil
        }
        MsQuicClose(api)
    }

    // Respond to a message with a specific messageID using Data
    func respondGetStatus(to messageID: String, with data: Data, kind: StreamKind? = nil) async
        -> QuicStatus
    {
        var status = QuicStatusCode.internalError.rawValue
        if let (_, stream) = pendingMessages[messageID] {
            let streamKind = kind ?? stream.kind
            pendingMessages.removeValue(forKey: messageID)
            status = stream.send(with: data, kind: streamKind)
        } else {
            serverLogger.error("Message not found")
        }
        return status
    }

    public func didReceiveMessage(
        connection: QuicConnection, stream: QuicStream, message: QuicMessage
    ) async {
        switch message.type {
        case .received:
            let messageID = UUID().uuidString
            pendingMessages[messageID] = (connection, stream)
            // Call messageHandler safely in the actor context
            Task { [weak self] in
                guard let self else { return }
                await messageHandler?.didReceiveMessage(server: self, messageID: messageID, message: message)
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
