import Atomics
import Foundation
import Utils

private final class SchedulerTask: Sendable {
    let id: Int
    let scheduleTime: UInt32
    let repeats: TimeInterval?
    let task: @Sendable () -> Void
    let cancel: (@Sendable () -> Void)?

    init(
        id: Int,
        scheduleTime: UInt32,
        repeats: TimeInterval?,
        task: @escaping @Sendable () -> Void,
        cancel: (@Sendable () -> Void)?
    ) {
        self.id = id
        self.scheduleTime = scheduleTime
        self.repeats = repeats
        self.task = task
        self.cancel = cancel
    }
}

private struct Storage: Sendable {
    var tasks: [SchedulerTask] = []
    var prevTime: UInt32 = 0
}

public final class MockScheduler: Scheduler, Sendable {
    static let idGenerator = ManagedAtomic<Int>(0)

    private let mockTimeProvider: MockTimeProvider
    public var timeProvider: TimeProvider {
        mockTimeProvider
    }

    private let storage: ThreadSafeContainer<Storage> = .init(.init())

    public init(timeProvider: MockTimeProvider) {
        mockTimeProvider = timeProvider
    }

    public func schedule(
        delay: TimeInterval,
        repeats: Bool,
        task: @escaping @Sendable () -> Void,
        onCancel: (@Sendable () -> Void)?
    ) -> Cancellable {
        let now = timeProvider.getTime()
        let scheduleTime = now + UInt32(delay)
        let id = Self.idGenerator.loadThenWrappingIncrement(ordering: .relaxed)
        let task = SchedulerTask(id: id, scheduleTime: scheduleTime, repeats: repeats ? delay : nil, task: task, cancel: onCancel)
        storage.write { storage in
            storage.tasks.append(task)
        }
        return Cancellable {
            self.storage.mutate { storage in
                if let index = storage.tasks.firstIndex(where: { $0.id == id }) {
                    let task = storage.tasks.remove(at: index)
                    task.cancel?()
                }
            }
        }
    }

    public func advance(by interval: UInt32) {
        mockTimeProvider.advance(by: interval)
        trigger()
    }

    public func trigger() {
        let now = timeProvider.getTime()
        let tasks = storage.mutate { storage in
            var tasksToDispatch: [SchedulerTask] = []
            var remainingTasks: [SchedulerTask] = []

            for task in storage.tasks {
                if task.scheduleTime <= now {
                    tasksToDispatch.append(task)
                } else {
                    remainingTasks.append(task)
                }
            }

            storage.tasks = remainingTasks
            storage.prevTime = now
            for task in tasksToDispatch {
                if let repeats = task.repeats {
                    storage.tasks.append(SchedulerTask(
                        id: task.id,
                        scheduleTime: task.scheduleTime + UInt32(repeats),
                        repeats: repeats,
                        task: task.task,
                        cancel: task.cancel
                    ))
                }
            }
            return tasksToDispatch
        }

        for task in tasks {
            task.task()
        }
    }
}
