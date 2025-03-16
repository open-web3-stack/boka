import Foundation
import TracingUtils

public enum ContinuationError: Error {
    case timeout
    case unreachable
}

public func withCheckedContinuationTimeout<T: Sendable>(
    seconds timeout: TimeInterval,
    operation: @escaping @Sendable (CheckedContinuation<T, Error>) -> Void
) async throws -> T {
    try await withCheckedThrowingContinuation { continuation in
        Task {
            try await Task.sleep(for: .seconds(timeout))
            continuation.resume(throwing: ContinuationError.timeout)
        }

        operation(continuation)
    }
}
