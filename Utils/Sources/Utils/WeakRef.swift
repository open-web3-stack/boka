/// Helper to make a Sendable weak reference
public struct WeakRef<T: AnyObject & Sendable>: Sendable {
    public weak var value: T?

    public init(_ value: T) {
        self.value = value
    }
}
