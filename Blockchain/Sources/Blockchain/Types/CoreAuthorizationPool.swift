import Utils

public struct CoreAuthorizationPoolItem {
    public private(set) var value: SizeLimitedArray<H256> = SizeLimitedArray(
        deafultValue: H256.zero, minLength: 0, maxLength: Constants.maxAuthorizationsPoolItems
    )

    public init(_ value: [H256]) {
        self.value = SizeLimitedArray(
            array: value, minLength: 0, maxLength: Constants.maxAuthorizationsPoolItems
        )
    }

    public init() {
        self.init([])
    }
}

public struct CoreAuthorizationPool {
    public private(set) var value: SizeLimitedArray<CoreAuthorizationPoolItem>

    public init(_ value: [CoreAuthorizationPoolItem]) {
        self.value = SizeLimitedArray(
            array: value, length: Constants.totalNumberofCores
        )
    }

    public init() {
        self.init(Array(repeating: CoreAuthorizationPoolItem(), count: Constants.totalNumberofCores))
    }
}
