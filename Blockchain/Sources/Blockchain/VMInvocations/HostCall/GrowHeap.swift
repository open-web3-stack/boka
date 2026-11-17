import PolkaVM
import Utils

/// Grow the writable heap, draining gas on exhaustion and preserving
/// the zone-aligned stack reservation.
public struct GrowHeap: HostCall {
    public static let identifier: UInt8 = 1

    public func call(config _: ProtocolConfigRef, state: VMState) async -> ExecOutcome {
        guard let bounds = state.heapPages else { return .exit(.panic(.trap)) }
        let requested: UInt64 = state.readRegister(Registers.Index(raw: 7))
        let target = requested > bounds.current && requested <= bounds.limit ? UInt32(requested) : bounds.current
        let cost = Gas(275 + UInt64(target - bounds.current) * 121)
        state.writeRegister(Registers.Index(raw: 7), bounds.current)
        guard state.getGas() >= GasInt(cost) else {
            state.consumeGas(Gas(max(0, state.getGas().value)))
            return .exit(.outOfGas)
        }
        state.consumeGas(cost)
        do {
            try state.growHeap(to: target)
            state.writeRegister(Registers.Index(raw: 7), target)
            return .continued
        } catch {
            return .exit(.panic(.trap))
        }
    }

    public func _callImpl(config _: ProtocolConfigRef, state _: VMState) async throws {}
}
