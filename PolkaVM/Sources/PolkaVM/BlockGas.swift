import Foundation
import Utils

/// GP 0.8.0 Appendix A pipeline model, including GP #559 cmov dependencies.
enum BlockGas {
    private struct Operation {
        var cycles = 2
        var slots = 1
        var units = [0, 0, 0, 0, 0]
        var sources: UInt16 = 0
        var destinations: UInt16 = 0
        var move = false
        var terminates = false
    }

    private enum Phase {
        case decoding, waiting, executing, executed
    }

    private struct Entry {
        var id: Int
        var phase = Phase.decoding
        var cycles: Int
        var dependencies: Set<Int>
        var registers: UInt16
        var units: [Int]
    }

    static func cost(program: ProgramCode, start: UInt32) -> Gas {
        var pc: UInt32? = start
        var cycles = 0
        var slots = 4
        var starts = 5
        var units = [4, 4, 4, 1, 1]
        var buffer: [Entry] = []
        var serial = 0
        while true {
            if let address = pc {
                let op = operation(program: program, pc: address)
                if op.slots <= slots, buffer.count < 32 {
                    slots -= op.slots
                    pc = op.terminates ? nil : address + program.skip(address) + 1
                    if op.move {
                        for i in buffer.indices {
                            if buffer[i].registers & op.sources != 0 {
                                buffer[i].registers |= op.destinations
                            } else {
                                buffer[i].registers &= ~op.destinations
                            }
                        }
                    } else {
                        let dependencies = Set(buffer.filter { $0.registers & op.sources != 0 }.map(\.id))
                        for i in buffer.indices {
                            buffer[i].registers &= ~op.destinations
                        }
                        buffer.append(Entry(id: serial, cycles: op.cycles, dependencies: dependencies,
                                            registers: op.destinations, units: op.units))
                        serial += 1
                    }
                    continue
                }
            }
            if starts > 0, let ready = buffer.firstIndex(where: { entry in
                entry.phase == .waiting && zip(entry.units, units).allSatisfy { $0 <= $1 }
                    && !buffer.contains { entry.dependencies.contains($0.id) && $0.cycles != 0 }
            }) {
                buffer[ready].phase = .executing
                for i in units.indices {
                    units[i] -= buffer[ready].units[i]
                }
                starts -= 1
                continue
            }
            if pc == nil, buffer.isEmpty {
                return Gas(max(cycles - 3, 1))
            }
            // All changes in a cycle use the previous pipeline state.
            let retired = buffer.prefix(while: { $0.phase == .executed }).count
            for i in buffer.indices {
                switch buffer[i].phase {
                case .decoding:
                    buffer[i].phase = .waiting
                case .executing:
                    if buffer[i].cycles == 1 {
                        for j in units.indices {
                            units[j] += buffer[i].units[j]
                        }
                    }
                    if buffer[i].cycles == 0 {
                        buffer[i].phase = .executed
                    } else {
                        buffer[i].cycles -= 1
                    }
                default:
                    break
                }
            }
            buffer.removeFirst(retired)
            cycles += 1
            slots = 4
            starts = 5
        }
    }

