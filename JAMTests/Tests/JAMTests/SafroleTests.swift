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
    var epochMark: Header.EpochMarker?
    var ticketsMark: ConfigFixedSizeArray<
        Ticket,
        ProtocolConfig.EpochLength
    >?
}

extension OutputMarks: ScaleCodec.Encodable {
    init(config: ProtocolConfigRef, from decoder: inout some ScaleCodec.Decoder) throws {
        try self.init(
            epochMark: Optional(from: &decoder, decodeItem: { try Header.EpochMarker(config: config, from: &$0) }),
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

struct SafroleState {
    var tau: UInt32
    var eta: (Data32, Data32, Data32, Data32)
    var lambda: ConfigFixedSizeArray<
        ValidatorKey, ProtocolConfig.TotalNumberOfValidators
    >
    var kappa: ConfigFixedSizeArray<
        ValidatorKey, ProtocolConfig.TotalNumberOfValidators
    >
    var gammaK: ConfigFixedSizeArray<
        ValidatorKey, ProtocolConfig.TotalNumberOfValidators
    >
    var iota: ConfigFixedSizeArray<
        ValidatorKey, ProtocolConfig.TotalNumberOfValidators
    >
    var gammaA: ConfigLimitedSizeArray<
        Ticket,
        ProtocolConfig.Int0,
        ProtocolConfig.EpochLength
    >
    var gammaS: Either<
        ConfigFixedSizeArray<
            Ticket,
            ProtocolConfig.EpochLength
        >,
        ConfigFixedSizeArray<
            BandersnatchPublicKey,
            ProtocolConfig.EpochLength
        >
    >
    var gammaZ: BandersnatchRingVRFRoot
}

extension SafroleState: ScaleCodec.Encodable {
    init(config: ProtocolConfigRef, from decoder: inout some ScaleCodec.Decoder) throws {
        try self.init(
            tau: decoder.decode(),
            eta: decoder.decode(),
            lambda: ConfigFixedSizeArray(config: config, from: &decoder),
            kappa: ConfigFixedSizeArray(config: config, from: &decoder),
            gammaK: ConfigFixedSizeArray(config: config, from: &decoder),
            iota: ConfigFixedSizeArray(config: config, from: &decoder),
            gammaA: ConfigLimitedSizeArray(config: config, from: &decoder),
            gammaS: Either(
                from: &decoder,
                decodeLeft: { try ConfigFixedSizeArray(config: config, from: &$0) },
                decodeRight: { try ConfigFixedSizeArray(config: config, from: &$0) }
            ),
            gammaZ: decoder.decode()
        )
    }

    func encode(in encoder: inout some ScaleCodec.Encoder) throws {
        try encoder.encode(tau)
        try encoder.encode(eta)
        try encoder.encode(lambda)
        try encoder.encode(kappa)
        try encoder.encode(gammaK)
        try encoder.encode(iota)
        try encoder.encode(gammaA)
        try encoder.encode(gammaS)
        try encoder.encode(gammaZ)
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
        print(String(reflecting: testcase))
    }
}
