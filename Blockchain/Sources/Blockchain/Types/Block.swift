import ScaleCodec
import Utils

public struct Block: Sendable {
    public var header: Header
    public var extrinsic: Extrinsic

    public init(header: Header, extrinsic: Extrinsic) {
        self.header = header
        self.extrinsic = extrinsic
    }
}

public typealias BlockRef = Ref<Block>

extension Block: Dummy {
    public typealias Config = ProtocolConfigRef
    public static func dummy(config: Config) -> Block {
        Block(
            header: Header.dummy(config: config),
            extrinsic: Extrinsic.dummy(config: config)
        )
    }
}

extension Block: ScaleCodec.Encodable {
    public init(config: ProtocolConfigRef, from decoder: inout some ScaleCodec.Decoder) throws {
        try self.init(
            header: Header(config: config, from: &decoder),
            extrinsic: Extrinsic(config: config, from: &decoder)
        )
    }

    public func encode(in encoder: inout some ScaleCodec.Encoder) throws {
        try encoder.encode(header)
        try encoder.encode(extrinsic)
    }
}
