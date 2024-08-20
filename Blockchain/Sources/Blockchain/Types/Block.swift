import Utils

public struct Block: Sendable, Equatable, Codable {
    public var header: Header
    public var extrinsic: Extrinsic

    public init(header: Header, extrinsic: Extrinsic) {
        self.header = header
        self.extrinsic = extrinsic
    }
}

extension Block {
    public func asRef() -> BlockRef {
        BlockRef(self)
    }
}

extension Block: Dummy {
    public typealias Config = ProtocolConfigRef
    public static func dummy(config: Config) -> Block {
        Block(
            header: Header.dummy(config: config),
            extrinsic: Extrinsic.dummy(config: config)
        )
    }
}

public final class BlockRef: Ref<Block>, @unchecked Sendable {
    public required init(_ value: Block) {
        lazy = Lazy {
            Ref(value.header.hash())
        }

        super.init(value)
    }

    private let lazy: Lazy<Ref<Data32>>

    public var hash: Data32 {
        lazy.value.value
    }

    public var header: Header { value.header }
    public var extrinsic: Extrinsic { value.extrinsic }
}

extension BlockRef: Codable {
    public convenience init(from decoder: Decoder) throws {
        try self.init(.init(from: decoder))
    }

    public func encode(to encoder: Encoder) throws {
        try value.encode(to: encoder)
    }
}
