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
        case authorizationError(AuthorizationError)
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

    public func validateHeaderSeal(block: BlockRef, state: State) throws(Error) {
        let vrfOutput: Data32
        // H_a
        let blockAuthorKey = try Result {
            try Bandersnatch.PublicKey(data: state.currentValidators[Int(block.header.authorIndex)].bandersnatch)
        }.mapError(Error.invalidBlockSeal).get()

        let index = block.header.timeslot % UInt32(config.value.epochLength)
        let encodedHeader = try Result { try JamEncoder.encode(block.header.unsigned) }.mapError(Error.invalidBlockSeal).get()
        let entropyVRFInputData: Data
        switch state.safroleState.ticketsOrKeys {
        case let .left(tickets):
            let ticket = tickets[Int(index)]
            let vrfInputData = SigningContext.safroleTicketInputData(entropy: state.entropyPool.t3, attempt: ticket.attempt)
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
            let vrfInputData = SigningContext.fallbackSealInputData(entropy: state.entropyPool.t3)
            vrfOutput = try Result {
                logger.trace("verifying ticket", metadata: ["key": "\(blockAuthorKey.data.toHexString())"])
                return try blockAuthorKey.ietfVRFVerify(
                    vrfInputData: vrfInputData,
                    auxData: encodedHeader,
                    signature: block.header.seal
                )
            }.mapError(Error.invalidBlockSeal).get()

            entropyVRFInputData = SigningContext.entropyInputData(entropy: vrfOutput)
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

        try validate(block: validatedBlock, state: prevState, context: context)

        return try await apply(block: validatedBlock, state: prevState)
    }

    public func apply(block: Validated<BlockRef>, state prevState: StateRef) async throws(Error) -> StateRef {
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

            try validateHeaderSeal(block: block, state: newState)

            try updateDisputes(block: block, state: &newState)

            // depends on Safrole and Disputes
            let availableReports = try updateReports(block: block, state: &newState)

            // accumulate
            let accumulateRoot = try await newState.update(
                config: config,
                availableReports: availableReports,
                timeslot: block.header.timeslot,
                prevTimeslot: prevState.value.timeslot,
                entropy: newState.entropyPool.t0
            )

            do {
                let authorizationResult = try newState.update(
                    config: config,
                    timeslot: block.header.timeslot,
                    auths: block.extrinsic.reports.guarantees.map { ($0.workReport.coreIndex, $0.workReport.authorizerHash) }
                )
                newState.mergeWith(postState: authorizationResult)
            } catch let error as AuthorizationError {
                throw Error.authorizationError(error)
            }

            try await updatePreimages(block: block, state: &newState)

            newState.activityStatistics = try prevState.value.update(
                config: config,
                newTimeslot: block.header.timeslot,
                extrinsic: block.extrinsic,
                authorIndex: block.header.authorIndex
            )

            // after reports as it need old recent history
            try updateRecentHistory(block: block, state: &newState, accumulateRoot: accumulateRoot)

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

    public func updateRecentHistory(block: BlockRef, state newState: inout State, accumulateRoot: Data32) throws {
        let lookup: [Data32: Data32] = Dictionary(uniqueKeysWithValues: block.extrinsic.reports.guarantees.map { (
            $0.workReport.packageSpecification.workPackageHash,
            $0.workReport.packageSpecification.segmentRoot
        ) })
        newState.recentHistory.update(
            headerHash: block.hash,
            parentStateRoot: block.header.priorStateRoot,
            accumulateRoot: accumulateRoot,
            lookup: lookup
        )
    }

    public func updateSafrole(block: BlockRef, state newState: inout State) throws {
        let safroleResult = try newState.updateSafrole(
            config: config,
            slot: block.header.timeslot,
            entropy: Bandersnatch.getIetfSignatureOutput(signature: block.header.vrfSignature),
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

    public func updatePreimages(block: BlockRef, state newState: inout State) async throws {
        let res = try await newState.updatePreimages(
            config: config, timeslot: newState.timeslot, preimages: block.extrinsic.preimages
        )
        newState.mergeWith(postState: res)
    }
}
