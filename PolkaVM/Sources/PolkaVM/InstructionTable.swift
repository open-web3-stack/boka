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
            Instructions.CountSetBits64.self,
            Instructions.CountSetBits32.self,
            Instructions.LeadingZeroBits64.self,
            Instructions.LeadingZeroBits32.self,
            Instructions.SignExtend8.self,
            Instructions.SignExtend16.self,
            Instructions.ZeroExtend16.self,
            Instructions.ReverseBytes.self,
            Instructions.StoreIndU8.self,
            Instructions.StoreIndU16.self,
            Instructions.StoreIndU32.self,
            Instructions.LoadIndU8.self,
            Instructions.LoadIndI8.self,
            Instructions.LoadIndU16.self,
            Instructions.LoadIndI16.self,
            Instructions.LoadIndU32.self,
            Instructions.AddImm32.self,
            Instructions.AddImm64.self,
            Instructions.AndImm.self,
            Instructions.XorImm.self,
            Instructions.OrImm.self,
            Instructions.MulImm32.self,
            Instructions.MulImm64.self,
            Instructions.SetLtUImm.self,
            Instructions.SetLtSImm.self,
            Instructions.ShloLImm32.self,
            Instructions.ShloLImm64.self,
            Instructions.ShloRImm32.self,
            Instructions.ShloRImm64.self,
            Instructions.SharRImm32.self,
            Instructions.SharRImm64.self,
            Instructions.NegAddImm32.self,
            Instructions.NegAddImm64.self,
            Instructions.SetGtUImm.self,
            Instructions.SetGtSImm.self,
            Instructions.ShloLImmAlt32.self,
            Instructions.ShloRImmAlt32.self,
            Instructions.SharRImmAlt32.self,
            Instructions.ShloLImmAlt64.self,
            Instructions.ShloRImmAlt64.self,
            Instructions.SharRImmAlt64.self,
            Instructions.CmovIzImm.self,
            Instructions.CmovNzImm.self,
            Instructions.RotR64Imm.self,
            Instructions.RotR64ImmAlt.self,
            Instructions.RotR32Imm.self,
            Instructions.RotR32ImmAlt.self,
            Instructions.BranchEq.self,
            Instructions.BranchNe.self,
            Instructions.BranchLtU.self,
            Instructions.BranchLtS.self,
            Instructions.BranchGeU.self,
            Instructions.BranchGeS.self,
            Instructions.LoadImmJumpInd.self,
            Instructions.Add32.self,
            Instructions.Sub32.self,
            Instructions.Add64.self,
            Instructions.Sub64.self,
            Instructions.And.self,
            Instructions.Xor.self,
            Instructions.Or.self,
            Instructions.Mul32.self,
            Instructions.Mul64.self,
            Instructions.MulUpperSS.self,
            Instructions.MulUpperUU.self,
            Instructions.MulUpperSU.self,
            Instructions.DivU32.self,
            Instructions.DivU64.self,
            Instructions.DivS32.self,
            Instructions.DivS64.self,
            Instructions.RemU32.self,
            Instructions.RemU64.self,
            Instructions.RemS32.self,
            Instructions.RemS64.self,
            Instructions.SetLtU.self,
            Instructions.SetLtS.self,
            Instructions.ShloL32.self,
            Instructions.ShloR32.self,
            Instructions.SharR32.self,
            Instructions.ShloL64.self,
            Instructions.ShloR64.self,
            Instructions.SharR64.self,
            Instructions.CmovIz.self,
            Instructions.CmovNz.self,
            Instructions.RotL64.self,
            Instructions.RotL32.self,
            Instructions.RotR64.self,
            Instructions.RotR32.self,
            Instructions.AndInv.self,
            Instructions.OrInv.self,
            Instructions.Xnor.self,
            Instructions.Max.self,
            Instructions.MaxU.self,
            Instructions.Min.self,
            Instructions.MinU.self,
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
