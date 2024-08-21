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

enum SafroleOutput: Codable {
    case ok(OutputMarks)
    case err(UInt8)
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

    let config: ProtocolConfigRef = .dev

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

    public static func == (lhs: SafroleState, rhs: SafroleState) -> Bool {
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

struct SafroleTestcase: CustomStringConvertible, Codable {
    enum CodingKeys: String, CodingKey {
        case input
        case preState
        case output
        case postState
    }

    var description: String = ""
    var input: SafroleInput
    var preState: SafroleState
    var output: SafroleOutput
    var postState: SafroleState
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

struct SafroleTests {
    static func loadTests(variant: SafroleTestVariants) throws -> [SafroleTestcase] {
        let tests = try TestLoader.getTestFiles(path: "safrole/\(variant)", extension: "scale")
        return try tests.map {
            let data = try Data(contentsOf: URL(fileURLWithPath: $0.path))
            let decoder = JamDecoder()
            return try decoder.decode(SafroleTestcase.self, from: data, withConfig: variant.config)
        }
    }

    func safroleTests(_ testcase: SafroleTestcase) throws {
        let result = testcase.preState.updateSafrole(
            slot: testcase.input.slot,
            entropy: testcase.input.entropy,
            extrinsics: testcase.input.extrinsics
        )
        switch result {
        case let .success((state, epochMark, ticketsMark)):
            switch testcase.output {
            case let .ok(marks):
                #expect(epochMark == marks.epochMark)
                #expect(ticketsMark == marks.ticketsMark)
                var postState = testcase.preState
                postState.mergeWith(postState: state)
                #expect(postState == testcase.postState)
            case .err:
                Issue.record("Expected error, got \(result)")
            }
        case .failure:
            switch testcase.output {
            case .ok:
                Issue.record("Expected success, got \(result)")
            case .err:
                // ignore error code because it is unspecified
                break
            }
        }
    }

    @Test(arguments: try SafroleTests.loadTests(variant: .tiny))
    func tinyTests(_ testcase: SafroleTestcase) throws {
        try safroleTests(testcase)
    }

    @Test(arguments: try SafroleTests.loadTests(variant: .full))
    func fullTests(_ testcase: SafroleTestcase) throws {
        try safroleTests(testcase)
    }
}
