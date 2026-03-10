import Foundation
import Synchronization
import TracingUtils

private let logger = Logger(label: "EventBus")

public protocol SubscriptionTokenProtocol: Sendable {}

public protocol Subscribable: AnyObject, Sendable {
    associatedtype SubscriptionToken: SubscriptionTokenProtocol

    func subscribe<T: Event>(
        _ eventType: T.Type,
        id: UniqueId,
        handler: @escaping @Sendable (T) async throws -> Void,
    ) async -> SubscriptionToken

    func unsubscribe(token: SubscriptionToken) async
}

extension Subscribable {
    public func subscribe<T: Event>(
        _ eventType: T.Type,
        id: UniqueId = "",
        handler: @escaping @Sendable (T) async throws -> Void,
    ) async -> SubscriptionToken {
        await subscribe(eventType, id: id, handler: handler)
    }
}

public actor EventBus: Subscribable {
    public struct SubscriptionToken: SubscriptionTokenProtocol, Hashable {
        fileprivate let id: UniqueId
        fileprivate let eventTypeId: ObjectIdentifier

        public func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }

        public static func == (lhs: SubscriptionToken, rhs: SubscriptionToken) -> Bool {
            lhs.id == rhs.id
        }
    }

    private struct AnyEventHandler: Sendable {
        let token: SubscriptionToken
        private let _handle: @Sendable (Event) async throws -> Void

        init<T: Event>(_ token: SubscriptionToken, _ handler: @escaping @Sendable (T) async throws -> Void) {
            self.token = token
            _handle = { event in
                guard let event = event as? T else { return }
                try await handler(event)
            }
        }

        func handle(_ event: Event) async throws {
            try await _handle(event)
        }
    }

    private struct ContinuationHandler {
        let id = UniqueId()
        let eventType: Event.Type
        let continuation: SafeContinuation<Event>
        let handler: @Sendable (Event) -> Bool

        init<T: Event>(_ eventType: T.Type, _ continuation: SafeContinuation<Event>, _ handler: @escaping @Sendable (T) -> Bool) {
            self.eventType = eventType
            self.continuation = continuation
            self.handler = { event in
                guard let event = event as? T else { return false }
                return handler(event)
            }
        }
    }

    private var handlers: [ObjectIdentifier: [AnyEventHandler]] = [:]
    private let eventMiddleware: Middleware
    private let handlerMiddleware: Middleware

    private var waitContinuations: [ObjectIdentifier: [ContinuationHandler]] = [:]

    public init(eventMiddleware: Middleware = .noop, handlerMiddleware: Middleware = .noop) {
        self.eventMiddleware = eventMiddleware
        self.handlerMiddleware = handlerMiddleware
    }

    func waitContinuationCount<T: Event>(for eventType: T.Type) -> Int {
        waitContinuations[ObjectIdentifier(eventType)]?.count ?? 0
    }

    public func subscribe<T: Event>(
        _ eventType: T.Type,
        id: UniqueId = "",
        handler: @escaping @Sendable (T) async throws -> Void,
    ) -> SubscriptionToken {
        let key = ObjectIdentifier(eventType)
        let token = SubscriptionToken(id: id, eventTypeId: key)

        handlers[key, default: []].append(AnyEventHandler(token, handler))

        return token
    }

    public func unsubscribe(token: SubscriptionToken) {
        if var eventHandlers = handlers[token.eventTypeId] {
            eventHandlers.removeAll { $0.token == token }
            if eventHandlers.isEmpty {
                handlers.removeValue(forKey: token.eventTypeId)
            } else {
                handlers[token.eventTypeId] = eventHandlers
            }
        }
    }

    public nonisolated func publish(_ event: some Event) {
        Task {
            await publish(event)
        }
    }

    public func publish(_ event: some Event) async {
        let key = ObjectIdentifier(type(of: event))
        let eventHandlers = handlers[key]
        let eventMiddleware = eventMiddleware
        let handlerMiddleware = handlerMiddleware

        // Process wait continuations
        if let continuations = waitContinuations[key] {
            var remainingContinuations: [ContinuationHandler] = []

            for handler in continuations {
                if handler.handler(event) {
                    // Found a match, resume the continuation with this event
                    handler.continuation.resume(returning: event)
                    // Don't keep this continuation
                } else {
                    // No match, keep waiting
                    remainingContinuations.append(handler)
                }
            }

            if remainingContinuations.isEmpty {
                waitContinuations.removeValue(forKey: key)
            } else {
                waitContinuations[key] = remainingContinuations
            }
        }

        do {
            try await eventMiddleware.handle(event) { event in
                guard let eventHandlers else {
                    return
                }
                for handler in eventHandlers {
                    do {
                        try await handlerMiddleware.handle(event) { evt in
                            try await handler.handle(evt)
                        }
                    } catch {
                        logger.warning("Unhandled error for event: \(event) with error: \(error) and handler: \(handler.token.id)")
                    }
                }
            }
        } catch {
            logger.warning("Unhandled error for event: \(event) with error: \(error)")
        }
    }

    private func addWaitContinuation<T: Event>(
        _ eventType: T.Type,
        check: @escaping @Sendable (T) -> Bool,
        continuation: SafeContinuation<Event>,
    ) -> UniqueId {
        let key = ObjectIdentifier(eventType)
        let handler = ContinuationHandler(eventType, continuation, check)
        waitContinuations[key, default: []].append(handler)
        return handler.id
    }

    private func removeWaitContinuation<T: Event>(
        _ eventType: T.Type,
        id: UniqueId,
    ) {
        let key = ObjectIdentifier(eventType)
        guard var continuations = waitContinuations[key] else {
            return
        }

        continuations.removeAll { $0.id == id }
        if continuations.isEmpty {
            waitContinuations.removeValue(forKey: key)
        } else {
            waitContinuations[key] = continuations
        }
    }

    private func timeoutWaitContinuation<T: Event>(
        _ eventType: T.Type,
        id: UniqueId,
        continuation: SafeContinuation<Event>,
    ) {
        let key = ObjectIdentifier(eventType)
        guard let continuations = waitContinuations[key], continuations.contains(where: { $0.id == id }) else {
            // Continuation already resumed or removed, nothing to do
            return
        }

        removeWaitContinuation(eventType, id: id)
        continuation.resume(throwing: ContinuationError.timeout)
    }

    private func awaitEvent<T: Event>(
        _ eventType: T.Type,
        check: @escaping @Sendable (T) -> Bool = { _ in true },
        timeout: TimeInterval = 10,
        afterRegistration: (@Sendable () -> Void)? = nil,
    ) async throws -> T {
        let contId: Mutex<UniqueId?> = .init(nil)
        let timeoutTask: Mutex<Task<Void, Never>?> = .init(nil)
        let hasResumed = Atomic<Bool>(false)

        defer {
            // Cancel timeout task
            timeoutTask.withLock { value in
                value?.cancel()
                value = nil
            }

            // If continuation wasn't resumed, remove it from registry
            if !hasResumed.load(ordering: .sequentiallyConsistent) {
                if let id = contId.withLock({ $0 }) {
                    removeWaitContinuation(eventType, id: id)
                }
            }
        }

        let res = try await withCheckedThrowingContinuation { (originalContinuation: CheckedContinuation<T, Error>) in
            let localHasResumed = Atomic<Bool>(false)

            @Sendable func resumeOnce(_ result: Result<T, Error>) {
                let resumed = localHasResumed.exchange(true, ordering: .sequentiallyConsistent)
                if resumed {
                    return
                }
                hasResumed.store(true, ordering: .sequentiallyConsistent)
                originalContinuation.resume(with: result)
            }

            let continuation = SafeContinuation<Event>(
                onSuccess: { event in
                    guard let result = event as? T else {
                        resumeOnce(.failure(ContinuationError.unreachable))
                        return
                    }
                    resumeOnce(.success(result))
                },
                onFailure: { error in
                    resumeOnce(.failure(error))
                },
            )

            // Register synchronously to avoid missing events published right after waitFor starts.
            // This must happen BEFORE the timeout task starts to avoid race conditions.
            let id = addWaitContinuation(eventType, check: check, continuation: continuation)
            contId.withLock { value in
                value = id
            }

            // Start timeout task AFTER continuation is registered
            let task = Task { [weak self] in
                do {
                    try await Task.sleep(for: .seconds(timeout))
                } catch {
                    return
                }
                await self?.timeoutWaitContinuation(eventType, id: id, continuation: continuation)
            }
            timeoutTask.withLock { value in
                value = task
            }

            afterRegistration?()
        }

        return res
    }

    public func waitFor<T: Event>(
        _ eventType: T.Type,
        check: @escaping @Sendable (T) -> Bool = { _ in true },
        timeout: TimeInterval = 10,
    ) async throws -> T {
        try await awaitEvent(eventType, check: check, timeout: timeout)
    }

    public func publishAndWaitFor<Published: Event, Response: Event>(
        _ event: Published,
        responseType: Response.Type,
        check: @escaping @Sendable (Response) -> Bool = { _ in true },
        timeout: TimeInterval = 10,
    ) async throws -> Response {
        try await awaitEvent(responseType, check: check, timeout: timeout) { [event] in
            Task { [self] in
                await publish(event)
            }
        }
    }
}