    private static func operation(program: ProgramCode, pc: UInt32) -> Operation {
        let skip = Int(program.skip(pc))

        func byte(_ offset: Int) -> UInt8 {
            let index = Int(pc) + offset
            guard offset == 0 || offset <= skip, index < program.code.count else { return 0 }
            return program.code[relative: index]
        }
        func register(_ value: UInt8) -> UInt16 {
            1 << min(value, 12)
        }

        let opcode = byte(0)
        let low = register(byte(1) & 15)
        let high = register(byte(1) >> 4)
        let third = register(byte(2))

        var op = Operation()
        switch opcode {
        case 20, 51 ... 58, 80:
            op.destinations = low
        case 50, 59 ... 62, 70 ... 73, 81 ... 90:
            op.sources = low
        case 100 ... 110, 124 ... 161:
            op.sources = high
            op.destinations = low
        case 120 ... 123, 170 ... 175:
            op.sources = low | high
        case 180:
            op.sources = high
            op.destinations = low
        case 190 ... 230:
            op.sources = low | high
            op.destinations = third
        default:
            break
        }

        if [147, 148, 218, 219].contains(opcode) {
            op.sources |= op.destinations
        }
        let overlaps = op.sources & op.destinations != 0
        let shiftOverlaps = low == third
        op.units[0] = 1

        switch opcode {
        case 0, 1:
            op.units[0] = 0
            op.terminates = true
        case 2:
            op.cycles = 40
            op.units[0] = 0
        case 10:
            op.cycles = 100
            op.slots = 4
        case 20:
            op.cycles = 1
            op.slots = 2
            op.units[0] = 0
        case 51:
            op.cycles = 1
            op.units[0] = 0
        case 40, 80:
            op.cycles = 15
            op.units[0] = 0
            op.terminates = true
        case 50, 180:
            op.cycles = 22
            op.units[0] = 0
            op.terminates = true
        case 30 ... 33, 59 ... 62, 70 ... 73, 120 ... 123:
            op.cycles = 25
            op.units[2] = 1
        case 52 ... 58, 124 ... 130:
            op.cycles = 25
            op.units[1] = 1
        case 81 ... 90, 170 ... 175:
            let immediateSize = opcode < 100 ? min(4, Int(byte(1) >> 4) % 8) : 0
            let length = min(4, max(0, skip - immediateSize - 1))
            var offset: UInt32 = 0
            for i in 0 ..< length {
                offset |= UInt32(byte(2 + immediateSize + i)) << (8 * i)
            }
            if length > 0, length < 4, offset & (1 << (length * 8 - 1)) != 0 {
                offset |= UInt32.max << (length * 8)
            }
            func unlikely(_ target: UInt32) -> Bool {
                guard target < program.code.count else { return true }
                return [0, 2].contains(program.code[relative: Int(target)])
            }
            op.cycles = unlikely(pc &+ offset) || unlikely(pc + UInt32(skip) + 1) ? 1 : 20
            op.terminates = true
        case 100:
            op.move = true
            op.cycles = 0
            op.units[0] = 0
        case 101 ... 104, 107 ... 109:
            op.cycles = 1
        case 105, 106:
            op.cycles = 2
            op.units[0] = 2
        case 110, 132 ... 134, 149, 151 ... 153, 158, 200, 201, 210 ... 212:
            op.cycles = 1
            op.slots = overlaps ? 1 : 2
        case 131, 138 ... 140, 160, 190, 191:
            op.cycles = 2
            op.slots = overlaps ? 2 : 3
        case 135, 192:
            op.cycles = 4
            op.slots = overlaps ? 2 : 3
            op.units[3] = 1
        case 150, 202:
            op.cycles = 3
            op.slots = overlaps ? 1 : 2
            op.units[3] = 1
        case 136, 137, 142, 143, 216, 217:
            op.cycles = 3
            op.slots = 3
        case 141:
            op.cycles = 3
            op.slots = 4
        case 144 ... 146, 161:
            op.cycles = 2
            op.slots = 4
        case 147, 148:
            op.cycles = 2
            op.slots = 3
        case 154, 224, 225:
            op.cycles = 2
            op.slots = 3
        case 155 ... 157, 159:
            op.cycles = 1
            op.slots = 3
        case 193 ... 196, 203 ... 206:
            op.cycles = 60
            op.slots = 4
            op.units[4] = 1
        case 197 ... 199, 221, 223:
            op.cycles = 2
            op.slots = shiftOverlaps ? 3 : 4
        case 207 ... 209, 220, 222:
            op.cycles = 1
            op.slots = shiftOverlaps ? 2 : 3
        case 213, 214:
            op.cycles = 4
            op.slots = 4
            op.units[3] = 1
        case 215:
            op.cycles = 6
            op.slots = 4
            op.units[3] = 1
        case 218, 219:
            op.cycles = 2
            op.slots = 2
        case 226:
            op.cycles = 2
            op.slots = overlaps ? 2 : 3
        case 227 ... 230:
            op.cycles = 3
            op.slots = overlaps ? 2 : 3
        default:
            op = Operation()
            op.terminates = true
        }

        return op
    }
}
