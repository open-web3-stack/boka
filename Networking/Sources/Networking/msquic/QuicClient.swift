import Atomics
import Foundation
import Logging
import msquic
import NIO

let clientLogger = Logger(label: "QuicClient")

public protocol QuicClientMessageHandler: AnyObject {
    func didReceiveMessage(quicClient: QuicClient, message: QuicMessage)
    // TODO: add error or remove it
    func didReceiveError(quicClient: QuicClient, error: QuicError)
}

public class QuicClient: @unchecked Sendable {
    private var api: UnsafePointer<QuicApiTable>?
    private var registration: HQuic?
    private var configuration: HQuic?
    private var connection: QuicConnection?
    private let config: QuicConfig
    private weak var messageHandler: QuicClientMessageHandler?
    private let isClosed: ManagedAtomic<Bool> = .init(false)

    init(config: QuicConfig, messageHandler: QuicClientMessageHandler? = nil) throws {
        self.config = config
        self.messageHandler = messageHandler
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
        let registrationStatus =
            boundPointer.pointee.RegistrationOpen(nil, &registrationHandle)
        if QuicStatus(registrationStatus).isFailed {
            throw QuicError.invalidStatus(status: registrationStatus.code)
        }

        api = boundPointer
        registration = registrationHandle
    }

    func start() throws -> QuicStatus {
        let status = QuicStatusCode.success.rawValue
        try loadConfiguration()
        connection = QuicConnection(
            api: api, registration: registration, configuration: configuration, messageHandler: self
        )
        try connection?.open()
        try connection?.start(ipAddress: config.ipAddress, port: config.port)
        return status
    }

    // Asynchronous send method that waits for a reply
    func send(message: Data) async throws -> QuicMessage {
        try await send(message: message, streamKind: .uniquePersistent)
    }

    //  send method that not wait for a reply
    func send(message: Data, streamKind: StreamKind) throws -> QuicStatus {
        guard let connection else {
            throw QuicError.getConnectionFailed
        }
        let sendStream: QuicStream
        // Check if there is an existing stream of the same kind
        if streamKind == .uniquePersistent {
            // If there is, send the message to the existing stream
            sendStream = try connection.createOrGetUniquePersistentStream(kind: streamKind)
        } else {
            // If there is not, create a new stream
            sendStream = try connection.createCommonEphemeralStream()
            // Start the stream
            try sendStream.start()
        }
        return sendStream.send(buffer: message, kind: streamKind)
    }

    // Asynchronous send method that waits for a reply
    func send(message: Data, streamKind: StreamKind = .uniquePersistent) async throws -> QuicMessage {
        guard let connection else {
            throw QuicError.getConnectionFailed
        }
        let sendStream: QuicStream
        // Check if there is an existing stream of the same kind
        if streamKind == .uniquePersistent {
            // If there is, send the message to the existing stream
            sendStream = try connection.createOrGetUniquePersistentStream(kind: streamKind)
        } else {
            // If there is not, create a new stream
            sendStream = try connection.createCommonEphemeralStream()
            // Start the stream
            try sendStream.start()
        }
        return try await sendStream.send(buffer: message)
    }

    func getNetAddr() -> NetAddr {
        NetAddr(ipAddress: config.ipAddress, port: config.port)
    }

    func close() {
        if isClosed.compareExchange(expected: false, desired: true, ordering: .acquiring).exchanged {
            if let connection {
                connection.close()
                self.connection = nil
            }

            if let configuration {
                api?.pointee.ConfigurationClose(configuration)
                self.configuration = nil
            }

            if let registration {
                api?.pointee.RegistrationClose(registration)
                self.registration = nil
            }

            if api != nil {
                MsQuicClose(api)
                api = nil
            }

            if let messageHandler {
                messageHandler.didReceiveMessage(
                    quicClient: self, message: QuicMessage(type: .close, data: nil)
                )
            }
            clientLogger.info("QuicClient Close")
        }
    }

    deinit {
        close()
        clientLogger.info("QuicClient Deinit")
    }
}

extension QuicClient: QuicConnectionMessageHandler {
    public func didReceiveMessage(
        connection _: QuicConnection, stream _: QuicStream?, message: QuicMessage
    ) {
        switch message.type {
        case .received:
            let buffer = message.data!
            clientLogger.info(
                "Client received: \(String([UInt8](buffer).map { Character(UnicodeScalar($0)) }))"
            )

        case .shutdownComplete:
            // Use [weak self] to avoid strong reference cycle
            Task { [weak self] in
                guard let self else { return }
                close()
            }

        default:
            break
        }
    }

    public func didReceiveError(
        connection _: QuicConnection, stream _: QuicStream, error: QuicError
    ) {
        clientLogger.error("Failed to receive message: \(error)")
    }
}

extension QuicClient {
    private func loadConfiguration() throws {
        configuration = try QuicConfigHelper.loadConfiguration(
            api: api, registration: registration, config: config
        )
    }
}
