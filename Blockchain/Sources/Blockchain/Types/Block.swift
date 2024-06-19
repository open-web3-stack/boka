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
    public static var dummy: Block {
        Block(
            header: Header.dummy,
            extrinsic: Extrinsic.dummy
        )
    }
}

extension Block: ScaleCodec.Codable {
    public init(from decoder: inout some ScaleCodec.Decoder) throws {
        try self.init(
            header: decoder.decode(),
            extrinsic: decoder.decode()
        )
    }

    public func encode(in encoder: inout some ScaleCodec.Encoder) throws {
        try encoder.encode(header)
        try encoder.encode(extrinsic)
    }
}
