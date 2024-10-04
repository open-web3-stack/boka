import Blake2
import Codec
import Foundation
import Utils

public enum SafroleError: Error {
    case invalidTimeslot
    case tooManyExtrinsics
    case extrinsicsNotAllowed
    case extrinsicsNotSorted
    case extrinsicsTooLow
    case extrinsicsNotUnique
    case bandersnatchError(Bandersnatch.Error)
    case other(any Swift.Error)
}

public struct EntropyPool: Sendable, Equatable, Codable {
    public var t0: Data32
    public var t1: Data32
    public var t2: Data32
    public var t3: Data32

    public init(_ entropyPool: (Data32, Data32, Data32, Data32)) {
        t0 = entropyPool.0
        t1 = entropyPool.1
        t2 = entropyPool.2
        t3 = entropyPool.3
    }
}

public typealias SafroleTicketsOrKeys = Either<
    ConfigFixedSizeArray<
        Ticket,
        ProtocolConfig.EpochLength
    >,
    ConfigFixedSizeArray<
        BandersnatchPublicKey,
        ProtocolConfig.EpochLength
    >
>

public struct SafrolePostState: Sendable, Equatable {
    public var timeslot: TimeslotIndex
    public var entropyPool: EntropyPool
    public var previousValidators: ConfigFixedSizeArray<
        ValidatorKey, ProtocolConfig.TotalNumberOfValidators
    >
    public var currentValidators: ConfigFixedSizeArray<
        ValidatorKey, ProtocolConfig.TotalNumberOfValidators
    >
    public var nextValidators: ConfigFixedSizeArray<
        ValidatorKey, ProtocolConfig.TotalNumberOfValidators
    >
    public var validatorQueue: ConfigFixedSizeArray<
        ValidatorKey, ProtocolConfig.TotalNumberOfValidators
    >
    public var ticketsAccumulator: ConfigLimitedSizeArray<
        Ticket,
        ProtocolConfig.Int0,
        ProtocolConfig.EpochLength
    >
    public var ticketsOrKeys: SafroleTicketsOrKeys
    public var ticketsVerifier: BandersnatchRingVRFRoot

    public init(
        timeslot: TimeslotIndex,
        entropyPool: EntropyPool,
        previousValidators: ConfigFixedSizeArray<
            ValidatorKey, ProtocolConfig.TotalNumberOfValidators
        >,
        currentValidators: ConfigFixedSizeArray<
            ValidatorKey, ProtocolConfig.TotalNumberOfValidators
        >,
        nextValidators: ConfigFixedSizeArray<
            ValidatorKey, ProtocolConfig.TotalNumberOfValidators
        >,
        validatorQueue: ConfigFixedSizeArray<
            ValidatorKey, ProtocolConfig.TotalNumberOfValidators
        >,
        ticketsAccumulator: ConfigLimitedSizeArray<
            Ticket,
            ProtocolConfig.Int0,
            ProtocolConfig.EpochLength
        >,
        ticketsOrKeys: Either<
            ConfigFixedSizeArray<
                Ticket,
                ProtocolConfig.EpochLength
            >,
            ConfigFixedSizeArray<
                BandersnatchPublicKey,
                ProtocolConfig.EpochLength
            >
        >,
        ticketsVerifier: BandersnatchRingVRFRoot
    ) {
        self.timeslot = timeslot
        self.entropyPool = entropyPool
        self.previousValidators = previousValidators
        self.currentValidators = currentValidators
        self.nextValidators = nextValidators
        self.validatorQueue = validatorQueue
        self.ticketsAccumulator = ticketsAccumulator
        self.ticketsOrKeys = ticketsOrKeys
        self.ticketsVerifier = ticketsVerifier
    }
}

public protocol Safrole {
    var timeslot: TimeslotIndex { get }
    var entropyPool: EntropyPool { get }
    var previousValidators: ConfigFixedSizeArray<
        ValidatorKey, ProtocolConfig.TotalNumberOfValidators
    > { get }
    var currentValidators: ConfigFixedSizeArray<
        ValidatorKey, ProtocolConfig.TotalNumberOfValidators
    > { get }
    var nextValidators: ConfigFixedSizeArray<
        ValidatorKey, ProtocolConfig.TotalNumberOfValidators
    > { get }
    var validatorQueue: ConfigFixedSizeArray<
        ValidatorKey, ProtocolConfig.TotalNumberOfValidators
    > { get }
    var ticketsAccumulator: ConfigLimitedSizeArray<
        Ticket,
        ProtocolConfig.Int0,
        ProtocolConfig.EpochLength
    > { get }
    var ticketsOrKeys: SafroleTicketsOrKeys { get }
    var ticketsVerifier: BandersnatchRingVRFRoot { get }

