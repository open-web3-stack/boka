import Codec
import Foundation
import PolkaVM
import Utils

extension AccumulateFunction {
    public func invoke(
        config: ProtocolConfigRef,
        serviceIndex: ServiceIndex,
        code _: Data,
        serviceAccounts: [ServiceIndex: ServiceAccount],
        gas: Gas,
        arguments: [AccumulateArguments],
        validatorQueue: ConfigFixedSizeArray<
            ValidatorKey, ProtocolConfig.TotalNumberOfValidators
        >,
        authorizationQueue: ConfigFixedSizeArray<
            ConfigFixedSizeArray<
                Data32,
                ProtocolConfig.MaxAuthorizationsQueueItems
            >,
            ProtocolConfig.TotalNumberOfCores
        >,
        privilegedServices: PrivilegedServices,
        initialIndex: ServiceIndex,
        timeslot: TimeslotIndex
    ) throws -> (ctx: AccumlateResultContext, result: Data32?) {
        var defaultCtx = AccumlateResultContext(
            account: serviceAccounts[serviceIndex],
            authorizationQueue: authorizationQueue,
            validatorQueue: validatorQueue,
            serviceIndex: serviceIndex,
            transfers: [],
            newAccounts: [:],
            privilegedServices: privilegedServices
        )

        if serviceAccounts[serviceIndex]?.codeHash.data == nil {
            return (ctx: defaultCtx, result: nil)
        }

        defaultCtx.serviceIndex = try AccumulateContext.check(
            i: initialIndex & (serviceIndexModValue - 1) + 256,
            serviceAccounts: serviceAccounts
        )

        let ctx = AccumulateContext(
            context: (
                x: defaultCtx,
                y: defaultCtx,
                serviceIndex: serviceIndex,
                accounts: serviceAccounts,
                timeslot: timeslot
            ),
            config: config
        )
        let argument = try JamEncoder.encode(arguments)

        let (exitReason, _, _, output) = invokePVM(
            config: config,
            blob: serviceAccounts[serviceIndex]!.codeHash.data,
            pc: 10,
            gas: gas,
            argumentData: argument,
            ctx: ctx
        )

        return try collapse(exitReason: exitReason, output: output, context: ctx.context)
    }

    // collapse function C selects one of the two dimensions of context depending on whether the virtual
    // machine’s halt was regular or exceptional
    private func collapse(
        exitReason: ExitReason, output: Data?, context: AccumulateContext.ContextType
    ) throws -> (ctx: AccumlateResultContext, result: Data32?) {
        switch exitReason {
        case .halt:
            if let output, let o = Data32(output) {
                (ctx: context.x, result: o)
            } else {
                (ctx: context.x, result: nil)
            }
        default:
            (ctx: context.y, result: nil)
        }
    }
}
