import Foundation
import Utils

public enum PreimagesError: Error {
    case preimagesNotSorted
    case duplicatedPreimage
    case invalidServiceIndex
    case preimageNotSolicited
    case preimageIsProvided
}

public struct PreimageUpdate: Sendable, Equatable {
    public let serviceIndex: UInt32
    public let hash: Data32
    public let data: Data
    public let length: UInt32
    public let timeslot: TimeslotIndex

    public init(serviceIndex: UInt32, hash: Data32, data: Data, length: UInt32, timeslot: TimeslotIndex) {
        self.serviceIndex = serviceIndex
        self.hash = hash
        self.data = data
        self.length = length
        self.timeslot = timeslot
    }
}

public struct PreimagesPostState: Sendable, Equatable {
    public let updates: [PreimageUpdate]

    public init(updates: [PreimageUpdate]) {
        self.updates = updates
    }
}

public protocol Preimages {
    func get(serviceAccount index: ServiceIndex, preimageHash hash: Data32) async throws -> Data?
    func get(serviceAccount index: ServiceIndex, preimageHash hash: Data32, length: UInt32) async throws
        -> LimitedSizeArray<TimeslotIndex, ConstInt0, ConstInt3>?

    mutating func mergeWith(postState: PreimagesPostState) async throws
}

extension Preimages {
    public func updatePreimages(
        config _: ProtocolConfigRef,
        timeslot: TimeslotIndex,
        preimages: ExtrinsicPreimages,
        priorState: any Preimages
    ) async throws(PreimagesError) -> PreimagesPostState {
        let preimages = preimages.preimages
        var updates: [PreimageUpdate] = []

        for preimage in preimages {
            let hash = preimage.data.blake2b256hash()

            // check prior state
            let prevPreimageData = try await Result {
                try await priorState.get(serviceAccount: preimage.serviceIndex, preimageHash: hash)
            }.mapError { _ in PreimagesError.invalidServiceIndex }.get()

            guard prevPreimageData == nil else {
                throw PreimagesError.duplicatedPreimage
            }

            let requested = try? await priorState.get(
                serviceAccount: preimage.serviceIndex,
                preimageHash: hash,
                length: UInt32(preimage.data.count)
            )
            guard let requested else {
                throw PreimagesError.preimageNotSolicited
            }

            guard requested.isEmpty else {
                throw PreimagesError.preimageIsProvided
            }

            // check post-accumulation state
            // disregard, without prejudice, any preimages which due to effects of accumulation are no longer useful
            let stillRequested = try? await get(
                serviceAccount: preimage.serviceIndex,
                preimageHash: hash,
                length: UInt32(preimage.data.count)
            )
            guard let stillRequested, stillRequested.isEmpty else {
                continue
            }

            updates.append(PreimageUpdate(
                serviceIndex: preimage.serviceIndex,
                hash: hash,
                data: preimage.data,
                length: UInt32(preimage.data.count),
                timeslot: timeslot
            ))
        }

        return PreimagesPostState(updates: updates)
    }
}
