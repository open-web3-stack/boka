import Foundation
import Utils

public struct ServiceAccount: Sendable, Equatable, Codable {
    // s
    public var storage: [Data32: Data]

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
    public var minOnTransferGas: Gas

    public init(
        storage: [Data32: Data],
        preimages: [Data32: Data],
        preimageInfos: [HashAndLength: LimitedSizeArray<TimeslotIndex, ConstInt0, ConstInt3>],
        codeHash: Data32,
        balance: Balance,
        minAccumlateGas: Gas,
        minOnTransferGas: Gas
    ) {
        self.storage = storage
        self.preimages = preimages
        self.preimageInfos = preimageInfos
        self.codeHash = codeHash
        self.balance = balance
        self.minAccumlateGas = minAccumlateGas
        self.minOnTransferGas = minOnTransferGas
    }
}

extension ServiceAccount: Dummy {
    public typealias Config = ProtocolConfigRef
    public static func dummy(config _: Config) -> ServiceAccount {
        ServiceAccount(
            storage: [:],
            preimages: [:],
            preimageInfos: [:],
            codeHash: Data32(),
            balance: 0,
            minAccumlateGas: 0,
            minOnTransferGas: 0
        )
    }
}

extension ServiceAccount {
    // i: number of items in storage
    public var itemsCount: UInt32 {
        UInt32(2 * preimageInfos.count + storage.count)
    }

    // l: the total number of octets used in storage
    public var totalByteLength: UInt64 {
        let preimageInfosBytes = preimageInfos.keys.reduce(into: 0) { $0 += 81 + $1.length }
        let storageBytes = storage.values.reduce(into: 0) { $0 += 32 + $1.count }
        return UInt64(preimageInfosBytes) + UInt64(storageBytes)
    }

    // t: the minimum, or threshold, balance needed for any given service account in terms of its storage footprint
    public func thresholdBalance(config: ProtocolConfigRef) -> Balance {
        let base = Balance(config.value.serviceMinBalance)
        let items = Balance(config.value.additionalMinBalancePerStateItem) * Balance(itemsCount)
        let bytes = Balance(config.value.additionalMinBalancePerStateByte) * Balance(totalByteLength)
        return base + items + bytes
    }
}
