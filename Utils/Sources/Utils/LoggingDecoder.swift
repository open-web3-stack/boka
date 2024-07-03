import Foundation
import ScaleCodec

public protocol Logger {
    func log(_ message: String)
}

public struct ConsoleLogger: Logger {
    public init() {}

    public func log(_ message: String) {
        print(message)
    }
}

public struct NoopLogger: Logger {
    public init() {}

    public func log(_: String) {}
}

public struct LoggingDecoder: ScaleCodec.Decoder {
    private var decoder: ScaleCodec.Decoder
    private let logger: Logger

    public init(decoder: ScaleCodec.Decoder, logger: Logger = ConsoleLogger()) {
        self.decoder = decoder
        self.logger = logger
    }

    public var length: Int { decoder.length }
    public var path: [String] { decoder.path }

    public mutating func decode<T: Decodable>() throws -> T {
        logger.log("Decoding \(T.self)")
        let res: T = try decoder.decode()
        logger.log("Done decoding \(T.self) with value \(String(reflecting: res))")
        return res
    }

    public mutating func read(count: Int) throws -> Data {
        logger.log("Reading \(count) bytes")
        return try decoder.read(count: count)
    }

    public func peek(count: Int) throws -> Data {
        logger.log("Peeking \(count) bytes")
        return try decoder.peek(count: count)
    }

    public func peek() throws -> UInt8 {
        logger.log("Peeking 1 byte")
        return try decoder.peek()
    }

    public func skippable() -> SkippableDecoder {
        logger.log("Skipping")
        return decoder.skippable()
    }
}
