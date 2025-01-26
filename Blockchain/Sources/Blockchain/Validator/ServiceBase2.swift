import Foundation
import TracingUtils
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

    public init(id: UniqueId, config: ProtocolConfigRef, eventBus: EventBus, scheduler: Scheduler) {
        self.scheduler = scheduler
        super.init(id: id, config: config, eventBus: eventBus)
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
    public func schedule(
        id: UniqueId,
        delay: TimeInterval,
        repeats: Bool = false,
        task: @escaping @Sendable () async -> Void
    ) -> Cancellable {
        let cancellables = cancellables
        let cancellable = scheduler.schedule(id: id, delay: delay, repeats: repeats) {
            if !repeats {
                cancellables.write { c -> Void in
                    c.remove(IdCancellable(id: id, cancellable: nil))
                }
            }
            await task()
        } onCancel: {
            cancellables.write { c -> Void in
                c.remove(IdCancellable(id: id, cancellable: nil))
            }
        }
        cancellables.write { c -> Void in
            c.insert(IdCancellable(id: id, cancellable: cancellable))
        }
        return cancellable
    }

    @discardableResult
    public func scheduleForNextEpoch(_ id: UniqueId, fn: @escaping @Sendable (EpochIndex) async -> Void) -> Cancellable {
        let now = timeProvider.getTime()
        let nowTimeslot = now.timeToTimeslot(config: config)
        let nextEpoch = nowTimeslot.timeslotToEpochIndex(config: config) + 1
        return scheduleFor(epoch: nextEpoch, id: id, fn: fn)
    }

    @discardableResult
    private func scheduleFor(epoch: EpochIndex, id: UniqueId, fn: @escaping @Sendable (EpochIndex) async -> Void) -> Cancellable {
        let scheduleTime = config.scheduleTimeForPrepareEpoch(epoch: epoch)
        let now = timeProvider.getTimeInterval()
        var delay = scheduleTime - now
        if delay < 0 {
            logger.debug("\(id): late epoch start \(epoch), expectedDelay \(delay)")
            delay = 0
        }
        logger.trace("\(id): scheduling epoch \(epoch) in \(delay)")
        return schedule(id: id, delay: delay) { [weak self] in
            if let self {
                scheduleFor(epoch: epoch + 1, id: id, fn: fn)
                await fn(epoch)
            }
        }
    }
}
