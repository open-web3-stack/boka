import Atomics
import Foundation
import Utils

private struct IdCancellable: Hashable, Sendable {
    let id: UniqueId
    let cancellable: Cancellable?

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: IdCancellable, rhs: IdCancellable) -> Bool {
        lhs.id == rhs.id
    }
}

public class ServiceBase2: ServiceBase, @unchecked Sendable {
    private let scheduler: Scheduler
    private let cancellables: ThreadSafeContainer<Set<IdCancellable>> = .init([])

    public init(_ config: ProtocolConfigRef, _ eventBus: EventBus, _ scheduler: Scheduler) {
        self.scheduler = scheduler
        super.init(config, eventBus)
    }

    deinit {
        for cancellable in cancellables.value {
            cancellable.cancellable?.cancel()
        }
    }

    public var timeProvider: TimeProvider {
        scheduler.timeProvider
    }

    @discardableResult
    public func schedule(id: UniqueId, delay: TimeInterval, repeats: Bool = false,
                         task: @escaping @Sendable () async -> Void) -> Cancellable
    {
        let cancellables = cancellables
        let cancellable = scheduler.schedule(id: id, delay: delay, repeats: repeats) {
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
    public func schedule(id: UniqueId, at timeslot: TimeslotIndex, task: @escaping @Sendable () async -> Void) -> Cancellable {
        let cancellables = cancellables
        let cancellable = scheduler.schedule(id: id, at: timeslot) {
            cancellables.write { $0.remove(IdCancellable(id: id, cancellable: nil)) }
            await task()
        } onCancel: {
            cancellables.write { $0.remove(IdCancellable(id: id, cancellable: nil)) }
        }
        cancellables.write { $0.insert(IdCancellable(id: id, cancellable: cancellable)) }
        return cancellable
    }

    @discardableResult
    public func scheduleForNextEpoch(_ id: UniqueId, fn: @escaping @Sendable (TimeslotIndex) async -> Void) -> Cancellable {
        let now = timeProvider.getTimeslot()
        let nextEpoch = now.timeslotToEpochIndex(config: config) + 2
        let timeslot = nextEpoch.epochToTimeslotIndex(config: config)

        // at end of an epoch, try to determine the block author of next epoch
        // and schedule new block task
        return schedule(id: id, at: timeslot - 1) { [weak self] in
            if let self {
                scheduleForNextEpoch(id, fn: fn)
                await fn(timeslot)
            }
        }
    }
}
