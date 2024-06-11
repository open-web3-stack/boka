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
}

public struct HashAndLength: Hashable {
    public var hash: H256
    public var length: DataLength
}
