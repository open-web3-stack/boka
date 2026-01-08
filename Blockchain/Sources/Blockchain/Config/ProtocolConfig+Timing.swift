import Foundation
import Utils

extension ProtocolConfigRef {
    /// Time delta for block authoring start (relative to timeslot start)
    /// Negative value means authoring begins before the timeslot starts
    /// Current value: -1 slot period (authoring starts 1 timeslot early)
    /// Note: These timing values are working parameters that may need tuning based on network conditions
    public var authoringStartTimeDelta: TimeInterval {
        -TimeInterval(value.slotPeriodSeconds)
    }

    public var authoringDeadline: TimeInterval {
        TimeInterval(value.slotPeriodSeconds) / 3
    }

    public var guaranteeingStartTimeDelta: TimeInterval {
        authoringStartTimeDelta - TimeInterval(value.slotPeriodSeconds)
    }

    public var guaranteeingDeadline: TimeInterval {
        TimeInterval(value.slotPeriodSeconds) / 3 * 2
    }

    public var prepareEpochStartTimeDelta: TimeInterval {
        if value.epochLength < 15 {
            return -TimeInterval(value.slotPeriodSeconds)
        }
        return -TimeInterval(value.slotPeriodSeconds) * 3
    }

    public func scheduleTimeForAuthoring(timeslot: TimeslotIndex) -> TimeInterval {
        TimeInterval(timeslot.timeslotToTime(config: self)) + authoringStartTimeDelta
    }

    public func scheduleTimeForGuaranteeing(timeslot: TimeslotIndex) -> TimeInterval {
        TimeInterval(timeslot.timeslotToTime(config: self)) + guaranteeingStartTimeDelta
    }

    public func scheduleTimeForPrepareEpoch(epoch: EpochIndex) -> TimeInterval {
        let timeslot = epoch.epochToTimeslotIndex(config: self)
        return TimeInterval(timeslot.timeslotToTime(config: self)) + prepareEpochStartTimeDelta
    }
}
