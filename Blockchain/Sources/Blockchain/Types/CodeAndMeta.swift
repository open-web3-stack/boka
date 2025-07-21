import Codec
import TracingUtils
import Utils

private let logger = Logger(label: "CodeAndMeta")

public struct Metadata: Sendable, Equatable, Codable {
    public let formatVersion: UInt8
    public let programName: Data
    public let version: Data
    public let license: Data
    public let authors: [Data]
}

extension Metadata: CustomStringConvertible {
    public var description: String {
        var result = "\(String(data: programName, encoding: .utf8) ?? "") v\(String(data: version, encoding: .utf8) ?? "")"
        if !license.isEmpty {
            result += " (\(String(data: license, encoding: .utf8) ?? ""))"
        }
        if !authors.isEmpty {
            result += " by \(authors.map { String(data: $0, encoding: .utf8) ?? "" }.joined(separator: ", "))"
        }
        return result
    }
}

/// account preimage data is: meta length + meta + code
public struct CodeAndMeta: Sendable, Equatable {
    public enum Error: Swift.Error {
        case invalidMetadataLength
    }

    public var metadata: Metadata
    public var codeBlob: Data

    public init(data: Data) throws {
        var slice = Slice(base: data, bounds: data.startIndex ..< data.endIndex)
        let metaLength = slice.decode()
        guard let metaLength else { throw Error.invalidMetadataLength }
        metadata = try JamDecoder.decode(Metadata.self, from: data[slice.startIndex ..< slice.startIndex + Int(metaLength)])
        logger.debug("Program Metadata: \(metadata)")
        codeBlob = data[slice.startIndex + Int(metaLength) ..< slice.endIndex]
    }
}
