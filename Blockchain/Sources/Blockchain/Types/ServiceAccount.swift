import Codec
import Foundation
import Utils

public struct ServiceAccountDetails: Sendable, Equatable, Codable {
    @CodingAs<Compact<UInt8>> public var version: UInt8

    // c
    public var codeHash: Data32

    // b
    public var balance: Balance

    // g
    public var minAccumlateGas: Gas

    // m
    public var minMemoGas: Gas

    // o: the total number of octets used in storage
    public var totalByteLength: UInt64

    // f
    public var gratisStorage: Balance

    // i: number of items in storage
    public var itemsCount: UInt32

    // r
    public var createdAt: TimeslotIndex

    // a
    public var lastAccAt: TimeslotIndex

    // p
    public var parentService: ServiceIndex

    // t: the minimum, or threshold, balance needed for any given service account in terms of its storage footprint
    public func thresholdBalance(config: ProtocolConfigRef) -> Balance {
        let base = Balance(config.value.serviceMinBalance)
        let items = Balance(config.value.additionalMinBalancePerStateItem) * Balance(itemsCount)
        let bytes = Balance(config.value.additionalMinBalancePerStateByte) * Balance(totalByteLength)
        return max(Balance(0), base + items + bytes - gratisStorage)
    }

    public mutating func updateFootprintStorage(key: Data, oldValue: Data?, newValue: Data?) {
        if let oldValue {
            if let newValue {
                // replace: update byte count difference
                totalByteLength = totalByteLength - UInt64(oldValue.count) + UInt64(newValue.count)
            } else {
                // remove: decrease count and bytes
                itemsCount = UInt32(max(0, Int(itemsCount) - 1))
                totalByteLength = UInt64(max(0, Int(totalByteLength) - (34 + oldValue.count + key.count)))
            }
        } else {
            if let newValue {
                // add: increase count and bytes
                itemsCount += 1
                totalByteLength = totalByteLength + 34 + UInt64(newValue.count) + UInt64(key.count)
            }
        }
    }

    public mutating func updateFootprintPreimage(
        oldValue: StateKeys.ServiceAccountPreimageInfoKey.Value?,
        newValue: StateKeys.ServiceAccountPreimageInfoKey.Value?,
        length: UInt32
    ) {
        if oldValue != nil {
            // replace: no change on footprint
            // remove: decrease count and bytes
            if newValue == nil {
                itemsCount = UInt32(max(0, Int(itemsCount) - 2))
                totalByteLength = UInt64(max(0, Int(totalByteLength) - (81 + Int(length))))
            }
        } else {
            if newValue != nil {
                // add: increase count and bytes
                itemsCount += 2
                totalByteLength = totalByteLength + 81 + UInt64(length)
            }
        }
    }
}

public struct ServiceAccount: Sendable, Equatable, Codable {
    // v
    @CodingAs<Compact<UInt8>> public var version: UInt8

    // s
    public var storage: [Data: Data]

    // p
    public var preimages: [Data32: Data]

    // l
    public var preimageInfos: [
        HashAndLength: LimitedSizeArray<TimeslotIndex, ConstInt0, ConstInt3>
    ]

    // c
    public var codeHash: Data32

    // b
    public var balance: Balance

    // g
    public var minAccumlateGas: Gas

    // m
    public var minMemoGas: Gas

    // f
    public var gratisStorage: Balance

    // r
    public var createdAt: TimeslotIndex

    // a
    public var lastAccAt: TimeslotIndex

    // p
    public var parentService: ServiceIndex

    public init(
        version: UInt8,
        storage: [Data: Data],
        preimages: [Data32: Data],
        preimageInfos: [HashAndLength: LimitedSizeArray<TimeslotIndex, ConstInt0, ConstInt3>],
        codeHash: Data32,
        balance: Balance,
        minAccumlateGas: Gas,
        minMemoGas: Gas,
        gratisStorage: Balance,
        createdAt: TimeslotIndex,
        lastAccAt: TimeslotIndex,
        parentService: ServiceIndex
    ) {
        self.version = version
        self.storage = storage
        self.preimages = preimages
        self.preimageInfos = preimageInfos
        self.codeHash = codeHash
        self.balance = balance
        self.minAccumlateGas = minAccumlateGas
        self.minMemoGas = minMemoGas
        self.gratisStorage = gratisStorage
        self.createdAt = createdAt
        self.lastAccAt = lastAccAt
        self.parentService = parentService
    }

    public func toDetails() -> ServiceAccountDetails {
        ServiceAccountDetails(
            version: version,
            codeHash: codeHash,
            balance: balance,
            minAccumlateGas: minAccumlateGas,
            minMemoGas: minMemoGas,
            totalByteLength: totalByteLength,
            gratisStorage: gratisStorage,
            itemsCount: itemsCount,
            createdAt: createdAt,
            lastAccAt: lastAccAt,
            parentService: parentService
        )
    }
}

extension ServiceAccount: Dummy {
    public typealias Config = ProtocolConfigRef
    public static func dummy(config _: Config) -> ServiceAccount {
        ServiceAccount(
            version: 0,
            storage: [:],
            preimages: [:],
            preimageInfos: [:],
            codeHash: Data32(),
            balance: Balance(0),
            minAccumlateGas: Gas(0),
            minMemoGas: Gas(0),
            gratisStorage: Balance(0),
            createdAt: TimeslotIndex(0),
            lastAccAt: TimeslotIndex(0),
            parentService: ServiceIndex(0)
        )
    }
}

extension ServiceAccount {
    // i: number of items in storage
    public var itemsCount: UInt32 {
        UInt32(2 * preimageInfos.count + storage.count)
    }

    // o: the total number of octets used in storage
    public var totalByteLength: UInt64 {
        let preimageInfosBytes = preimageInfos.keys.reduce(into: 0) { $0 += 81 + $1.length }
        let storageBytes = storage.enumerated().reduce(into: 0) { $0 += 34 + $1.element.key.count + $1.element.value.count }
        return UInt64(preimageInfosBytes) + UInt64(storageBytes)
    }

    // t: the minimum, or threshold, balance needed for any given service account in terms of its storage footprint
    public func thresholdBalance(config: ProtocolConfigRef) -> Balance {
        let base = Balance(config.value.serviceMinBalance)
        let items = Balance(config.value.additionalMinBalancePerStateItem) * Balance(itemsCount)
        let bytes = Balance(config.value.additionalMinBalancePerStateByte) * Balance(totalByteLength)
        return max(Balance(0), base + items + bytes - gratisStorage)
    }
}
