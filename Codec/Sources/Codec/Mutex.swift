#if canImport(Glibc)
    import Glibc
#elseif canImport(Darwin)
    import Darwin
#endif
// can't use Mutex from Synchronization because this bug https://github.com/swiftlang/swift/issues/76690
public final class Mutex<T>: @unchecked Sendable {
    private var mutex: pthread_mutex_t
    private var value: T

    public init(_ value: T) {
        self.value = value
        mutex = .init()
        pthread_mutex_init(&mutex, nil)
    }

    public func withLock<R>(_ fn: (inout T) throws -> R) rethrows -> R {
        pthread_mutex_lock(&mutex)
        defer {
            pthread_mutex_unlock(&mutex)
        }
        return try fn(&value)
    }

    deinit {
        pthread_mutex_destroy(&mutex)
    }
}
