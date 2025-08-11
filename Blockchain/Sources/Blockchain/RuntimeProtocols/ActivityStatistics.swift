import Foundation
import Utils

public protocol ActivityStatistics {
    var activityStatistics: Statistics { get }
    var timeslot: TimeslotIndex { get }
    var currentValidators: ConfigFixedSizeArray<ValidatorKey, ProtocolConfig.TotalNumberOfValidators> { get }
}

extension ActivityStatistics {
    public func update(
        config: ProtocolConfigRef,
        newTimeslot: TimeslotIndex,
        extrinsic: Extrinsic,
        reporters: [Ed25519PublicKey],
        authorIndex: ValidatorIndex,
        availableReports: [WorkReport],
        accumulateStats: AccumulationStats,
        transfersStats: TransfersStats
    ) throws -> Statistics {
        let epochLength = UInt32(config.value.epochLength)
        let currentEpoch = timeslot / epochLength
        let newEpoch = newTimeslot / epochLength
        let isEpochChange = currentEpoch != newEpoch

        var acc = try isEpochChange
            ? ConfigFixedSizeArray<_, ProtocolConfig.TotalNumberOfValidators>(
                config: config,
                defaultValue: Statistics.Validator.dummy(config: config)
            ) : activityStatistics.accumulator

        let prev = isEpochChange ? activityStatistics.accumulator : activityStatistics.previous

        var item = acc[authorIndex]
        item.blocks += 1
        item.tickets += UInt32(extrinsic.tickets.tickets.count)
        item.preimages += UInt32(extrinsic.preimages.preimages.count)
        item.preimagesBytes += UInt32(extrinsic.preimages.preimages.reduce(into: 0) { $0 += $1.data.count })
        acc[authorIndex] = item

        for reporter in reporters {
            if let index = currentValidators.firstIndex(where: { $0.ed25519 == reporter }) {
                acc[index].guarantees += 1
            }
        }

        for assurance in extrinsic.availability.assurances {
            acc[assurance.validatorIndex].assurances += 1
        }

        // service indices (to be used in the service statistics)
        var indices = Set(accumulateStats.keys).union(transfersStats.keys)
        indices.formUnion(extrinsic.preimages.preimages.map(\.serviceIndex))
        indices.formUnion(extrinsic.reports.guarantees.flatMap(\.workReport.digests).map(\.serviceIndex))

        // core and service statistics
        var coreStats = try ConfigFixedSizeArray<Statistics.Core, ProtocolConfig.TotalNumberOfCores>(
            config: config,
            defaultValue: .dummy(config: config)
        )
        var serviceStats = [UInt32: Statistics.Service]()
        for index in indices {
            serviceStats[UInt32(index)] = .dummy(config: config)
        }

        for guaranteeItem in extrinsic.reports.guarantees {
            let report = guaranteeItem.workReport
            let index = report.coreIndex
            coreStats[index].packageSize += UInt(report.packageSpecification.length)
            for digest in report.digests {
                coreStats[index].gasUsed += digest.gasUsed
                coreStats[index].importsCount += digest.importsCount
                coreStats[index].exportsCount += digest.exportsCount
                coreStats[index].extrinsicsCount += digest.extrinsicsCount
                coreStats[index].extrinsicsSize += digest.extrinsicsSize

                let serviceIndex = UInt32(digest.serviceIndex)
                serviceStats[serviceIndex]!.importsCount += digest.importsCount
                serviceStats[serviceIndex]!.exportsCount += digest.exportsCount
                serviceStats[serviceIndex]!.extrinsicsCount += digest.extrinsicsCount
                serviceStats[serviceIndex]!.extrinsicsSize += digest.extrinsicsSize
                serviceStats[serviceIndex]!.refines.count += 1
                serviceStats[serviceIndex]!.refines.gasUsed += digest.gasUsed
            }
        }
        for report in availableReports {
            let index = report.coreIndex
            let segmentsSize = UInt32(config.value.segmentSize) * ((UInt32(report.packageSpecification.segmentCount) * 65 + 63) / 64)
            coreStats[index].dataSize += UInt(report.packageSpecification.length + segmentsSize)
        }
        for assuranceItem in extrinsic.availability.assurances {
            for (index, bool) in assuranceItem.assurance.enumerated() {
                coreStats[index].assuranceCount += bool ? 1 : 0
            }
        }
        for preimageItem in extrinsic.preimages.preimages {
            let index = UInt32(preimageItem.serviceIndex)
            serviceStats[index]!.preimages.count += 1
            serviceStats[index]!.preimages.size += UInt(preimageItem.data.count)
        }
        for accumulateItem in accumulateStats {
            let index = UInt32(accumulateItem.key)
            serviceStats[index]!.accumulates.count += UInt(accumulateItem.value.1)
            serviceStats[index]!.accumulates.gasUsed += UInt(accumulateItem.value.0.value)
        }
        for transferItem in transfersStats {
            let index = UInt32(transferItem.key)
            serviceStats[index]!.transfers.count += UInt(transferItem.value.0)
            serviceStats[index]!.transfers.gasUsed += UInt(transferItem.value.1.value)
        }

        return Statistics(
            accumulator: acc,
            previous: prev,
            core: coreStats,
            service: serviceStats
        )
    }
}
