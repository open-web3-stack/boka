// Test for withCheckedContinuationTimeout functionality

import Foundation
import Testing

@testable import Utils

struct ContinuationTests {
    @Test func completeBeforeTimeout() async throws {
        // Test that operation completes normally when finished before timeout
        let result = try await withCheckedContinuationTimeout(seconds: 1.0) { continuation in
            Task {
                try? await Task.sleep(for: .seconds(0.1))
                continuation.resume(returning: "success")
            }
        }

        #expect(result == "success")
    }

    @Test func throwsOnTimeout() async throws {
        let now = Date()
        // Test that timeout error is thrown when operation takes too long
        await #expect(throws: ContinuationError.timeout) {
            try await withCheckedContinuationTimeout(seconds: 0.1) { continuation in
                Task {
                    try? await Task.sleep(for: .seconds(10))
                    continuation.resume(returning: "success")
                }
            }
        }
        #expect(Date().timeIntervalSince(now) < 5)
    }
}
