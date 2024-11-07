import Codec
import Foundation
import TracingUtils
import Utils

private let logger = Logger(label: "Runtime")

// the STF
public final class Runtime {
    public enum Error: Swift.Error {
        case safroleError(SafroleError)
        case DisputeError(DisputeError)
        case invalidTimeslot(got: TimeslotIndex, context: TimeslotIndex)
        case invalidReportAuthorizer
        case encodeError(any Swift.Error)
        case invalidExtrinsicHash
        case invalidParentHash
        case invalidHeaderStateRoot
        case invalidHeaderEpochMarker
        case invalidHeaderWinningTickets
        case invalidHeaderOffendersMarkers
        case invalidAssuranceParentHash
        case invalidAssuranceSignature
        case assuranceForEmptyCore
        case preimagesNotSorted
        case invalidPreimageServiceIndex
        case duplicatedPreimage
        case invalidAuthorTicket
        case invalidAuthorKey
        case invalidBlockSeal(any Swift.Error)
        case invalidVrfSignature
        case other(any Swift.Error)
        case validateError(any Swift.Error)
    }

    public struct ApplyContext {
        public let timeslot: TimeslotIndex

        public init(timeslot: TimeslotIndex) {
            self.timeslot = timeslot
        }
    }

    public let config: ProtocolConfigRef

    public init(config: ProtocolConfigRef) {
        self.config = config
    }

    public func validateHeader(block: Validated<BlockRef>, state: StateRef, context: ApplyContext) throws(Error) {
        let block = block.value

        guard block.header.parentHash == state.value.lastBlockHash else {
            throw Error.invalidParentHash
        }

        guard block.header.priorStateRoot == state.stateRoot else {
            throw Error.invalidHeaderStateRoot
        }

        let expectedExtrinsicHash = try Result { try JamEncoder.encode(block.extrinsic).blake2b256hash() }
            .mapError(Error.encodeError).get()

        guard block.header.extrinsicsHash == expectedExtrinsicHash else {
            throw Error.invalidExtrinsicHash
        }

        guard block.header.timeslot <= context.timeslot else {
            throw Error.invalidTimeslot(got: block.header.timeslot, context: context.timeslot)
        }

        // epoch is validated at apply time by Safrole

        // winning tickets is validated at apply time by Safrole

        // offendersMarkers is validated at apply time by Disputes
    }

    public func validateHeaderSeal(block: BlockRef, state: inout State, prevState: StateRef) throws(Error) {
        let vrfOutput: Data32
        let blockAuthorKey = try Result {
            try Bandersnatch.PublicKey(data: state.currentValidators[Int(block.header.authorIndex)].bandersnatch)
        }.mapError(Error.invalidBlockSeal).get()
        let index = block.header.timeslot % UInt32(config.value.epochLength)
        let encodedHeader = try Result { try JamEncoder.encode(block.header.unsigned) }.mapError(Error.invalidBlockSeal).get()
        let entropyVRFInputData: Data
        switch state.safroleState.ticketsOrKeys {
        case let .left(tickets):
            let ticket = tickets[Int(index)]
            let vrfInputData = SigningContext.safroleTicketInputData(entropy: prevState.value.entropyPool.t3, attempt: ticket.attempt)
            vrfOutput = try Result {
                try blockAuthorKey.ietfVRFVerify(
                    vrfInputData: vrfInputData,
                    auxData: encodedHeader,
                    signature: block.header.seal
                )
            }.mapError(Error.invalidBlockSeal).get()
            guard ticket.id == vrfOutput else {
                throw Error.invalidAuthorTicket
            }

            entropyVRFInputData = SigningContext.entropyInputData(entropy: vrfOutput)

        case let .right(keys):
            let key = keys[Int(index)]
            guard key == blockAuthorKey.data else {
                logger.debug("expected key: \(key.toHexString()), got key: \(blockAuthorKey.data.toHexString())")
                throw Error.invalidAuthorKey
            }
            let vrfInputData = SigningContext.fallbackSealInputData(entropy: prevState.value.entropyPool.t3)
            vrfOutput = try Result {
                logger.trace("verifying ticket", metadata: ["key": "\(blockAuthorKey.data.toHexString())"])
                return try blockAuthorKey.ietfVRFVerify(
                    vrfInputData: vrfInputData,
                    auxData: encodedHeader,
                    signature: block.header.seal
                )
            }.mapError(Error.invalidBlockSeal).get()

            entropyVRFInputData = SigningContext.fallbackSealInputData(entropy: prevState.value.entropyPool.t3)
        }

        _ = try Result {
            try blockAuthorKey.ietfVRFVerify(vrfInputData: entropyVRFInputData, signature: block.header.vrfSignature)
        }.mapError { _ in Error.invalidVrfSignature }.get()
    }

