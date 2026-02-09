import Foundation

public enum MerklizeError: Error {
    case invalidIndex
}

/// State Merklization function
///
/// Input is serialized state
public func stateMerklize(kv: [Data31: Data], i: Int = 0) throws(MerklizeError) -> Data32 {
    func branch(l: Data32, r: Data32) -> Data64 {
        var data = l.data + r.data
        data[0] = l.data[0] & 0x7F // clear the highest bit
        return Data64(data)!
    }

    func embeddedLeaf(key: Data31, value: Data, size: UInt8) -> Data64 {
        var data = Data(capacity: 64)
        data.append(0b1000_0000 | size)
        data += key.data
        data += value
        data.append(contentsOf: repeatElement(0, count: 32 - Int(size)))
        return Data64(data)!
    }

    func regularLeaf(key: Data31, value: Data) -> Data64 {
        var data = Data(capacity: 64)
        data.append(0b1100_0000)
        data += key.data
        data += value.blake2b256hash().data
        return Data64(data)!
    }

    func leaf(key: Data31, value: Data) -> Data64 {
        if value.count <= 32 {
            embeddedLeaf(key: key, value: value, size: UInt8(value.count))
        } else {
            regularLeaf(key: key, value: value)
        }
    }

    // bit at i, returns true if it is 1
    func bit(_ data: Data, _ i: Int) throws(MerklizeError) -> Bool {
        let byteIndex = i / 8
        guard byteIndex < data.count else {
            throw MerklizeError.invalidIndex
        }
        let byte = data[data.startIndex + byteIndex]
        return (byte & (1 << (7 - (i % 8)))) != 0
    }

    if kv.isEmpty {
        return Data32()
    }

    if kv.count == 1, let first = kv.first {
        return leaf(key: first.key, value: first.value).blake2b256hash()
    }

    var l: [Data31: Data] = [:]
    var r: [Data31: Data] = [:]
    l.reserveCapacity(kv.count / 2 + 1)
    r.reserveCapacity(kv.count / 2 + 1)

    for (k, v) in kv {
        if try bit(k.data, i) {
            r[k] = v
        } else {
            l[k] = v
        }
    }

    return try branch(l: stateMerklize(kv: l, i: i + 1), r: stateMerklize(kv: r, i: i + 1)).blake2b256hash()
}
