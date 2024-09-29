import Foundation
import Logging
import msquic
import NIO

let clientLogger = Logger(label: "QuicClient")

public protocol QuicClientMessageHandler: AnyObject {
    func didReceiveMessage(quicClient: QuicClient, message: QuicMessage)
    func didReceiveError(quicClient: QuicClient, error: QuicError)
}

public actor QuicClient: Sendable {
    private var api: UnsafePointer<QuicApiTable>?
    private var registration: HQuic?
    private var configuration: HQuic?
    private var connection: QuicConnection?
    private let config: QuicConfig
    private weak var messageHandler: QuicClientMessageHandler?

    public init(config: QuicConfig, messageHandler: QuicClientMessageHandler? = nil) async throws {
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
        try config.loadConfiguration(
            api: api, registration: registration, configuration: &configuration
        )
        connection = try QuicConnection(
            api: api, registration: registration, configuration: configuration, messageHandler: self
        )
        try connection?.start(ipAddress: config.ipAddress, port: config.port)
    }

    deinit {
        closeSync()
    }

    nonisolated func closeSync() {
        clientLogger.info("client closeSync")
        Task { [weak self] in
            await self?.close() // Using weak self to avoid retain cycle
            clientLogger.info("QuicClient Deinit")
        }
    }

    // Asynchronous send method that waits for a QuicMessage reply
    public func send(message: Data) async throws -> QuicMessage {
        try await send(message: message, streamKind: .uniquePersistent)
    }

    // Send method that returns a QuicStatus
    public func send(message: Data, streamKind: StreamKind) async throws -> QuicMessage {
        guard let connection else {
            throw QuicError.getConnectionFailed
        }
        let sendStream: QuicStream =
            if streamKind == .uniquePersistent {
                try await connection.createOrGetUniquePersistentStream(kind: streamKind)
            } else {
                try await connection.createCommonEphemeralStream()
            }
        return try await sendStream.send(buffer: message, kind: streamKind)
    }

    // Send method that returns a QuicStatus
    public func send(data: Data, streamKind: StreamKind) async throws -> QuicStatus {
        guard let connection else {
            throw QuicError.getConnectionFailed
        }
        let sendStream: QuicStream =
            if streamKind == .uniquePersistent {
                try await connection.createOrGetUniquePersistentStream(kind: streamKind)
            } else {
                try await connection.createCommonEphemeralStream()
            }
        return sendStream.send(data: data, kind: streamKind)
    }

    func getNetAddr() -> NetAddr {
        NetAddr(ipAddress: config.ipAddress, port: config.port)
    }

    public func close() async {
        if let connection {
            await connection.close()
            self.connection = nil
            clientLogger.info("QuicConnection close")
        }

        if let configuration {
            api?.pointee.ConfigurationClose(configuration)
            self.configuration = nil
            clientLogger.info("configuration close")
        }

        if let registration {
            api?.pointee.RegistrationClose(registration)
            self.registration = nil
            clientLogger.info("registration close")
        }

        if api != nil {
            MsQuicClose(api)
            api = nil
            clientLogger.info("api close")
        }
        clientLogger.info("QuicClient Close")
    }
}

extension QuicClient: @preconcurrency QuicConnectionMessageHandler {
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
            clientLogger.info(
                "Client[\(getNetAddr())] shutdown"
            )
            // Use [weak self] to avoid strong reference cycle
            Task { [weak self] in
                guard let self else { return }
                await close()
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
