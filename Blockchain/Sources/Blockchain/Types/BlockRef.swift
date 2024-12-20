import Utils

public final class BlockRef: Ref<Block>, @unchecked Sendable {
    public required init(_ value: Block) {
        lazyHash = Lazy {
            Ref(value.header.hash())
        }

        super.init(value)
    }

    private let lazyHash: Lazy<Ref<Data32>>

    public var hash: Data32 {
        lazyHash.value.value
    }

    public var header: Header { value.header }
    public var extrinsic: Extrinsic { value.extrinsic }

    override public var description: String {
        "Block(hash: \(hash), timeslot: \(header.timeslot))"
    }
}

extension BlockRef: Codable {
    public convenience init(from decoder: Decoder) throws {
        try self.init(.init(from: decoder))
    }

    public func encode(to encoder: Encoder) throws {
        try value.encode(to: encoder)
    }
}

extension BlockRef {
    public static func dummy(config: ProtocolConfigRef, parent: BlockRef) -> BlockRef {
        dummy(config: config).mutate {
            $0.header.unsigned.parentHash = parent.hash
            $0.header.unsigned.timeslot = parent.header.timeslot + 1
        }
    }
}
