import Blake2
import Foundation
import Utils

public enum SafroleError: Error {
    case invalidTimeslot
    case tooManyExtrinsics
    case extrinsicsNotAllowed
    case extrinsicsNotSorted
    case extrinsicsTooLow
    case extrinsicsNotUnique
    case extrinsicsTooManyEntry
    case hashingError
    case bandersnatchError(BandersnatchError)
    case decodingError(DecodingError)
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
    public var ticketsOrKeys: Either<
        ConfigFixedSizeArray<
            Ticket,
            ProtocolConfig.EpochLength
        >,
        ConfigFixedSizeArray<
            BandersnatchPublicKey,
            ProtocolConfig.EpochLength
        >
    >
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

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.timeslot == rhs.timeslot &&
            lhs.entropyPool == rhs.entropyPool &&
            lhs.previousValidators == rhs.previousValidators &&
            lhs.currentValidators == rhs.currentValidators &&
            lhs.nextValidators == rhs.nextValidators &&
            lhs.validatorQueue == rhs.validatorQueue &&
            lhs.ticketsAccumulator == rhs.ticketsAccumulator &&
            lhs.ticketsOrKeys == rhs.ticketsOrKeys &&
            lhs.ticketsVerifier == rhs.ticketsVerifier
    }
}

public protocol Safrole {
    var config: ProtocolConfigRef { get }
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
    var ticketsOrKeys: Either<
        ConfigFixedSizeArray<
            Ticket,
            ProtocolConfig.EpochLength
        >,
        ConfigFixedSizeArray<
            BandersnatchPublicKey,
            ProtocolConfig.EpochLength
        >
    > { get }
    var ticketsVerifier: BandersnatchRingVRFRoot { get }

    func updateSafrole(slot: TimeslotIndex, entropy: Data32, extrinsics: ExtrinsicTickets)
        -> Result<
            (
                state: SafrolePostState,
                epochMark: EpochMarker?,
                ticketsMark: ConfigFixedSizeArray<Ticket, ProtocolConfig.EpochLength>?
            ),
            SafroleError
        >

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
        let bytes = UInt32(i).encode(method: .fixedWidth(4))
        let data = entropy.data + Data(bytes)
        let hash = try blake2b256(data)
        var hash4 = hash.data[0 ..< 4]
        let idx: UInt32 = hash4.decode(length: 4)!
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

extension Safrole {
    public func updateSafrole(slot: TimeslotIndex, entropy: Data32, extrinsics: ExtrinsicTickets)
        -> Result<
            (
                state: SafrolePostState,
                epochMark: EpochMarker?,
                ticketsMark: ConfigFixedSizeArray<Ticket, ProtocolConfig.EpochLength>?
            ),
            SafroleError
        >
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
            return .failure(.invalidTimeslot)
        }

        if newPhase < ticketSubmissionEndSlot {
            guard extrinsics.tickets.count <= config.value.maxTicketsPerExtrinsic else {
                return .failure(.tooManyExtrinsics)
            }
        } else {
            guard extrinsics.tickets.isEmpty else {
                return .failure(.extrinsicsNotAllowed)
            }
        }

        do {
            let verifier = try Verifier(ring: nextValidators.map(\.bandersnatch))
            let newVerifier = try Verifier(ring: validatorQueue.map(\.bandersnatch))

            let (newNextValidators, newCurrentValidators, newPreviousValidators, newTicketsVerifier) = isEpochChange
                ? (
                    validatorQueue, // TODO: Φ filter out the one in the punishment set
                    nextValidators,
                    currentValidators,
                    newVerifier.ringRoot
                )
                : (nextValidators, currentValidators, previousValidators, ticketsVerifier)

            let newRandomness = try blake2b256(entropyPool.t0.data + entropy.data)

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
            guard newTickets.isSorted() else {
                return .failure(.extrinsicsNotSorted)
            }

            for ticket in newTickets {
                guard ticket.attempt < config.value.ticketEntriesPerValidator else {
                    return .failure(.extrinsicsTooManyEntry)
                }
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
            return .success((state: postState, epochMark: epochMark, ticketsMark: ticketsMark))
        } catch let e as SafroleError {
            return .failure(e)
        } catch let e as BandersnatchError {
            return .failure(.bandersnatchError(e))
        } catch Blake2Error.hashingError {
            return .failure(.hashingError)
        } catch let e as DecodingError {
            return .failure(.decodingError(e))
        } catch {
            return .failure(.other(error))
        }
    }
}
