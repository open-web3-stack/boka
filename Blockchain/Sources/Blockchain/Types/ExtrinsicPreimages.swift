import Foundation
import ScaleCodec
import Utils

public struct ExtrinsicPreimages: Sendable, Equatable {
    public struct SizeAndData: Sendable, Equatable {
        public var serviceIndices: ServiceIndices
        public var data: Data

        public init(serviceIndices: ServiceIndices, data: Data) {
            self.serviceIndices = serviceIndices
            self.data = data
        }
    }

    public var preimages: [SizeAndData]

    public init(
        preimages: [SizeAndData]
    ) {
        self.preimages = preimages
    }
}

extension ExtrinsicPreimages: Dummy {
    public typealias Config = ProtocolConfigRef
    public static func dummy(config _: Config) -> ExtrinsicPreimages {
        ExtrinsicPreimages(preimages: [])
    }
}

extension ExtrinsicPreimages: ScaleCodec.Codable {
    public init(from decoder: inout some ScaleCodec.Decoder) throws {
        try self.init(
            preimages: decoder.decode()
        )
    }

    public func encode(in encoder: inout some ScaleCodec.Encoder) throws {
        try encoder.encode(preimages)
    }
}

extension ExtrinsicPreimages.SizeAndData: ScaleCodec.Codable {
    public init(from decoder: inout some ScaleCodec.Decoder) throws {
        try self.init(
            serviceIndices: decoder.decode(),
            data: decoder.decode()
        )
    }

    public func encode(in encoder: inout some ScaleCodec.Encoder) throws {
        try encoder.encode(serviceIndices)
        try encoder.encode(data)
    }
}
