import Foundation
import TracingUtils

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

    func schedule(
        delay: TimeInterval,
        repeats: Bool,
        task: @escaping @Sendable () async -> Void,
        onCancel: (@Sendable () -> Void)?
    ) -> Cancellable
}

extension Scheduler {
    func schedule(
        delay: TimeInterval,
        repeats: Bool = false,
        task: @escaping @Sendable () async -> Void,
        onCancel: (@Sendable () -> Void)? = nil
    ) -> Cancellable {
        schedule(delay: delay, repeats: repeats, task: task, onCancel: onCancel)
    }

    public func schedule(
        at timeslot: TimeslotIndex,
        task: @escaping @Sendable () async -> Void,
        onCancel: (@Sendable () -> Void)? = nil
    ) -> Cancellable {
        let nowTimeslot = timeProvider.getTimeslot()
        if timeslot == nowTimeslot {
            return schedule(delay: 0, repeats: false, task: task, onCancel: onCancel)
        }

        let deadline = timeProvider.timeslotToTime(timeslot)
        let now = timeProvider.getTime()
        if deadline < now {
            logger.error("scheduling task in the past", metadata: ["deadline": "\(deadline)", "now": "\(now)"])
            return Cancellable {}
        }
        return schedule(delay: TimeInterval(deadline - now), repeats: false, task: task, onCancel: onCancel)
    }
}

extension Scheduler {
    public func getTime() -> UInt32 {
        timeProvider.getTime()
    }
}
