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
        var data = Data()
        data.reserveCapacity(32)
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
        res[Self.constructKey(3)] = try JamEncoder.encode(lastBlock)

        return res
    }
}
