import Foundation
import ScaleCodec
import Utils

public struct ExtrinsicPreimages: Sendable {
    public struct SizeAndData: Sendable {
        public var size: DataLength
        public var data: Data

        public init(size: DataLength, data: Data) {
            self.size = size
            self.data = data
        }
    }

    public var preimages: [SizeAndData]

    public init(
        preimages: [SizeAndData]
    ) {
        self.preimages = preimages
    }
}

extension ExtrinsicPreimages: Dummy {
    public typealias Config = ProtocolConfigRef
    public static func dummy(config _: Config) -> ExtrinsicPreimages {
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

extension ExtrinsicPreimages.SizeAndData: ScaleCodec.Codable {
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
