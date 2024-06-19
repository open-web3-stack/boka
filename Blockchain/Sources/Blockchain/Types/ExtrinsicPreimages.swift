import Foundation
import Utils

public struct ExtrinsicPreimages {
    public var preimages: [(size: DataLength, data: Data)]

    public init(
        preimages: [(size: DataLength, data: Data)]
    ) {
        self.preimages = preimages
    }
}

extension ExtrinsicPreimages: Dummy {
    public static var dummy: ExtrinsicPreimages {
        ExtrinsicPreimages(preimages: [])
    }
}
