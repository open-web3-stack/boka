import Utils

/// Thread-safe reference wrapper for Block with cached hash
///
/// Thread-safety: @unchecked Sendable is inherited from RefWithHash<T>
/// which provides synchronization for immutable value access
public final class BlockRef: RefWithHash<Block>, @unchecked Sendable {
    public var header: Header {
        value.header
    }

    public var extrinsic: Extrinsic {
        value.extrinsic
    }

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
