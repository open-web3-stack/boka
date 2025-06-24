import Codec
import TracingUtils
import Utils

private let logger = Logger(label: "CodeAndMeta")

/// account preimage data is: meta length + meta + code
public struct CodeAndMeta: Sendable, Equatable {
    public enum Error: Swift.Error {
        case invalidMetadataLength
    }

    public var metadata: Data
    public var codeBlob: Data

    public init(data: Data) throws {
        var slice = Slice(base: data, bounds: data.startIndex ..< data.endIndex)
        let metaLength = slice.decode()
        guard let metaLength else { throw Error.invalidMetadataLength }
        metadata = data[slice.startIndex ..< slice.startIndex + Int(metaLength)]
        logger.debug("Metadata: \(String(data: metadata, encoding: .utf8) ?? "nil")")
        codeBlob = data[slice.startIndex + Int(metaLength) ..< slice.endIndex]
    }
}
