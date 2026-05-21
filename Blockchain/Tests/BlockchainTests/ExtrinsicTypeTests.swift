@testable import Blockchain
import Codec
import Foundation
import Testing
import Utils

struct ExtrinsicTypeTests {
    @Test
    func extrinsicGuaranteesValidateAcceptsSortedUniqueReports() throws {
        let config = ProtocolConfigRef.tiny
        let guarantees = try makeGuarantees(config: config, [
            makeGuarantee(config: config, coreIndex: 0, packageHash: data32(1)),
            makeGuarantee(config: config, coreIndex: 1, packageHash: data32(2)),
        ])

        try guarantees.validate(config: config)
    }

    @Test
    func extrinsicGuaranteesRejectInvalidOrderingAndBounds() throws {
        let config = ProtocolConfigRef.tiny

        do {
            try makeGuarantees(config: config, [
                makeGuarantee(config: config, coreIndex: 1, packageHash: data32(1)),
                makeGuarantee(config: config, coreIndex: 0, packageHash: data32(2)),
            ]).validate(config: config)
            Issue.record("Expected guaranteesNotSorted")
        } catch ExtrinsicGuarantees.Error.guaranteesNotSorted {
        } catch {
            Issue.record("Expected guaranteesNotSorted, got \(error)")
        }

        do {
            try makeGuarantees(config: config, [
                makeGuarantee(config: config, coreIndex: UInt(config.value.totalNumberOfCores), packageHash: data32(3)),
            ]).validate(config: config)
            Issue.record("Expected invalidCoreIndex")
        } catch ValidateError.childError(field: "workReport", error: WorkReport.WorkReportError.invalidCoreIndex) {
        } catch {
            Issue.record("Expected invalidCoreIndex, got \(error)")
        }

        do {
            try makeGuarantees(config: config, [
                makeGuarantee(
                    config: config,
                    coreIndex: 0,
                    packageHash: data32(4),
                    credential: LimitedSizeArray([makeCredential(index: 0)], validate: false),
                ),
            ]).validate(config: config)
            Issue.record("Expected invalidCredentialCount")
        } catch ExtrinsicGuarantees.Error.invalidCredentialCount {
        } catch {
            Issue.record("Expected invalidCredentialCount, got \(error)")
        }

        do {
            try makeGuarantees(config: config, [
                makeGuarantee(config: config, coreIndex: 0, packageHash: data32(5), credential: [
                    makeCredential(index: 2),
                    makeCredential(index: 1),
                ]),
            ]).validate(config: config)
            Issue.record("Expected credentialsNotSorted")
        } catch ExtrinsicGuarantees.Error.credentialsNotSorted {
        } catch {
            Issue.record("Expected credentialsNotSorted, got \(error)")
        }

        do {
            try makeGuarantees(config: config, [
                makeGuarantee(config: config, coreIndex: 0, packageHash: data32(6), credential: [
                    makeCredential(index: 0),
                    makeCredential(index: ValidatorIndex(config.value.totalNumberOfValidators)),
                ]),
            ]).validate(config: config)
            Issue.record("Expected invalidValidatorIndex")
        } catch ExtrinsicGuarantees.Error.invalidValidatorIndex {
        } catch {
            Issue.record("Expected invalidValidatorIndex, got \(error)")
        }

        do {
            try makeGuarantees(config: config, [
                makeGuarantee(config: config, coreIndex: 0, packageHash: data32(7)),
                makeGuarantee(config: config, coreIndex: 1, packageHash: data32(7)),
            ]).validate(config: config)
            Issue.record("Expected duplicatedWorkPackageHash")
        } catch ExtrinsicGuarantees.Error.duplicatedWorkPackageHash {
        } catch {
            Issue.record("Expected duplicatedWorkPackageHash, got \(error)")
        }
    }

    @Test
    func extrinsicPreimagesCompareValidateAndRejectDuplicates() throws {
        let sorted = ExtrinsicPreimages(preimages: [
            .init(serviceIndex: 1, data: Data([1])),
            .init(serviceIndex: 1, data: Data([2])),
            .init(serviceIndex: 2, data: Data([0])),
        ])

        #expect(sorted.preimages[0] < sorted.preimages[1])
        #expect(sorted.preimages[1] < sorted.preimages[2])
        try sorted.validate(config: ProtocolConfigRef.tiny)

        let duplicate = ExtrinsicPreimages(preimages: [
            .init(serviceIndex: 1, data: Data([1])),
            .init(serviceIndex: 1, data: Data([1])),
        ])
        do {
            try duplicate.validate(config: ProtocolConfigRef.tiny)
            Issue.record("Expected preimagesNotSorted")
        } catch ExtrinsicPreimages.Error.preimagesNotSorted {
        } catch {
            Issue.record("Expected preimagesNotSorted, got \(error)")
        }
    }

    @Test
    func extrinsicAvailabilityValidatesSortedValidatorIndices() throws {
        let config = ProtocolConfigRef.tiny
        let valid = try ExtrinsicAvailability(assurances: ConfigLimitedSizeArray(config: config, array: [
            makeAssurance(config: config, validatorIndex: 0),
            makeAssurance(config: config, validatorIndex: 1),
        ]))
        try valid.validate(config: config)

        let unsorted = try ExtrinsicAvailability(assurances: ConfigLimitedSizeArray(config: config, array: [
            makeAssurance(config: config, validatorIndex: 1),
            makeAssurance(config: config, validatorIndex: 0),
        ]))
        do {
            try unsorted.validate(config: config)
            Issue.record("Expected assurancesNotSorted")
        } catch ExtrinsicAvailability.Error.assurancesNotSorted {
        }

        let invalid = try ExtrinsicAvailability(assurances: ConfigLimitedSizeArray(config: config, array: [
            makeAssurance(config: config, validatorIndex: ValidatorIndex(config.value.totalNumberOfValidators)),
        ]))
        do {
            try invalid.validate(config: config)
            Issue.record("Expected invalidValidatorIndex")
        } catch ExtrinsicAvailability.Error.invalidValidatorIndex {
        }
    }

