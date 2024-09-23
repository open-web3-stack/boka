import Foundation

public final class ThreadSafeContainer<T: Sendable>: @unchecked Sendable {
    private var storage: T
    private let queue: DispatchQueue

    public init(_ initialValue: T, label: String = "boka.threadsafecontainer") {
        storage = initialValue
        queue = DispatchQueue(label: label, attributes: .concurrent)
    }

    public func read<U>(_ action: (T) -> U) -> U {
        queue.sync { action(self.storage) }
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

    public var value: T {
        get {
            read { $0 }
        }
        set {
            write { $0 = newValue }
        }
    }
}