    public func validate(block: Validated<BlockRef>, state: StateRef, context: ApplyContext) throws(Error) {
        try validateHeader(block: block, state: state, context: context)

        let block = block.value

        for ext in block.extrinsic.availability.assurances {
            guard ext.parentHash == block.header.parentHash else {
                throw Error.invalidAssuranceParentHash
            }
        }

        // TODO: abstract input validation logic from Safrole state update function and call it here
        // TODO: validate other things
    }

    public func apply(block: BlockRef, state prevState: StateRef, context: ApplyContext) async throws(Error) -> StateRef {
        let validatedBlock = try Result(catching: { try block.toValidated(config: config) })
            .mapError(Error.validateError)
            .get()

        return try await apply(block: validatedBlock, state: prevState, context: context)
    }

    public func apply(block: Validated<BlockRef>, state prevState: StateRef, context: ApplyContext) async throws(Error) -> StateRef {
        try validate(block: block, state: prevState, context: context)
        let block = block.value

        var newState = prevState.value

        do {
            try updateSafrole(block: block, state: &newState)

            if newState.ticketsOrKeys != prevState.value.ticketsOrKeys {
                logger.trace("state tickets changed", metadata: [
                    "old": "\(prevState.value.ticketsOrKeys)",
                    "new": "\(newState.ticketsOrKeys)",
                ])
            }

            try validateHeaderSeal(block: block, state: &newState, prevState: prevState)

            try updateDisputes(block: block, state: &newState)

            // depends on Safrole and Disputes
            let availableReports = try updateReports(block: block, state: &newState)
            let res = try await newState.update(config: config, block: block, workReports: availableReports)
            newState.privilegedServices = res.privilegedServices

            for (service, account) in res.newServiceAccounts {
                newState[serviceAccount: service] = account.toDetails()
                for (hash, value) in account.storage {
                    newState[serviceAccount: service, storageKey: hash] = value
                }
                for (hash, value) in account.preimages {
                    newState[serviceAccount: service, preimageHash: hash] = value
                }
                for (hashLength, value) in account.preimageInfos {
                    newState[serviceAccount: service, preimageHash: hashLength.hash, length: hashLength.length] = value
                }
            }

            newState.authorizationQueue = res.authorizationQueue
            newState.validatorQueue = res.validatorQueue

            newState.coreAuthorizationPool = try updateAuthorizationPool(
                block: block, state: prevState
            )

            newState.activityStatistics = try updateValidatorActivityStatistics(
                block: block, state: prevState
            )

            // after reports as it need old recent history
            try updateRecentHistory(block: block, state: &newState)
        } catch let error as Error {
            throw error
        } catch let error as SafroleError {
            throw .safroleError(error)
        } catch let error as DisputeError {
            throw .DisputeError(error)
        } catch {
            throw .other(error)
        }

        return StateRef(newState)
    }

    public func updateRecentHistory(block: BlockRef, state newState: inout State) throws {
        let workReportHashes = block.extrinsic.reports.guarantees.map(\.workReport.packageSpecification.workPackageHash)
        try newState.recentHistory.update(
            headerHash: block.hash,
            parentStateRoot: block.header.priorStateRoot,
            accumulateRoot: Data32(), // TODO: calculate accumulation result
            workReportHashes: ConfigLimitedSizeArray(config: config, array: workReportHashes)
        )
    }

    public func updateSafrole(block: BlockRef, state newState: inout State) throws {
        let safroleResult = try newState.updateSafrole(
            config: config,
            slot: block.header.timeslot,
            entropy: newState.entropyPool.t0,
            offenders: newState.judgements.punishSet,
            extrinsics: block.extrinsic.tickets
        )
        newState.mergeWith(postState: safroleResult.state)

        guard safroleResult.epochMark == block.header.epoch else {
            throw Error.invalidHeaderEpochMarker
        }

        guard safroleResult.ticketsMark == block.header.winningTickets else {
            throw Error.invalidHeaderWinningTickets
        }
    }

    public func updateDisputes(block: BlockRef, state newState: inout State) throws {
        let (posState, offenders) = try newState.update(config: config, disputes: block.extrinsic.judgements)
        newState.mergeWith(postState: posState)

        guard offenders == block.header.offendersMarkers else {
            throw Error.invalidHeaderOffendersMarkers
        }
    }

