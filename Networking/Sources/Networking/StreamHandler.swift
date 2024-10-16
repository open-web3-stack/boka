import Foundation

public protocol StreamKindProtocol: Sendable, Hashable, RawRepresentable<UInt8>, CaseIterable {}

public protocol Response {
    func encode() -> Data
}

public protocol RequestDecoder<Request> {
    associatedtype Request

    func decode(data: Data) throws
    func finish() throws -> Request
}

public protocol PresistentStreamHandler: Sendable {
    associatedtype StreamKind: StreamKindProtocol

    func streamOpened(stream: any StreamProtocol, kind: StreamKind) throws
    func dataReceived(stream: any StreamProtocol, kind: StreamKind, data: Data) throws
}

public protocol EphemeralStreamHandler: Sendable {
    associatedtype StreamKind: StreamKindProtocol
    associatedtype Request

    func createDecoder(kind: StreamKind) throws -> any RequestDecoder<Request>
    func handle(request: Request) throws -> Response
}

public protocol StreamHandler: Sendable {
    associatedtype PresistentHandler: PresistentStreamHandler
    associatedtype EphemeralHandler: EphemeralStreamHandler
}

extension Data: Response {
    public func encode() -> Data {
        self
    }
}
