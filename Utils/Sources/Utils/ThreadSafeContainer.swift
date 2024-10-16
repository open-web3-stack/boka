import Foundation

public final class ThreadSafeContainer<T>: @unchecked Sendable {
    private var storage: T
    private let lock: ReadWriteLock = .init()

    public init(_ initialValue: T) {
        storage = initialValue
    }

    public func read<U>(_ action: (T) throws -> U) rethrows -> U {
        try lock.withReadLock { try action(self.storage) }
    }

    public func write(_ action: (inout T) throws -> Void) rethrows {
        try lock.withWriteLock {
            try action(&self.storage)
        }
    }

    public func write<U>(_ action: (inout T) throws -> U) rethrows -> U {
        try lock.withWriteLock {
            try action(&self.storage)
        }
    }

    public func exchange(_ value: T) -> T {
        lock.withWriteLock {
            let ret = self.storage
            self.storage = value
            return ret
        }
    }

    public var value: T {
        get {
            read { $0 }
        }
        set {
            write { $0 = newValue }
        }
    }
}
