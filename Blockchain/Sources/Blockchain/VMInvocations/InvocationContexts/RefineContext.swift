import Foundation
import PolkaVM
import TracingUtils

private let logger = Logger(label: "RefineContext")

public struct InnerPvm {
    public var code: Data
    public var memory: Memory
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

        if index == GasFn.identifier {
            return await GasFn().call(config: config, state: state)
        } else if index == HistoricalLookup.identifier {
            return await HistoricalLookup(
                context: context,
                service: service,
                serviceAccounts: serviceAccounts,
                lookupAnchorTimeslot: lookupAnchorTimeslot
            )
            .call(config: config, state: state)
        } else if index == Import.identifier {
            return await Import(context: context, importSegments: importSegments).call(config: config, state: state)
        } else if index == Export.identifier {
            return await Export(context: &context, exportSegmentOffset: exportSegmentOffset).call(config: config, state: state)
        } else if index == Machine.identifier {
            return await Machine(context: &context).call(config: config, state: state)
        } else if index == Peek.identifier {
            return await Peek(context: context).call(config: config, state: state)
        } else if index == Zero.identifier {
            return await Zero(context: &context).call(config: config, state: state)
        } else if index == Poke.identifier {
            return await Poke(context: &context).call(config: config, state: state)
        } else if index == VoidFn.identifier {
            return await VoidFn(context: &context).call(config: config, state: state)
        } else if index == Invoke.identifier {
            return await Invoke(context: &context).call(config: config, state: state)
        } else if index == Expunge.identifier {
            return await Expunge(context: &context).call(config: config, state: state)
        } else {
            state.consumeGas(Gas(10))
            state.writeRegister(Registers.Index(raw: 7), HostCallResultCode.WHAT.rawValue)
            return .continued
        }
    }
}
