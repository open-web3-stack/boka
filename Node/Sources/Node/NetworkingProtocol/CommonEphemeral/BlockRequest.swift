import Utils

public struct BlockRequest: Codable, Sendable {
    public enum Direction: UInt8, Codable, Sendable {
        case ascendingExcludsive = 0
        case descendingInclusive = 1
    }

    public var hash: Data32
    public var direction: Direction
    public var maxBlocks: UInt32
}
