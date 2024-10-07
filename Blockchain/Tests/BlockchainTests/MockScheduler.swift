import Atomics
import Blockchain
import Foundation
import Utils

final class SchedulerTask: Sendable, Comparable {
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

    static func < (lhs: SchedulerTask, rhs: SchedulerTask) -> Bool {
        lhs.scheduleTime < rhs.scheduleTime
    }

    static func == (lhs: SchedulerTask, rhs: SchedulerTask) -> Bool {
        lhs.scheduleTime == rhs.scheduleTime
    }
}

struct Storage: Sendable {
    var tasks: SortedArray<SchedulerTask> = .init([])
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

    func scheduleImpl(
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
            storage.tasks.insert(task)
        }
        return Cancellable {
            self.storage.mutate { storage in
                if let index = storage.tasks.array.firstIndex(where: { $0.id == id }) {
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
        while await triggerNext() {}
    }

    func triggerNext() async -> Bool {
        let now = timeProvider.getTime()

        let task: SchedulerTask? = storage.mutate { storage in
            if let task = storage.tasks.array.first, task.scheduleTime <= now {
                storage.tasks.remove(at: 0)
                storage.prevTime = task.scheduleTime
                return task
            }
            return nil
        }

        if let task {
            await task.task()

            return true
        }

        return false
    }
}
