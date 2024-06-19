import Foundation
import ScaleCodec
import Utils

public struct ServiceAccount {
    public struct HashAndLength: Hashable {
        public var hash: H256
        public var length: DataLength

        public init(hash: H256, length: DataLength) {
            self.hash = hash
            self.length = length
        }
    }

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
        preimageInfos: [HashAndLength: LimitedSizeArray<TimeslotIndex, ConstInt0, ConstInt3>],
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

extension ServiceAccount.HashAndLength: ScaleCodec.Codable {
    public init(from decoder: inout some ScaleCodec.Decoder) throws {
        try self.init(
            hash: decoder.decode(),
            length: decoder.decode()
        )
    }

    public func encode(in encoder: inout some ScaleCodec.Encoder) throws {
        try encoder.encode(hash)
        try encoder.encode(length)
    }
}

extension ServiceAccount: ScaleCodec.Codable {
    public init(from decoder: inout some ScaleCodec.Decoder) throws {
        try self.init(
            storage: decoder.decode(),
            preimages: decoder.decode(),
            preimageInfos: decoder.decode(),
            codeHash: decoder.decode(),
            balance: decoder.decode(),
            accumlateGasLimit: decoder.decode(),
            onTransferGasLimit: decoder.decode()
        )
    }

    public func encode(in encoder: inout some ScaleCodec.Encoder) throws {
        try encoder.encode(storage)
        try encoder.encode(preimages)
        try encoder.encode(preimageInfos)
        try encoder.encode(codeHash)
        try encoder.encode(balance)
        try encoder.encode(accumlateGasLimit)
        try encoder.encode(onTransferGasLimit)
    }
}
