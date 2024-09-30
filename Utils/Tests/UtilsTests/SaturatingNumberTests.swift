import Foundation
import Testing

@testable import Utils

struct SaturatingNumberTests {
    @Test func testAdditionWithNoOverflow() {
        let gas1 = Gas(100)
        let gas2 = Gas(200)
        let result = gas1 + gas2

        #expect(result == Gas(300))
    }

    @Test func testAdditionWithOverflow() {
        let maxGas = Gas.max
        let result = maxGas + 1

        #expect(result == Gas.max)
    }

    @Test func testSubtractionWithNoOverflow() {
        let gas1 = Gas(100)
        let gas2 = Gas(200)
        let result = gas1 - gas2

        #expect(result == Gas(-100))
    }

    @Test func testSubtractionWithOverflow() {
        let minGas = Gas.min
        let result = minGas - 1

        #expect(result == Gas.min)
    }

    @Test func testMultiplicationWithNoOverflow() {
        let gas1 = Gas(100)
        let gas2 = Gas(200)
        let result = gas1 * gas2

        #expect(result == Gas(20000))
    }

    @Test func testMultiplicationWithOverflow() {
        let maxGas = Gas.max
        let result = maxGas * 2

        #expect(result == Gas.max)
    }

    @Test func testNegation() {
        let gas1 = Gas(100)
        let result = -gas1

        #expect(result == Gas(-100))
    }

    @Test func testAdditionWithOtherType() {
        let gas1 = Gas(100)
        let result = gas1 + 1

        #expect(result == Gas(101))
    }

    @Test func testSubtractionWithOtherType() {
        let gas1 = Gas(100)
        let result = gas1 - 1

        #expect(result == Gas(99))
    }

    @Test func testMultiplicationWithOtherType() {
        let gas1 = Gas(100)
        let result = gas1 * 2

        #expect(result == Gas(200))
    }

    @Test func testComparison() {
        let gas1 = Gas(100)
        let gas2 = Gas(200)
        let gas3 = Gas(300)

        #expect(gas1 < gas2)
        #expect(gas1 <= gas2)
        #expect(gas2 > gas1)
        #expect(gas2 >= gas1)
        #expect(gas1 == gas1)
        #expect(gas1 != gas2)
        #expect(gas1 + gas2 == gas3)
    }
}
