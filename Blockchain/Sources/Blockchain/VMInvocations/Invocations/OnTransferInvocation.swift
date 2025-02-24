import Codec
import Foundation
import PolkaVM
import Utils

public func onTransfer(
    config: ProtocolConfigRef,
    serviceIndex: ServiceIndex,
    serviceAccounts: inout some ServiceAccounts,
    timeslot: TimeslotIndex,
    transfers: [DeferredTransfers]
) async throws {
    guard var account = try await serviceAccounts.get(serviceAccount: serviceIndex),
          let codeBlob = try await serviceAccounts.get(serviceAccount: serviceIndex, preimageHash: account.codeHash),
          !transfers.isEmpty
    else {
        return
    }

    account.balance += transfers.reduce(Balance(0)) { $0 + $1.amount }

    var contextContent = OnTransferContext.ContextType(serviceIndex, serviceAccounts)
    let ctx = OnTransferContext(context: &contextContent, config: config)
    let gasLimitSum = transfers.reduce(Balance(0)) { $0 + $1.gasLimit }
    let argument = try JamEncoder.encode(timeslot, serviceIndex, transfers)

    _ = await invokePVM(
        config: config,
        blob: codeBlob,
        pc: 10,
        gas: gasLimitSum,
        argumentData: argument,
        ctx: ctx
    )
}
