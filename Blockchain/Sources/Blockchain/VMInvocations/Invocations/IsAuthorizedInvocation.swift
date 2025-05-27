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
    let codeBlob = try await package.authorizationCode(serviceAccounts: serviceAccounts)
    guard let codeBlob else {
        return (.failure(.invalidCode), Gas(0))
    }
    guard codeBlob.count <= config.value.maxIsAuthorizedCodeSize else {
        return (.failure(.codeTooLarge), Gas(0))
    }

    let ctx = IsAuthorizedContext(config: config, package: package)
    let (exitReason, gasUsed, output) = await invokePVM(
        config: config,
        blob: codeBlob,
        pc: 0,
        gas: config.value.workPackageIsAuthorizedGas,
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
