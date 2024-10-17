import Foundation

public protocol StreamKindProtocol: Sendable, Hashable, RawRepresentable<UInt8>, CaseIterable {}

public protocol MessageProtocol {
    func encode() -> Data
}

public protocol RequestProtocol<StreamKind>: MessageProtocol {
    associatedtype StreamKind: StreamKindProtocol

    var kind: StreamKind { get }
}

public protocol MessageDecoder<Message> {
    associatedtype Message

    // return nil if need more data
    // data will be kept in internal buffer
    func decode(data: Data) throws -> Message?

    // return leftover data
    func finish() -> Data?
}

public protocol PresistentStreamHandler: Sendable {
    associatedtype StreamKind: StreamKindProtocol
    associatedtype Message: MessageProtocol

    func createDecoder(kind: StreamKind) -> any MessageDecoder<Message>
    func streamOpened(stream: any StreamProtocol, kind: StreamKind) throws
    func handle(message: Message) throws
}

public protocol EphemeralStreamHandler: Sendable {
    associatedtype StreamKind: StreamKindProtocol
    associatedtype Request: RequestProtocol<StreamKind>

    func createDecoder(kind: StreamKind) -> any MessageDecoder<Request>
    func handle(request: Request) async throws -> Data
}

public protocol StreamHandler: Sendable {
    associatedtype PresistentHandler: PresistentStreamHandler
    associatedtype EphemeralHandler: EphemeralStreamHandler
}
