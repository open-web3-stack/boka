import Foundation
import Utils

public protocol TimeProvider: Sendable {
    var slotPeriodSeconds: UInt32 { get }

    func getTime() -> UInt32
}

extension TimeProvider {
    public func getTimeslot() -> TimeslotIndex {
        timeToTimeslot(getTime())
    }

    public func timeslotToTime(_ timeslot: TimeslotIndex) -> UInt32 {
        timeslot * slotPeriodSeconds
    }

    public func timeToTimeslot(_ time: UInt32) -> TimeslotIndex {
        time / slotPeriodSeconds
    }
}

public final class SystemTimeProvider: TimeProvider {
    public let slotPeriodSeconds: UInt32

    public init(slotPeriodSeconds: UInt32) {
        self.slotPeriodSeconds = slotPeriodSeconds
    }

    public func getTime() -> UInt32 {
        Date().timeIntervalSinceJamCommonEra
    }
}

public final class MockTimeProvider: TimeProvider {
    public let slotPeriodSeconds: UInt32
    public let time: ThreadSafeContainer<UInt32>

    public init(slotPeriodSeconds: UInt32, time: UInt32 = 0) {
        self.slotPeriodSeconds = slotPeriodSeconds
        self.time = ThreadSafeContainer(time)
    }

    public func getTime() -> UInt32 {
        time.value
    }

    public func advance(by interval: UInt32) {
        time.value += interval
    }
}
