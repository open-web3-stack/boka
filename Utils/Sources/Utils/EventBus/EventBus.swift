import Atomics
import Foundation
import TracingUtils

private let logger = Logger(label: "EventBus")

public actor EventBus: Sendable {
    private static let idGenerator = ManagedAtomic<Int>(0)

    public struct SubscriptionToken: Hashable, Sendable {
        fileprivate let id: Int
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
        private let _handle: @Sendable (Any) async throws -> Void

        init<T>(_ token: SubscriptionToken, _ handler: @escaping @Sendable (T) async throws -> Void) {
            self.token = token
            _handle = { event in
                guard let event = event as? T else { return }
                try await handler(event)
            }
        }

        func handle(_ event: Any) async throws {
            try await _handle(event)
        }
    }

    private var handlers: [ObjectIdentifier: [AnyEventHandler]] = [:]
    private let eventMiddleware: Middleware
    private let handlerMiddleware: Middleware

    public init(eventMiddleware: Middleware = .noop, handlerMiddleware: Middleware = .noop) {
        self.eventMiddleware = eventMiddleware
        self.handlerMiddleware = handlerMiddleware
    }

    public func subscribe<T: Event>(_ eventType: T.Type, handler: @escaping @Sendable (T) async throws -> Void) -> SubscriptionToken {
        let key = ObjectIdentifier(eventType)
        let token = SubscriptionToken(id: EventBus.idGenerator.loadThenWrappingIncrement(ordering: .relaxed), eventTypeId: key)

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

    public func publish(_ event: some Event) {
        let key = ObjectIdentifier(type(of: event))
        if let eventHandlers = handlers[key] {
            Task {
                do {
                    try await self.eventMiddleware.handle(event) { event in
                        for handler in eventHandlers {
                            try await self.handlerMiddleware.handle(event) { evt in
                                try await handler.handle(evt)
                            }
                        }
                    }
                } catch {
                    logger.warning("Unhandled error for event: \(event) with error: \(error)")
                }
            }
        }
    }
}
