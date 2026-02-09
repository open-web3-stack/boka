import Foundation
import TracingUtils
import Utils

/// Base class for blockchain services
///
/// Thread-safety: @unchecked Sendable is safe here because:
/// - All properties are either immutable (let) or thread-safe actors
/// - EventSubscriptions is an actor that manages its own state
/// - No mutable shared state
public class ServiceBase: @unchecked Sendable {
    public let id: UniqueId
    let logger: Logger
    public let config: ProtocolConfigRef
    private let subscriptions: EventSubscriptions

    init(id: UniqueId, config: ProtocolConfigRef, eventBus: EventBus) {
        self.id = id
        logger = Logger(label: id)
        self.config = config
        subscriptions = EventSubscriptions(eventBus: eventBus)
    }

    @discardableResult
    func subscribe<T: Event>(
        _ eventType: T.Type, id _: UniqueId, handler: @escaping @Sendable (T) async throws -> Void,
    ) async -> EventBus.SubscriptionToken {
        await subscriptions.subscribe(eventType, id: id, handler: handler)
    }

    func unsubscribe(token: EventBus.SubscriptionToken) async {
        await subscriptions.unsubscribe(token: token)
    }

    func publish(_ event: some Event) {
        subscriptions.publish(event)
    }

    func waitFor<T: Event>(
        eventType: T.Type,
        check: @escaping @Sendable (T) -> Bool = { _ in true },
        timeout: TimeInterval = 10,
    ) async throws -> T {
        try await subscriptions.waitFor(eventType, check: check, timeout: timeout)
    }
}
