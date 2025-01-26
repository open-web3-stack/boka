import Testing

@testable import Utils

struct ConstIntTests {
    @Test
    func constIntValues() {
        #expect(ConstInt0.value == 0)
        #expect(ConstInt1.value == 1)
        #expect(ConstInt2.value == 2)
        #expect(ConstInt3.value == 3)
        #expect(ConstIntMax.value == Int.max)
        #expect(ConstInt32.value == 32)
        #expect(ConstInt48.value == 48)
        #expect(ConstInt64.value == 64)
        #expect(ConstUInt96.value == 96)
        #expect(ConstUInt128.value == 128)
        #expect(ConstUInt144.value == 144)
        #expect(ConstUInt384.value == 384)
        #expect(ConstUInt784.value == 784)
    }
}
