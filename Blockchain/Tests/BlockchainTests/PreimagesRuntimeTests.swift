@testable import Blockchain
import Foundation
import Testing
import Utils

struct PreimagesRuntimeTests {
    private let config = ProtocolConfigRef.tiny
    private let service: ServiceIndex = 42

    @Test
    func updatePreimagesCreatesUpdatesForStillSolicitedEmptyRequests() async throws {
        let preimage = Data([1, 2, 3])
        let hash = preimage.blake2b256hash()
        let request = HashAndLength(hash: hash, length: UInt32(preimage.count))
        let prior = PreimageState(requests: [service: [request: []]])
        let current = PreimageState(requests: [service: [request: []]])

        let postState = try await current.updatePreimages(
            config: config,
            timeslot: 7,
            preimages: ExtrinsicPreimages(preimages: [.init(serviceIndex: service, data: preimage)]),
            priorState: prior,
        )

        #expect(postState.updates == [
            PreimageUpdate(
                serviceIndex: service,
                hash: hash,
                data: preimage,
                length: UInt32(preimage.count),
                timeslot: 7,
            ),
        ])
    }

    @Test
    func updatePreimagesRejectsDuplicateDataInPriorState() async {
        let preimage = Data([4, 5, 6])
        let hash = preimage.blake2b256hash()
        let request = HashAndLength(hash: hash, length: UInt32(preimage.count))
        let prior = PreimageState(
            preimageData: [service: [hash: preimage]],
            requests: [service: [request: []]],
        )
        let current = PreimageState(requests: [service: [request: []]])

        await expectPreimagesError(.duplicatedPreimage) {
            _ = try await current.updatePreimages(
                config: config,
                timeslot: 7,
                preimages: ExtrinsicPreimages(preimages: [.init(serviceIndex: service, data: preimage)]),
                priorState: prior,
            )
        }
    }

    @Test
    func updatePreimagesRejectsUnsolicitedPreimage() async {
        let preimage = Data([7, 8, 9])
        let prior = PreimageState()
        let current = PreimageState()

        await expectPreimagesError(.preimageNotSolicited) {
            _ = try await current.updatePreimages(
                config: config,
                timeslot: 7,
                preimages: ExtrinsicPreimages(preimages: [.init(serviceIndex: service, data: preimage)]),
                priorState: prior,
            )
        }
    }

    @Test
    func updatePreimagesRejectsAlreadyProvidedRequest() async {
        let preimage = Data([10, 11, 12])
        let hash = preimage.blake2b256hash()
        let request = HashAndLength(hash: hash, length: UInt32(preimage.count))
        let prior = PreimageState(requests: [service: [request: [3]]])
        let current = PreimageState(requests: [service: [request: []]])

        await expectPreimagesError(.preimageIsProvided) {
            _ = try await current.updatePreimages(
                config: config,
                timeslot: 7,
                preimages: ExtrinsicPreimages(preimages: [.init(serviceIndex: service, data: preimage)]),
                priorState: prior,
            )
        }
    }

    @Test
    func updatePreimagesSkipsRequestsNoLongerNeededAfterAccumulation() async throws {
        let preimage = Data([13, 14, 15])
        let hash = preimage.blake2b256hash()
        let request = HashAndLength(hash: hash, length: UInt32(preimage.count))
        let prior = PreimageState(requests: [service: [request: []]])
        let current = PreimageState()

        let postState = try await current.updatePreimages(
            config: config,
            timeslot: 7,
            preimages: ExtrinsicPreimages(preimages: [.init(serviceIndex: service, data: preimage)]),
            priorState: prior,
        )

        #expect(postState.updates.isEmpty)
    }

    private func expectPreimagesError(
        _ expected: PreimagesError,
        operation: () async throws -> Void,
    ) async {
        do {
            try await operation()
            Issue.record("Expected \(expected)")
        } catch let error as PreimagesError {
            #expect(samePreimagesError(error, expected))
        } catch {
            Issue.record("Expected \(expected), got \(error)")
        }
    }
}

private struct PreimageState: Preimages {
    var preimageData: [ServiceIndex: [Data32: Data]] = [:]
    var requests: [ServiceIndex: [HashAndLength: LimitedSizeArray<TimeslotIndex, ConstInt0, ConstInt3>]] = [:]

    func get(serviceAccount index: ServiceIndex, preimageHash hash: Data32) async throws -> Data? {
        preimageData[index]?[hash]
    }

    func get(
        serviceAccount index: ServiceIndex,
        preimageHash hash: Data32,
        length: UInt32,
    ) async throws -> LimitedSizeArray<TimeslotIndex, ConstInt0, ConstInt3>? {
        requests[index]?[HashAndLength(hash: hash, length: length)]
    }

    mutating func mergeWith(postState: PreimagesPostState) async throws {
        for update in postState.updates {
            preimageData[update.serviceIndex, default: [:]][update.hash] = update.data
            requests[update.serviceIndex, default: [:]][
                HashAndLength(hash: update.hash, length: update.length)
            ] = [update.timeslot]
        }
    }
}

private func samePreimagesError(_ lhs: PreimagesError, _ rhs: PreimagesError) -> Bool {
    switch (lhs, rhs) {
    case (.preimagesNotSorted, .preimagesNotSorted),
         (.duplicatedPreimage, .duplicatedPreimage),
         (.invalidServiceIndex, .invalidServiceIndex),
         (.preimageNotSolicited, .preimageNotSolicited),
         (.preimageIsProvided, .preimageIsProvided):
        true
    default:
        false
    }
}

