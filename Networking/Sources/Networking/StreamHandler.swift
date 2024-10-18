import Foundation

public protocol StreamKindProtocol: Sendable, Hashable, RawRepresentable<UInt8>, CaseIterable {}

public protocol MessageProtocol: Sendable {
    func encode() throws -> Data
}

public protocol RequestProtocol<StreamKind>: MessageProtocol {
    associatedtype StreamKind: StreamKindProtocol

    var kind: StreamKind { get }
}

public protocol MessageDecoder<Message> {
    associatedtype Message

    // return nil if need more data
    // data will be kept in internal buffer
    mutating func decode(data: Data) throws

    consuming func finish()
}

public protocol PresistentStreamHandler: Sendable {
    associatedtype StreamKind: StreamKindProtocol
    associatedtype Message: MessageProtocol

    func createDecoder(kind: StreamKind, onResult: @escaping @Sendable (Result<Message, Error>) -> Void) -> any MessageDecoder<Message>
    func streamOpened(connection: any ConnectionInfoProtocol, stream: any StreamProtocol, kind: StreamKind) throws
    func handle(connection: any ConnectionInfoProtocol, message: Message) throws
}

public protocol EphemeralStreamHandler: Sendable {
    associatedtype StreamKind: StreamKindProtocol
    associatedtype Request: RequestProtocol<StreamKind>

    func createDecoder(kind: StreamKind, onResult: @escaping @Sendable (Result<Request, Error>) -> Void) -> any MessageDecoder<Request>
    func handle(connection: any ConnectionInfoProtocol, request: Request) async throws -> Data
}

public protocol StreamHandler: Sendable {
    associatedtype PresistentHandler: PresistentStreamHandler
    associatedtype EphemeralHandler: EphemeralStreamHandler
}

extension Data: MessageProtocol {
    public func encode() -> Data {
        self
    }
}
