import TracingUtils
import Utils

private let logger = Logger(label: "StoreMiddleware")

struct StoreMiddleware: MiddlewareProtocol {
    let storage: ThreadSafeContainer<[(Sendable, Task<Void, Error>)]> = .init([])

    init() {}

    func handle<T: Sendable>(_ event: T, next: @escaping MiddlewareHandler<T>) async throws {
        logger.debug(">>> dispatching event: \(event)")
        let task = Task { try await next(event) }
        storage.write { storage in
            storage.append((event, task))
        }
        try await task.value
        logger.debug("<<< event dispatched: \(event)")
    }

    @discardableResult
    func wait() async -> [Sendable] {
        await Task.yield()

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
