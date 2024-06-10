import Foundation
import Utils

public struct ServiceAccount {
    // s
    public var storage: [H256: Data]

    // p
    public var preimages: [H256: Data]

    // l
    public var preimageInfos: [
        (hash: H256, length: DataLength): LimitedSizeArray<TimeslotIndex, ConstInt0, ConstInt3>
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
