import TracingUtils

private let logger = Logger(label: "StoreMiddleware")

/// Store events in memory and wait for all handlers to be executed
/// For testing purposes only
public struct StoreMiddleware: MiddlewareProtocol {
    private let storage: ThreadSafeContainer<[(Sendable, Task<Void, Error>)]> = .init([])

    public init() {}

    public func handle<T: Sendable>(_ event: T, next: @escaping MiddlewareHandler<T>) async throws {
        logger.debug(">>> dispatching event: \(event)")
        let task = Task { try await next(event) }
        storage.mutate { storage in
            storage.append((event, task))
        }
        try await task.value
        logger.debug("<<< event dispatched: \(event)")
    }

    @discardableResult
    public func wait() async -> [Sendable] {
        try? await Task.sleep(for: .milliseconds(5))

        let value = storage.value

        for (_, task) in value {
            try? await task.value
        }

        // new event is published in event hanlder
        // wait for the new event handlers to be executed
        let newValue = storage.value
        if newValue.count != value.count {
            return await wait()
        }

        return newValue.map(\.0)
    }
}
