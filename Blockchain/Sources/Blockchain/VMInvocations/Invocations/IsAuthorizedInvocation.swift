import Codec
import Foundation
import PolkaVM

public protocol IsAuthorizedFunction {
    func invoke(
        config: ProtocolConfigRef,
        package: WorkPackage,
        coreIndex: CoreIndex
    ) async throws -> Result<Data, WorkResultError>
}

extension IsAuthorizedFunction {
    public func invoke(
        config: ProtocolConfigRef,
        package: WorkPackage,
        coreIndex: CoreIndex
    ) async throws -> Result<Data, WorkResultError> {
        let args = try JamEncoder.encode(package, coreIndex)
        let ctx = IsAuthorizedContext(config: config)
        // TODO: change blob: package.authorizationCodeHash.data to parameterizationBlob
        let (exitReason, _, output) = await invokePVM(
            config: config,
            blob: package.parameterizationBlob,
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
}
