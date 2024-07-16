import Blockchain
import Foundation
import ScaleCodec
import Testing
import Utils

@testable import JAMTests

struct SafroleInput {
    var slot: UInt32
    var entropy: Data32
    var extrinsics: ExtrinsicTickets
}

extension SafroleInput: ScaleCodec.Encodable {
    init(config: ProtocolConfigRef, from decoder: inout some ScaleCodec.Decoder) throws {
        try self.init(
            slot: decoder.decode(),
            entropy: decoder.decode(),
            extrinsics: ExtrinsicTickets(config: config, from: &decoder)
        )
    }

    func encode(in encoder: inout some ScaleCodec.Encoder) throws {
        try encoder.encode(slot)
        try encoder.encode(entropy)
        try encoder.encode(extrinsics)
    }
}

struct OutputMarks {
    var epochMark: EpochMarker?
    var ticketsMark: ConfigFixedSizeArray<
        Ticket,
        ProtocolConfig.EpochLength
    >?
}

extension OutputMarks: ScaleCodec.Encodable {
    init(config: ProtocolConfigRef, from decoder: inout some ScaleCodec.Decoder) throws {
        try self.init(
            epochMark: Optional(from: &decoder, decodeItem: { try EpochMarker(config: config, from: &$0) }),
            ticketsMark: Optional(from: &decoder, decodeItem: { try ConfigFixedSizeArray(config: config, from: &$0) })
        )
    }

    func encode(in encoder: inout some ScaleCodec.Encoder) throws {
        try encoder.encode(epochMark)
        try encoder.encode(ticketsMark)
    }
}

enum SafroleOutput {
    case ok(OutputMarks)
    case err(UInt8)
}

extension SafroleOutput: ScaleCodec.Encodable {
    init(config: ProtocolConfigRef, from decoder: inout some ScaleCodec.Decoder) throws {
        let id = try decoder.decode(.enumCaseId)
        switch id {
        case 0:
            self = try .ok(OutputMarks(config: config, from: &decoder))
        case 1:
            self = try .err(decoder.decode())
        default:
            throw decoder.enumCaseError(for: id)
        }
    }

    func encode(in encoder: inout some ScaleCodec.Encoder) throws {
        switch self {
        case let .ok(marks):
            try encoder.encode(0, .enumCaseId)
            try marks.encode(in: &encoder)
        case let .err(error):
            try encoder.encode(1, .enumCaseId)
            try encoder.encode(error)
        }
    }
}

struct SafroleState: Equatable, Safrole {
    let config: ProtocolConfigRef

    // tau
    var timeslot: UInt32
    // eta
    var entropyPool: (Data32, Data32, Data32, Data32)
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

    public func mergeWith(postState: SafrolePostState) -> Self {
        Self(
            config: config,
            timeslot: postState.timeslot,
            entropyPool: postState.entropyPool,
            previousValidators: postState.previousValidators,
            currentValidators: postState.currentValidators,
            nextValidators: postState.nextValidators,
            validatorQueue: postState.validatorQueue,
            ticketsAccumulator: postState.ticketsAccumulator,
            ticketsOrKeys: postState.ticketsOrKeys,
            ticketsVerifier: postState.ticketsVerifier
        )
    }
}

extension SafroleState: ScaleCodec.Encodable {
    init(config: ProtocolConfigRef, from decoder: inout some ScaleCodec.Decoder) throws {
        try self.init(
            config: config,
            timeslot: decoder.decode(),
            entropyPool: decoder.decode(),
            previousValidators: ConfigFixedSizeArray(config: config, from: &decoder),
            currentValidators: ConfigFixedSizeArray(config: config, from: &decoder),
            nextValidators: ConfigFixedSizeArray(config: config, from: &decoder),
            validatorQueue: ConfigFixedSizeArray(config: config, from: &decoder),
            ticketsAccumulator: ConfigLimitedSizeArray(config: config, from: &decoder),
            ticketsOrKeys: Either(
                from: &decoder,
                decodeLeft: { try ConfigFixedSizeArray(config: config, from: &$0) },
                decodeRight: { try ConfigFixedSizeArray(config: config, from: &$0) }
            ),
            ticketsVerifier: decoder.decode()
        )
    }

    func encode(in encoder: inout some ScaleCodec.Encoder) throws {
        try encoder.encode(timeslot)
        try encoder.encode(entropyPool)
        try encoder.encode(previousValidators)
        try encoder.encode(currentValidators)
        try encoder.encode(nextValidators)
        try encoder.encode(validatorQueue)
        try encoder.encode(ticketsAccumulator)
        try encoder.encode(ticketsOrKeys)
        try encoder.encode(ticketsVerifier)
    }
}

struct SafroleTestcase: CustomStringConvertible {
    var description: String
    var input: SafroleInput
    var preState: SafroleState
    var output: SafroleOutput
    var postState: SafroleState
}

extension SafroleTestcase: ScaleCodec.Encodable {
    init(description: String, config: ProtocolConfigRef, from decoder: inout some ScaleCodec.Decoder) throws {
        try self.init(
            description: description,
            input: SafroleInput(config: config, from: &decoder),
            preState: SafroleState(config: config, from: &decoder),
            output: SafroleOutput(config: config, from: &decoder),
            postState: SafroleState(config: config, from: &decoder)
        )
    }

    func encode(in encoder: inout some ScaleCodec.Encoder) throws {
        try encoder.encode(input)
        try encoder.encode(preState)
        try encoder.encode(output)
        try encoder.encode(postState)
    }
}

enum SafroleTestVariants: String, CaseIterable {
    case tiny
    case full

    static let tinyConfig = {
        var config = ProtocolConfigRef.mainnet.value
        config.totalNumberOfValidators = 6
        config.epochLength = 12
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
            var decoder = LoggingDecoder(decoder: decoder(from: data), logger: NoopLogger())
            return try SafroleTestcase(description: $0.description, config: variant.config, from: &decoder)
        }
    }

    @Test(arguments: try SafroleTests.loadTests(variant: .tiny))
    func tinyTests(_ testcase: SafroleTestcase) throws {
        withKnownIssue("not yet implemented", isIntermittent: true) {
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
                    #expect(testcase.preState.mergeWith(postState: state) == testcase.postState)
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
    }
}
