import Foundation
import Utils

enum ActivityStatisticsError: Error {
    case invalidAuthorKey
}

public protocol ActivityStatistics {
    var activityStatistics: ValidatorActivityStatistics { get }
    var timeslot: TimeslotIndex { get }
    var currentValidators: ConfigFixedSizeArray<ValidatorKey, ProtocolConfig.TotalNumberOfValidators> { get }
}

extension ActivityStatistics {
    public func update(
        config: ProtocolConfigRef,
        newTimeslot: TimeslotIndex,
        extrinsic: Extrinsic,
        authorIndex: ValidatorIndex
    ) throws -> ValidatorActivityStatistics {
        let epochLength = UInt32(config.value.epochLength)
        let currentEpoch = timeslot / epochLength
        let newEpoch = newTimeslot / epochLength
        let isEpochChange = currentEpoch != newEpoch

        var acc = try isEpochChange
            ? ConfigFixedSizeArray<_, ProtocolConfig.TotalNumberOfValidators>(
                config: config,
                defaultValue: ValidatorActivityStatistics.StatisticsItem.dummy(config: config)
            ) : activityStatistics.accumulator

        let prev = isEpochChange ? activityStatistics.accumulator : activityStatistics.previous

        var item = acc[authorIndex]
        item.blocks += 1
        item.tickets += UInt32(extrinsic.tickets.tickets.count)
        item.preimages += UInt32(extrinsic.preimages.preimages.count)
        item.preimagesBytes += UInt32(extrinsic.preimages.preimages.reduce(into: 0) { $0 += $1.data.count })
        acc[authorIndex] = item

        for report in extrinsic.reports.guarantees {
            for cred in report.credential {
                acc[cred.index].guarantees += 1
            }
        }

        for assurance in extrinsic.availability.assurances {
            acc[assurance.validatorIndex].assurances += 1
        }

        return ValidatorActivityStatistics(
            accumulator: acc,
            previous: prev
        )
    }
}