    // TODO: add tests
    public func updateAuthorizationPool(block: BlockRef, state: StateRef) throws -> ConfigFixedSizeArray<
        ConfigLimitedSizeArray<
            Data32,
            ProtocolConfig.Int0,
            ProtocolConfig.MaxAuthorizationsPoolItems
        >,
        ProtocolConfig.TotalNumberOfCores
    > {
        var pool = state.value.coreAuthorizationPool

        for coreIndex in 0 ..< pool.count {
            var corePool = pool[coreIndex]
            let coreQueue = state.value.authorizationQueue[coreIndex]
            if coreQueue.count == 0 {
                continue
            }
            let newItem = coreQueue[Int(block.header.timeslot) % coreQueue.count]

            // remove used authorizers from pool
            for report in block.extrinsic.reports.guarantees {
                let authorizer = report.workReport.authorizerHash
                if let idx = corePool.firstIndex(of: authorizer) {
                    _ = try corePool.remove(at: idx)
                } else {
                    throw Error.invalidReportAuthorizer
                }
            }

            // add new item from queue
            corePool.safeAppend(newItem)
            pool[coreIndex] = corePool
        }

        return pool
    }

    // returns available reports
    public func updateReports(block: BlockRef, state newState: inout State) throws -> [WorkReport] {
        for assurance in block.extrinsic.availability.assurances {
            let hash = Blake2b256.hash(assurance.parentHash, assurance.assurance)
            let payload = SigningContext.available + hash.data
            let validatorKey = try newState.currentValidators.at(Int(assurance.validatorIndex))
            let pubkey = try Ed25519.PublicKey(from: validatorKey.ed25519)
            guard pubkey.verify(signature: assurance.signature, message: payload) else {
                throw Error.invalidAssuranceSignature
            }
        }

        var availabilityCount = Array(repeating: 0, count: config.value.totalNumberOfCores)
        for assurance in block.extrinsic.availability.assurances {
            for bit in assurance.assurance where bit {
                // ExtrinsicAvailability.validate() ensures that validatorIndex is in range
                availabilityCount[Int(assurance.validatorIndex)] += 1
            }
        }

        var availableReports = [WorkReport]()

        for (idx, count) in availabilityCount.enumerated() where count > 0 {
            guard let report = newState.reports[idx] else {
                throw Error.assuranceForEmptyCore
            }
            if count >= ProtocolConfig.TwoThirdValidatorsPlusOne.read(config: config) {
                availableReports.append(report.workReport)
                newState.reports[idx] = nil // remove available report from pending reports
            }
        }

        newState.reports = try newState.update(config: config, extrinsic: block.extrinsic.reports)

        return availableReports
    }

    public func updatePreimages(block: BlockRef, state newState: inout State) async throws {
        let preimages = block.extrinsic.preimages.preimages

        guard preimages.isSortedAndUnique() else {
            throw Error.preimagesNotSorted
        }

        for preimage in preimages {
            let hash = preimage.data.blake2b256hash()
            let preimageData: Data? = try await newState.get(serviceAccount: preimage.serviceIndex, preimageHash: hash)
            let info = try await newState.get(
                serviceAccount: preimage.serviceIndex, preimageHash: hash, length: UInt32(preimage.data.count)
            )
            guard preimageData == nil, info == nil else {
                throw Error.duplicatedPreimage
            }

            newState[serviceAccount: preimage.serviceIndex, preimageHash: hash] = preimage.data
            newState[
                serviceAccount: preimage.serviceIndex, preimageHash: hash, length: UInt32(preimage.data.count)
            ] = .init([newState.timeslot])
        }
    }

    // TODO: add tests
    public func updateValidatorActivityStatistics(block: BlockRef, state: StateRef) throws -> ValidatorActivityStatistics {
        let epochLength = UInt32(config.value.epochLength)
        let currentEpoch = state.value.timeslot / epochLength
        let newEpoch = block.header.timeslot / epochLength
        let isEpochChange = currentEpoch != newEpoch

        var acc = try isEpochChange
            ? ConfigFixedSizeArray<_, ProtocolConfig.TotalNumberOfValidators>(
                config: config,
                defaultValue: ValidatorActivityStatistics.StatisticsItem.dummy(config: config)
            ) : state.value.activityStatistics.accumulator

        let prev = isEpochChange ? state.value.activityStatistics.accumulator : state.value.activityStatistics.previous

        var item = acc[block.header.authorIndex]
        item.blocks += 1
        item.tickets += UInt32(block.extrinsic.tickets.tickets.count)
        item.preimages += UInt32(block.extrinsic.preimages.preimages.count)
        item.preimagesBytes += UInt32(block.extrinsic.preimages.preimages.reduce(into: 0) { $0 += $1.data.count })
        acc[block.header.authorIndex] = item

        for report in block.extrinsic.reports.guarantees {
            for cred in report.credential {
                acc[cred.index].guarantees += 1
            }
        }

        for assurance in block.extrinsic.availability.assurances {
            acc[assurance.validatorIndex].assurances += 1
        }

        return ValidatorActivityStatistics(
            accumulator: acc,
            previous: prev
        )
    }
}
