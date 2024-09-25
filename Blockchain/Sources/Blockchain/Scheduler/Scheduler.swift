import Foundation

public final class Cancellable: Sendable {
    private let fn: @Sendable () -> Void
    public init(_ fn: @escaping @Sendable () -> Void) {
        self.fn = fn
    }

    public func cancel() {
        fn()
    }
}

public protocol Scheduler: Sendable {
    var timeProvider: TimeProvider { get }

    func schedule(delay: TimeInterval, repeats: Bool, task: @escaping @Sendable () -> Void) -> Cancellable
}

extension Scheduler {
    public func schedule(at timeslot: TimeslotIndex, task: @escaping @Sendable () -> Void) -> Cancellable {
        let deadline = timeProvider.timeslotToTime(timeslot)
        return schedule(delay: TimeInterval(deadline - timeProvider.getTime()), repeats: false, task: task)
    }
}
