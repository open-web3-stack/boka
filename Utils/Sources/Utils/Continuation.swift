import Foundation
import Synchronization
import TracingUtils

public enum ContinuationError: Error {
    case timeout
    case unreachable
}

/// A lightweight wrapper that ensures `resume` is only invoked once.
public struct SafeContinuation<T: Sendable>: Sendable {
    private let onSuccess: @Sendable (T) -> Void
    private let onFailure: @Sendable (Error) -> Void

    public init(
        onSuccess: @escaping @Sendable (T) -> Void,
        onFailure: @escaping @Sendable (Error) -> Void
    ) {
        self.onSuccess = onSuccess
        self.onFailure = onFailure
    }

    public func resume(returning value: T) {
        onSuccess(value)
    }

    public func resume(throwing error: Error) {
        onFailure(error)
    }
}

public func withCheckedContinuationTimeout<T: Sendable>(
    seconds timeout: TimeInterval,
    operation: @escaping @Sendable (SafeContinuation<T>) -> Void
) async throws -> T {
    try await withCheckedThrowingContinuation { originalContinuation in
        let hasResumed = Atomic<Bool>(false)

        @Sendable func resumeOnce(_ result: Result<T, Error>) {
            let resumed = hasResumed.exchange(true, ordering: .sequentiallyConsistent)
            if resumed {
                return
            }
            originalContinuation.resume(with: result)
        }

        // Fire a timeout task:
        Task {
            try await Task.sleep(for: .seconds(timeout))
            resumeOnce(.failure(ContinuationError.timeout))
        }

        // Give the caller a thread-safe continuation wrapper:
        let safe = SafeContinuation<T>(
            onSuccess: { value in
                resumeOnce(.success(value))
            },
            onFailure: { error in
                resumeOnce(.failure(error))
            }
        )

        operation(safe)
    }
}
