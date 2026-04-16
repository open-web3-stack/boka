@testable import Blockchain
import Foundation
import Testing
import Utils

struct DispatchQueueSchedulerTests {
    private func makeScheduler(label: String) -> DispatchQueueScheduler {
        DispatchQueueScheduler(
            timeProvider: SystemTimeProvider(),
            queue: DispatchQueue(label: label, qos: .userInteractive)
        )
    }

    @Test func scheduleTaskWithoutDelay() async throws {
        let scheduler = makeScheduler(label: "DispatchQueueSchedulerTests.scheduleTaskWithoutDelay")

        try await confirmation { confirm in
            let cancel = scheduler.schedule(delay: 0, repeats: false) {
                confirm()
            }

            try await Task.sleep(for: .seconds(0.5))

            _ = cancel
        }
    }

    // @Test func scheduleDelayedTask() async throws {
    //     await withKnownIssue("unstable when cpu is busy", isIntermittent: true) {
    //         try await confirmation { confirm in
    //             let delay = 0.5
    //             let now = Date()
    //             let end: ThreadSafeContainer<Date?> = .init(nil)
    //             let cancel = scheduler.schedule(delay: delay, repeats: false) {
    //                 end.value = Date()
    //                 confirm()
    //             }

    //             try await Task.sleep(for: .seconds(1))

    //             _ = cancel

    //             let diff = try #require(end.value).timeIntervalSince(now) - delay
    //             let diffAbs = abs(diff)
    //             #expect(diffAbs < 0.5)
    //         }
    //     }
    // }

    // @Test func scheduleRepeatingTask() async throws {
    //     await withKnownIssue("unstable when cpu is busy", isIntermittent: true) {
    //         try await confirmation(expectedCount: 2) { confirm in
    //             let delay = 1.5
    //             let now = Date()
    //             let executionTimes = ThreadSafeContainer<[Date]>([])
    //             let expectedExecutions = 2

    //             let cancel = scheduler.schedule(delay: delay, repeats: true) {
    //                 executionTimes.value.append(Date())
    //                 confirm()
    //             }

    //             try await Task.sleep(for: .seconds(3.1))

    //             _ = cancel

    //             #expect(executionTimes.value.count == expectedExecutions)

    //             for (index, time) in executionTimes.value.enumerated() {
    //                 let expectedInterval = delay * Double(index + 1)
    //                 let actualInterval = time.timeIntervalSince(now)
    //                 let difference = abs(actualInterval - expectedInterval)
    //                 #expect(difference < 0.5)
    //             }
    //         }
    //     }
    // }

    @Test func cancelTask() async throws {
        let scheduler = makeScheduler(label: "DispatchQueueSchedulerTests.cancelTask")

        try await confirmation(expectedCount: 0) { confirm in
            let cancel = scheduler.schedule(delay: 0.2, repeats: false) {
                confirm()
            }

            cancel.cancel()

            // Wait past the original deadline to verify cancellation prevents execution.
            try await Task.sleep(for: .seconds(0.3))
        }
    }

    @Test func cancelRepeatingTask() async throws {
        let scheduler = makeScheduler(label: "DispatchQueueSchedulerTests.cancelRepeatingTask")
        let fireCount = ThreadSafeContainer<Int>(0)
        let cancellation = ThreadSafeContainer<Cancellable?>(nil)

        try await confirmation(expectedCount: 2) { confirm in
            let cancel = scheduler.schedule(delay: 0.2, repeats: true) {
                let count = fireCount.value + 1
                fireCount.value = count
                confirm()

                if count == 2 {
                    cancellation.value?.cancel()
                }
            }

            cancellation.value = cancel

            // Give the second invocation time to cancel before the third would be due.
            try await Task.sleep(for: .seconds(0.7))
        }
    }

    @Test func onCancelHandler() async throws {
        let scheduler = makeScheduler(label: "DispatchQueueSchedulerTests.onCancelHandler")

        try await confirmation(expectedCount: 1) { confirm in
            let cancel = scheduler.schedule(delay: 0.1, repeats: false, task: {
                Issue.record("Task executed")
            }, onCancel: {
                confirm()
            })

            cancel.cancel()

            try await Task.sleep(for: .seconds(1))
        }
    }
}
