import Codec

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

    public func superPeak() -> Data32 {
        func helper(_ peaks: ArraySlice<Data32>) -> Data32 {
            if peaks.count == 0 {
                Data32()
            } else if peaks.count == 1 {
                peaks[0]
            } else {
                Keccak.hash("node", helper(peaks[0 ..< peaks.count - 1]), peaks.last!)
            }
        }

        let nonNilPeaks = peaks.compactMap(\.self)
        return helper(nonNilPeaks[...])
    }
}
