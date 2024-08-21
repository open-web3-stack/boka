import Atomics

open class Ref<T: Sendable>: @unchecked Sendable, AtomicReference {
    public let value: T

    public required init(_ value: T) {
        self.value = value
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

extension Ref: Dummy where T: Dummy {
    public typealias Config = T.Config
    public static func dummy(config: Config) -> Self {
        Self(T.dummy(config: config))
    }
}
