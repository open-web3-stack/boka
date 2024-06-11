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
