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
