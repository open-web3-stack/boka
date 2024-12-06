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
        let data = try read(length: 8)
        return data.withUnsafeBytes { (pointer: UnsafeRawBufferPointer) -> UInt64 in
            pointer.load(as: UInt64.self)
        }
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
