import Foundation
import TracingUtils
import Utils

private let logger = Logger(label: "Scheduler")

public final class Cancellable: Sendable, Hashable {
    private let fn: @Sendable () -> Void
    public init(_ fn: @escaping @Sendable () -> Void) {
        self.fn = fn
    }

    public func cancel() {
        fn()
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }

    public static func == (lhs: Cancellable, rhs: Cancellable) -> Bool {
        lhs === rhs
    }
}

public protocol Scheduler: Sendable {
    var timeProvider: TimeProvider { get }

    func scheduleImpl(
        delay: TimeInterval,
        repeats: Bool,
        task: @escaping @Sendable () async -> Void,
        onCancel: (@Sendable () -> Void)?
    ) -> Cancellable
}

extension Scheduler {
    func schedule(
        id: UniqueId = "",
        delay: TimeInterval,
        repeats: Bool = false,
        task: @escaping @Sendable () async -> Void,
        onCancel: (@Sendable () -> Void)? = nil
    ) -> Cancellable {
        logger.trace("scheduling task: \(id)", metadata: ["delay": "\(delay)", "repeats": "\(repeats)"])
        let cancellable = scheduleImpl(delay: delay, repeats: repeats, task: {
            logger.trace("executing task: \(id)")
            await task()
        }, onCancel: onCancel)
        return Cancellable {
            logger.trace("cancelling task: \(id)")
            cancellable.cancel()
        }
    }

    public func schedule(
        id: UniqueId = "",
        at timeslot: TimeslotIndex,
        task: @escaping @Sendable () async -> Void,
        onCancel: (@Sendable () -> Void)? = nil
    ) -> Cancellable {
        let nowTimeslot = timeProvider.getTimeslot()
        if timeslot == nowTimeslot {
            return schedule(id: id, delay: 0, repeats: false, task: task, onCancel: onCancel)
        }

        let deadline = timeProvider.timeslotToTime(timeslot)
        let now = timeProvider.getTime()
        if deadline < now {
            logger.error("scheduling task in the past", metadata: ["deadline": "\(deadline)", "now": "\(now)"])
            return Cancellable {}
        }
        return schedule(id: id, delay: TimeInterval(deadline - now), repeats: false, task: task, onCancel: onCancel)
    }
}

extension Scheduler {
    public func getTime() -> UInt32 {
        timeProvider.getTime()
    }
}
