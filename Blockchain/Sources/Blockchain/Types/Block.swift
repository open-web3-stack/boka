import ScaleCodec
import Utils

public struct Block {
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
    public static func dummy(withConfig config: Config) -> Block {
        Block(
            header: Header.dummy(withConfig: config),
            extrinsic: Extrinsic.dummy(withConfig: config)
        )
    }
}

extension Block: ScaleCodec.Encodable {
    public init(withConfig config: ProtocolConfigRef, from decoder: inout some ScaleCodec.Decoder) throws {
        try self.init(
            header: Header(withConfig: config, from: &decoder),
            extrinsic: Extrinsic(withConfig: config, from: &decoder)
        )
    }

    public func encode(in encoder: inout some ScaleCodec.Encoder) throws {
        try encoder.encode(header)
        try encoder.encode(extrinsic)
    }
}
