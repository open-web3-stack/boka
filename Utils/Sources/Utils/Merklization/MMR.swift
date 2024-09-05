// TODO: add tests
// Merkle Mountain Range
public struct MMR: Sendable, Equatable, Codable {
    public var peaks: [Data32?]

    public init(_ peaks: [Data32?]) {
        self.peaks = peaks
    }

    public mutating func append(_ data: Data32, hasher: Hashing.Type = Blake2b256.self) {
        append(data, at: 0, hasher: hasher)
    }

    private mutating func append(_ data: Data32, at index: Int, hasher: Hashing.Type = Blake2b256.self) {
        if index >= peaks.count {
            peaks.append(data)
        } else if let current = peaks[index] {
            peaks[index] = nil
            append(hasher.hash(current, data), at: index + 1, hasher: hasher)
        } else {
            peaks[index] = data
        }
    }
}