    func updateSafrole(
        config: ProtocolConfigRef,
        slot: TimeslotIndex,
        entropy: Data32,
        offenders: Set<Ed25519PublicKey>,
        extrinsics: ExtrinsicTickets
    ) throws(SafroleError)
        -> (
            state: SafrolePostState,
            epochMark: EpochMarker?,
            ticketsMark: ConfigFixedSizeArray<Ticket, ProtocolConfig.EpochLength>?
        )

    mutating func mergeWith(postState: SafrolePostState)
}

func outsideInReorder<T>(_ array: [T]) -> [T] {
    var reordered = [T]()
    reordered.reserveCapacity(array.count)

    var left = 0
    var right = array.count - 1

    while left <= right {
        if left == right {
            reordered.append(array[left])
        } else {
            reordered.append(array[left])
            reordered.append(array[right])
        }
        left += 1
        right -= 1
    }

    return reordered
}

func generateFallbackIndices(entropy: Data32, count: Int, length: Int) throws -> [Int] {
    try (0 ..< count).map { i throws in
        // convert i to little endian
        let bytes = UInt32(i).encode()
        let hash = Blake2b256.hash(entropy, bytes)
        let hash4 = hash.data[0 ..< 4]
        let idx = hash4.decode(UInt32.self)
        return Int(idx % UInt32(length))
    }
}

func pickFallbackValidators(
    entropy: Data32,
    validators: ConfigFixedSizeArray<ValidatorKey, ProtocolConfig.TotalNumberOfValidators>,
    count: Int
) throws -> [BandersnatchPublicKey] {
    let indices = try generateFallbackIndices(entropy: entropy, count: count, length: validators.count)
    return indices.map { validators[$0].bandersnatch }
}

func withoutOffenders(
    offenders: Set<Ed25519PublicKey>,
    validators: ConfigFixedSizeArray<ValidatorKey, ProtocolConfig.TotalNumberOfValidators>
) -> ConfigFixedSizeArray<ValidatorKey, ProtocolConfig.TotalNumberOfValidators> {
    var validators = validators

    for i in validators.indices {
        let validator = validators[i]
        if offenders.contains(validator.ed25519) {
            validators[i] = ValidatorKey() // replace to empty key
        }
    }

    return validators
}

