import Foundation
import TracingUtils

private let logger = Logger(label: "EventBus")

public protocol SubscriptionTokenProtocol: Sendable {}

public protocol Subscribable: AnyObject, Sendable {
    associatedtype SubscriptionToken: SubscriptionTokenProtocol

    func subscribe<T: Event>(
        _ eventType: T.Type,
        id: UniqueId,
        handler: @escaping @Sendable (T) async throws -> Void
    ) async -> SubscriptionToken

    func unsubscribe(token: SubscriptionToken) async
}

extension Subscribable {
    public func subscribe<T: Event>(
        _ eventType: T.Type,
        id: UniqueId = "",
        handler: @escaping @Sendable (T) async throws -> Void
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

    public func subscribe<T: Event>(
        _ eventType: T.Type,
        id: UniqueId = "",
        handler: @escaping @Sendable (T) async throws -> Void
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
}
