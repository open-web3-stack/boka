import Foundation
import Utils

public protocol StateKey: Hashable, Sendable {
    associatedtype Value: StateValueProtocol
    func encode() -> Data32
}

extension StateKey {
    public func decodeType() -> (Sendable & Codable).Type {
        Value.DecodeType.self
    }
}

public protocol StateValueProtocol {
    associatedtype ValueType: Codable & Sendable
    associatedtype DecodeType: Codable & Sendable
    static var optional: Bool { get }
}

public struct StateValue<T: Codable & Sendable>: StateValueProtocol {
    public typealias ValueType = T
    public typealias DecodeType = T
    public static var optional: Bool { false }
}

public struct StateOptionalValue<T: Codable & Sendable>: StateValueProtocol {
    public typealias ValueType = T?
    public typealias DecodeType = T
    public static var optional: Bool { true }
}

private func constructKey(_ idx: UInt8) -> Data32 {
    var data = Data(repeating: 0, count: 32)
    data[0] = idx
    return Data32(data)!
}

private func constructKey(_ idx: UInt8, _ service: ServiceIndex) -> Data32 {
    var data = Data(repeating: 0, count: 32)
    data[0] = idx
    withUnsafeBytes(of: service) { ptr in
        data[1] = ptr.load(as: UInt8.self)
        data[3] = ptr.load(fromByteOffset: 1, as: UInt8.self)
        data[5] = ptr.load(fromByteOffset: 2, as: UInt8.self)
        data[7] = ptr.load(fromByteOffset: 3, as: UInt8.self)
    }
    return Data32(data)!
}

private func constructKey(_ service: ServiceIndex, _ val: UInt32, _: Data) -> Data32 {
    var data = Data(capacity: 32)

    withUnsafeBytes(of: service) { servicePtr in
        withUnsafeBytes(of: val) { valPtr in
            data.append(servicePtr.load(as: UInt8.self))
            data.append(valPtr.load(as: UInt8.self))
            data.append(servicePtr.load(fromByteOffset: 1, as: UInt8.self))
            data.append(valPtr.load(fromByteOffset: 1, as: UInt8.self))
            data.append(servicePtr.load(fromByteOffset: 2, as: UInt8.self))
            data.append(valPtr.load(fromByteOffset: 2, as: UInt8.self))
            data.append(servicePtr.load(fromByteOffset: 3, as: UInt8.self))
            data.append(valPtr.load(fromByteOffset: 3, as: UInt8.self))
        }
    }
    data.append(contentsOf: data[relative: 0 ..< 24])
    return Data32(data)!
}

public enum StateKeys {
    public struct CoreAuthorizationPoolKey: StateKey {
        public typealias Value = StateValue<
            ConfigFixedSizeArray<
                ConfigLimitedSizeArray<
                    Data32,
                    ProtocolConfig.Int0,
                    ProtocolConfig.MaxAuthorizationsPoolItems
                >,
                ProtocolConfig.TotalNumberOfCores
            >
        >

        public init() {}

        public func encode() -> Data32 {
            constructKey(1)
        }
    }

    public struct AuthorizationQueueKey: StateKey {
        public typealias Value = StateValue<
            ConfigFixedSizeArray<
                ConfigFixedSizeArray<
                    Data32,
                    ProtocolConfig.MaxAuthorizationsQueueItems
                >,
                ProtocolConfig.TotalNumberOfCores
            >
        >

        public init() {}

        public func encode() -> Data32 {
            constructKey(2)
        }
    }

    public struct RecentHistoryKey: StateKey {
        public typealias Value = StateValue<RecentHistory>

        public init() {}

        public func encode() -> Data32 {
            constructKey(3)
        }
    }

    public struct SafroleStateKey: StateKey {
        public typealias Value = StateValue<SafroleState>

        public init() {}

        public func encode() -> Data32 {
            constructKey(4)
        }
    }

    public struct JudgementsKey: StateKey {
        public typealias Value = StateValue<JudgementsState>

        public init() {}

        public func encode() -> Data32 {
            constructKey(5)
        }
    }

    public struct EntropyPoolKey: StateKey {
        public typealias Value = StateValue<EntropyPool>

        public init() {}

        public func encode() -> Data32 {
            constructKey(6)
        }
    }

    public struct ValidatorQueueKey: StateKey {
        public typealias Value = StateValue<
            ConfigFixedSizeArray<
                ValidatorKey,
                ProtocolConfig.TotalNumberOfValidators
            >
        >

        public init() {}

        public func encode() -> Data32 {
            constructKey(7)
        }
    }

    public struct CurrentValidatorsKey: StateKey {
        public typealias Value = StateValue<
            ConfigFixedSizeArray<
                ValidatorKey,
                ProtocolConfig.TotalNumberOfValidators
            >
        >

        public init() {}

        public func encode() -> Data32 {
            constructKey(8)
        }
    }

    public struct PreviousValidatorsKey: StateKey {
        public typealias Value = StateValue<
            ConfigFixedSizeArray<
                ValidatorKey,
                ProtocolConfig.TotalNumberOfValidators
            >
        >

        public init() {}

        public func encode() -> Data32 {
            constructKey(9)
        }
    }

    public struct ReportsKey: StateKey {
        public typealias Value = StateValue<
            ConfigFixedSizeArray<
                ReportItem?,
                ProtocolConfig.TotalNumberOfCores
            >
        >

        public init() {}

        public func encode() -> Data32 {
            constructKey(10)
        }
    }

    public struct TimeslotKey: StateKey {
        public typealias Value = StateValue<TimeslotIndex>

        public init() {}

        public func encode() -> Data32 {
            constructKey(11)
        }
    }

    public struct PrivilegedServicesKey: StateKey {
        public typealias Value = StateValue<PrivilegedServices>

        public init() {}

        public func encode() -> Data32 {
            constructKey(12)
        }
    }

    public struct ActivityStatisticsKey: StateKey {
        public typealias Value = StateValue<ValidatorActivityStatistics>

        public init() {}

        public func encode() -> Data32 {
            constructKey(13)
        }
    }

    public struct ServiceAccountKey: StateKey {
        public typealias Value = StateOptionalValue<ServiceAccountDetails>

        public var index: ServiceIndex

        public init(index: ServiceIndex) {
            self.index = index
        }

        public func encode() -> Data32 {
            constructKey(255, index)
        }
    }

    public struct ServiceAccountStorageKey: StateKey {
        public typealias Value = StateOptionalValue<Data>

        public var index: ServiceIndex
        public var key: Data32

        public init(index: ServiceIndex, key: Data32) {
            self.index = index
            self.key = key
        }

        public func encode() -> Data32 {
            constructKey(index, UInt32.max, key.data)
        }
    }

    public struct ServiceAccountPreimagesKey: StateKey {
        public typealias Value = StateOptionalValue<Data>

        public var index: ServiceIndex
        public var hash: Data32

        public init(index: ServiceIndex, hash: Data32) {
            self.index = index
            self.hash = hash
        }

        public func encode() -> Data32 {
            constructKey(index, UInt32.max - 1, hash.data[1...])
        }
    }

    public struct ServiceAccountPreimageInfoKey: StateKey {
        public typealias Value = StateOptionalValue<LimitedSizeArray<TimeslotIndex, ConstInt0, ConstInt3>>

        public var index: ServiceIndex
        public var hash: Data32
        public var length: UInt32

        public init(index: ServiceIndex, hash: Data32, length: UInt32) {
            self.index = index
            self.hash = hash
            self.length = length
        }

        public func encode() -> Data32 {
            constructKey(index, length, hash.blake2b256hash().data)
        }
    }
}
