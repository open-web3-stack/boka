open class Ref<T: Sendable>: @unchecked Sendable, CustomStringConvertible {
    public let value: T

    public required init(_ value: T) {
        self.value = value
    }

    public func mutate(fn: (inout T) throws -> Void) rethrows -> Self {
        var config = value
        try fn(&config)
        return Self(config)
    }

    open var description: String {
        "\(value)"
    }
}

public final class RefMut<T> {
    public var value: T

    public required init(_ value: T) {
        self.value = value
    }
}

extension Ref: Equatable where T: Equatable {
    public static func == (lhs: Ref<T>, rhs: Ref<T>) -> Bool {
        lhs.value == rhs.value
    }
}

extension Ref: Hashable where T: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(value)
    }
}

extension Ref: HasConfig where T: HasConfig {
    public typealias Config = T.Config
}

extension Ref: Dummy where T: Dummy {
    public static func dummy(config: Config) -> Self {
        Self(T.dummy(config: config))
    }
}

open class RefWithHash<T: Hashable32 & Sendable>: Ref<T>, @unchecked Sendable {
    private let lazyHash: Lazy<Ref<Data32>>

    public required init(_ value: T) {
        lazyHash = Lazy {
            Ref(value.hash())
        }

        super.init(value)
    }

    public var hash: Data32 {
        lazyHash.value.value
    }
}
