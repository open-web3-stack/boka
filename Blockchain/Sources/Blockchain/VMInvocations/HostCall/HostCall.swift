import PolkaVM
import TracingUtils
import Utils

private let logger = Logger(label: "HostCall ")

public protocol HostCall {
    static var identifier: UInt8 { get }

    func gasCost(state: VMState) -> Gas
    func _callImpl(config: ProtocolConfigRef, state: VMState) async throws
}

extension HostCall {
    public func call(config: ProtocolConfigRef, state: VMState) async -> ExecOutcome {
        logger.debug("===== host call: \(Self.self) =====")
        let cost = gasCost(state: state)
        state.consumeGas(cost)
        logger.debug("consumed \(cost) gas, \(state.getGas()) left")

        guard state.getGas() >= GasInt(0) else {
            logger.trace("not enough gas")
            return .exit(.outOfGas)
        }

        do {
            try await _callImpl(config: config, state: state)
            return .continued
        } catch let e as MemoryError {
            logger.trace("memory error: \(e)")
            return .exit(.pageFault(e.address))
        } catch VMInvocationsError.forceHalt {
            logger.trace("force halt")
            return .exit(.halt)
        } catch let e as VMInvocationsError {
            logger.trace("invocation error: \(e)")
            return .exit(.panic(.trap))
        } catch let e {
            logger.trace("unknown error: \(e)")
            return .exit(.panic(.trap))
        }
    }

    public func gasCost(state: VMState) -> Gas {
        func register(_ index: Int) -> UInt64 {
            state.readRegister(Registers.Index(raw: UInt8(index)))
        }
        func memory(_ rate: UInt64, _ index: Int) -> Gas {
            let size = register(index)
            // Divide first to preserve ceil(rate * size / 1024) without overflow.
            return Gas(size / 1024) * rate + Gas((size % 1024 * rate + 1023) / 1024)
        }
        switch Self.identifier {
        case 0:
            return Gas(48)
        case 2:
            let bases: [UInt64] = [390, 103, 80, 85, 85, 171, 171, 85, 84, 88, 111, 317, 250, 95, 287, 355]
            let rates: [UInt64] = [0, 0, 96, 96, 96, 0, 0, 96, 0, 0, 0, 0, 0, 96, 400, 344]
            let selector = register(10)
            guard selector < 16 else {
                return Gas(80)
            }
            return Gas(bases[Int(selector)]) + memory(rates[Int(selector)], 9)
        case 3:
            return Gas(600) + memory(248, 11)
        case 4:
            return Gas(2407) + memory(1736, 9) + memory(248, 12)
        case 5:
            return Gas(2442) + memory(3358, 8) + memory(216, 10)
        case 6:
            return Gas(703)
        case 7:
            return Gas(1125) + memory(264, 11)
        case 8:
            return Gas(3521)
        case 9:
            return Gas(1862) + memory(112, 8)
        case 10:
            return Gas(377) + memory(336, 10)
        case 11:
            return Gas(297) + memory(224, 10)
        case 12:
            switch register(10) {
            case 0:
                return Gas(212) + Gas(register(9)) * 118
            case 1, 2:
                return Gas(275) + Gas(register(9)) * 121
            case 3, 4:
                return Gas(130) + Gas(register(9)) * 29
            default:
                return Gas(80)
            }
        case 13:
            return Gas(968)
        case 14:
            return Gas(335)
        case 15:
            return Gas(422) + Gas(register(12)) * 20
        case 16:
            return Gas(1818)
        case 17:
            return Gas(1100) + Gas(register(8)) * 302
        case 18:
            return Gas(103)
        case 19:
            return Gas(3855)
        case 20:
            return Gas(1028)
        case 21:
            return Gas(575)
        case 22:
            return Gas(458)
        case 23:
            return Gas(643)
        case 24:
            return Gas(2193)
        case 25:
            return Gas(3250)
        case 26:
            return Gas(98)
        case 27:
            return Gas(3980) + memory(2264, 9)
        default:
            return Gas(1000)
        }
    }
}
