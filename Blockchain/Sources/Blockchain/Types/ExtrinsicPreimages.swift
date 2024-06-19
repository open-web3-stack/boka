import Foundation
import ScaleCodec
import Utils

public struct ExtrinsicPreimages {
    public var preimages: [SizeAndData]

    public init(
        preimages: [SizeAndData]
    ) {
        self.preimages = preimages
    }
}

extension ExtrinsicPreimages: Dummy {
    public static var dummy: ExtrinsicPreimages {
        ExtrinsicPreimages(preimages: [])
    }
}

extension ExtrinsicPreimages: ScaleCodec.Codable {
    public init(from decoder: inout some ScaleCodec.Decoder) throws {
        try self.init(
            preimages: decoder.decode()
        )
    }

    public func encode(in encoder: inout some ScaleCodec.Encoder) throws {
        try encoder.encode(preimages)
    }
}

public struct SizeAndData {
    public var size: DataLength
    public var data: Data

    public init(size: DataLength, data: Data) {
        self.size = size
        self.data = data
    }
}

extension SizeAndData: ScaleCodec.Codable {
    public init(from decoder: inout some ScaleCodec.Decoder) throws {
        try self.init(
            size: decoder.decode(),
            data: decoder.decode()
        )
    }

    public func encode(in encoder: inout some ScaleCodec.Encoder) throws {
        try encoder.encode(size)
        try encoder.encode(data)
    }
}
