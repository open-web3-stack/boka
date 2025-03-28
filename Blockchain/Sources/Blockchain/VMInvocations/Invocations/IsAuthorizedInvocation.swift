import Codec
import Foundation
import PolkaVM

public func isAuthorized(
    config: ProtocolConfigRef,
    serviceAccounts: some ServiceAccounts,
    package: WorkPackage,
    coreIndex: CoreIndex
) async throws -> Result<Data, WorkResultError> {
    let args = try JamEncoder.encode(package, coreIndex)
    let ctx = IsAuthorizedContext(config: config)
    let (exitReason, _, output) = try await invokePVM(
        config: config,
        blob: package.authorizationCode(serviceAccounts: serviceAccounts),
        pc: 0,
        gas: config.value.workPackageAuthorizerGas,
        argumentData: args,
        ctx: ctx
    )

    switch exitReason {
    case .outOfGas:
        return .failure(.outOfGas)
    case .panic(.trap):
        return .failure(.panic)
    default:
        if let output {
            return .success(output)
        } else {
            return .failure(.panic)
        }
    }
}
