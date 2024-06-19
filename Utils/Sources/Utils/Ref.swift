public final class Ref<T> {
    public let value: T

    public init(_ value: T) {
        self.value = value
    }
}

public final class RefMut<T> {
    public var value: T

    public init(_ value: T) {
        self.value = value
    }

    public func asRef() -> Ref<T> {
        Ref(value)
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
    public static var dummy: Ref<T> {
        Ref(T.dummy)
    }
}
