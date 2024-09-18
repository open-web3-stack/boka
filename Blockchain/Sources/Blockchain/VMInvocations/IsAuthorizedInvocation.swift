import Codec
import Foundation
import PolkaVM

public protocol IsAuthorizedFunction {
    func invoke(
        config: ProtocolConfigRef,
        package: WorkPackage,
        coreIndex: CoreIndex
    ) throws -> Result<Data, WorkResultError>
}

extension IsAuthorizedFunction {
    public func invoke(config: ProtocolConfigRef, package: WorkPackage, coreIndex: CoreIndex) throws -> Result<Data, WorkResultError> {
        let args = try JamEncoder.encode(package) + JamEncoder.encode(coreIndex)
        let ctx = IsAuthorizedContext()

        let (exitReason, _, _, output) = invokePVM(
            config: config,
            blob: package.authorizationCodeHash.data,
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
