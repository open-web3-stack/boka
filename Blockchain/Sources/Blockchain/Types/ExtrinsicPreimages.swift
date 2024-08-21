import Foundation
import Utils

public struct ExtrinsicPreimages: Sendable, Equatable, Codable {
    public struct PreimageItem: Sendable, Equatable, Codable {
        public var serviceIndices: ServiceIndices
        public var data: Data

        public init(serviceIndices: ServiceIndices, data: Data) {
            self.serviceIndices = serviceIndices
            self.data = data
        }
    }

    public var preimages: [PreimageItem]

    public init(
        preimages: [PreimageItem]
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
