import Foundation

public protocol OnTransferFunction {
    func invoke(
        config: ProtocolConfigRef,
        service: ServiceIndex,
        code: Data,
        serviceAccounts: [ServiceIndex: ServiceAccount],
        transfers: [DeferredTransfers]
    ) throws -> ServiceAccount
}
