import Codec
import Foundation
import PolkaVM

public func isAuthorized(
    config: ProtocolConfigRef,
    serviceAccounts: some ServiceAccounts,
    package: WorkPackage,
    coreIndex: CoreIndex
) async throws -> (Result<Data, WorkResultError>, Gas) {
    let args = try JamEncoder.encode(package, coreIndex)
    let ctx = IsAuthorizedContext(config: config)
    let (exitReason, gasUsed, output) = try await invokePVM(
        config: config,
        blob: package.authorizationCode(serviceAccounts: serviceAccounts),
        pc: 0,
        gas: config.value.workPackageAuthorizerGas,
        argumentData: args,
        ctx: ctx
    )

    let result: Result<Data, WorkResultError> = switch exitReason {
    case .outOfGas:
        .failure(.outOfGas)
    case .panic(.trap):
        .failure(.panic)
    default:
        if let output {
            .success(output)
        } else {
            .failure(.panic)
        }
    }

    return (result, gasUsed)
}
