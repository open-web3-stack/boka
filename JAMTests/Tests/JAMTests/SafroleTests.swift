import Blockchain
import Codec
import Foundation
import Testing
import Utils

@testable import JAMTests

struct SafroleInput: Codable {
    var slot: UInt32
    var entropy: Data32
    var extrinsics: ExtrinsicTickets
}

struct OutputMarks: Codable {
    var epochMark: EpochMarker?
    var ticketsMark: ConfigFixedSizeArray<
        Ticket,
        ProtocolConfig.EpochLength
    >?
}

struct SafroleState: Equatable, Safrole, Codable {
    enum CodingKeys: String, CodingKey {
        case timeslot
        case entropyPool
        case previousValidators
        case currentValidators
        case nextValidators
        case validatorQueue
        case ticketsAccumulator
        case ticketsOrKeys
        case ticketsVerifier
    }

    // tau
    var timeslot: UInt32
    // eta
    var entropyPool: EntropyPool
    // lambda
    var previousValidators: ConfigFixedSizeArray<
        ValidatorKey, ProtocolConfig.TotalNumberOfValidators
    >
    // kappa
    var currentValidators: ConfigFixedSizeArray<
        ValidatorKey, ProtocolConfig.TotalNumberOfValidators
    >
    // gammaK
    var nextValidators: ConfigFixedSizeArray<
        ValidatorKey, ProtocolConfig.TotalNumberOfValidators
    >
    // iota
    var validatorQueue: ConfigFixedSizeArray<
        ValidatorKey, ProtocolConfig.TotalNumberOfValidators
    >
    // gammaA
    var ticketsAccumulator: ConfigLimitedSizeArray<
        Ticket,
        ProtocolConfig.Int0,
        ProtocolConfig.EpochLength
    >
    // gammaS
    var ticketsOrKeys: Either<
        ConfigFixedSizeArray<
            Ticket,
            ProtocolConfig.EpochLength
        >,
        ConfigFixedSizeArray<
            BandersnatchPublicKey,
            ProtocolConfig.EpochLength
        >
    >
    // gammaZ
    var ticketsVerifier: BandersnatchRingVRFRoot

    public mutating func mergeWith(postState: SafrolePostState) {
        timeslot = postState.timeslot
        entropyPool = postState.entropyPool
        previousValidators = postState.previousValidators
        currentValidators = postState.currentValidators
        nextValidators = postState.nextValidators
        validatorQueue = postState.validatorQueue
        ticketsAccumulator = postState.ticketsAccumulator
        ticketsOrKeys = postState.ticketsOrKeys
        ticketsVerifier = postState.ticketsVerifier
    }
}

struct SafroleTestcase: Codable {
    var input: SafroleInput
    var preState: SafroleState
    var output: Either<OutputMarks, UInt8>
    var postState: SafroleState
}

struct Testcase: CustomStringConvertible {
    var description: String
    var data: Data
}

enum SafroleTestVariants: String, CaseIterable {
    case tiny
    case full

    static let tinyConfig = {
        var config = ProtocolConfigRef.mainnet.value
        config.totalNumberOfValidators = 6
        config.epochLength = 12
        // 10 = 12 * 500/600, not sure what this should be for tiny, but this passes tests
        config.ticketSubmissionEndSlot = 10
        return Ref(config)
    }()

    var config: ProtocolConfigRef {
        switch self {
        case .tiny:
            Self.tinyConfig
        case .full:
            ProtocolConfigRef.mainnet
        }
    }
}

final class SafroleTests {
    static func loadTests(variant: SafroleTestVariants) throws -> [Testcase] {
        let tests = try TestLoader.getTestFiles(path: "safrole/\(variant)", extension: "scale")
        return try tests.map { path, description in
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            return Testcase(description: description, data: data)
        }
    }

    func safroleTests(_ input: Testcase, variant: SafroleTestVariants) throws {
        let config = variant.config
        let testcase = try JamDecoder.decode(SafroleTestcase.self, from: input.data, withConfig: config)

        let result = Result {
            try testcase.preState.updateSafrole(
                config: config,
                slot: testcase.input.slot,
                entropy: testcase.input.entropy,
                extrinsics: testcase.input.extrinsics
            )
        }
        switch result {
        case let .success((state, epochMark, ticketsMark)):
            switch testcase.output {
            case let .left(marks):
                #expect(epochMark == marks.epochMark)
                #expect(ticketsMark == marks.ticketsMark)
                var postState = testcase.preState
                postState.mergeWith(postState: state)
                #expect(postState == testcase.postState)
            case .right:
                Issue.record("Expected error, got \(result)")
            }
        case .failure:
            switch testcase.output {
            case .left:
                Issue.record("Expected success, got \(result)")
            case .right:
                // ignore error code because it is unspecified
                break
            }
        }
    }

    @Test(arguments: try SafroleTests.loadTests(variant: .tiny))
    func tinyTests(_ testcase: Testcase) throws {
        try safroleTests(testcase, variant: .tiny)
    }

    @Test(arguments: try SafroleTests.loadTests(variant: .full))
    func fullTests(_ testcase: Testcase) throws {
        try safroleTests(testcase, variant: .full)
    }
}
