import Foundation

public protocol StreamKindProtocol: Sendable, Hashable, Equatable, RawRepresentable<UInt8>, CaseIterable {}

public protocol MessageProtocol: Sendable {
    func encode() throws -> [Data]
}

public protocol RequestProtocol<StreamKind>: MessageProtocol {
    associatedtype StreamKind: StreamKindProtocol

    var kind: StreamKind { get }
}

public protocol PresistentStreamMessageDecoder<Message> {
    associatedtype Message

    mutating func decode(data: Data) throws -> Message
}

public protocol EphemeralStreamMessageDecoder<Message> {
    associatedtype Message

    mutating func decode(data: [Data]) throws -> Message
}

public protocol PresistentStreamHandler: Sendable {
    associatedtype StreamKind: StreamKindProtocol
    associatedtype Message: MessageProtocol

    func createDecoder(kind: StreamKind) -> any PresistentStreamMessageDecoder<Message>
    func streamOpened(connection: any ConnectionInfoProtocol, stream: any StreamProtocol<Message>, kind: StreamKind) async throws
    func handle(connection: any ConnectionInfoProtocol, message: Message) async throws
}

public protocol EphemeralStreamHandler: Sendable {
    associatedtype StreamKind: StreamKindProtocol
    associatedtype Request: RequestProtocol<StreamKind>

    func createDecoder(kind: StreamKind) -> any EphemeralStreamMessageDecoder<Request>
    func handle(connection: any ConnectionInfoProtocol, request: Request) async throws -> [Data]
}

public protocol StreamHandler: Sendable {
    associatedtype PresistentHandler: PresistentStreamHandler
    associatedtype EphemeralHandler: EphemeralStreamHandler
}
