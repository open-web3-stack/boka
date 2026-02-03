import Testing
@testable import Utils

struct ConstIntTests {
    @Test
    func constIntValues() {
        #expect(ConstInt0.value == 0)
        #expect(ConstInt1.value == 1)
        #expect(ConstInt2.value == 2)
        #expect(ConstInt3.value == 3)
        #expect(ConstInt12.value == 12)
        #expect(ConstInt32.value == 32)
        #expect(ConstInt48.value == 48)
        #expect(ConstInt64.value == 64)
        #expect(ConstInt96.value == 96)
        #expect(ConstInt128.value == 128)
        #expect(ConstInt144.value == 144)
        #expect(ConstInt384.value == 384)
        #expect(ConstInt784.value == 784)
        #expect(ConstInt4104.value == 4104)
        #expect(ConstIntMax.value == Int.max)
    }
}
