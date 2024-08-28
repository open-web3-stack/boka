import Foundation

public enum MerklizeError: Error {
    case invalidIndex
}

/// State Merklization function from GP D.2
///
/// Input is serialized state defined in the GP D.1
public func stateMerklize(kv: [Data32: Data], i: Int = 0) throws(MerklizeError) -> Data32 {
    func branch(l: Data32, r: Data32) -> Data64 {
        var data = l.data + r.data
        data[0] = l.data[0] & 0xFE
        return Data64(data)!
    }

    func embeddedLeaf(key: Data32, value: Data, size: UInt8) -> Data64 {
        var data = Data()
        data.reserveCapacity(64)
        data.append(0b01 | (size << 2))
        data += key.data[..<31]
        data += value
        data.append(contentsOf: repeatElement(0, count: 32 - Int(size)))
        return Data64(data)!
    }

    func regularLeaf(key: Data32, value: Data) -> Data64 {
        var data = Data()
        data.reserveCapacity(64)
        data.append(0b11)
        data += key.data[..<31]
        data += value.blake2b256hash().data
        return Data64(data)!
    }

    func leaf(key: Data32, value: Data) -> Data64 {
        if value.count <= 32 {
            embeddedLeaf(key: key, value: value, size: UInt8(value.count))
        } else {
            regularLeaf(key: key, value: value)
        }
    }

    /// bit at i, returns true if it is 1
    func bit(_ data: Data, _ i: Int) throws(MerklizeError) -> Bool {
        guard let byte = data[safe: i / 8] else {
            throw MerklizeError.invalidIndex
        }
        return (byte & (1 << (i % 8))) != 0
    }

    if kv.isEmpty {
        return Data32()
    }

    if kv.count == 1 {
        return leaf(key: kv.first!.key, value: kv.first!.value).blake2b256hash()
    }

    var l: [Data32: Data] = [:]
    var r: [Data32: Data] = [:]
    for (k, v) in kv {
        if try bit(k.data, i) {
            r[k] = v
        } else {
            l[k] = v
        }
    }

    return try branch(l: stateMerklize(kv: l, i: i + 1), r: stateMerklize(kv: r, i: i + 1)).blake2b256hash()
}
