// Tests for the EventBus.waitFor method

import Foundation
import Testing

@testable import Utils

struct TestEvent: Event {
    let id: Int
    let value: String
}

struct AnotherTestEvent: Event {
    let name: String
}

struct EventBusTests {
    let eventBus = EventBus()

    @Test func testBasicWaitFor() async throws {
        let testEvent = TestEvent(id: 1, value: "test")

        // Start waiting for the event in a separate task
        let waitTask = Task {
            try await eventBus.waitFor(TestEvent.self)
        }

        // Give a small delay to ensure the wait is set up
        try await Task.sleep(for: .seconds(0.1))

        // Publish the event
        await eventBus.publish(testEvent)

        // Wait for the result and verify
        let receivedEvent = try await waitTask.value
        #expect(receivedEvent.id == testEvent.id)
        #expect(receivedEvent.value == testEvent.value)
    }

    @Test func testWaitForWithCustomCheck() async throws {
        // Start waiting for an event with id = 2
        let waitTask = Task {
            try await eventBus.waitFor(TestEvent.self) { event in
                event.id == 2
            }
        }

        // Give a small delay to ensure the wait is set up
        try await Task.sleep(for: .seconds(0.1))

        // Publish an event that doesn't match the check
        await eventBus.publish(TestEvent(id: 1, value: "wrong event"))

        // Publish an event that matches the check
        let correctEvent = TestEvent(id: 2, value: "correct event")
        await eventBus.publish(correctEvent)

        // Wait for the result and verify
        let receivedEvent = try await waitTask.value
        #expect(receivedEvent.id == 2)
        #expect(receivedEvent.value == "correct event")
    }

    @Test func testWaitForTimeout() async throws {
        await #expect(throws: ContinuationError.timeout) {
            // Wait for an event with a short timeout
            _ = try await eventBus.waitFor(TestEvent.self, timeout: 0.1)
            Issue.record()
        }
    }

    @Test func testMultipleConcurrentWaits() async throws {
        // Start waiting for two different event types
        let waitTask1 = Task {
            try await eventBus.waitFor(TestEvent.self)
        }

        let waitTask2 = Task {
            try await eventBus.waitFor(AnotherTestEvent.self)
        }

        // Give a small delay to ensure the waits are set up
        try await Task.sleep(for: .seconds(0.1))

        // Publish events
        let testEvent = TestEvent(id: 5, value: "test value")
        let anotherEvent = AnotherTestEvent(name: "another test")

        await eventBus.publish(testEvent)
        await eventBus.publish(anotherEvent)

        // Wait for results and verify
        let receivedEvent1 = try await waitTask1.value
        let receivedEvent2 = try await waitTask2.value

        #expect(receivedEvent1.id == 5)
        #expect(receivedEvent1.value == "test value")
        #expect(receivedEvent2.name == "another test")
    }

    @Test func testMultipleWaitsForSameEventType() async throws {
        // Start multiple waits with different check conditions
        let waitTask1 = Task {
            try await eventBus.waitFor(TestEvent.self) { event in
                event.id == 1
            }
        }

        let waitTask2 = Task {
            try await eventBus.waitFor(TestEvent.self) { event in
                event.id == 2
            }
        }

        // Give a small delay to ensure the waits are set up
        try await Task.sleep(for: .seconds(0.1))

        // Publish events
        await eventBus.publish(TestEvent(id: 1, value: "first"))
        await eventBus.publish(TestEvent(id: 2, value: "second"))

        // Wait for results and verify
        let receivedEvent1 = try await waitTask1.value
        let receivedEvent2 = try await waitTask2.value

        #expect(receivedEvent1.id == 1)
        #expect(receivedEvent1.value == "first")
        #expect(receivedEvent2.id == 2)
        #expect(receivedEvent2.value == "second")
    }

    @Test func testWaitForContinuesAfterUnsubscribe() async throws {
        // Subscribe to events
        let token = await eventBus.subscribe(TestEvent.self) { _ in
            // Do nothing
        }

        // Start waiting for event
        let waitTask = Task {
            try await eventBus.waitFor(TestEvent.self)
        }

        // Give a small delay to ensure the wait is set up
        try await Task.sleep(for: .seconds(0.1))

        // Unsubscribe
        await eventBus.unsubscribe(token: token)

        // Publish event
        let testEvent = TestEvent(id: 42, value: "test after unsubscribe")
        await eventBus.publish(testEvent)

        // Wait for result and verify
        let receivedEvent = try await waitTask.value
        #expect(receivedEvent.id == 42)
        #expect(receivedEvent.value == "test after unsubscribe")
    }
}
