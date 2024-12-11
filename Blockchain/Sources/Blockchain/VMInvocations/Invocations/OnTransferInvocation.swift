import Codec
import Foundation
import PolkaVM
import Utils

extension OnTransferFunction {
    public func invoke(
        config: ProtocolConfigRef,
        service: ServiceIndex,
        serviceAccounts: inout some ServiceAccounts,
        timeslot: TimeslotIndex,
        transfers: [DeferredTransfers]
    ) async throws {
        guard var account = try await serviceAccounts.get(serviceAccount: service) else {
            throw VMInvocationsError.serviceAccountNotFound
        }

        account.balance += transfers.reduce(Balance(0)) { $0 + $1.amount }

        if account.codeHash.data.isEmpty || transfers.isEmpty {
            return
        }

        var contextContent = OnTransferContext.ContextType(service, serviceAccounts)
        let ctx = OnTransferContext(context: &contextContent, config: config)
        let gasLimitSum = transfers.reduce(Balance(0)) { $0 + $1.gasLimit }
        let argument = try JamEncoder.encode(timeslot) + JamEncoder.encode(service) + JamEncoder.encode(transfers)

        _ = await invokePVM(
            config: config,
            blob: account.codeHash.data,
            pc: 10,
            gas: gasLimitSum,
            argumentData: argument,
            ctx: ctx
        )
    }
}
