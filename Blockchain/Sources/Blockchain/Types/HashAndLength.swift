import Utils

public struct HashAndLength: Sendable, Codable, Comparable {
    public var hash: Data32
    public var length: DataLength

    public init(hash: Data32, length: DataLength) {
        self.hash = hash
        self.length = length
    }

    public static func < (lhs: HashAndLength, rhs: HashAndLength) -> Bool {
        if lhs.hash == rhs.hash {
            return lhs.length < rhs.length
        }
        return lhs.hash < rhs.hash
    }
}

extension HashAndLength: Hashable {
    public func hash(into hasher: inout Hasher) {
        // we assume hash is alraedy a high quality hash
        // and we know the output is 32 bytes
        // so we can just take the first 4 bytes and should be good enough
        // NOTE: we will never use the Hashable protocol for any critical operations
        hasher.combine(hash.data[hash.data.startIndex ..< hash.data.startIndex + 4])
    }
}
