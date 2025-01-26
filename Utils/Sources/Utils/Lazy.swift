import Synchronization

/// A thread-safe lazy value.
/// Note: The initializer could be called multiple times.
public final class Lazy<T: AnyObject> {
    private let ref = AtomicLazyReference<T>()
    private let initFn: @Sendable () -> T

    public init(_ initFn: @Sendable @escaping () -> T) {
        self.initFn = initFn
    }

    public var value: T {
        guard let value = ref.load() else {
            return ref.storeIfNil(initFn())
        }
        return value
    }
}

extension Lazy: Sendable where T: Sendable {}
