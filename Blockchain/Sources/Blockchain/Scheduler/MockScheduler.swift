import Foundation
import Utils

public final class MockScheduler: Scheduler, Sendable {
    public final class Task: Sendable {
        let scheduleTime: UInt32
        let repeats: Bool
        let task: @Sendable () -> Void

        init(scheduleTime: UInt32, repeats: Bool, task: @escaping @Sendable () -> Void) {
            self.scheduleTime = scheduleTime
            self.repeats = repeats
            self.task = task
        }
    }

    public let timeProvider: MockTimeProvider
    public let tasks: ThreadSafeContainer<[Task]> = .init([])
    private let prevTime: ThreadSafeContainer<UInt32>

    public init(timeProvider: MockTimeProvider) {
        self.timeProvider = timeProvider
        prevTime = ThreadSafeContainer(timeProvider.getTime())
    }

    public func schedule(delay: TimeInterval, repeats: Bool, task: @escaping @Sendable () -> Void) -> Cancellable {
        let now = timeProvider.getTime()
        let scheduleTime = now + UInt32(delay)
        let task = Task(scheduleTime: scheduleTime, repeats: repeats, task: task)
        tasks.value.append(task)
        return Cancellable {
            self.tasks.value.removeAll { $0 === task }
        }
    }

    public func advance(by interval: UInt32) {
        timeProvider.advance(by: interval)
        trigger()
    }

    public func trigger() {}
}
