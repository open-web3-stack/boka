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
        preimages: [PreimageItem],
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

extension ExtrinsicPreimages.PreimageItem: Comparable {
    public static func < (lhs: ExtrinsicPreimages.PreimageItem, rhs: ExtrinsicPreimages.PreimageItem) -> Bool {
        if lhs.serviceIndex != rhs.serviceIndex {
            return lhs.serviceIndex < rhs.serviceIndex
        }
        return lhs.data.lexicographicallyPrecedes(rhs.data)
    }
}

extension ExtrinsicPreimages: Validate {
    public enum Error: Swift.Error {
        case preimagesNotSorted
    }

    public func validate(config _: Config) throws {
        guard preimages.isSortedAndUnique() else {
            throw Error.preimagesNotSorted
        }
    }
}
