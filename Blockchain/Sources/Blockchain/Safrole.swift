import Blake2
import Foundation
import ScaleCodec
import Utils

public enum SafroleError: Error {
    case invalidTimeslot
    case hashingError
    case decodingError
    case unspecified
}

public struct SafrolePostState: Sendable, Equatable {
    public var timeslot: TimeslotIndex
    public var entropyPool: (Data32, Data32, Data32, Data32)
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
        entropyPool: (Data32, Data32, Data32, Data32),
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
    var entropyPool: (Data32, Data32, Data32, Data32) { get }
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

    func mergeWith(postState: SafrolePostState) -> Self
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

func generateFallbackIndices(entropy: Data32, count: Int) throws -> [Int] {
    try (0 ..< count).map { i throws in
        // convert i to little endian
        let bytes = UInt32(i).data(littleEndian: true, trimmed: false)
        let data = entropy.data + Data(bytes)
        let hash = try blake2b256(data)
        let hash4 = hash.data[0 ..< 4]
        let idx = try decode(UInt32.self, from: hash4)
        return Int(idx) % count
    }
}

func pickFallbackValidators(
    entropy: Data32,
    validators: ConfigFixedSizeArray<ValidatorKey, ProtocolConfig.TotalNumberOfValidators>
) throws -> [BandersnatchPublicKey] {
    let indices = try generateFallbackIndices(entropy: entropy, count: validators.count)
    return indices.map { validators[$0].bandersnatch }
}

extension Safrole {
    public func updateSafrole(slot: TimeslotIndex, entropy: Data32, extrinsics _: ExtrinsicTickets)
        -> Result<
            (
                state: SafrolePostState,
                epochMark: EpochMarker?,
                ticketsMark: ConfigFixedSizeArray<Ticket, ProtocolConfig.EpochLength>?
            ),
            SafroleError
        >
    {
        guard slot > timeslot else {
            return .failure(.invalidTimeslot)
        }

        do {
            let epochLength = UInt32(config.value.epochLength)
            let currentEpoch = timeslot / epochLength
            // let currentPhase = timeslot % epochLength
            let newEpoch = slot / epochLength
            let newPhase = slot % epochLength
            let isEpochChange = currentEpoch != newEpoch

            let isClosingPeriod = newPhase >= UInt32(config.value.ticketSubmissionEndSlot)

            let (newNextValidators, newCurrentValidators, newPreviousValidators, newTicketsVerifier) = isEpochChange
                ? (
                    validatorQueue, // TODO: Φ filter out the one in the punishment set
                    nextValidators,
                    currentValidators,
                    ticketsVerifier // TODO: calculate the new ring root from the new validators
                )
                : (nextValidators, currentValidators, previousValidators, ticketsVerifier)

            let newRandomness = try blake2b256(entropyPool.0.data + entropy.data)

            let newEntropyPool = isEpochChange
                ? (newRandomness, entropyPool.0, entropyPool.1, entropyPool.2)
                : (newRandomness, entropyPool.1, entropyPool.2, entropyPool.3)

            let newTicketsOrKeys: Either<
                ConfigFixedSizeArray<
                    Ticket,
                    ProtocolConfig.EpochLength
                >,
                ConfigFixedSizeArray<
                    BandersnatchPublicKey,
                    ProtocolConfig.EpochLength
                >
            > = if newEpoch == currentEpoch + 1, isClosingPeriod, ticketsAccumulator.count == config.value.epochLength {
                .left(ConfigFixedSizeArray(config: config, array: outsideInReorder(ticketsAccumulator.array)))
            } else if newEpoch == currentEpoch {
                ticketsOrKeys
            } else {
                try .right(ConfigFixedSizeArray(config: config, array: pickFallbackValidators(entropy: entropy, validators: newCurrentValidators)))
            }

            let postState = SafrolePostState(
                timeslot: slot,
                entropyPool: newEntropyPool,
                previousValidators: newPreviousValidators,
                currentValidators: newCurrentValidators,
                nextValidators: newNextValidators,
                validatorQueue: validatorQueue,
                ticketsAccumulator: ticketsAccumulator,
                ticketsOrKeys: newTicketsOrKeys,
                ticketsVerifier: newTicketsVerifier
            )
            return .success((postState, nil, nil))
        } catch let e as SafroleError {
            return .failure(e)
        } catch Blake2Error.hashingError {
            return .failure(.hashingError)
        } catch is DecodingError {
            // TODO: log details
            return .failure(.decodingError)
        } catch {
            // TODO: log details
            return .failure(.unspecified)
        }
    }
}
