import Foundation
import Utils

public protocol StateKey: Hashable, Sendable {
    associatedtype Value: Codable & Sendable
    func encode() -> Data31
    static var optional: Bool { get }
}

extension StateKey {
    public func decodeType() -> (Sendable & Codable).Type {
        Value.self
    }

    public static var optional: Bool { false }
}

private func constructKey(_ idx: UInt8) -> Data31 {
    var data = Data(repeating: 0, count: 31)
    data[0] = idx
    return Data31(data)!
}

private func constructKey(_ idx: UInt8, _ service: ServiceIndex) -> Data31 {
    var data = Data(repeating: 0, count: 31)
    data[0] = idx
    withUnsafeBytes(of: service.littleEndian) { ptr in
        data[1] = ptr.load(as: UInt8.self)
        data[3] = ptr.load(fromByteOffset: 1, as: UInt8.self)
        data[5] = ptr.load(fromByteOffset: 2, as: UInt8.self)
        data[7] = ptr.load(fromByteOffset: 3, as: UInt8.self)
    }
    return Data31(data)!
}

private func constructKey(_ service: ServiceIndex, _ val: UInt32, _ data: Data) -> Data31 {
    var stateKey = Data(capacity: 31)

    let valEncoded = val.encode()
    let h = valEncoded + data
    let a = h.blake2b256hash().data[relative: 0 ..< 27]

    withUnsafeBytes(of: service.littleEndian) { servicePtr in
        a.withUnsafeBytes { aPtr in
            stateKey.append(servicePtr.load(as: UInt8.self))
            stateKey.append(aPtr.load(as: UInt8.self))
            stateKey.append(servicePtr.load(fromByteOffset: 1, as: UInt8.self))
            stateKey.append(aPtr.load(fromByteOffset: 1, as: UInt8.self))
            stateKey.append(servicePtr.load(fromByteOffset: 2, as: UInt8.self))
            stateKey.append(aPtr.load(fromByteOffset: 2, as: UInt8.self))
            stateKey.append(servicePtr.load(fromByteOffset: 3, as: UInt8.self))
            stateKey.append(aPtr.load(fromByteOffset: 3, as: UInt8.self))
        }
    }
    stateKey.append(contentsOf: a[relative: 4 ..< 27])
    return Data31(stateKey)!
}

public enum StateKeys {
    public static let prefetchKeys: [any StateKey] = [
        CoreAuthorizationPoolKey(),
        AuthorizationQueueKey(),
        RecentHistoryKey(),
        SafroleStateKey(),
        JudgementsKey(),
        EntropyPoolKey(),
        ValidatorQueueKey(),
        CurrentValidatorsKey(),
        PreviousValidatorsKey(),
        ReportsKey(),
        TimeslotKey(),
        PrivilegedServicesKey(),
        ActivityStatisticsKey(),
        AccumulationQueueKey(),
        AccumulationHistoryKey(),
        LastAccumulationOutputsKey(),
    ]

    public struct CoreAuthorizationPoolKey: StateKey {
        public typealias Value = ConfigFixedSizeArray<
            ConfigLimitedSizeArray<
                Data32,
                ProtocolConfig.Int0,
                ProtocolConfig.MaxAuthorizationsPoolItems
            >,
            ProtocolConfig.TotalNumberOfCores
        >

        public init() {}

        public func encode() -> Data31 {
            constructKey(1)
        }
    }

    public struct AuthorizationQueueKey: StateKey {
        public typealias Value = ConfigFixedSizeArray<
            ConfigFixedSizeArray<
                Data32,
                ProtocolConfig.MaxAuthorizationsQueueItems
            >,
            ProtocolConfig.TotalNumberOfCores
        >

        public init() {}

        public func encode() -> Data31 {
            constructKey(2)
        }
    }

    public struct RecentHistoryKey: StateKey {
        public typealias Value = RecentHistory

        public init() {}

        public func encode() -> Data31 {
            constructKey(3)
        }
    }

    public struct SafroleStateKey: StateKey {
        public typealias Value = SafroleState

        public init() {}

        public func encode() -> Data31 {
            constructKey(4)
        }
    }

    public struct JudgementsKey: StateKey {
        public typealias Value = JudgementsState

        public init() {}

        public func encode() -> Data31 {
            constructKey(5)
        }
    }

    public struct EntropyPoolKey: StateKey {
        public typealias Value = EntropyPool

        public init() {}

        public func encode() -> Data31 {
            constructKey(6)
        }
    }

    public struct ValidatorQueueKey: StateKey {
        public typealias Value = ConfigFixedSizeArray<
            ValidatorKey,
            ProtocolConfig.TotalNumberOfValidators
        >

        public init() {}

