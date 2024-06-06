public class Ref<T> {
    public let value: T

    public init(_ value: T) {
        self.value = value
    }
}

public class RefMut<T> {
    public var value: T

    public init(_ value: T) {
        self.value = value
    }

    public func asRef() -> Ref<T> {
        Ref(value)
    }
}
