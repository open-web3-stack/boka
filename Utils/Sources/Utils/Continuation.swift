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
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await withCheckedThrowingContinuation { continuation in
                operation(continuation)
            }
        }

        group.addTask {
            try await Task.sleep(for: .seconds(timeout))
            throw ContinuationError.timeout
        }

        guard let result = try await group.next() else {
            try throwUnreachable("cannot be nil")
        }

        group.cancelAll()
        return result
    }
}
