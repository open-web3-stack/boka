import Utils

public struct HashAndLength: Sendable, Codable {
    public var hash: Data32
    public var length: DataLength

    public init(hash: Data32, length: DataLength) {
        self.hash = hash
        self.length = length
    }
}

extension HashAndLength: Hashable {
    public func hash(into hasher: inout Hasher) {
        // we assume hash is alraedy a high quality hash
        // and we know the output is 32 bytes
        // so we can just take the first 4 bytes and should be good enough
        // NOTE: we will never use the Hashable protocol for any critical operations
        hasher.combine(hash.data[0 ..< 4])
    }
}
