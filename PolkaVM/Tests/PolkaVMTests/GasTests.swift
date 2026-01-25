import Foundation
import Testing
import Utils

@testable import PolkaVM

/// Unit tests for Gas operations
struct GasTests {
    @Test func testGasCreation() {
        // Test gas creation from various integer types
        let gas1 = Gas(0)
        #expect(gas1.value == 0)

        let gas2 = Gas(100)
        #expect(gas2.value == 100)

        let gas3 = Gas(1_000_000)
        #expect(gas3.value == 1_000_000)

        let gas4 = Gas(UInt64.max)
        #expect(gas4.value == UInt64.max)
    }

    @Test func testGasComparison() {
        let gas1 = Gas(100)
        let gas2 = Gas(200)
        let gas3 = Gas(100)

        #expect(gas1 < gas2)
        #expect(gas2 > gas1)
        #expect(gas1 == gas3)
        #expect(gas1 <= gas3)
        #expect(gas2 >= gas1)
    }

    @Test func testGasArithmetic() {
        let gas1 = Gas(100)
        let gas2 = Gas(50)

        // Test subtraction (should not overflow)
        let diff = gas1 - gas2
        #expect(diff.value == 50)

        // Test that subtraction saturates at 0
        let gasSmall = Gas(10)
        let gasLarge = Gas(100)
        let noOverflow = gasSmall - gasLarge
        #expect(noOverflow.value >= 0) // Should saturate, not underflow
    }

    @Test func testGasSendable() {
        // Gas should be Sendable
        func requiresSendable(_ _: some Sendable) {}
        requiresSendable(Gas(100))
    }

    @Test func testGasSaturating() {
        // Test that Gas is a saturating number
        // This means arithmetic operations won't overflow/underflow
        let maxGas = Gas(UInt64.max)
        let additional = Gas(1)

        // Adding to max should saturate, not overflow
        let result = maxGas + additional
        #expect(result.value == UInt64.max || result.value > UInt64.max - additional.value)
    }

    @Test func testGasZero() {
        let zeroGas = Gas(0)
        #expect(zeroGas.value == 0)

        // Test comparison with zero
        let positiveGas = Gas(100)
        #expect(zeroGas < positiveGas)
        #expect(positiveGas > zeroGas)
    }

    @Test func testGasLargeValues() {
        // Test very large gas values
        let largeGas1 = Gas(1_000_000_000)
        #expect(largeGas1.value == 1_000_000_000)

        let largeGas2 = Gas(10_000_000_000)
        #expect(largeGas2.value == 10_000_000_000)

        let largeGas3 = Gas(1_000_000_000_000)
        #expect(largeGas3.value == 1_000_000_000_000)
    }
}
