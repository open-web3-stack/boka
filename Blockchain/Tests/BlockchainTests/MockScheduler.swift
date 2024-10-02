import Atomics
import Blockchain
import Foundation
import Utils

final class SchedulerTask: Sendable {
    let id: Int
    let scheduleTime: UInt32
    let repeats: TimeInterval?
    let task: @Sendable () async -> Void
    let cancel: (@Sendable () -> Void)?

    init(
        id: Int,
        scheduleTime: UInt32,
        repeats: TimeInterval?,
        task: @escaping @Sendable () async -> Void,
        cancel: (@Sendable () -> Void)?
    ) {
        self.id = id
        self.scheduleTime = scheduleTime
        self.repeats = repeats
        self.task = task
        self.cancel = cancel
    }
}

struct Storage: Sendable {
    var tasks: [SchedulerTask] = []
    var prevTime: UInt32 = 0
}

final class MockScheduler: Scheduler, Sendable {
    static let idGenerator = ManagedAtomic<Int>(0)

    let mockTimeProvider: MockTimeProvider
    var timeProvider: TimeProvider {
        mockTimeProvider
    }

    let storage: ThreadSafeContainer<Storage> = .init(.init())

    init(timeProvider: MockTimeProvider) {
        mockTimeProvider = timeProvider
    }

    func schedule(
        delay: TimeInterval,
        repeats: Bool,
        task: @escaping @Sendable () async -> Void,
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

    func advance(by interval: UInt32) async {
        mockTimeProvider.advance(by: interval)
        await trigger()
    }

    func trigger() async {
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
            await task.task()
        }
    }
}
