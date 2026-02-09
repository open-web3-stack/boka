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
            extrinsic: Extrinsic.dummy(config: config),
        )
    }
}

extension Block: Validate {}

extension Block: Hashable32 {
    public func hash() -> Data32 {
        header.hash()
    }
}
