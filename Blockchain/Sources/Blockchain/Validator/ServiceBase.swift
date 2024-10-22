import TracingUtils
import Utils

public class ServiceBase {
    public let id: UniqueId
    let logger: Logger
    public let config: ProtocolConfigRef
    private let eventBus: EventBus
    private let subscriptionTokens: ThreadSafeContainer<[EventBus.SubscriptionToken]> = .init([])

    init(id: UniqueId, config: ProtocolConfigRef, eventBus: EventBus) {
        self.id = id
        logger = Logger(label: id)
        self.config = config
        self.eventBus = eventBus
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

    @discardableResult
    func subscribe<T: Event>(_ eventType: T.Type, id _: UniqueId, handler: @escaping @Sendable (T) async throws -> Void) async -> EventBus
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

    func publish(_ event: some Event) {
        eventBus.publish(event)
    }
}
