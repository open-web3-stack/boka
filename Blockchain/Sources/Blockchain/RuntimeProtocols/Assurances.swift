import Utils

public enum AssurancesError: Error {
    case invalidAssuranceSignature
    case assuranceForEmptyCore
    case invalidAssuranceParentHash
}

public protocol Assurances {
    var availabilityAssignments:
        ConfigFixedSizeArray<
            ReportItem?,
            ProtocolConfig.TotalNumberOfCores,
        >
    { get }

    var currentValidators:
        ConfigFixedSizeArray<
            ValidatorKey,
            ProtocolConfig.TotalNumberOfValidators,
        >
    { get }
}

extension Assurances {
    public func validateAssurances(
        extrinsics: ExtrinsicAvailability,
        parentHash: Data32,
    ) throws {
        for assurance in extrinsics.assurances {
            guard assurance.parentHash == parentHash else {
                throw AssurancesError.invalidAssuranceParentHash
            }

            let hash = Blake2b256.hash(assurance.parentHash, assurance.assurance)
            let payload = SigningContext.available + hash.data
            let validatorKey = try currentValidators.at(Int(assurance.validatorIndex))
            let pubkey = try Ed25519.PublicKey(from: validatorKey.ed25519)
            guard pubkey.verify(signature: assurance.signature, message: payload) else {
                throw AssurancesError.invalidAssuranceSignature
            }
        }
    }

    public func update(
        config: ProtocolConfigRef,
        timeslot: TimeslotIndex,
        extrinsic: ExtrinsicAvailability,
    ) throws -> (
        newAvailabilityAssignments: ConfigFixedSizeArray<
            ReportItem?,
            ProtocolConfig.TotalNumberOfCores,
        >,
        availableReports: [WorkReport],
    ) {
        var newAvailabilityAssignments = availabilityAssignments

        for i in 0 ..< newAvailabilityAssignments.count {
            if let report = newAvailabilityAssignments[i] {
                if (report.timeslot + UInt32(config.value.preimageReplacementPeriod)) <= timeslot {
                    newAvailabilityAssignments[i] = nil
                }
            }
        }

        var availabilityCount = Array(repeating: 0, count: config.value.totalNumberOfCores)
        for assurance in extrinsic.assurances {
            for (coreIdx, bit) in assurance.assurance.enumerated() where bit {
                // ExtrinsicAvailability.validate() ensures that validatorIndex is in range
                availabilityCount[coreIdx] += 1
            }
        }

        var availableReports = [WorkReport]()

        for (idx, count) in availabilityCount.enumerated() where count > 0 {
            guard let report = availabilityAssignments[idx] else {
                throw AssurancesError.assuranceForEmptyCore
            }
            if count >= ProtocolConfig.TwoThirdValidatorsPlusOne.read(config: config) {
                availableReports.append(report.workReport)
                newAvailabilityAssignments[idx] = nil // remove available report from pending assignments
            }
        }

        return (
            newAvailabilityAssignments: newAvailabilityAssignments,
            availableReports: availableReports,
        )
    }
}
