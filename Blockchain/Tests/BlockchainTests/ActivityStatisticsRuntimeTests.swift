@testable import Blockchain
import Foundation
import Testing
import Utils

struct ActivityStatisticsRuntimeTests {
    private let config = ProtocolConfigRef.tiny

    @Test
    func updateAggregatesValidatorCoreAndServiceActivity() throws {
        let validators = try makeActivityValidators(config: config)
        let state = ActivityStatisticsState(
            activityStatistics: Statistics.dummy(config: config),
            timeslot: 0,
            currentValidators: validators,
        )
        let report = try makeActivityReport(config: config)
        let extrinsic = try makeActivityExtrinsic(config: config, report: report)

        let stats = try state.update(
            config: config,
            newTimeslot: 1,
            extrinsic: extrinsic,
            reporters: [validators[3].ed25519, data32(200)],
            authorIndex: 2,
            availableReports: [report],
            accumulateStats: [7: (Gas(13), 2)],
        )

        #expect(stats.accumulator[2].blocks == 1)
        #expect(stats.accumulator[2].tickets == 2)
        #expect(stats.accumulator[2].preimages == 1)
        #expect(stats.accumulator[2].preimagesBytes == 3)
        #expect(stats.accumulator[3].guarantees == 1)
        #expect(stats.accumulator[4].assurances == 1)

        #expect(stats.core[1].packageSize == 12)
        #expect(stats.core[1].gasUsed == 9)
        #expect(stats.core[1].importsCount == 2)
        #expect(stats.core[1].exportsCount == 3)
        #expect(stats.core[1].extrinsicsCount == 4)
        #expect(stats.core[1].extrinsicsSize == 5)
        #expect(stats.core[1].assuranceCount == 1)

        let segmentsSize = UInt32(config.value.segmentSize) * ((UInt32(report.packageSpecification.segmentCount) * 65 + 63) / 64)
        #expect(stats.core[1].dataSize == UInt(report.packageSpecification.length + segmentsSize))

        let service = try #require(stats.service[7])
        #expect(service.preimages.count == 1)
        #expect(service.preimages.size == 3)
        #expect(service.refines.count == 1)
        #expect(service.refines.gasUsed == 9)
        #expect(service.importsCount == 2)
        #expect(service.exportsCount == 3)
        #expect(service.extrinsicsCount == 4)
        #expect(service.extrinsicsSize == 5)
        #expect(service.accumulates.count == 2)
        #expect(service.accumulates.gasUsed == 13)
    }

    @Test
    func updateResetsAccumulatorAndCarriesPreviousOnEpochChange() throws {
        let validators = try makeActivityValidators(config: config)
        var activity = Statistics.dummy(config: config)
        activity.accumulator[1].blocks = 9
        activity.accumulator[1].tickets = 3
        let state = ActivityStatisticsState(
            activityStatistics: activity,
            timeslot: 11,
            currentValidators: validators,
        )

        let stats = try state.update(
            config: config,
            newTimeslot: 12,
            extrinsic: Extrinsic.dummy(config: config),
            reporters: [],
            authorIndex: 1,
            availableReports: [],
            accumulateStats: [:],
        )

        #expect(stats.previous[1].blocks == 9)
        #expect(stats.previous[1].tickets == 3)
        #expect(stats.accumulator[1].blocks == 1)
        #expect(stats.accumulator[1].tickets == 0)
    }
}

private struct ActivityStatisticsState: ActivityStatistics {
    var activityStatistics: Statistics
    var timeslot: TimeslotIndex
    var currentValidators: ConfigFixedSizeArray<ValidatorKey, ProtocolConfig.TotalNumberOfValidators>
}

private func makeActivityValidators(
    config: ProtocolConfigRef,
) throws -> ConfigFixedSizeArray<ValidatorKey, ProtocolConfig.TotalNumberOfValidators> {
    try ConfigFixedSizeArray(
        config: config,
        array: (0 ..< config.value.totalNumberOfValidators).map { index in
            ValidatorKey(
                bandersnatch: BandersnatchPublicKey(),
                ed25519: data32(UInt8(10 + index)),
                bls: BLSKey(),
                metadata: Data128(),
            )
        },
    )
}

private func makeActivityReport(config: ProtocolConfigRef) throws -> WorkReport {
    var report = WorkReport.dummy(config: config)
    report.coreIndex = 1
    report.packageSpecification = AvailabilitySpecifications(
        workPackageHash: data32(21),
        length: 12,
        erasureRoot: data32(22),
        segmentRoot: data32(23),
        segmentCount: 1,
    )
    report.digests = try ConfigLimitedSizeArray(config: config, array: [
        WorkDigest(
            serviceIndex: 7,
            codeHash: data32(24),
            payloadHash: data32(25),
            gasLimit: Gas(10),
            result: WorkResult(.success(Data())),
            gasUsed: 9,
            importsCount: 2,
            exportsCount: 3,
            extrinsicsCount: 4,
            extrinsicsSize: 5,
        ),
    ])
    return report
}

private func makeActivityExtrinsic(config: ProtocolConfigRef, report: WorkReport) throws -> Extrinsic {
    var assurance = ConfigSizeBitString<ProtocolConfig.TotalNumberOfCores>(config: config)
    try assurance.set(1, to: true)

    return try Extrinsic(
        tickets: ExtrinsicTickets(tickets: ConfigLimitedSizeArray(config: config, array: [
            ExtrinsicTickets.TicketItem(attempt: 0, signature: Data784()),
            ExtrinsicTickets.TicketItem(attempt: 1, signature: Data784()),
        ])),
        disputes: ExtrinsicDisputes.dummy(config: config),
        preimages: ExtrinsicPreimages(preimages: [
            ExtrinsicPreimages.PreimageItem(serviceIndex: 7, data: Data([1, 2, 3])),
        ]),
        availability: ExtrinsicAvailability(assurances: ConfigLimitedSizeArray(config: config, array: [
            ExtrinsicAvailability.AssuranceItem(
                parentHash: data32(26),
                assurance: assurance,
                validatorIndex: 4,
                signature: data64(27),
            ),
        ])),
        reports: ExtrinsicGuarantees(guarantees: ConfigLimitedSizeArray(config: config, array: [
            ExtrinsicGuarantees.GuaranteeItem(
                workReport: report,
                timeslot: 1,
                credential: [
                    .init(index: 0, signature: data64(28)),
                    .init(index: 1, signature: data64(29)),
                ],
            ),
        ])),
    )
}
