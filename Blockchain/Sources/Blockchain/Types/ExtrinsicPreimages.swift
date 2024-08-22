import Foundation
import Utils

public struct ExtrinsicPreimages: Sendable, Equatable, Codable {
    public struct PreimageItem: Sendable, Equatable, Codable {
        public var serviceIndex: ServiceIndex
        public var data: Data

        public init(serviceIndex: ServiceIndex, data: Data) {
            self.serviceIndex = serviceIndex
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
