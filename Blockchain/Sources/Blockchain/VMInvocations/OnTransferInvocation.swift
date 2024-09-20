import Codec
import Foundation
import PolkaVM

extension OnTransferFunction {
    public func invoke(
        config: ProtocolConfigRef,
        service: ServiceIndex,
        code _: Data,
        serviceAccounts: [ServiceIndex: ServiceAccount],
        transfers: [DeferredTransfers]
    ) throws -> ServiceAccount {
        guard var account = serviceAccounts[service] else {
            throw VMInvocationsError.serviceAccountNotFound
        }

        account.balance += transfers.reduce(0) { $0 + $1.amount }

        if account.codeHash.data.isEmpty || transfers.isEmpty {
            return account
        }

        let ctx = OnTransferContext(context: (account, service, serviceAccounts), config: config)
        let gasLimitSum = transfers.reduce(0) { $0 + $1.gasLimit }
        let argument = try JamEncoder.encode(transfers)

        _ = invokePVM(
            config: config,
            blob: account.codeHash.data,
            pc: 3,
            gas: gasLimitSum,
            argumentData: argument,
            ctx: ctx
        )

        return ctx.context.0
    }
}
