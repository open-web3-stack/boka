import Codec
import Foundation
import TracingUtils
import Utils

private let logger = Logger(label: "Runtime")

// the STF
public final class Runtime {
    public enum Error: Swift.Error {
        case safroleError(SafroleError)
        case disputesError(DisputesError)
        case invalidTimeslot(got: TimeslotIndex, context: TimeslotIndex)
        case invalidReportAuthorizer
        case encodeError(any Swift.Error)
        case invalidExtrinsicHash
        case invalidParentHash(state: Data32, header: Data32)
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
        public let stateRoot: Data32

        public init(timeslot: TimeslotIndex, stateRoot: Data32) {
            self.timeslot = timeslot
            self.stateRoot = stateRoot
        }
    }

    public let config: ProtocolConfigRef

    public init(config: ProtocolConfigRef) {
        self.config = config
    }

    public func validateHeader(block: Validated<BlockRef>, state: StateRef, context: ApplyContext) throws(Error) {
        let block = block.value

        guard block.header.parentHash == state.value.lastBlockHash else {
            throw Error.invalidParentHash(state: state.value.lastBlockHash, header: block.header.parentHash)
        }

        guard block.header.priorStateRoot == context.stateRoot else {
            throw Error.invalidHeaderStateRoot
        }

        guard block.header.extrinsicsHash == block.extrinsic.hash() else {
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

            // accumulation
            try await accumulate(
                config: config,
                block: block,
                availableReports: availableReports,
                state: &newState,
                prevTimeslot: prevState.value.timeslot
            )

            newState.coreAuthorizationPool = try updateAuthorizationPool(
                block: block, state: prevState
            )

            newState.activityStatistics = try updateValidatorActivityStatistics(
                block: block, state: prevState
            )

            // after reports as it need old recent history
            try updateRecentHistory(block: block, state: &newState)

            try await newState.save()
        } catch let error as Error {
            throw error
        } catch let error as SafroleError {
            throw .safroleError(error)
        } catch let error as DisputesError {
            throw .disputesError(error)
        } catch {
            throw .other(error)
        }

        return StateRef(newState)
    }

    // accumulation related state updates
    public func accumulate(
        config: ProtocolConfigRef,
        block: BlockRef,
        availableReports: [WorkReport],
        state: inout State,
        prevTimeslot: TimeslotIndex
    ) async throws {
        let curIndex = Int(block.header.timeslot) % config.value.epochLength
        var (accumulatableReports, newQueueItems) = state.getAccumulatableReports(
            index: curIndex,
            availableReports: availableReports,
            history: state.accumulationHistory
        )

        // accumulate and transfers
        let (numAccumulated, accumulateState, _) = try await state.update(config: config, block: block, workReports: accumulatableReports)

        state.authorizationQueue = accumulateState.authorizationQueue
        state.validatorQueue = accumulateState.validatorQueue
        state.privilegedServices = accumulateState.privilegedServices
        for (service, account) in accumulateState.serviceAccounts {
            state[serviceAccount: service] = account.toDetails()
            for (hash, value) in account.storage {
                state[serviceAccount: service, storageKey: hash] = value
            }
            for (hash, value) in account.preimages {
                state[serviceAccount: service, preimageHash: hash] = value
            }
            for (hashLength, value) in account.preimageInfos {
                state[serviceAccount: service, preimageHash: hashLength.hash, length: hashLength.length] = value
            }
        }

        // update accumulation history
        let accumulated = accumulatableReports[0 ..< numAccumulated]
        let newHistoryItem = Set(accumulated.map(\.packageSpecification.workPackageHash))
        for i in 0 ..< config.value.epochLength {
            if i == config.value.epochLength - 1 {
                state.accumulationHistory[i] = newHistoryItem
            } else {
                state.accumulationHistory[i] = state.accumulationHistory[i + 1]
            }
        }

        // update accumulation queue
        for i in 0 ..< config.value.epochLength {
            let queueIdx = (curIndex - i) %% config.value.epochLength
            if i == 0 {
                state.editAccumulatedItems(items: &newQueueItems, accumulatedPackages: newHistoryItem)
                state.accumulationQueue[queueIdx] = newQueueItems
            } else if i >= 1, i < state.timeslot - prevTimeslot {
                state.accumulationQueue[queueIdx] = []
            } else {
                state.editAccumulatedItems(items: &state.accumulationQueue[queueIdx], accumulatedPackages: newHistoryItem)
            }
        }
    }

    public func updateRecentHistory(block: BlockRef, state newState: inout State) throws {
        let lookup: [Data32: Data32] = Dictionary(uniqueKeysWithValues: block.extrinsic.reports.guarantees.map { (
            $0.workReport.packageSpecification.workPackageHash,
            $0.workReport.packageSpecification.segmentRoot
        ) })
        newState.recentHistory.update(
            headerHash: block.hash,
            parentStateRoot: block.header.priorStateRoot,
            accumulateRoot: Data32(), // TODO: calculate accumulation result
            lookup: lookup
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
        let (posState, offenders) = try newState.update(config: config, disputes: block.extrinsic.disputes)
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
        let (
            newReports: newReports, availableReports: availableReports
        ) = try newState.update(
            config: config,
            timeslot: block.header.timeslot,
            extrinsic: block.extrinsic.availability,
            parentHash: block.header.parentHash
        )

        newState.reports = newReports
        let result = try newState.update(
            config: config, timeslot: newState.timeslot, extrinsic: block.extrinsic.reports
        )

        newState.reports = result.newReports

        return availableReports
    }

    public func updatePreimages(block: BlockRef, state newState: inout State, prevState: StateRef) async throws {
        let preimages = block.extrinsic.preimages.preimages

        guard preimages.isSortedAndUnique() else {
            throw Error.preimagesNotSorted
        }

        for preimage in preimages {
            let hash = preimage.data.blake2b256hash()

            // check prior state
            let prevPreimageData: Data? = try await prevState.value.get(serviceAccount: preimage.serviceIndex, preimageHash: hash)
            let prevInfo = try await prevState.value.get(
                serviceAccount: preimage.serviceIndex, preimageHash: hash, length: UInt32(preimage.data.count)
            )
            guard prevPreimageData == nil, prevInfo == nil else {
                throw Error.duplicatedPreimage
            }

            // disregard no longer useful ones in new state
            let preimageData: Data? = try await newState.get(serviceAccount: preimage.serviceIndex, preimageHash: hash)
            let info = try await newState.get(
                serviceAccount: preimage.serviceIndex, preimageHash: hash, length: UInt32(preimage.data.count)
            )
            if preimageData != nil || info != nil {
                continue
            }

            // update state
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
