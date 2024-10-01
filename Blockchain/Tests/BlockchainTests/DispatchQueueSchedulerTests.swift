import Foundation
import Testing
import Utils

@testable import Blockchain

struct DispatchQueueSchedulerTests {
    let scheduler = DispatchQueueScheduler(timeProvider: SystemTimeProvider(slotPeriodSeconds: 6))

    @Test func scheduleTaskWithoutDelay() async throws {
        try await confirmation { confirm in
            let cancel = scheduler.schedule(delay: 0, repeats: false) {
                confirm()
            }

            try await Task.sleep(for: .milliseconds(1))

            _ = cancel
        }
    }

    @Test func scheduleDelayedTask() async throws {
        try await confirmation { confirm in
            let delay = 0.05
            let now = Date()
            let end: ThreadSafeContainer<Date?> = .init(nil)
            let cancel = scheduler.schedule(delay: delay, repeats: false) {
                end.value = Date()
                confirm()
            }

            try await Task.sleep(for: .seconds(0.06))

            _ = cancel

            let diff = end.value!.timeIntervalSince(now) - delay
            let diffAbs = abs(diff)
            #expect(diffAbs < 0.01)
        }
    }

    @Test func scheduleRepeatingTask() async throws {
        try await confirmation(expectedCount: 3) { confirm in
            let delay = 0.05
            let now = Date()
            let executionTimes = ThreadSafeContainer<[Date]>([])
            let expectedExecutions = 3

            let cancel = scheduler.schedule(delay: delay, repeats: true) {
                executionTimes.value.append(Date())
                confirm()
            }

            try await Task.sleep(for: .seconds(0.16))

            _ = cancel

            #expect(executionTimes.value.count == expectedExecutions)

            for (index, time) in executionTimes.value.enumerated() {
                let expectedInterval = delay * Double(index + 1)
                let actualInterval = time.timeIntervalSince(now)
                let difference = abs(actualInterval - expectedInterval)
                #expect(difference < 0.01)
            }
        }
    }

    @Test func cancelTask() async throws {
        try await confirmation(expectedCount: 0) { confirm in
            let cancel = scheduler.schedule(delay: 0, repeats: false) {
                confirm()
            }

            cancel.cancel()

            try await Task.sleep(for: .seconds(0.1))
        }
    }

    @Test func cancelRepeatingTask() async throws {
        try await confirmation(expectedCount: 2) { confirm in
            let delay = 0.05

            let cancel = scheduler.schedule(delay: delay, repeats: true) {
                confirm()
            }

            try await Task.sleep(for: .seconds(0.11))

            cancel.cancel()

            try await Task.sleep(for: .seconds(0.01))
        }
    }

    @Test func onCancelHandler() async throws {
        try await confirmation(expectedCount: 1) { confirm in
            let cancel = scheduler.schedule(delay: 0.01, repeats: false, task: {
                Issue.record("Task executed")
            }, onCancel: {
                confirm()
            })

            cancel.cancel()

            try await Task.sleep(for: .seconds(0.02))
        }
    }
}
