import Foundation

public protocol DataInput {
    /// read some data chunk
    /// throw when no more data
    mutating func read(length: Int) throws -> Data

    var isEmpty: Bool { get }
}

extension DataInput {
    public mutating func read() throws -> UInt8 {
        try read(length: 1).first!
    }

    public mutating func decodeUInt64() throws -> UInt64 {
        // TODO: improve this by use `read(minLength: 8)` to avoid read byte by byte
        let res = try IntegerCodec.decode { try self.read() }
        guard let res else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: [],
                    debugDescription: "Not enough data to perform variable length integer decoding"
                )
            )
        }
        return res
    }
}

extension Data: DataInput {
    public mutating func read(length: Int) throws -> Data {
        guard count >= length else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: [],
                    debugDescription: "Not enough data to decode \(length) bytes"
                )
            )
        }
        let res = self[startIndex ..< startIndex + length]
        self = self[startIndex + length ..< endIndex]
        return res
    }
}
