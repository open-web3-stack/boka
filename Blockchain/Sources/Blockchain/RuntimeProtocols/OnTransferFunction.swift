import Foundation

public protocol OnTransferFunction {
    func invoke(
        config: ProtocolConfigRef,
        service: ServiceIndex,
        serviceAccounts: inout some ServiceAccounts,
        timeslot: TimeslotIndex,
        transfers: [DeferredTransfers]
    ) async throws
}
