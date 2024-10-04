import Atomics
import Foundation
import Utils

private struct IdCancellable: Hashable, Sendable {
    let id: Int
    let cancellable: Cancellable?

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: IdCancellable, rhs: IdCancellable) -> Bool {
        lhs.id == rhs.id
    }
}

public class ServiceBase2: ServiceBase {
    private static let idGenerator = ManagedAtomic<Int>(0)
    private let scheduler: Scheduler
    private let cancellables: ThreadSafeContainer<Set<IdCancellable>> = .init([])

    public init(_ config: ProtocolConfigRef, _ eventBus: EventBus, _ scheduler: Scheduler) {
        self.scheduler = scheduler
        super.init(config, eventBus)
    }

    public var timeProvider: TimeProvider {
        scheduler.timeProvider
    }

    @discardableResult
    public func schedule(delay: TimeInterval, repeats: Bool = false, task: @escaping @Sendable () async -> Void) -> Cancellable {
        let id = Self.idGenerator.loadThenWrappingIncrement(ordering: .relaxed)
        let cancellables = cancellables
        let cancellable = scheduler.schedule(delay: delay, repeats: repeats) {
            if !repeats {
                cancellables.write { $0.remove(IdCancellable(id: id, cancellable: nil)) }
            }
            await task()
        } onCancel: {
            cancellables.write { $0.remove(IdCancellable(id: id, cancellable: nil)) }
        }
        cancellables.write { $0.insert(IdCancellable(id: id, cancellable: cancellable)) }
        return cancellable
    }

    @discardableResult
    public func schedule(at timeslot: TimeslotIndex, task: @escaping @Sendable () async -> Void) -> Cancellable {
        let id = Self.idGenerator.loadThenWrappingIncrement(ordering: .relaxed)
        let cancellables = cancellables
        let cancellable = scheduler.schedule(at: timeslot) {
            cancellables.write { $0.remove(IdCancellable(id: id, cancellable: nil)) }
            await task()
        } onCancel: {
            cancellables.write { $0.remove(IdCancellable(id: id, cancellable: nil)) }
        }
        cancellables.write { $0.insert(IdCancellable(id: id, cancellable: cancellable)) }
        return cancellable
    }

    deinit {
        for cancellable in cancellables.value {
            cancellable.cancellable?.cancel()
        }
    }
}