    @Test
    func privilegedServicesCodecsRoundTripCompactGas() throws {
        let config = ProtocolConfigRef.tiny
        let services = PrivilegedServices(
            manager: 1,
            assigners: try ConfigFixedSizeArray(config: config, array: [2, 3]),
            delegator: 4,
            registrar: 5,
            alwaysAcc: [6: Gas(7), 8: Gas(9)],
        )

        let jamDecoded = try JamDecoder.decode(
            PrivilegedServices.self,
            from: JamEncoder.encode(services),
            withConfig: config,
        )
        #expect(jamDecoded == services)

        let jsonDecoded: PrivilegedServices = try jsonRoundTrip(services, config: config)
        #expect(jsonDecoded == services)
    }

    @Test
    func hashAndLengthGuaranteedReportAndExtrinsicHashesAreStable() throws {
        let config = ProtocolConfigRef.tiny
        let shorter = HashAndLength(hash: data32(1), length: 1)
        let longer = HashAndLength(hash: data32(1), length: 2)
        let laterHash = HashAndLength(hash: data32(2), length: 0)

        #expect(shorter < longer)
        #expect(longer < laterHash)
        #expect(Set([shorter, longer, laterHash]).contains(shorter))

        let report = GuaranteedWorkReport.dummy(config: config)
        let expectedReportHash = try JamEncoder.encode(report).blake2b256hash()
        #expect(report.hash() == expectedReportHash)
        #expect(report.asRef().value == report)

        let extrinsic = Extrinsic.dummy(config: config)
        let expectedHash = try JamEncoder.encode(
            JamEncoder.encode(extrinsic.tickets).blake2b256hash(),
            JamEncoder.encode(extrinsic.preimages).blake2b256hash(),
            JamEncoder.encode(extrinsic.reports.guarantees.array.map { item in
                try JamEncoder.encode(item.workReport.hash(), item.timeslot, item.credential)
            }).blake2b256hash(),
            JamEncoder.encode(extrinsic.availability).blake2b256hash(),
            JamEncoder.encode(extrinsic.disputes).blake2b256hash(),
        ).blake2b256hash()
        #expect(extrinsic.hash() == expectedHash)

        let jsonDecoded: Extrinsic = try jsonRoundTrip(extrinsic, config: config)
        #expect(jsonDecoded == extrinsic)
    }

    @Test
    func ticketsCompareAndValidateAttemptBounds() throws {
        let config = ProtocolConfigRef.tiny
        #expect(Ticket.dummy(config: config) < Ticket(id: data32(1), attempt: 0))
        #expect(Ticket(id: data32(1), attempt: 0) < Ticket(id: data32(1), attempt: 1))

        try ExtrinsicTickets.TicketItem(attempt: 0, signature: Data784()).validate(config: config)

        do {
            try ExtrinsicTickets.TicketItem(
                attempt: TicketIndex(config.value.ticketEntriesPerValidator),
                signature: Data784(),
            ).validate(config: config)
            Issue.record("Expected invalidAttempt")
        } catch ExtrinsicTickets.TicketItem.Error.invalidAttempt {
        } catch {
            Issue.record("Expected invalidAttempt, got \(error)")
        }
    }

    private func makeGuarantees(
        config: ProtocolConfigRef,
        _ guarantees: [ExtrinsicGuarantees.GuaranteeItem],
    ) throws -> ExtrinsicGuarantees {
        try ExtrinsicGuarantees(guarantees: ConfigLimitedSizeArray(config: config, array: guarantees))
    }

    private func makeGuarantee(
        config: ProtocolConfigRef,
        coreIndex: UInt,
        packageHash: Data32,
        credential: LimitedSizeArray<
            ExtrinsicGuarantees.IndexAndSignature,
            ConstInt2,
            ConstInt3
        > = [
            ExtrinsicGuarantees.IndexAndSignature(index: 0, signature: data64(1)),
            ExtrinsicGuarantees.IndexAndSignature(index: 1, signature: data64(2)),
        ],
    ) -> ExtrinsicGuarantees.GuaranteeItem {
        var report = WorkReport.dummy(config: config)
        report.coreIndex = coreIndex
        report.packageSpecification.workPackageHash = packageHash
        return ExtrinsicGuarantees.GuaranteeItem(
            workReport: report,
            timeslot: 42,
            credential: credential,
        )
    }

    private func makeCredential(index: ValidatorIndex) -> ExtrinsicGuarantees.IndexAndSignature {
        ExtrinsicGuarantees.IndexAndSignature(index: index, signature: data64(UInt8(index & 0xFF)))
    }

    private func makeAssurance(
        config: ProtocolConfigRef,
        validatorIndex: ValidatorIndex,
    ) -> ExtrinsicAvailability.AssuranceItem {
        var bitfield = ConfigSizeBitString<ProtocolConfig.TotalNumberOfCores>(config: config)
        bitfield[0] = true
        return ExtrinsicAvailability.AssuranceItem(
            parentHash: data32(3),
            assurance: bitfield,
            validatorIndex: validatorIndex,
            signature: data64(4),
        )
    }

    private func jsonRoundTrip<T: Codable>(_ value: T, config: ProtocolConfigRef) throws -> T {
        let encoder = JSONEncoder()
        encoder.userInfo[.config] = config
        let encoded = try encoder.encode(value)

        let decoder = JSONDecoder()
        decoder.userInfo[.config] = config
        return try decoder.decode(T.self, from: encoded)
    }
}
