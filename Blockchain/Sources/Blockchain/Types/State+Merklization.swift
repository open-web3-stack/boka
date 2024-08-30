import Codec
import Foundation
import Utils

extension State {
    private static func constructKey(_ idx: UInt8) -> Data32 {
        var data = Data(repeating: 0, count: 32)
        data[0] = idx
        return Data32(data)!
    }

    private static func constructKey(_ idx: UInt8, _ service: ServiceIndex) -> Data32 {
        var data = Data(repeating: 0, count: 32)
        data[0] = idx
        withUnsafeBytes(of: service) { ptr in
            data[1] = ptr.load(as: UInt8.self)
            data[2] = ptr.load(fromByteOffset: 1, as: UInt8.self)
            data[3] = ptr.load(fromByteOffset: 2, as: UInt8.self)
            data[4] = ptr.load(fromByteOffset: 3, as: UInt8.self)
        }
        return Data32(data)!
    }

    private static func constructKey(_ service: ServiceIndex, _ codeHash: Data32) -> Data32 {
        var data = Data(capacity: 32)
        withUnsafeBytes(of: service) { ptr in
            data.append(ptr.load(as: UInt8.self))
            data.append(codeHash.data[0])
            data.append(ptr.load(fromByteOffset: 1, as: UInt8.self))
            data.append(codeHash.data[1])
            data.append(ptr.load(fromByteOffset: 2, as: UInt8.self))
            data.append(codeHash.data[2])
            data.append(ptr.load(fromByteOffset: 3, as: UInt8.self))
            data.append(codeHash.data[3])
        }
        data.append(contentsOf: codeHash.data[4 ..< 28])
        return Data32(data)!
    }

    private func serialize() throws -> [Data32: Data] {
        var res: [Data32: Data] = [:]

        res[Self.constructKey(1)] = try JamEncoder.encode(coreAuthorizationPool)
        res[Self.constructKey(2)] = try JamEncoder.encode(authorizationQueue)
        res[Self.constructKey(3)] = try JamEncoder.encode(recentHistory)
        res[Self.constructKey(4)] = try JamEncoder.encode(safroleState)
        res[Self.constructKey(5)] = try JamEncoder.encode(judgements)
        res[Self.constructKey(6)] = try JamEncoder.encode(entropyPool)
        res[Self.constructKey(7)] = try JamEncoder.encode(validatorQueue)
        res[Self.constructKey(8)] = try JamEncoder.encode(currentValidators)
        res[Self.constructKey(9)] = try JamEncoder.encode(previousValidators)
        res[Self.constructKey(10)] = try JamEncoder.encode(reports)
        res[Self.constructKey(11)] = try JamEncoder.encode(timeslot)
        res[Self.constructKey(12)] = try JamEncoder.encode(privilegedServiceIndices)
        res[Self.constructKey(13)] = try JamEncoder.encode(activityStatistics)

        for (idx, account) in serviceAccounts {
            res[Self.constructKey(255, idx)] = try JamEncoder.encode(account)

            for (hash, value) in account.storage {
                res[Self.constructKey(idx, hash)] = value
            }

            for (hash, value) in account.preimages {
                res[Self.constructKey(idx, hash)] = value
            }

            for (hash, value) in account.preimageInfos {
                // this can be optimized, but mayby later
                var key = hash.hash.data
                key[0 ..< 4] = hash.length.encode()
                for (idx, byte) in key[4 ..< 32].enumerated() {
                    key[idx] = ~byte
                }
                res[Self.constructKey(idx, Data32(key)!)] = try JamEncoder.encode(value)
            }
        }

        return res
    }

    private func encode(_ account: ServiceAccount) throws -> Data {
        let capacity = 32 + 8 * 4 + 4 // codeHash, balance, accumlateGasLimit, onTransferGasLimit, totalByteLength, itemsCount

        let encoder = JamEncoder(capacity: capacity)

        try encoder.encode(account.codeHash)
        try encoder.encode(account.balance)
        try encoder.encode(account.accumlateGasLimit)
        try encoder.encode(account.onTransferGasLimit)

        // derived values
        try encoder.encode(account.totalByteLength)
        try encoder.encode(account.itemsCount)

        return encoder.data
    }

    public func stateRoot() throws -> Data32 {
        try stateMerklize(kv: serialize())
    }
}
