import Codec
import Foundation
import Utils

// L
public struct WorkResult: Sendable, Equatable, Codable {
    // s: the index of the service whose state is to be altered and thus whose refine code was already executed
    public var serviceIndex: ServiceIndex

    // c: the hash of the code of the service at the time of being reported
    public var codeHash: Data32

    // l: the hash of the payload
    public var payloadHash: Data32

    // g: the gas prioritization ratio
    // used when determining how much gas should be allocated to execute of this item’s accumulate
    public var gas: Gas

    // o: there is the output or error of the execution of the code o
    // which may be either an octet sequence in case it was successful, or a member of the set J, if not
    public var output: WorkOutput

    public init(
        serviceIndex: ServiceIndex,
        codeHash: Data32,
        payloadHash: Data32,
        gas: Gas,
        output: WorkOutput
    ) {
        self.serviceIndex = serviceIndex
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
            serviceIndex: 0,
            codeHash: Data32(),
            payloadHash: Data32(),
            gas: 0,
            output: .init(.success(Data()))
        )
    }
}

extension WorkResult: EncodedSize {
    public var encodedSize: Int {
        serviceIndex.encodedSize + codeHash.encodedSize + payloadHash.encodedSize + gas.encodedSize + output.encodedSize
    }

    public static var encodeedSizeHint: Int? {
        nil
    }
}
