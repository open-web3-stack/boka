import Testing

@testable import Utils

struct ConstIntTests {
    enum ConstInt888: ConstInt {
        public static var value: Int {
            888
        }
    }

    @Test
    func constIntValues() {
        let arr: [any ConstInt.Type] = [
            ConstInt0.self,
            ConstInt1.self,
            ConstInt2.self,
            ConstInt3.self,
            ConstIntMax.self,
            ConstInt32.self,
            ConstInt48.self,
            ConstInt64.self,
            ConstUInt96.self,
            ConstUInt128.self,
            ConstUInt144.self,
            ConstUInt384.self,
            ConstUInt784.self,
            ConstInt888.self,
        ]

        for type in arr {
            let value = type.value
            switch type {
            case is ConstInt0.Type:
                #expect(value == 0)
            case is ConstInt1.Type:
                #expect(value == 1)
            case is ConstInt2.Type:
                #expect(value == 2)
            case is ConstInt3.Type:
                #expect(value == 3)
            case is ConstIntMax.Type:
                #expect(value == Int.max)
            case is ConstInt32.Type:
                #expect(value == 32)
            case is ConstInt48.Type:
                #expect(value == 48)
            case is ConstInt64.Type:
                #expect(value == 64)
            case is ConstUInt96.Type:
                #expect(value == 96)
            case is ConstUInt128.Type:
                #expect(value == 128)
            case is ConstUInt144.Type:
                #expect(value == 144)
            case is ConstUInt384.Type:
                #expect(value == 384)
            case is ConstUInt784.Type:
                #expect(value == 784)
            default:
                break
            }
        }
    }
}
