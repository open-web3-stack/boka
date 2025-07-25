#include "instructions.hh"

namespace Instructions {
    // to workaround duplicated .init issue in Swift
    Trap::Trap() {}
    Fallthrough::Fallthrough() {}

    const uint8_t Trap::opcode = 0;
    const uint8_t Fallthrough::opcode = 1;
    const uint8_t Ecalli::opcode = 10;
    const uint8_t LoadImm64::opcode = 20;
    const uint8_t StoreImmU8::opcode = 30;
    const uint8_t StoreImmU16::opcode = 31;
    const uint8_t StoreImmU32::opcode = 32;
    const uint8_t StoreImmU64::opcode = 33;
    const uint8_t Jump::opcode = 40;
    const uint8_t JumpInd::opcode = 50;
    const uint8_t LoadImm::opcode = 51;
    const uint8_t LoadU8::opcode = 52;
    const uint8_t LoadI8::opcode = 53;
    const uint8_t LoadU16::opcode = 54;
    const uint8_t LoadI16::opcode = 55;
    const uint8_t LoadU32::opcode = 56;
    const uint8_t LoadI32::opcode = 57;
    const uint8_t LoadU64::opcode = 58;
    const uint8_t StoreU8::opcode = 59;
    const uint8_t StoreU16::opcode = 60;
    const uint8_t StoreU32::opcode = 61;
    const uint8_t StoreU64::opcode = 62;
    const uint8_t StoreImmIndU8::opcode = 70;
    const uint8_t StoreImmIndU16::opcode = 71;
    const uint8_t StoreImmIndU32::opcode = 72;
    const uint8_t StoreImmIndU64::opcode = 73;
    const uint8_t LoadImmJump::opcode = 80;
    const uint8_t BranchEqImm::opcode = 81;
    const uint8_t BranchNeImm::opcode = 82;
    const uint8_t BranchLtUImm::opcode = 83;
    const uint8_t BranchLeUImm::opcode = 84;
    const uint8_t BranchGeUImm::opcode = 85;
    const uint8_t BranchGtUImm::opcode = 86;
    const uint8_t BranchLtSImm::opcode = 87;
    const uint8_t BranchLeSImm::opcode = 88;
    const uint8_t BranchGeSImm::opcode = 89;
    const uint8_t BranchGtSImm::opcode = 90;
    const uint8_t MoveReg::opcode = 100;
    const uint8_t Sbrk::opcode = 101;
    const uint8_t CountSetBits64::opcode = 102;
    const uint8_t CountSetBits32::opcode = 103;
    const uint8_t LeadingZeroBits64::opcode = 104;
    const uint8_t LeadingZeroBits32::opcode = 105;
    const uint8_t TrailingZeroBits64::opcode = 106;
    const uint8_t TrailingZeroBits32::opcode = 107;
    const uint8_t SignExtend8::opcode = 108;
    const uint8_t SignExtend16::opcode = 109;
    const uint8_t ZeroExtend16::opcode = 110;
    const uint8_t ReverseBytes::opcode = 111;
    const uint8_t StoreIndU8::opcode = 120;
    const uint8_t StoreIndU16::opcode = 121;
    const uint8_t StoreIndU32::opcode = 122;
    const uint8_t StoreIndU64::opcode = 123;
    const uint8_t LoadIndU8::opcode = 124;
    const uint8_t LoadIndI8::opcode = 125;
    const uint8_t LoadIndU16::opcode = 126;
    const uint8_t LoadIndI16::opcode = 127;
    const uint8_t LoadIndU32::opcode = 128;
    const uint8_t LoadIndI32::opcode = 129;
    const uint8_t LoadIndU64::opcode = 130;
    const uint8_t AddImm32::opcode = 131;
    const uint8_t AndImm::opcode = 132;
    const uint8_t XorImm::opcode = 133;
    const uint8_t OrImm::opcode = 134;
    const uint8_t MulImm32::opcode = 135;
    const uint8_t SetLtUImm::opcode = 136;
    const uint8_t SetLtSImm::opcode = 137;
    const uint8_t ShloLImm32::opcode = 138;
    const uint8_t ShloRImm32::opcode = 139;
    const uint8_t SharRImm32::opcode = 140;
    const uint8_t NegAddImm32::opcode = 141;
    const uint8_t SetGtUImm::opcode = 142;
    const uint8_t SetGtSImm::opcode = 143;
    const uint8_t ShloLImmAlt32::opcode = 144;
    const uint8_t ShloRImmAlt32::opcode = 145;
    const uint8_t SharRImmAlt32::opcode = 146;
    const uint8_t CmovIzImm::opcode = 147;
    const uint8_t CmovNzImm::opcode = 148;
    const uint8_t AddImm64::opcode = 149;
    const uint8_t MulImm64::opcode = 150;
    const uint8_t ShloLImm64::opcode = 151;
    const uint8_t ShloRImm64::opcode = 152;
    const uint8_t SharRImm64::opcode = 153;
    const uint8_t NegAddImm64::opcode = 154;
    const uint8_t ShloLImmAlt64::opcode = 155;
    const uint8_t ShloRImmAlt64::opcode = 156;
    const uint8_t SharRImmAlt64::opcode = 157;
    const uint8_t RotR64Imm::opcode = 158;
    const uint8_t RotR64ImmAlt::opcode = 159;
    const uint8_t RotR32Imm::opcode = 160;
    const uint8_t RotR32ImmAlt::opcode = 161;
    const uint8_t BranchEq::opcode = 170;
    const uint8_t BranchNe::opcode = 171;
    const uint8_t BranchLtU::opcode = 172;
    const uint8_t BranchLtS::opcode = 173;
    const uint8_t BranchGeU::opcode = 174;
    const uint8_t BranchGeS::opcode = 175;
    const uint8_t LoadImmJumpInd::opcode = 180;
    const uint8_t Add32::opcode = 190;
    const uint8_t Sub32::opcode = 191;
    const uint8_t Mul32::opcode = 192;
    const uint8_t DivU32::opcode = 193;
    const uint8_t DivS32::opcode = 194;
    const uint8_t RemU32::opcode = 195;
    const uint8_t RemS32::opcode = 196;
    const uint8_t ShloL32::opcode = 197;
    const uint8_t ShloR32::opcode = 198;
    const uint8_t SharR32::opcode = 199;
    const uint8_t Add64::opcode = 200;
    const uint8_t Sub64::opcode = 201;
    const uint8_t Mul64::opcode = 202;
    const uint8_t DivU64::opcode = 203;
    const uint8_t DivS64::opcode = 204;
    const uint8_t RemU64::opcode = 205;
    const uint8_t RemS64::opcode = 206;
    const uint8_t ShloL64::opcode = 207;
    const uint8_t ShloR64::opcode = 208;
    const uint8_t SharR64::opcode = 209;
    const uint8_t And::opcode = 210;
    const uint8_t Xor::opcode = 211;
    const uint8_t Or::opcode = 212;
    const uint8_t MulUpperSS::opcode = 213;
    const uint8_t MulUpperUU::opcode = 214;
    const uint8_t MulUpperSU::opcode = 215;
    const uint8_t SetLtU::opcode = 216;
    const uint8_t SetLtS::opcode = 217;
    const uint8_t CmovIz::opcode = 218;
    const uint8_t CmovNz::opcode = 219;
    const uint8_t RotL64::opcode = 220;
    const uint8_t RotL32::opcode = 221;
    const uint8_t RotR64::opcode = 222;
    const uint8_t RotR32::opcode = 223;
    const uint8_t AndInv::opcode = 224;
    const uint8_t OrInv::opcode = 225;
    const uint8_t Xnor::opcode = 226;
    const uint8_t Max::opcode = 227;
    const uint8_t MaxU::opcode = 228;
    const uint8_t Min::opcode = 229;
    const uint8_t MinU::opcode = 230;
}
