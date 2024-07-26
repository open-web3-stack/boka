import Foundation
import Testing

@testable import PolkaVM

struct InstructionTests {
    @Test func decodeImmediate() {
        #expect(Instructions.decodeImmidate(Data()) == 0)
        #expect(Instructions.decodeImmidate(Data([0])) == 0)
        #expect(Instructions.decodeImmidate(Data([0x07])) == 0x07)
        #expect(Instructions.decodeImmidate(Data([0xFF])) == 0xFFFF_FFFF)
        #expect(Instructions.decodeImmidate(Data([0xF0])) == 0xFFFF_FFF0)
        #expect(Instructions.decodeImmidate(Data([0x23, 0x7F])) == 0x7F23)
        #expect(Instructions.decodeImmidate(Data([0x12, 0x80])) == 0xFFFF_8012)
        #expect(Instructions.decodeImmidate(Data([0x34, 0x12, 0x7F])) == 0x7F1234)
        #expect(Instructions.decodeImmidate(Data([0x34, 0x12, 0x80])) == 0xFF80_1234)
        #expect(Instructions.decodeImmidate(Data([0x12, 0x34, 0x56, 0x78])) == 0x7856_3412)
        #expect(Instructions.decodeImmidate(Data([0x12, 0x34, 0x56, 0xFA])) == 0xFA56_3412)
    }

    @Test func decodeImmiate2() {
        #expect(Instructions.decodeImmidate2(Data()) == nil)
        // TODO: add more tests
    }
}
