#if canImport(Glibc)
    import Glibc
#elseif canImport(Darwin)
    import Darwin
#endif

public final class ReadWriteLock: @unchecked Sendable {
    private var lock: pthread_rwlock_t = .init()

    public init() {
        let result = pthread_rwlock_init(&lock, nil)
        precondition(result == 0, "Failed to initialize read-write lock")
    }

    deinit {
        pthread_rwlock_destroy(&lock)
    }

    private func readLock() {
        let result = pthread_rwlock_rdlock(&lock)
        precondition(result == 0, "Failed to acquire read lock")
    }

    private func writeLock() {
        let result = pthread_rwlock_wrlock(&lock)
        precondition(result == 0, "Failed to acquire write lock")
    }

    private func unlock() {
        let result = pthread_rwlock_unlock(&lock)
        precondition(result == 0, "Failed to release lock")
    }

    public func withReadLock<T>(_ closure: () throws -> T) rethrows -> T {
        readLock()
        defer { unlock() }
        return try closure()
    }

    public func withWriteLock<T>(_ closure: () throws -> T) rethrows -> T {
        writeLock()
        defer { unlock() }
        return try closure()
    }
}
