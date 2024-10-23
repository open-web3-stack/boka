import Synchronization

extension Mutex where Value: Sendable {
    public var value: Value {
        get {
            withLock { $0 }
        }
        set {
            withLock {
                $0 = newValue
            }
        }
    }
}
