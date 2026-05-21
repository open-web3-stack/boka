@testable import Blockchain
import Foundation
import Testing
import Utils

struct MockSchedulerTests {
    @Test func scheduledTaskRunsOnlyAfterTimeAdvancesPastDelay() async {
        let timeProvider = MockTimeProvider(time: 10)
        let scheduler = MockScheduler(timeProvider: timeProvider)
        let fireTimes = ThreadSafeContainer<[TimeInterval]>([])

        _ = scheduler.schedule(delay: 5) {
            fireTimes.write { $0.append(timeProvider.getTimeInterval()) }
        }

        await scheduler.advance(by: 4.99)
        #expect(fireTimes.value.isEmpty)
        #expect(scheduler.taskCount == 1)

        await scheduler.advance(by: 0.01)
        #expect(fireTimes.value == [15])
        #expect(scheduler.taskCount == 0)
    }

    @Test func repeatingTaskReschedulesUntilCancelled() async {
        let timeProvider = MockTimeProvider()
        let scheduler = MockScheduler(timeProvider: timeProvider)
        let fireTimes = ThreadSafeContainer<[TimeInterval]>([])

        let cancel = scheduler.schedule(delay: 2, repeats: true) {
            fireTimes.write { $0.append(timeProvider.getTimeInterval()) }
        }

        await scheduler.advance(by: 6)

        #expect(fireTimes.value == [2, 4, 6])
        #expect(scheduler.taskCount == 1)

        cancel.cancel()
        #expect(scheduler.taskCount == 0)

        await scheduler.advance(by: 10)
        #expect(fireTimes.value == [2, 4, 6])
    }

    @Test func cancellingQueuedTaskPreventsExecutionAndCallsOnCancelOnce() async {
        let scheduler = MockScheduler(timeProvider: MockTimeProvider())
        let fireCount = ThreadSafeContainer(0)
        let cancelCount = ThreadSafeContainer(0)

        let cancel = scheduler.schedule(delay: 1, task: {
            fireCount.write { $0 += 1 }
        }, onCancel: {
            cancelCount.write { $0 += 1 }
        })

        cancel.cancel()
        cancel.cancel()

        await scheduler.advance(by: 2)

        #expect(fireCount.value == 0)
        #expect(cancelCount.value == 1)
        #expect(scheduler.taskCount == 0)
    }

    @Test func negativeDelayDoesNotScheduleTask() async {
        let scheduler = MockScheduler(timeProvider: MockTimeProvider())
        let fireCount = ThreadSafeContainer(0)

        _ = scheduler.schedule(delay: -1) {
            fireCount.write { $0 += 1 }
        }

        await scheduler.advance(by: 10)

        #expect(fireCount.value == 0)
        #expect(scheduler.taskCount == 0)
    }
}
