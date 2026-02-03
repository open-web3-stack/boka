import Foundation

public enum RepeatUntilError: Error {
    case timeout
}

public func repeatUntil<T>(
    _ repeatFn: () async -> T,
    withCondition: (T) -> Bool,
    timeout: TimeInterval = 10,
    sleep: TimeInterval = 0.01,
) async throws -> T {
    let start = Date()
    while true {
        let val = await repeatFn()
        if withCondition(val) {
            return val
        }
        let elapsed = Date().timeIntervalSince(start)
        if elapsed > timeout {
            throw RepeatUntilError.timeout
        }
        try await Task.sleep(for: .seconds(sleep))
    }
}

public func repeatUntil<T>(
    _ repeatFn: () async -> T?,
    timeout: TimeInterval = 5,
    sleep: TimeInterval = 0.05,
) async throws -> T {
    let start = Date()
    while true {
        let val = await repeatFn()
        if let val {
            return val
        }
        let elapsed = Date().timeIntervalSince(start)
        if elapsed > timeout {
            throw RepeatUntilError.timeout
        }
        try await Task.sleep(for: .seconds(sleep))
    }
}

public func repeatUntil(
    _ repeatFn: () async -> Bool,
    timeout: TimeInterval = 10,
    sleep: TimeInterval = 0.01,
) async throws {
    let start = Date()
    while true {
        if await repeatFn() {
            return
        }
        let elapsed = Date().timeIntervalSince(start)
        if elapsed > timeout {
            throw RepeatUntilError.timeout
        }
        try await Task.sleep(for: .seconds(sleep))
    }
}
