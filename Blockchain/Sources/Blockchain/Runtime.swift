import Codec
import Utils

// the STF
public final class Runtime {
    public enum Error: Swift.Error {
        case safroleError(SafroleError)
        case invalidTimeslot
        case invalidReportAuthorizer
        case encodeError(any Swift.Error)
        case invalidExtrinsicHash
        case invalidParentHash
        case invalidHeaderStateRoot
        case invalidHeaderEpochMarker
        case invalidHeaderWinningTickets
        case other(any Swift.Error)
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

    public func validateHeader(block: BlockRef, state: StateRef, context: ApplyContext) throws(Error) {
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
            throw Error.invalidTimeslot
        }

        // epoch is validated at apply time

        // winning tickets is validated at apply time

        // TODO: validate judgementsMarkers
        // TODO: validate offendersMarkers

        // TODO: validate block.header.seal
    }

    public func validate(block: BlockRef, state: StateRef, context: ApplyContext) throws(Error) {
        try validateHeader(block: block, state: state, context: context)

        // TODO: abstract input validation logic from Safrole state update function and call it here
        // TODO: validate other things
    }

    public func apply(block: BlockRef, state prevState: StateRef, context: ApplyContext) throws(Error) -> StateRef {
        try validate(block: block, state: prevState, context: context)

        var newState = prevState.value

        do {
            newState.recentHistory = try updateRecentHistory(block: block, state: prevState)

            let safroleResult = try newState.updateSafrole(
                config: config, slot: block.header.timeslot, entropy: newState.entropyPool.t0, extrinsics: block.extrinsic.tickets
            )
            newState.mergeWith(postState: safroleResult.state)

            guard safroleResult.epochMark == block.header.epoch else {
                throw Error.invalidHeaderEpochMarker
            }

            guard safroleResult.ticketsMark == block.header.winningTickets else {
                throw Error.invalidHeaderWinningTickets
            }

            newState.coreAuthorizationPool = try updateAuthorizationPool(
                block: block, state: prevState
            )

            newState.activityStatistics = try updateValidatorActivityStatistics(
                block: block, state: prevState
            )
        } catch let error as Error {
            throw error
        } catch let error as SafroleError {
            throw .safroleError(error)
        } catch {
            throw .other(error)
        }

        return StateRef(newState)
    }

    public func updateRecentHistory(block: BlockRef, state: StateRef) throws -> RecentHistory {
        var history = state.value.recentHistory
        if history.items.count >= 0 { // if this is not block #0
            // write the state root of last block
            history.items[history.items.endIndex - 1].stateRoot = state.stateRoot
        }

        let workReportHashes = block.extrinsic.reports.guarantees.map(\.workReport.packageSpecification.workPackageHash)

        let accumulationResult = Data32() // TODO: calculate accumulation result

        var mmr = history.items.last?.mmr ?? .init([])
        mmr.append(accumulationResult, hasher: Keccak.self)

        let newItem = try RecentHistory.HistoryItem(
            headerHash: block.header.parentHash,
            mmr: mmr,
            stateRoot: Data32(), // empty and will be updated upon next block
            workReportHashes: ConfigLimitedSizeArray(config: config, array: workReportHashes)
        )

        history.items.safeAppend(newItem)

        return history
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
