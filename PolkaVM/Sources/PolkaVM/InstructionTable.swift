import Foundation
import Utils

public class InstructionTable {
    public static let table: [Instruction.Type?] = {
        let insts: [Instruction.Type] = [
            Instructions.Trap.self,
            Instructions.Fallthrough.self,
            Instructions.Ecalli.self,
            Instructions.StoreImmU8.self,
            Instructions.StoreImmU16.self,
            Instructions.StoreImmU32.self,
            Instructions.JumpInd.self,
            Instructions.LoadImm.self,
            Instructions.LoadU8.self,
            Instructions.LoadI8.self,
            Instructions.LoadU16.self,
            Instructions.LoadI16.self,
            Instructions.LoadU32.self,
            Instructions.StoreU8.self,
            Instructions.StoreU16.self,
            Instructions.StoreU32.self,
        ]
        var table: [Instruction.Type?] = Array(repeating: nil, count: 256)
        for i in 0 ..< insts.count {
            table[Int(insts[i].opcode)] = insts[i]
        }
        return table
    }()

    public static func parse(_ data: Data) -> (any Instruction)? {
        guard data.count >= 1 else {
            return nil
        }
        let opcode = data[data.startIndex]
        guard let instType = table[Int(opcode)] else {
            return nil
        }
        // TODO: log errors
        return try? instType.init(data: data[relative: 1...])
    }
}
