import Foundation

public final class ThreadSafeContainer<T>: @unchecked Sendable {
    private var storage: T
    private let queue: DispatchQueue

    public init(_ initialValue: T, label: String = "boka.threadsafecontainer") {
        storage = initialValue
        queue = DispatchQueue(label: label, attributes: .concurrent)
    }

    public func read<U>(_ action: (T) throws -> U) rethrows -> U {
        try queue.sync { try action(self.storage) }
    }

    public func write(_ action: @escaping @Sendable (inout T) -> Void) {
        queue.async(flags: .barrier) {
            action(&self.storage)
        }
    }

    public func mutate<U>(_ action: @escaping (inout T) throws -> U) rethrows -> U {
        try queue.sync(flags: .barrier) {
            try action(&self.storage)
        }
    }
}

extension ThreadSafeContainer {
    public var value: T {
        get {
            read { $0 }
        }
        set {
            mutate { $0 = newValue }
        }
    }
}

extension ThreadSafeContainer where T: Sendable {
    public var value: T {
        get {
            read { $0 }
        }
        set {
            write { $0 = newValue }
        }
    }
}
