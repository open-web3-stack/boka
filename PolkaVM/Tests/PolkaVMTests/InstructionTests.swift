import Foundation
import Testing
import Utils

@testable import PolkaVM

struct InstructionTests {
    @Test func decodeImmediate() {
        #expect(Instructions.decodeImmediate(Data()) == 0)
        #expect(Instructions.decodeImmediate(Data([0])) == 0)
        #expect(Instructions.decodeImmediate(Data([0x07])) == 0x07)
        #expect(Instructions.decodeImmediate(Data([0xFF])) as UInt32 == 0xFFFF_FFFF)
        #expect(Instructions.decodeImmediate(Data([0xF0])) as UInt32 == 0xFFFF_FFF0)
        #expect(Instructions.decodeImmediate(Data([0x23, 0x7F])) as UInt32 == 0x7F23)
        #expect(Instructions.decodeImmediate(Data([0x12, 0x80])) as UInt32 == 0xFFFF_8012)
        #expect(Instructions.decodeImmediate(Data([0x34, 0x12, 0x7F])) as UInt32 == 0x7F1234)
        #expect(Instructions.decodeImmediate(Data([0x34, 0x12, 0x80])) as UInt32 == 0xFF80_1234)
        #expect(Instructions.decodeImmediate(Data([0x12, 0x34, 0x56, 0x78])) as UInt32 == 0x7856_3412)
        #expect(Instructions.decodeImmediate(Data([0x12, 0x34, 0x56, 0xFA])) as UInt8 == 0x12)
        #expect(Instructions.decodeImmediate(Data([0x12, 0x34, 0x56, 0xFA])) as UInt16 == 0x3412)
        #expect(Instructions.decodeImmediate(Data([0x12, 0x34, 0x56, 0xFA])) as UInt32 == 0xFA56_3412)
        #expect(Instructions.decodeImmediate(Data([0x12, 0x34, 0x56, 0xFA])) as UInt64 == 0xFFFF_FFFF_FA56_3412)
    }

    @Test func decodeImmiate2() throws {
        #expect(throws: IndexOutOfBounds.self) { try Instructions.decodeImmediate2(Data()) as (UInt32, UInt32) }
        #expect(try Instructions.decodeImmediate2(Data([0x00, 0x00])) as (UInt32, UInt32) == (0, 0))
        // 2 byte X, 0 byte Y
        #expect(try Instructions.decodeImmediate2(Data([0x02, 0x12, 0x34, 0x00])) as (UInt32, UInt32) == (0x3412, 0))
        // 4 byte X, 4 byte Y
        #expect(try Instructions.decodeImmediate2(Data([0x0C, 0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC, 0xDE])) as (UInt32, UInt32) ==
            (0x7856_3412, 0xFFDE_BC9A))
        #expect(try Instructions.decodeImmediate2(Data([0x0C, 0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC, 0xDE])) as (UInt32, UInt16) ==
            (0x7856_3412, 0xBC9A))
    }
}
