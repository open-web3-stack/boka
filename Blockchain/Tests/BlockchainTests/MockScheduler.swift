import Atomics
import Blockchain
import Foundation
import Utils

final class SchedulerTask: Sendable, Comparable {
    let id: Int
    let scheduleTime: TimeInterval
    let repeats: TimeInterval?
    let task: @Sendable () async -> Void
    let cancel: (@Sendable () -> Void)?

    init(
        id: Int,
        scheduleTime: TimeInterval,
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

    static func < (lhs: SchedulerTask, rhs: SchedulerTask) -> Bool {
        lhs.scheduleTime < rhs.scheduleTime
    }

    static func == (lhs: SchedulerTask, rhs: SchedulerTask) -> Bool {
        lhs.scheduleTime == rhs.scheduleTime
    }
}

struct Storage: Sendable {
    var tasks: SortedArray<SchedulerTask> = .init([])
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

    func scheduleImpl(
        delay: TimeInterval,
        repeats: Bool,
        task: @escaping @Sendable () async -> Void,
        onCancel: (@Sendable () -> Void)?
    ) -> Cancellable {
        let now = timeProvider.getTimeInterval()
        let scheduleTime = now + delay
        let id = Self.idGenerator.loadThenWrappingIncrement(ordering: .relaxed)
        let task = SchedulerTask(id: id, scheduleTime: scheduleTime, repeats: repeats ? delay : nil, task: task, cancel: onCancel)
        storage.write { storage in
            storage.tasks.insert(task)
        }
        return Cancellable {
            self.storage.write { storage in
                if let index = storage.tasks.array.firstIndex(where: { $0.id == id }) {
                    let task = storage.tasks.remove(at: index)
                    task.cancel?()
                }
            }
        }
    }

    func advance(by interval: TimeInterval) async {
        let to = timeProvider.getTimeInterval() + interval
        while await advanceNext(to: to) {}
    }

    func advanceNext(to time: TimeInterval) async -> Bool {
        let task: SchedulerTask? = storage.write { storage in
            if let task = storage.tasks.array.first, task.scheduleTime <= time {
                storage.tasks.remove(at: 0)
                return task
            }
            return nil
        }

        if let task {
            mockTimeProvider.advance(to: task.scheduleTime)
            await task.task()

            return true
        }

        return false
    }
}
