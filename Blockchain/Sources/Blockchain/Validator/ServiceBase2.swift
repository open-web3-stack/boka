import Atomics
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

    public init(logger: Logger, config: ProtocolConfigRef, eventBus: EventBus, scheduler: Scheduler) {
        self.scheduler = scheduler
        super.init(logger: logger, config: config, eventBus: eventBus)
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
        let now = timeProvider.getTimeInterval()
        let nowTimeslot = UInt32(now).timeToTimeslot(config: config)
        let nextEpoch = (nowTimeslot + 1).timeslotToEpochIndex(config: config) + 1
        return scheduleFor(epoch: nextEpoch, id: id, fn: fn)
    }

    @discardableResult
    private func scheduleFor(epoch: EpochIndex, id: UniqueId, fn: @escaping @Sendable (EpochIndex) async -> Void) -> Cancellable {
        let scheduleTime = config.scheduleTimeForPrepareEpoch(epoch: epoch)
        let now = timeProvider.getTimeInterval()
        let delay = scheduleTime - now
        if delay < 0 {
            // too late / current epoch is about to end
            // schedule for the one after
            logger.debug("\(id): skipping epoch \(epoch) because it is too late")
            return scheduleFor(epoch: epoch + 1, id: id, fn: fn)
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
