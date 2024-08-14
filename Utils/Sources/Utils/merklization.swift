import Foundation

public enum MerklizeError: Error {
    case invalidIndex
}

/// State Merklization function from GP D.2
///
/// Input is serialized state defined in the GP D.1
public func stateMerklize(kv: [Data32: Data]) throws -> Data32 {
    func branch(l: Data32, r: Data32) -> Data64 {
        var data = l.data + r.data
        data[0] = l.data[0] & 0xFE
        assert(data.count == 64, "branch data should be 64 bytes")
        return Data64(data)!
    }

    func embeddedLeaf(key: Data32, value: Data, size: UInt8) -> Data64 {
        var data = Data()
        data.reserveCapacity(64)
        data[0] = 0b01 | (size << 2)
        data += key.data[..<31]
        data += value
        data.append(contentsOf: repeatElement(0, count: 32 - Int(size)))
        assert(data.count == 64, "embeddedLeaf data should be 64 bytes")
        return Data64(data)!
    }

    func regularLeaf(key: Data32, value: Data) throws -> Data64 {
        var data = Data()
        data.reserveCapacity(64)
        data[0] = 0b11
        data += key.data[..<31]
        data += try blake2b256(value).data
        assert(data.count == 64, "regularLeaf data should be 64 bytes")
        return Data64(data)!
    }

    func leaf(key: Data32, value: Data) throws -> Data64 {
        if value.count <= 32 {
            embeddedLeaf(key: key, value: value, size: UInt8(value.count))
        } else {
            try regularLeaf(key: key, value: value)
        }
    }

    /// bit at index i, returns true if it is 1
    func bit(_ bits: Data, _ i: Int) throws -> Bool {
        guard let byte = bits[safe: i / 8] else {
            throw MerklizeError.invalidIndex
        }
        return (byte & (1 << (7 - i % 8))) == 1
    }

    if kv.isEmpty {
        return Data32()
    }

    if kv.count == 1 {
        return try blake2b256(leaf(key: kv.first!.key, value: kv.first!.value).data)
    }

    var l: [Data32: Data] = [:]
    var r: [Data32: Data] = [:]
    for (k, v) in kv {
        if try bit(k.data, 0) {
            r[k] = v
        } else {
            l[k] = v
        }
    }

    return try blake2b256(branch(l: stateMerklize(kv: l), r: stateMerklize(kv: r)).data)
}
