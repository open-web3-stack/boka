import Foundation

public protocol OnTransferFunction {
    func invoke(
        config: ProtocolConfigRef,
        service: ServiceIndex,
        code: Data,
        serviceAccounts: inout some ServiceAccounts,
        transfers: [DeferredTransfers]
    ) async throws
}
