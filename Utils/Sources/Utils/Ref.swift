import ScaleCodec

public class Ref<T> {
    public internal(set) var value: T

    public required init(_ value: T) {
        self.value = value
    }
}

public class RefMut<T>: Ref<T> {
    override public var value: T {
        get {
            super.value
        }
        set {
            super.value = newValue
        }
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
    public static func dummy(withConfig config: Config) -> Self {
        Self(T.dummy(withConfig: config))
    }
}