        public func encode() -> Data31 {
            constructKey(7)
        }
    }

    public struct CurrentValidatorsKey: StateKey {
        public typealias Value = ConfigFixedSizeArray<
            ValidatorKey,
            ProtocolConfig.TotalNumberOfValidators
        >

        public init() {}

        public func encode() -> Data31 {
            constructKey(8)
        }
    }

    public struct PreviousValidatorsKey: StateKey {
        public typealias Value = ConfigFixedSizeArray<
            ValidatorKey,
            ProtocolConfig.TotalNumberOfValidators
        >

        public init() {}

        public func encode() -> Data31 {
            constructKey(9)
        }
    }

    public struct ReportsKey: StateKey {
        public typealias Value = ConfigFixedSizeArray<
            ReportItem?,
            ProtocolConfig.TotalNumberOfCores
        >

        public init() {}

        public func encode() -> Data31 {
            constructKey(10)
        }
    }

    public struct TimeslotKey: StateKey {
        public typealias Value = TimeslotIndex

        public init() {}

        public func encode() -> Data31 {
            constructKey(11)
        }
    }

    public struct PrivilegedServicesKey: StateKey {
        public typealias Value = PrivilegedServices

        public init() {}

        public func encode() -> Data31 {
            constructKey(12)
        }
    }

    public struct ActivityStatisticsKey: StateKey {
        public typealias Value = Statistics

        public init() {}

        public func encode() -> Data31 {
            constructKey(13)
        }
    }

    public struct AccumulationQueueKey: StateKey {
        public typealias Value = ConfigFixedSizeArray<
            [AccumulationQueueItem],
            ProtocolConfig.EpochLength
        >

        public init() {}

        public func encode() -> Data31 {
            constructKey(14)
        }
    }

    public struct AccumulationHistoryKey: StateKey {
        public typealias Value = ConfigFixedSizeArray<
            SortedUniqueArray<Data32>,
            ProtocolConfig.EpochLength
        >

        public init() {}

        public func encode() -> Data31 {
            constructKey(15)
        }
    }

    public struct LastAccumulationOutputsKey: StateKey {
        public typealias Value = [Commitment]

        public init() {}

        public func encode() -> Data31 {
            constructKey(16)
        }
    }

    public struct ServiceAccountKey: StateKey {
        public typealias Value = ServiceAccountDetails
        public static var optional: Bool { true }

        public var index: ServiceIndex

        public init(index: ServiceIndex) {
            self.index = index
        }

        public func encode() -> Data31 {
            constructKey(255, index)
        }
    }

    public struct ServiceAccountStorageKey: StateKey {
        public typealias Value = Data
        public static var optional: Bool { true }

        public var index: ServiceIndex
        public var key: Data

        public init(index: ServiceIndex, key: Data) {
            self.index = index
            self.key = key
        }

        public func encode() -> Data31 {
            constructKey(index, UInt32.max, key)
        }
    }

    public struct ServiceAccountPreimagesKey: StateKey {
        public typealias Value = Data
        public static var optional: Bool { true }

        public var index: ServiceIndex
        public var hash: Data32

        public init(index: ServiceIndex, hash: Data32) {
            self.index = index
            self.hash = hash
        }

        public func encode() -> Data31 {
            constructKey(index, UInt32.max - 1, hash.data)
        }
    }

    public struct ServiceAccountPreimageInfoKey: StateKey {
        public typealias Value = LimitedSizeArray<TimeslotIndex, ConstInt0, ConstInt3>
        public static var optional: Bool { true }

        public var index: ServiceIndex
        public var hash: Data32
        public var length: UInt32

        public init(index: ServiceIndex, hash: Data32, length: UInt32) {
            self.index = index
            self.hash = hash
            self.length = length
        }

        public func encode() -> Data31 {
            constructKey(index, length, hash.data)
        }
    }
}

extension StateKeys {
    public static func isServiceKey(_ key: Data31, serviceIndex: ServiceIndex) -> Bool {
        let keyData = key.data
        let serviceBytes = withUnsafeBytes(of: serviceIndex.littleEndian) { Data($0) }

        // service details
        if keyData[relative: 0] == 255 {
            return keyData[relative: 1] == serviceBytes[relative: 0] &&
                keyData[relative: 3] == serviceBytes[relative: 1] &&
                keyData[relative: 5] == serviceBytes[relative: 2] &&
                keyData[relative: 7] == serviceBytes[relative: 3]
        }

        // other service keys
        return keyData[relative: 0] == serviceBytes[relative: 0] &&
            keyData[relative: 2] == serviceBytes[relative: 1] &&
            keyData[relative: 4] == serviceBytes[relative: 2] &&
            keyData[relative: 6] == serviceBytes[relative: 3]
    }
}
