import Foundation
import Utils

public struct ServiceAccount {
    // s
    public var storage: [H256: Data]

    // p
    public var preimages: [H256: Data]

    // l
    public var preimageInfos: [
        HashAndLength: LimitedSizeArray<TimeslotIndex, ConstInt0, ConstInt3>
    ]

    // c
    public var codeHash: H256

    // b
    public var balance: Balances

    // g
    public var accumlateGasLimit: Gas

    // m
    public var onTransferGasLimit: Gas

    public init(
        storage: [H256: Data],
        preimages: [H256: Data],
        preimageInfos: [
            HashAndLength: LimitedSizeArray<TimeslotIndex, ConstInt0, ConstInt3>,
        ],
        codeHash: H256,
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

public struct HashAndLength: Hashable {
    public var hash: H256
    public var length: DataLength
}

extension ServiceAccount: Dummy {
    public static var dummy: ServiceAccount {
        ServiceAccount(
            storage: [:],
            preimages: [:],
            preimageInfos: [:],
            codeHash: H256(),
            balance: 0,
            accumlateGasLimit: 0,
            onTransferGasLimit: 0
        )
    }
}
