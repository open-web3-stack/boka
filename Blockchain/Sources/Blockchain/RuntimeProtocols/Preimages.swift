import Foundation
import Utils

public enum PreimagesError: Error {
    case preimagesNotSorted
    case duplicatedPreimage
    case invalidServiceIndex
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

public protocol Preimages: ServiceAccounts {
    mutating func mergeWith(postState: PreimagesPostState)
}

extension Preimages {
    public func updatePreimages(
        config _: ProtocolConfigRef,
        timeslot: TimeslotIndex,
        preimages: ExtrinsicPreimages
    ) async throws(PreimagesError) -> PreimagesPostState {
        let preimages = preimages.preimages
        var updates: [PreimageUpdate] = []

        guard preimages.isSortedAndUnique() else {
            throw PreimagesError.preimagesNotSorted
        }

        for preimage in preimages {
            let hash = preimage.data.blake2b256hash()

            // check prior state
            let prevPreimageData = try await Result {
                try await get(serviceAccount: preimage.serviceIndex, preimageHash: hash)
            }.mapError { _ in PreimagesError.invalidServiceIndex }.get()
            let prevInfo = try await Result {
                try await get(serviceAccount: preimage.serviceIndex, preimageHash: hash, length: UInt32(preimage.data.count))
            }.mapError { _ in PreimagesError.invalidServiceIndex }.get()

            guard prevPreimageData == nil, prevInfo == nil else {
                throw PreimagesError.duplicatedPreimage
            }

            // disregard no longer useful ones in new state
            let preimageData = try await Result {
                try await self.get(serviceAccount: preimage.serviceIndex, preimageHash: hash)
            }.mapError { _ in PreimagesError.invalidServiceIndex }.get()
            let info = try await Result {
                try await self.get(serviceAccount: preimage.serviceIndex, preimageHash: hash, length: UInt32(preimage.data.count))
            }.mapError { _ in PreimagesError.invalidServiceIndex }.get()

            if preimageData != nil || info != nil {
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
