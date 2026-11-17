@testable import Blockchain
import Foundation
import Testing
import Utils

struct AssurancesRuntimeTests {
    private let config = ProtocolConfigRef.tiny

    @Test(arguments: [false, true])
    func resizedValidatorSetUsesPriorThreshold(growing: Bool) throws {
        let config = config.mutate { $0.totalNumberOfCores = 3 }
        let priorCount = growing ? 6 : 9
        let posteriorCount = growing ? 9 : 6
        let requiredAssurances = growing ? 5 : 7
        let report = makeReport(coreIndex: 0, timeslot: 6)
        let state = try AssuranceState(
            availabilityAssignments: .init(config: config, array: [report, nil, nil]),
            currentValidators: .init(config: config, array: Array(repeating: ValidatorKey(), count: posteriorCount)),
        )

        var bitfield = ConfigSizeBitString<ProtocolConfig.TotalNumberOfCores>(config: config)
        try bitfield.set(0, to: true)
        for count in [0, requiredAssurances - 1, requiredAssurances] {
            let assurances = (0 ..< count).map {
                ExtrinsicAvailability.AssuranceItem(
                    parentHash: data32(1), assurance: bitfield,
                    validatorIndex: ValidatorIndex($0), signature: data64(2),
                )
            }
            let result = try state.update(
                config: config, timeslot: 7,
                extrinsic: ExtrinsicAvailability(assurances: .init(config: config, array: assurances)),
                priorValidatorCount: priorCount,
            )
            // Resizing clears pending assignments, even without assurances or a timeout.
            #expect(result.newAvailabilityAssignments.allSatisfy { $0 == nil })
            #expect(result.availableReports == (count == requiredAssurances ? [report.workReport] : []))
        }
    }

    @Test
    func updatePrunesReportsOlderThanPreimageReplacementPeriod() throws {
        let staleReport = makeReport(coreIndex: 0, timeslot: 5)
        let freshReport = makeReport(coreIndex: 1, timeslot: 6)
        let state = try AssuranceState(
            availabilityAssignments: makeAvailabilityAssignments([staleReport, freshReport]),
            currentValidators: makeValidators(),
        )

        let result = try state.update(
            config: config,
            timeslot: 10,
            extrinsic: ExtrinsicAvailability.dummy(config: config),
            priorValidatorCount: state.currentValidators.count,
        )

        #expect(result.newAvailabilityAssignments[0] == nil)
        #expect(result.newAvailabilityAssignments[1] == freshReport)
        #expect(result.availableReports.isEmpty)
    }

    @Test
    func updateMakesReportAvailableAfterValidatorThreshold() throws {
        let report = makeReport(coreIndex: 0, timeslot: 6)
        let state = try AssuranceState(
            availabilityAssignments: makeAvailabilityAssignments([report, nil]),
            currentValidators: makeValidators(),
        )
        let threshold = ProtocolConfig.TwoThirdValidatorsPlusOne.read(config: config)
        let assurances = try (0 ..< threshold).map {
            try makeAssurance(coreIndex: 0, validatorIndex: ValidatorIndex($0))
        }

        let result = try state.update(
            config: config,
            timeslot: 7,
            extrinsic: makeAvailability(assurances),
            priorValidatorCount: state.currentValidators.count,
        )

        #expect(result.availableReports == [report.workReport])
        #expect(result.newAvailabilityAssignments[0] == nil)
        #expect(result.newAvailabilityAssignments[1] == nil)
    }

    @Test
    func updateRejectsAssuranceForEmptyCore() throws {
        let report = makeReport(coreIndex: 0, timeslot: 6)
        let state = try AssuranceState(
            availabilityAssignments: makeAvailabilityAssignments([report, nil]),
            currentValidators: makeValidators(),
        )

        #expect(throws: AssurancesError.self) {
            _ = try state.update(
                config: config,
                timeslot: 7,
                extrinsic: makeAvailability([makeAssurance(coreIndex: 1, validatorIndex: 0)]),
                priorValidatorCount: state.currentValidators.count,
            )
        }
    }

    private func makeReport(coreIndex: UInt, timeslot: TimeslotIndex) -> ReportItem {
        var workReport = WorkReport.dummy(config: config)
        workReport.coreIndex = coreIndex
        return ReportItem(guarantee: .init(
            workReport: workReport,
            timeslot: timeslot,
            credential: [.init(index: 0, signature: data64(0)), .init(index: 1, signature: data64(0))],
        ), timeslot: timeslot)
    }

    private func makeAvailabilityAssignments(
        _ assignments: [ReportItem?],
    ) throws -> ConfigFixedSizeArray<ReportItem?, ProtocolConfig.TotalNumberOfCores> {
        try ConfigFixedSizeArray(config: config, array: assignments)
    }

    private func makeValidators() throws -> ValidatorKeys {
        try ValidatorKeys(config: config, defaultValue: ValidatorKey())
    }

    private func makeAvailability(_ assurances: [ExtrinsicAvailability.AssuranceItem]) throws -> ExtrinsicAvailability {
        try ExtrinsicAvailability(assurances: ConfigLimitedSizeArray(config: config, array: assurances))
    }

    private func makeAssurance(
        coreIndex: Int,
        validatorIndex: ValidatorIndex,
    ) throws -> ExtrinsicAvailability.AssuranceItem {
        var bitfield = ConfigSizeBitString<ProtocolConfig.TotalNumberOfCores>(config: config)
        try bitfield.set(coreIndex, to: true)
        return ExtrinsicAvailability.AssuranceItem(
            parentHash: data32(1),
            assurance: bitfield,
            validatorIndex: validatorIndex,
            signature: data64(2),
        )
    }
}

private struct AssuranceState: Assurances {
    var availabilityAssignments: ConfigFixedSizeArray<ReportItem?, ProtocolConfig.TotalNumberOfCores>
    var currentValidators: ValidatorKeys
}
