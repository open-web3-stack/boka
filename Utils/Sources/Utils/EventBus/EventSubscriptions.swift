import Synchronization

public struct EventSubscriptions: ~Copyable, Sendable {
    private let eventBus: EventBus
    private let subscriptionTokens: Mutex<[EventBus.SubscriptionToken]> = .init([])

    public init(eventBus: EventBus) {
        self.eventBus = eventBus
    }

    deinit {
        let eventBus = self.eventBus
        let tokens = subscriptionTokens.value
        Task {
            for token in tokens {
                await eventBus.unsubscribe(token: token)
            }
        }
    }

    @discardableResult
    public func subscribe<T: Event>(
        _ eventType: T.Type,
        id _: UniqueId,
        handler: @escaping @Sendable (T) async throws -> Void
    ) async -> EventBus.SubscriptionToken {
        let token = await eventBus.subscribe(eventType, handler: handler)
        subscriptionTokens.withLock { $0.append(token) }
        return token
    }

    public func unsubscribe(token: EventBus.SubscriptionToken) async {
        subscriptionTokens.withLock { tokens in
            tokens.removeAll { $0 == token }
        }
        await eventBus.unsubscribe(token: token)
    }

    public func publish(_ event: some Event) {
        eventBus.publish(event)
    }
}
