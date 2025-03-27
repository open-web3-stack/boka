import Codec
import Utils

/// account preimage data is meta + code
public struct CodeAndMeta: Sendable, Equatable {
    public enum Error: Swift.Error {
        case invalidMetadataLength
    }

    public var metadata: Data
    public var codeBlob: Data

    // TODO: check if this is correct
    public init(data: Data) throws {
        var slice = Slice(base: data, bounds: data.startIndex ..< data.endIndex)
        let metaLength = slice.decode()
        guard let metaLength else { throw Error.invalidMetadataLength }
        metadata = data[slice.startIndex ..< slice.startIndex + Int(metaLength)]
        codeBlob = data[slice.startIndex + Int(metaLength) ..< slice.endIndex]
    }

    // public init(metadata: Data, codeBlob: Data) {
    //     self.metadata = metadata
    //     self.codeBlob = codeBlob
    // }
}

// extension CodeAndMeta: Codable {
//     private enum CodingKeys: String, CodingKey {
//         case metadata
//         case codeBlob
//     }

//     public func encode(to encoder: Encoder) throws {
//         var container = encoder.container(keyedBy: CodingKeys.self)
//         try container.encode(metadata, forKey: .metadata)
//     }

//     public init(from decoder: Decoder) throws {
//         let container = try decoder.container(keyedBy: CodingKeys.self)
//         metadata = try container.decode(Data.self, forKey: .metadata)
//     }
// }
