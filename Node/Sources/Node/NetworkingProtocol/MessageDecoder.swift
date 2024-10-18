import Blockchain
import Codec
import Dispatch
import Foundation
import Networking
import Synchronization
import TracingUtils

/// single producer, single consumer
/// run decode on a detached thread
private final class MessageDecoderImpl: Sendable {
    private let input = AsyncDataInput()

    init(
        config: ProtocolConfigRef,
        type: Decodable.Type,
        repeats: Bool,
        onResult: @escaping @Sendable (Result<Decodable, Error>) -> Void
    ) {
        let input = input

        Thread.detachNewThread {
            let decoder = JamDecoder(data: input, config: config)
            repeat {
                do {
                    let res = try decoder.decode(type)
                    if !repeats {
                        guard input.close() else {
                            // remaining data
                            onResult(.failure(DecodingError.dataCorrupted(DecodingError.Context(
                                codingPath: [],
                                debugDescription: "Not all data was consumed"
                            ))))
                            return
                        }
                    }
                    onResult(.success(res))
                } catch {
                    onResult(.failure(error))
                    return // end thread
                }
            } while repeats
        }
    }

    func append(data: Data) throws {
        try input.append(data: data)
    }

    func finish() {
        input.close()
    }
}

public class RequestMessageDecoder: MessageDecoder {
    public typealias Message = Request

    private let decoder: MessageDecoderImpl

    init(config: ProtocolConfigRef, kind: CommonEphemeralStreamKind, onResult: @escaping @Sendable (Result<Request, Error>) -> Void) {
        decoder = MessageDecoderImpl(
            config: config,
            type: Request.getType(kind: kind),
            repeats: false,
            onResult: { result in
                switch result {
                case let .success(req):
                    let req = Request.from(kind: kind, data: req)
                    guard let req else {
                        onResult(.failure(AssertionError.unreachable("invalid request")))
                        return
                    }
                    onResult(.success(req))
                case let .failure(error):
                    onResult(.failure(error))
                }
            }
        )
    }

    public func decode(data: Data) throws {
        try decoder.append(data: data)
    }

    public func finish() {
        decoder.finish()
    }
}
