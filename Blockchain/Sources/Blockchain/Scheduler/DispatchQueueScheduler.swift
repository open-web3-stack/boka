@preconcurrency import Dispatch
import Foundation
import TracingUtils
import Utils

private let logger = Logger(label: "Scheduler")

public final class DispatchQueueScheduler: Scheduler {
    public let timeProvider: TimeProvider
    public let queue: DispatchQueue

    public init(timeProvider: TimeProvider, queue: DispatchQueue = .global()) {
        self.timeProvider = timeProvider
        self.queue = queue
    }

    public func scheduleImpl(
        delay: TimeInterval,
        repeats: Bool,
        task: @escaping @Sendable () async -> Void,
        onCancel: (@Sendable () -> Void)?,
    ) -> Cancellable {
        logger.trace("scheduling task in \(delay) seconds, repeats: \(repeats)")
        let timer = DispatchSource.makeTimerSource(queue: queue)
        let isCancelled = ThreadSafeContainer(false)
        timer.setEventHandler {
            guard !isCancelled.value else {
                return
            }
            Task {
                guard !isCancelled.value else {
                    return
                }
                await task()
            }
        }
        timer.setCancelHandler {
            isCancelled.value = true
            onCancel?()
        }
        timer.schedule(deadline: .now() + delay, repeating: repeats ? delay : .infinity)
        timer.activate()
        return Cancellable {
            let shouldCancel = isCancelled.write { cancelled in
                if cancelled {
                    return false
                }
                cancelled = true
                return true
            }

            if shouldCancel {
                timer.cancel()
            }
        }
    }
}