extension Safrole {
    public func updateSafrole(
        config: ProtocolConfigRef,
        slot: TimeslotIndex,
        entropy: Data32,
        offenders: Set<Ed25519PublicKey>,
        extrinsics: ExtrinsicTickets
    ) throws(SafroleError)
        -> (
            state: SafrolePostState,
            epochMark: EpochMarker?,
            ticketsMark: ConfigFixedSizeArray<Ticket, ProtocolConfig.EpochLength>?
        )
    {
        // E
        let epochLength = UInt32(config.value.epochLength)
        // Y
        let ticketSubmissionEndSlot = UInt32(config.value.ticketSubmissionEndSlot)
        // e
        let currentEpoch = timeslot / epochLength
        // m
        let currentPhase = timeslot % epochLength
        // e'
        let newEpoch = slot / epochLength
        // m'
        let newPhase = slot % epochLength
        let isEpochChange = currentEpoch != newEpoch

        guard slot > timeslot else {
            throw .invalidTimeslot
        }

        if newPhase < ticketSubmissionEndSlot {
            guard extrinsics.tickets.count <= config.value.maxTicketsPerExtrinsic else {
                throw .tooManyExtrinsics
            }
        } else {
            guard extrinsics.tickets.isEmpty else {
                throw .extrinsicsNotAllowed
            }
        }

        do {
            let ctx = try Bandersnatch.RingContext(size: UInt(config.value.totalNumberOfValidators))
            let commitment = try Bandersnatch.RingCommitment(data: ticketsVerifier)

            let validatorQueueWithoutOffenders = withoutOffenders(offenders: offenders, validators: validatorQueue)

            let newCommitment = {
                try Bandersnatch.RingCommitment(
                    ring: validatorQueueWithoutOffenders.map { try? Bandersnatch.PublicKey(data: $0.bandersnatch) },
                    ctx: ctx
                ).data
            }
            let verifier = Bandersnatch.Verifier(ctx: ctx, commitment: commitment)

            let (newNextValidators, newCurrentValidators, newPreviousValidators, newTicketsVerifier) = try isEpochChange
                ? (
                    validatorQueueWithoutOffenders,
                    nextValidators,
                    currentValidators,
                    newCommitment()
                )
                : (nextValidators, currentValidators, previousValidators, ticketsVerifier)

            let newRandomness = Blake2b256.hash(entropyPool.t0, entropy)

            let newEntropyPool = isEpochChange
                ? (newRandomness, entropyPool.t0, entropyPool.t1, entropyPool.t2)
                : (newRandomness, entropyPool.t1, entropyPool.t2, entropyPool.t3)

            let newTicketsOrKeys: Either<
                ConfigFixedSizeArray<
                    Ticket,
                    ProtocolConfig.EpochLength
                >,
                ConfigFixedSizeArray<
                    BandersnatchPublicKey,
                    ProtocolConfig.EpochLength
                >
            > = if newEpoch == currentEpoch + 1,
                   currentPhase >= ticketSubmissionEndSlot,
                   ticketsAccumulator.count == config.value.epochLength
            {
                try .left(ConfigFixedSizeArray(config: config, array: outsideInReorder(ticketsAccumulator.array)))
            } else if newEpoch == currentEpoch {
                ticketsOrKeys
            } else {
                try .right(ConfigFixedSizeArray(
                    config: config,
                    array: pickFallbackValidators(
                        entropy: newEntropyPool.2,
                        validators: newCurrentValidators,
                        count: config.value.epochLength
                    )
                ))
            }

            let epochMark = try isEpochChange ? EpochMarker(
                entropy: newEntropyPool.1,
                validators: ConfigFixedSizeArray(config: config, array: newNextValidators.map(\.bandersnatch))
            ) : nil

            let ticketsMark: ConfigFixedSizeArray<Ticket, ProtocolConfig.EpochLength>? =
                if currentEpoch == newEpoch,
                currentPhase < ticketSubmissionEndSlot,
                ticketSubmissionEndSlot <= newPhase,
                ticketsAccumulator.count == config.value.epochLength {
                    try ConfigFixedSizeArray(
                        config: config, array: outsideInReorder(ticketsAccumulator.array)
                    )
                } else {
                    nil
                }

            let newTickets = try extrinsics.getTickets(verifier: verifier, entropy: newEntropyPool.2)
            guard newTickets.isSortedAndUnique() else {
                throw SafroleError.extrinsicsNotSorted
            }

            var newTicketsAccumulatorArr = if isEpochChange {
                [Ticket]()
            } else {
                ticketsAccumulator.array
            }

            try newTicketsAccumulatorArr.insertSorted(newTickets) {
                if $0 == $1 {
                    throw SafroleError.extrinsicsNotUnique
                }
                return $0 < $1
            }

            if newTicketsAccumulatorArr.count > config.value.epochLength {
                let firstToBeRemoved = newTicketsAccumulatorArr[config.value.epochLength]
                let highestTicket = newTickets.last! // newTickets must not be empty, otherwise we won't need to remove anything
                guard highestTicket < firstToBeRemoved else {
                    // every tickets must be valid or this is an invalid block
                    // i.e. the block producer must not include invalid tickets
                    throw SafroleError.extrinsicsTooLow
                }
                newTicketsAccumulatorArr.removeLast(newTicketsAccumulatorArr.count - config.value.epochLength)
            }

            let newTicketsAccumulator = try ConfigLimitedSizeArray<
                Ticket, ProtocolConfig.Int0, ProtocolConfig.EpochLength
            >(
                config: config,
                array: newTicketsAccumulatorArr
            )

            let postState = SafrolePostState(
                timeslot: slot,
                entropyPool: EntropyPool(newEntropyPool),
                previousValidators: newPreviousValidators,
                currentValidators: newCurrentValidators,
                nextValidators: newNextValidators,
                validatorQueue: validatorQueue,
                ticketsAccumulator: newTicketsAccumulator,
                ticketsOrKeys: newTicketsOrKeys,
                ticketsVerifier: newTicketsVerifier
            )
            return (state: postState, epochMark: epochMark, ticketsMark: ticketsMark)
        } catch let e as SafroleError {
            throw e
        } catch let e as Bandersnatch.Error {
            throw .bandersnatchError(e)
        } catch {
            throw .other(error)
        }
    }
}
