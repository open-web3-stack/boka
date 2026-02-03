import Testing
@testable import Utils

struct FixedWidthIntegerTests {
    @Test func nextPowerOfTwo() {
        #expect(UInt8(0).nextPowerOfTwo == nil)
        #expect(UInt8(1).nextPowerOfTwo == UInt8(1))
        #expect(UInt8(2).nextPowerOfTwo == UInt8(2))
        #expect(UInt8(3).nextPowerOfTwo == UInt8(4))
        #expect(UInt8(4).nextPowerOfTwo == UInt8(4))
        #expect(UInt8(5).nextPowerOfTwo == UInt8(8))
        #expect(UInt8(8).nextPowerOfTwo == UInt8(8))
        #expect(UInt8(127).nextPowerOfTwo == UInt8(128))
        #expect(UInt8(128).nextPowerOfTwo == UInt8(128))
        #expect(UInt8(129).nextPowerOfTwo == nil)
        #expect(UInt8(255).nextPowerOfTwo == nil)

        #expect(UInt32(0).nextPowerOfTwo == nil)
        #expect(UInt32(1).nextPowerOfTwo == UInt32(1))
        #expect(UInt32(2).nextPowerOfTwo == UInt32(2))
        #expect(UInt32(511).nextPowerOfTwo == UInt32(512))
        #expect(UInt32(512).nextPowerOfTwo == UInt32(512))
        #expect(UInt32(513).nextPowerOfTwo == UInt32(1024))
        #expect(UInt32(0x7FFF_FFFF).nextPowerOfTwo == UInt32(0x8000_0000))
        #expect(UInt32(0xF000_0000).nextPowerOfTwo == nil)
        #expect(UInt32(0xF000_0001).nextPowerOfTwo == nil)
        #expect(UInt32.max.nextPowerOfTwo == nil)
    }
}
