import Foundation
import Utils

public protocol TimeProvider: Sendable {
    func getTimeInterval() -> TimeInterval
}

extension TimeProvider {
    public func getTime() -> UInt32 {
        UInt32(getTimeInterval())
    }
}

public final class SystemTimeProvider: TimeProvider {
    public init() {}

    public func getTimeInterval() -> TimeInterval {
        Date().timeIntervalSinceJamCommonEra
    }
}

public final class MockTimeProvider: TimeProvider {
    public let time: ThreadSafeContainer<TimeInterval>

    public init(time: TimeInterval = 0) {
        self.time = ThreadSafeContainer(time)
    }

    public func getTimeInterval() -> TimeInterval {
        time.value
    }

    public func advance(by interval: TimeInterval) {
        time.write { $0 += interval }
    }

    public func advance(to: TimeInterval) {
        time.value = to
    }
}
