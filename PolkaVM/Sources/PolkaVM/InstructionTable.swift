import Foundation
import TracingUtils
import Utils

private let logger = Logger(label: "InstructionTable")

public class InstructionTable {
    public static let table: [Instruction.Type?] = {
        let insts: [Instruction.Type] = [
            Instructions.Trap.self,
            Instructions.Fallthrough.self,
            Instructions.Ecalli.self,
            Instructions.StoreImmU8.self,
            Instructions.StoreImmU16.self,
            Instructions.StoreImmU32.self,
            Instructions.Jump.self,
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
            Instructions.StoreImmIndU8.self,
            Instructions.StoreImmIndU16.self,
            Instructions.StoreImmIndU32.self,
            Instructions.LoadImmJump.self,
            Instructions.BranchEqImm.self,
            Instructions.BranchNeImm.self,
            Instructions.BranchLtUImm.self,
            Instructions.BranchLeUImm.self,
            Instructions.BranchGeUImm.self,
            Instructions.BranchGtUImm.self,
            Instructions.BranchLtSImm.self,
            Instructions.BranchLeSImm.self,
            Instructions.BranchGeSImm.self,
            Instructions.BranchGtSImm.self,
            Instructions.MoveReg.self,
            Instructions.Sbrk.self,
            Instructions.StoreIndU8.self,
            Instructions.StoreIndU16.self,
            Instructions.StoreIndU32.self,
            Instructions.LoadIndU8.self,
            Instructions.LoadIndI8.self,
            Instructions.LoadIndU16.self,
            Instructions.LoadIndI16.self,
            Instructions.LoadIndU32.self,
            Instructions.AddImm.self,
            Instructions.AndImm.self,
            Instructions.XorImm.self,
            Instructions.OrImm.self,
            Instructions.MulImm.self,
            Instructions.MulUpperSSImm.self,
            Instructions.MulUpperUUImm.self,
            Instructions.SetLtUImm.self,
            Instructions.SetLtSImm.self,
            Instructions.ShloLImm.self,
            Instructions.ShloRImm.self,
            Instructions.SharRImm.self,
            Instructions.NegAddImm.self,
            Instructions.SetGtUImm.self,
            Instructions.SetGtSImm.self,
            Instructions.ShloLImmAlt.self,
            Instructions.ShloRImmAlt.self,
            Instructions.SharRImmAlt.self,
            Instructions.CmovIzImm.self,
            Instructions.CmovNzImm.self,
            Instructions.BranchEq.self,
            Instructions.BranchNe.self,
            Instructions.BranchLtU.self,
            Instructions.BranchLtS.self,
            Instructions.BranchGeU.self,
            Instructions.BranchGeS.self,
            Instructions.LoadImmJumpInd.self,
            Instructions.Add.self,
            Instructions.Sub.self,
            Instructions.And.self,
            Instructions.Xor.self,
            Instructions.Or.self,
            Instructions.Mul.self,
            Instructions.MulUpperSS.self,
            Instructions.MulUpperUU.self,
            Instructions.MulUpperSU.self,
            Instructions.DivU.self,
            Instructions.DivS.self,
            Instructions.RemU.self,
            Instructions.RemS.self,
            Instructions.SetLtU.self,
            Instructions.SetLtS.self,
            Instructions.ShloL.self,
            Instructions.ShloR.self,
            Instructions.SharR.self,
            Instructions.CmovIz.self,
            Instructions.CmovNz.self,
        ]
        var table: [Instruction.Type?] = Array(repeating: nil, count: 256)
        for i in 0 ..< insts.count {
            table[Int(insts[i].opcode)] = insts[i]
        }
        return table
    }()

    public static func parse(_ data: Data) -> (any Instruction)? {
        logger.debug("parsing \(data)")
        guard data.count >= 1 else {
            return nil
        }
        let opcode = data[data.startIndex]
        logger.debug("parsed opcode: \(opcode)")
        guard let instType = table[Int(opcode)] else {
            return nil
        }

        logger.debug("initializing \(instType)")
        // TODO: log errors
        return try? instType.init(data: data[relative: 1...])
    }
}
