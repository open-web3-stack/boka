import Codec
import Foundation
import PolkaVM
import Utils

public func onTransfer(
    config: ProtocolConfigRef,
    serviceIndex: ServiceIndex,
    serviceAccounts: ServiceAccountsMutRef,
    timeslot: TimeslotIndex,
    transfers: [DeferredTransfers]
) async throws -> Gas {
    guard var account = try await serviceAccounts.value.get(serviceAccount: serviceIndex),
          let preimage = try await serviceAccounts.value.get(serviceAccount: serviceIndex, preimageHash: account.codeHash),
          !transfers.isEmpty
    else {
        return Gas(0)
    }

    let codeBlob = try CodeAndMeta(data: preimage).codeBlob

    account.balance += transfers.reduce(Balance(0)) { $0 + $1.amount }

    serviceAccounts.set(serviceAccount: serviceIndex, account: account)

    let contextContent = OnTransferContext.ContextType(serviceIndex: serviceIndex, accounts: serviceAccounts)
    let ctx = OnTransferContext(context: contextContent, config: config)
    let gasLimitSum = transfers.reduce(Balance(0)) { $0 + $1.gasLimit }
    let argument = try JamEncoder.encode(timeslot, serviceIndex, transfers)

    let (_, gas, _) = await invokePVM(
        config: config,
        blob: codeBlob,
        pc: 10,
        gas: gasLimitSum,
        argumentData: argument,
        ctx: ctx
    )

    return gas
}
