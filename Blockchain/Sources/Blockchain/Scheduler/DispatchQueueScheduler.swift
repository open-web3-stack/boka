@preconcurrency import Dispatch
import Foundation
import TracingUtils

private let logger = Logger(label: "Scheduler")

public final class DispatchQueueScheduler: Scheduler {
    public let timeProvider: TimeProvider

    public init(timeProvider: TimeProvider) {
        self.timeProvider = timeProvider
    }

    public func schedule(
        delay: TimeInterval,
        repeats: Bool,
        task: @escaping @Sendable () async -> Void,
        onCancel: (@Sendable () -> Void)?
    ) -> Cancellable {
        logger.trace("scheduling task in \(delay) seconds, repeats: \(repeats)")
        let timer = DispatchSource.makeTimerSource(queue: .global())
        timer.setEventHandler {
            Task {
                await task()
            }
        }
        timer.setCancelHandler(handler: onCancel)
        timer.schedule(deadline: .now() + delay, repeating: repeats ? delay : .infinity)
        timer.activate()
        return Cancellable {
            timer.cancel()
        }
    }
}
