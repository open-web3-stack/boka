import Foundation
import ScaleCodec
import Utils

public struct WorkResult: Sendable {
    // s: the index of the service whose state is to be altered and thus whose refine code was already executed
    public var serviceIdentifier: ServiceIdentifier

    // c: the hash of the code of the service at the time of being reported
    public var codeHash: Data32

    // l: the hash of the payload
    public var payloadHash: Data32

    // g: the gas prioritization ratio
    // used when determining how much gas should be allocated to execute of this item’s accumulate
    public var gas: Gas

    // o: there is the output or error of the execution of the code o
    // which may be either an octet sequence in case it was successful, or a member of the set J, if not
    public var output: Result<Data, WorkResultError>

    public init(
        serviceIdentifier: ServiceIdentifier,
        codeHash: Data32,
        payloadHash: Data32,
        gas: Gas,
        output: Result<Data, WorkResultError>
    ) {
        self.serviceIdentifier = serviceIdentifier
        self.codeHash = codeHash
        self.payloadHash = payloadHash
        self.gas = gas
        self.output = output
    }
}

extension WorkResult: Dummy {
    public typealias Config = ProtocolConfigRef
    public static func dummy(config _: Config) -> WorkResult {
        WorkResult(
            serviceIdentifier: ServiceIdentifier(),
            codeHash: Data32(),
            payloadHash: Data32(),
            gas: 0,
            output: .success(Data())
        )
    }
}

extension WorkResult: ScaleCodec.Codable {
    public init(from decoder: inout some ScaleCodec.Decoder) throws {
        try self.init(
            serviceIdentifier: decoder.decode(),
            codeHash: decoder.decode(),
            payloadHash: decoder.decode(),
            gas: decoder.decode(),
            output: decoder.decode()
        )
    }

    public func encode(in encoder: inout some ScaleCodec.Encoder) throws {
        try encoder.encode(serviceIdentifier)
        try encoder.encode(codeHash)
        try encoder.encode(payloadHash)
        try encoder.encode(gas)
        try encoder.encode(output)
    }
}
