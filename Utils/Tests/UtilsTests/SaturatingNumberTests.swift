import Foundation
import Testing
@testable import Utils

struct SaturatingNumberTests {
    @Test func moreAssignment() {
        var gas = Gas(100)
        gas += Gas(2)
        #expect(gas == Gas(102))
        gas = Gas(100)
        gas -= Gas(50)
        #expect(gas == Gas(50))
        gas = Gas(100)
        gas *= Gas(2)
        #expect(gas == Gas(200))
        gas = Gas(200)
        gas /= Gas(2)
        #expect(gas == Gas(100))
        gas = Gas(200)
        gas %= Gas(2)
        #expect(gas == Gas(0))
        gas = Gas(200)
        #expect(gas / 2 == Gas(100))
        gas = Gas(100)
        gas -= 50
        #expect(gas == Gas(50))
        gas = Gas(100)
        gas *= 2
        #expect(gas == Gas(200))
        gas = Gas(200)
        gas /= 2
        #expect(gas == Gas(100))
        gas = Gas(200)
        gas %= 2
        #expect(gas == Gas(0))
        gas = Gas(100)
        gas += 2
        #expect(gas == Gas(102))
        #expect(gas % 2 == Gas(0))
    }

    @Test func additionWithNoOverflow() {
        let gas1 = Gas(100)
        let gas2 = Gas(200)
        let result = gas1 + gas2

        #expect(result == Gas(300))
    }

    @Test func additionWithOverflow() {
        let maxGas = Gas.max
        let result = maxGas + 1

        #expect(result == Gas.max)
    }

    @Test func subtractionWithNoOverflow() {
        let gas1 = Gas(100)
        let gas2 = Gas(200)
        let result = gas1 - gas2

        #expect(result == Gas(-100))
    }

    @Test func subtractionWithOverflow() {
        let minGas = Gas.min
        let result = minGas - 1

        #expect(result == Gas.min)
    }

    @Test func multiplicationWithNoOverflow() {
        let gas1 = Gas(100)
        let gas2 = Gas(200)
        let result = gas1 * gas2

        #expect(result == Gas(20000))
    }

    @Test func multiplicationWithOverflow() {
        let maxGas = Gas.max
        let result = maxGas * 2

        #expect(result == Gas.max)
    }

    @Test func negation() {
        let gas1 = Gas(100)
        let result = -gas1

        #expect(result == Gas(-100))
    }

    @Test func additionWithOtherType() {
        let gas1 = Gas(100)
        let result = gas1 + 1

        #expect(result == Gas(101))
    }

    @Test func subtractionWithOtherType() {
        let gas1 = Gas(100)
        let result = gas1 - 1

        #expect(result == Gas(99))
    }

    @Test func multiplicationWithOtherType() {
        let gas1 = Gas(100)
        let result = gas1 * 2

        #expect(result == Gas(200))
    }

    @Test func comparison() {
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

    @Test func division() {
        let gas1 = Gas(100)
        let gas2 = Gas(200)
        let result = gas2 / gas1

        #expect(result == Gas(2))
    }

    @Test func modulo() {
        let gas1 = Gas(100)
        let gas2 = Gas(200)

        #expect(gas2 % gas1 == Gas(0))
        #expect(gas1 % gas2 == Gas(100))
    }

    @Test func testEncodedSize() {
        let gas = Gas(100)
        #expect(gas.encodedSize == MemoryLayout<Int>.size)
    }

    @Test func testEncodeedSizeHint() {
        #expect(Gas.encodeedSizeHint == MemoryLayout<Int>.size)
    }

    @Test func testDescription() {
        let gas = Gas(100)
        #expect(gas.description == "100")
    }
}
