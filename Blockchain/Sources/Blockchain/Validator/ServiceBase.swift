import Utils

public class ServiceBase {
    public let config: ProtocolConfigRef
    private let eventBus: EventBus
    private let subscriptionTokens: ThreadSafeContainer<[EventBus.SubscriptionToken]> = .init([])

    init(_ config: ProtocolConfigRef, _ eventBus: EventBus) {
        self.config = config
        self.eventBus = eventBus
    }

    @discardableResult
    func subscribe<T: Event>(_ eventType: T.Type, handler: @escaping @Sendable (T) async throws -> Void) async -> EventBus
        .SubscriptionToken
    {
        let token = await eventBus.subscribe(eventType, handler: handler)
        subscriptionTokens.write { $0.append(token) }
        return token
    }

    func unsubscribe(token: EventBus.SubscriptionToken) async {
        subscriptionTokens.write { tokens in
            tokens.removeAll { $0 == token }
        }
        await eventBus.unsubscribe(token: token)
    }

    func publish(_ event: some Event) async {
        await eventBus.publish(event)
    }

    deinit {
        let eventBus = self.eventBus
        let subscriptionTokens = self.subscriptionTokens
        Task {
            for token in subscriptionTokens.value {
                await eventBus.unsubscribe(token: token)
            }
        }
    }
}
