@preconcurrency import Foundation
import TracingUtils

private let logger = Logger(label: "Scheduler")

public final class DispatchQueueScheduler: Scheduler {
    public let timeProvider: TimeProvider
    private let queue: DispatchQueue

    public init(timeProvider: TimeProvider, queue: DispatchQueue = .global()) {
        self.timeProvider = timeProvider
        self.queue = queue
    }

    public func schedule(
        delay: TimeInterval,
        repeats: Bool,
        task: @escaping @Sendable () -> Void,
        onCancel: (@Sendable () -> Void)?
    ) -> Cancellable {
        logger.trace("scheduling task in \(delay) seconds, repeats: \(repeats)")
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.setEventHandler(handler: task)
        timer.setCancelHandler(handler: onCancel)
        timer.schedule(deadline: .now() + delay, repeating: repeats ? delay : .infinity)
        timer.activate()
        return Cancellable {
            timer.cancel()
        }
    }
}
