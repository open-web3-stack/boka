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
    public var balance: Balances

    // g
    public var accumlateGasLimit: Gas

    // m
    public var onTransferGasLimit: Gas

    public init(
        storage: [Data32: Data],
        preimages: [Data32: Data],
        preimageInfos: [HashAndLength: LimitedSizeArray<TimeslotIndex, ConstInt0, ConstInt3>],
        codeHash: Data32,
        balance: Balances,
        accumlateGasLimit: Gas,
        onTransferGasLimit: Gas
    ) {
        self.storage = storage
        self.preimages = preimages
        self.preimageInfos = preimageInfos
        self.codeHash = codeHash
        self.balance = balance
        self.accumlateGasLimit = accumlateGasLimit
        self.onTransferGasLimit = onTransferGasLimit
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
            accumlateGasLimit: 0,
            onTransferGasLimit: 0
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
        preimageInfos.keys.reduce(into: 0) { $0 += 81 + $1.length } + storage.values.reduce(into: 0) { $0 += 32 + $1.count }
    }

    // t: the minimum, or threshold, balance needed for any given service account in terms of its storage footprint
    public func thresholdBalance(config: ProtocolConfigRef) -> Balances {
        Balance(config.value.serviceMinBalance) +
            Balance(config.value.additionalMinBalancePerStateItem) * Balance(itemsCount) +
            Balance(config.value.additionalMinBalancePerStateByte) * Balance(totalByteLength)
    }
}
