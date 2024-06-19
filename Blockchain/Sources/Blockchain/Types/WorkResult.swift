import Foundation
import Utils

public struct WorkResult {
    // s: the index of the service whose state is to be altered and thus whose refine code was already executed
    public var serviceIdentifier: ServiceIdentifier

    // c: the hash of the code of the service at the time of being reported
    public var codeHash: H256

    // l: the hash of the payload
    public var payloadHash: H256

    // g: the gas prioritization ratio
    // used when determining how much gas should be allocated to execute of this item’s accumulate
    public var gas: Gas

    // o: there is the output or error of the execution of the code o
    // which may be either an octet sequence in case it was successful, or a member of the set J, if not
    public var output: Result<Data, WorkResultError>

    public init(
        serviceIdentifier: ServiceIdentifier,
        codeHash: H256,
        payloadHash: H256,
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

public enum WorkResultError: Error {
    case outofGas
    case panic
    case invalidCode
    case codeTooLarge // code larger than MaxServiceCodeSize
}

extension WorkResult: Dummy {
    public static var dummy: WorkResult {
        WorkResult(
            serviceIdentifier: ServiceIdentifier(),
            codeHash: H256(),
            payloadHash: H256(),
            gas: 0,
            output: .success(Data())
        )
    }
}
