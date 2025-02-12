import Foundation
import PolkaVM
import TracingUtils

private let logger = Logger(label: "RefineContext")

public struct InnerPvm {
    public var code: Data
    public var memory: GeneralMemory
    public var pc: UInt32
}

public class RefineContext: InvocationContext {
    public typealias ContextType = (
        pvms: [UInt64: InnerPvm],
        exports: [Data]
    )

    public let config: ProtocolConfigRef
    public var context: ContextType
    public let importSegments: [Data]
    public let exportSegmentOffset: UInt64
    public let service: ServiceIndex
    public let serviceAccounts: ServiceAccounts
    public let lookupAnchorTimeslot: TimeslotIndex

    public init(
        config: ProtocolConfigRef,
        context: ContextType,
        importSegments: [Data],
        exportSegmentOffset: UInt64,
        service: ServiceIndex,
        serviceAccounts: some ServiceAccounts,
        lookupAnchorTimeslot: TimeslotIndex
    ) {
        self.config = config
        self.context = context
        self.importSegments = importSegments
        self.exportSegmentOffset = exportSegmentOffset
        self.service = service
        self.serviceAccounts = serviceAccounts
        self.lookupAnchorTimeslot = lookupAnchorTimeslot
    }

    public func dispatch(index: UInt32, state: VMState) async -> ExecOutcome {
        logger.debug("dispatching host-call: \(index)")

        switch UInt8(index) {
        case GasFn.identifier:
            return await GasFn().call(config: config, state: state)
        case HistoricalLookup.identifier:
            return await HistoricalLookup(
                context: context,
                service: service,
                serviceAccounts: serviceAccounts,
                lookupAnchorTimeslot: lookupAnchorTimeslot
            )
            .call(config: config, state: state)
        case Import.identifier:
            return await Import(context: context, importSegments: importSegments).call(config: config, state: state)
        case Export.identifier:
            return await Export(context: &context, exportSegmentOffset: exportSegmentOffset).call(config: config, state: state)
        case Machine.identifier:
            return await Machine(context: &context).call(config: config, state: state)
        case Peek.identifier:
            return await Peek(context: context).call(config: config, state: state)
        case Zero.identifier:
            return await Zero(context: &context).call(config: config, state: state)
        case Poke.identifier:
            return await Poke(context: &context).call(config: config, state: state)
        case VoidFn.identifier:
            return await VoidFn(context: &context).call(config: config, state: state)
        case Invoke.identifier:
            return await Invoke(context: &context).call(config: config, state: state)
        case Expunge.identifier:
            return await Expunge(context: &context).call(config: config, state: state)
        case Log.identifier:
            return await Log(service: service).call(config: config, state: state)
        default:
            state.consumeGas(Gas(10))
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.WHAT.rawValue)
            return .continued
        }
    }
}
